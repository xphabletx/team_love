// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/input_service.dart';
import '../services/calendar_events_service.dart';

const _prefsKey = 'teamlove_budget_state_v3'; // envelopes+groups persistence

class EnvelopeGroupsScreen extends StatefulWidget {
  const EnvelopeGroupsScreen({
    super.key,
    required this.activeChildTab, // 1=envelopes, 2=groups
  });

  final int activeChildTab;

  @override
  State<EnvelopeGroupsScreen> createState() => EnvelopeGroupsScreenState();
}

class EnvelopeGroupsScreenState extends State<EnvelopeGroupsScreen> {
  final ScrollController _scrollControllerEnv = ScrollController();

  final List<_Envelope> _envelopes = [];
  final List<_Group> _groups = [];

  // A–Z overlay for envelopes
  static const _letters = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];
  bool _indexVisible = false;
  String? _activeLetter;
  Timer? _hideIndexTimer;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void didUpdateWidget(covariant EnvelopeGroupsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When parent switches between Envelopes/Groups, we just rebuild.
    setState(() {});
  }

  @override
  void dispose() {
    _scrollControllerEnv.dispose();
    _hideIndexTimer?.cancel();
    super.dispose();
  }

  // ===== persistence for envelopes/groups =====
  DateTime _ymd(DateTime d) => DateTime(d.year, d.month, d.day);
  String _ymdKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final obj = jsonDecode(raw) as Map<String, dynamic>;
        final envs = (obj['envelopes'] as List<dynamic>? ?? [])
            .map((e) => _Envelope.fromJson(e as Map<String, dynamic>))
            .toList();
        final grps = (obj['groups'] as List<dynamic>? ?? [])
            .map((g) => _Group.fromJson(g as Map<String, dynamic>))
            .toList();

        setState(() {
          _envelopes
            ..clear()
            ..addAll(envs);
          _groups
            ..clear()
            ..addAll(grps);
          _sortEnvelopes();

          for (final e in _envelopes) {
            if (e.payDate != null) {
              CalendarEvents.instance.upsert(
                CalEvent(
                  id: 'env:${e.id}',
                  title: 'Payment: ${e.name}',
                  date: _ymd(e.payDate!),
                  repeat: e.payRepeat ?? 'None',
                  every: (e.payEvery ?? 1),
                  reminder: 'None',
                  meta: {'envelopeId': e.id},
                ),
              );
            }
          }
        });
      } catch (_) {
        /* ignore malformed */
      }
    }
    await _maybeResetEnvelopesForToday();
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'envelopes': _envelopes.map((e) => e.toJson()).toList(),
      'groups': _groups.map((g) => g.toJson()).toList(),
    });
    await prefs.setString(_prefsKey, data);
  }

  Future<void> _maybeResetEnvelopesForToday() async {
    final today = _ymd(DateTime.now());
    final todayKey = _ymdKey(today);
    bool changed = false;

    for (final e in _envelopes) {
      if (e.resetOnRecurring != true) continue;
      if (e.payDate == null) continue;

      final ce = CalEvent(
        id: 'tmp:${e.id}',
        title: e.name,
        date: _ymd(e.payDate!),
        repeat: e.payRepeat ?? 'None',
        every: (e.payEvery ?? 1),
        reminder: 'None',
      );

      final occurs = CalendarEvents.instance.occursOn(ce, today);
      if (occurs && e.lastResetYmd != todayKey) {
        e.balance = 0;
        e.lastResetYmd = todayKey;
        changed = true;
      }
    }
    if (changed) {
      setState(() {});
      await _saveState();
    }
  }

  void _sortEnvelopes() {
    _envelopes.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  // ===== A–Z overlay helpers =====
  Map<String, int> _firstIndexByLetter(List<_Envelope> list) {
    final map = <String, int>{};
    for (var i = 0; i < list.length; i++) {
      final n = list[i].name.trim().toUpperCase();
      if (n.isEmpty) continue;
      map.putIfAbsent(n[0], () => i);
    }
    return map;
  }

  void _scrollToGridIndex(int itemIndex) {
    const columns = 2;
    const tileHeight = 190.0;
    const rowSpacing = 12.0;
    final row = (itemIndex / columns).floor();
    final offset = row * (tileHeight + rowSpacing);
    _scrollControllerEnv.animateTo(
      offset.toDouble(),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToLetter(String letter, List<_Envelope> list) {
    final map = _firstIndexByLetter(list);
    final idx = map[letter];
    if (idx != null) _scrollToGridIndex(idx);
  }

  void _showIndex() {
    _hideIndexTimer?.cancel();
    setState(() => _indexVisible = true);
  }

  void _scheduleHideIndex() {
    _hideIndexTimer?.cancel();
    _hideIndexTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _indexVisible = false;
          _activeLetter = null;
        });
      }
    });
  }

  // ===== FAB (exposed to parent) =====
  Widget? buildFab() {
    // Only build FAB when this page is visible (tab 1 or 2)
    return FloatingActionButton(
      onPressed: _openFabSheetLegacy,
      child: const Icon(Icons.add),
    );
  }

  // ===== UI (no Scaffold here; parent provides Scaffold/app bar) =====
  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final showGroups = (widget.activeChildTab == 2);

    final sorted = [..._envelopes]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final hasEnvData = sorted.isNotEmpty;
    final hasGroupData = _groups.isNotEmpty;

    return Stack(
      children: [
        if (!showGroups)
          (hasEnvData
              ? _buildEnvelopeGrid(sorted, currentUid)
              : _emptyState(
                  title: 'No envelopes yet',
                  actionText: 'Create your first envelope',
                  icon: Icons.account_balance_wallet_outlined,
                  onPressed: _createEnvelope,
                ))
        else
          (hasGroupData
              ? _buildGroupsList(currentUid)
              : _emptyState(
                  title: 'No groups yet',
                  actionText: 'Create your first group',
                  icon: Icons.create_new_folder_outlined,
                  onPressed: _createGroup,
                )),
        if (!showGroups) _buildAzOverlay(sorted),
      ],
    );
  }

  // ===== pages =====
  Widget _buildEnvelopeGrid(List<_Envelope> sorted, String? currentUid) {
    return GridView.builder(
      controller: _scrollControllerEnv,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final e = sorted[i];
        final isOwner = e.ownerId == currentUid;
        final progress = e.target <= 0
            ? 0.0
            : (e.balance / e.target).clamp(0, 1).toDouble();

        return GestureDetector(
          onLongPress: () => _onLongPressEnvelope(e, isOwner),
          child: Opacity(
            opacity: isOwner ? 1 : 0.55,
            child: IgnorePointer(
              ignoring: !isOwner,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [Text('Current'), Text('Target')],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '£${e.balance.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '£${e.target.toStringAsFixed(0)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (!isOwner)
                          Text(
                            'Partner',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupsList(String? currentUid) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final g = _groups[i];
        final members = _envelopes
            .where((e) => g.memberIds.contains(e.id))
            .toList();
        final total = members.fold<double>(0, (sum, e) => sum + e.balance);

        return GestureDetector(
          onLongPress: () => _onLongPressGroup(g),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        _GroupDetailScreen(group: g, members: members),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name, style: Theme.of(ctx).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Total in group',
                        style: Theme.of(ctx).textTheme.labelMedium,
                      ),
                      Text(
                        '£${total.toStringAsFixed(2)}',
                        style: Theme.of(ctx).textTheme.headlineSmall,
                      ),
                      const Spacer(),
                      Text(
                        '${members.length} envelope(s)',
                        style: Theme.of(ctx).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAzOverlay(List<_Envelope> sorted) {
    const double itemHeight = 18.0;
    final double barHeight = itemHeight * _letters.length;

    void selectByDy(double dy) {
      final idx = (dy ~/ itemHeight).clamp(0, _letters.length - 1);
      final letter = _letters[idx];
      if (_activeLetter != letter) {
        setState(() => _activeLetter = letter);
        _jumpToLetter(letter, sorted);
      }
    }

    return Stack(
      children: [
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (d) {
                _showIndex();
                selectByDy(d.localPosition.dy);
                _scheduleHideIndex();
              },
              onVerticalDragStart: (_) => _showIndex(),
              onVerticalDragUpdate: (d) => selectByDy(d.localPosition.dy),
              onVerticalDragEnd: (_) => _scheduleHideIndex(),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _indexVisible ? 1 : 0.15,
                child: SizedBox(
                  width: 28,
                  height: barHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _letters.map((ch) {
                        final active = _activeLetter == ch;
                        return SizedBox(
                          height: itemHeight,
                          child: Center(
                            child: Text(
                              ch,
                              style: TextStyle(
                                fontSize: active ? 12 : 10,
                                fontWeight: active
                                    ? FontWeight.bold
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_indexVisible && _activeLetter != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                boxShadow: kElevationToShadow[3],
              ),
              child: Text(
                _activeLetter!,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
        if (_indexVisible && _activeLetter != null)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _activeLetter!,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ===== empty state =====
  Widget _emptyState({
    required String title,
    required String actionText,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(title),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.add),
            label: Text(actionText),
          ),
        ],
      ),
    );
  }

  // ===== FAB sheet (legacy) =====
  void _openFabSheetLegacy() {
    final showGroups = (widget.activeChildTab == 2);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (!showGroups)
              ListTile(
                leading: const Icon(Icons.add_box_outlined),
                title: const Text('Create new envelope'),
                onTap: () {
                  Navigator.pop(ctx);
                  _createEnvelope();
                },
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Create group'),
              onTap: () {
                Navigator.pop(ctx);
                _createGroup();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===== actions (legacy) =====
  Future<void> _createEnvelope() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'me';
    final nameCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final balanceCtrl = TextEditingController();

    DateTime? payDate;
    bool recurring = false;
    String repeatUnit = 'Monthly';
    const allowedRepeats = ['Daily', 'Weekly', 'Monthly', 'Yearly'];
    if (!allowedRepeats.contains(repeatUnit)) repeatUnit = 'Monthly';
    final everyCtrl = TextEditingController(text: '1');
    bool resetOnRecurring = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          top: 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSB) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create envelope',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              AppInputs.textField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              AppInputs.textField(
                controller: targetCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  prefixText: '£ ',
                  labelText: 'Target',
                ),
              ),
              const SizedBox(height: 12),
              AppInputs.textField(
                controller: balanceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  prefixText: '£ ',
                  labelText: 'Starting amount (optional)',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(
                        payDate == null
                            ? 'Set pay date (optional)'
                            : '${payDate!.year}-${payDate!.month.toString().padLeft(2, '0')}-${payDate!.day.toString().padLeft(2, '0')}',
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setSB(
                            () => payDate = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Recurring'),
                  Switch(
                    value: recurring,
                    onChanged: (v) => setSB(() => recurring = v),
                  ),
                  const SizedBox(width: 8),
                  if (recurring) ...[
                    SizedBox(
                      width: 64,
                      child: AppInputs.textField(
                        controller: everyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Every'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: repeatUnit,
                      onChanged: (v) =>
                          setSB(() => repeatUnit = v ?? 'Monthly'),
                      items: const [
                        DropdownMenuItem(value: 'Daily', child: Text('days')),
                        DropdownMenuItem(value: 'Weekly', child: Text('weeks')),
                        DropdownMenuItem(
                          value: 'Monthly',
                          child: Text('months'),
                        ),
                        DropdownMenuItem(value: 'Yearly', child: Text('years')),
                      ],
                    ),
                  ],
                ],
              ),
              if (recurring)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reset starting amount each cycle'),
                  value: resetOnRecurring,
                  onChanged: (v) => setSB(() => resetOnRecurring = v),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final n = nameCtrl.text.trim();
                  final t =
                      double.tryParse(targetCtrl.text.replaceAll(',', '')) ?? 0;
                  final b =
                      double.tryParse(balanceCtrl.text.replaceAll(',', '')) ??
                      0;

                  if (n.isEmpty || t <= 0) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    return;
                  }

                  final env = _Envelope(
                    id: _newId(),
                    ownerId: currentUid,
                    name: n,
                    target: t,
                    balance: b,
                    payDate: payDate,
                    payRepeat: (payDate != null && recurring)
                        ? repeatUnit
                        : 'None',
                    payEvery: (payDate != null && recurring)
                        ? (int.tryParse(everyCtrl.text) ?? 1)
                        : null,
                    resetOnRecurring: (payDate != null && recurring)
                        ? resetOnRecurring
                        : false,
                  );

                  final first = _envelopes.isEmpty;
                  setState(() {
                    _envelopes.add(env);
                    _sortEnvelopes();
                  });
                  await _saveState();

                  if (env.payDate != null) {
                    CalendarEvents.instance.upsert(
                      CalEvent(
                        id: 'env:${env.id}',
                        title: 'Payment: ${env.name}',
                        date: _ymd(env.payDate!),
                        repeat: env.payRepeat ?? 'None',
                        every: env.payEvery ?? 1,
                        reminder: 'None',
                        meta: {'envelopeId': env.id},
                      ),
                    );
                  }

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (first && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Tip: use the + to add more envelopes or groups.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createGroup() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create group'),
        content: AppInputs.textField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) {
                Navigator.pop(ctx);
                return;
              }
              setState(
                () => _groups.add(
                  _Group(id: _newId(), name: name, memberIds: {}),
                ),
              );
              await _saveState();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _onLongPressEnvelope(_Envelope env, bool isOwner) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Deposit'),
              enabled: isOwner,
              onTap: !isOwner
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _editAmount(
                        title: 'Deposit to ${env.name}',
                        onConfirm: (amt) async {
                          setState(() => env.balance += amt);
                          await _saveState();
                        },
                      );
                    },
            ),
            ListTile(
              leading: const Icon(Icons.remove),
              title: const Text('Withdraw'),
              enabled: isOwner,
              onTap: !isOwner
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _editAmount(
                        title: 'Withdraw from ${env.name}',
                        onConfirm: (amt) async {
                          setState(
                            () => env.balance = (env.balance - amt).clamp(
                              0,
                              double.infinity,
                            ),
                          );
                          await _saveState();
                        },
                      );
                    },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transfer'),
              onTap: () {
                Navigator.pop(ctx);
                _transferFrom(env);
              },
            ),
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Edit Target'),
              enabled: isOwner,
              onTap: !isOwner
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _editAmount(
                        title: 'New target for ${env.name}',
                        initial: env.target,
                        onConfirm: (amt) async {
                          setState(
                            () => env.target = (amt <= 0 ? env.target : amt),
                          );
                          await _saveState();
                        },
                      );
                    },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              enabled: isOwner,
              onTap: !isOwner
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _editText(
                        title: 'Rename envelope',
                        initial: env.name,
                        onConfirm: (txt) async {
                          setState(() {
                            env.name = txt;
                            _sortEnvelopes();
                          });
                          await _saveState();
                          if (env.payDate != null) {
                            CalendarEvents.instance.upsert(
                              CalEvent(
                                id: 'env:${env.id}',
                                title: 'Payment: ${env.name}',
                                date: _ymd(env.payDate!),
                                repeat: env.payRepeat ?? 'None',
                                every: env.payEvery ?? 1,
                                reminder: 'None',
                                meta: {'envelopeId': env.id},
                              ),
                            );
                          }
                        },
                      );
                    },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete'),
              enabled: isOwner,
              onTap: !isOwner
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _confirmDelete(env);
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _onLongPressGroup(_Group group) {
    final selected = {...group.memberIds};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          top: 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSB) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Edit group members',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: ListView(
                  children: _envelopes.map((e) {
                    final checked = selected.contains(e.id);
                    return CheckboxListTile(
                      title: Text(e.name),
                      value: checked,
                      onChanged: (v) => setSB(() {
                        if (v == true) {
                          selected.add(e.id);
                        } else {
                          selected.remove(e.id);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      setState(() => group.memberIds = selected);
                      await _saveState();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editAmount({
    required String title,
    double? initial,
    required void Function(double amount) onConfirm,
  }) {
    final ctrl = TextEditingController(
      text: initial == null ? '' : initial.toStringAsFixed(2),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            AppInputs.textField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                prefixText: '£ ',
                labelText: 'Amount',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text.replaceAll(',', ''));
                if (v == null || v.isNaN || v.isInfinite || v <= 0) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  return;
                }
                onConfirm(v);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _editText({
    required String title,
    String initial = '',
    required void Function(String text) onConfirm,
  }) {
    final ctrl = TextEditingController(text: initial);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            AppInputs.textField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final txt = ctrl.text.trim();
                if (txt.isEmpty) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  return;
                }
                onConfirm(txt);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(_Envelope env) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete envelope?'),
        content: Text('This removes “${env.name}”. You can’t undo this.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              setState(() {
                _envelopes.remove(env);
                for (final g in _groups) {
                  g.memberIds.remove(env.id);
                }
              });
              await _saveState();
              CalendarEvents.instance.remove('env:${env.id}');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _transferFrom(_Envelope source) {
    EnvelopeDropdownResult? target;
    final amountCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final items = _envelopes.where((e) => e != source).map((e) {
          final isMine = e.ownerId == FirebaseAuth.instance.currentUser?.uid;
          return DropdownMenuItem<EnvelopeDropdownResult>(
            value: EnvelopeDropdownResult(env: e, isMine: isMine),
            child: Text('${e.name}${isMine ? '' : ' (partner)'}'),
          );
        }).toList();

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSB) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Transfer from ${source.name}',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<EnvelopeDropdownResult>(
                  items: items,
                  value: target,
                  onChanged: (v) => setSB(() => target = v),
                  decoration: const InputDecoration(
                    labelText: 'Target envelope',
                  ),
                ),
                const SizedBox(height: 12),
                AppInputs.textField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    prefixText: '£ ',
                    labelText: 'Amount',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final amt =
                        double.tryParse(amountCtrl.text.replaceAll(',', '')) ??
                        0;
                    if (target == null || amt <= 0) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      return;
                    }
                    setState(() {
                      source.balance = (source.balance - amt).clamp(
                        0,
                        double.infinity,
                      );
                      target!.env.balance += amt;
                    });
                    await _saveState();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Transfer'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===== Models (envelope/group) =====
class _Envelope {
  _Envelope({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.target,
    required this.balance,
    this.groupId,
    this.payDate,
    this.payRepeat = 'None',
    this.payEvery,
    this.resetOnRecurring = false,
    this.lastResetYmd,
  });

  final String id;
  final String ownerId;
  String name;
  double target;
  double balance;
  final String? groupId;

  DateTime? payDate;
  String? payRepeat;
  int? payEvery;

  bool resetOnRecurring;
  String? lastResetYmd;

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'name': name,
    'target': target,
    'balance': balance,
    'groupId': groupId,
    'payDate': payDate == null
        ? null
        : DateTime(
            payDate!.year,
            payDate!.month,
            payDate!.day,
          ).toIso8601String(),
    'payRepeat': payRepeat,
    'payEvery': payEvery,
    'resetOnRecurring': resetOnRecurring,
    'lastResetYmd': lastResetYmd,
  };

  factory _Envelope.fromJson(Map<String, dynamic> m) => _Envelope(
    id: m['id'] as String,
    ownerId: m['ownerId'] as String? ?? 'me',
    name: m['name'] as String? ?? '',
    target: (m['target'] as num?)?.toDouble() ?? 0,
    balance: (m['balance'] as num?)?.toDouble() ?? 0,
    groupId: m['groupId'] as String?,
    payDate: (m['payDate'] as String?) != null
        ? DateTime.tryParse(m['payDate'] as String)
        : null,
    payRepeat: m['payRepeat'] as String? ?? 'None',
    payEvery: (m['payEvery'] as num?)?.toInt(),
    resetOnRecurring: (m['resetOnRecurring'] as bool?) ?? false,
    lastResetYmd: m['lastResetYmd'] as String?,
  );
}

class _Group {
  _Group({required this.id, required this.name, required this.memberIds});

  final String id;
  String name;
  Set<String> memberIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'memberIds': memberIds.toList(),
  };

  factory _Group.fromJson(Map<String, dynamic> m) => _Group(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    memberIds: {...((m['memberIds'] as List<dynamic>? ?? []).cast<String>())},
  );
}

class EnvelopeDropdownResult {
  EnvelopeDropdownResult({required this.env, required this.isMine});
  final _Envelope env;
  final bool isMine;
}

// ===== Group detail page =====
class _GroupDetailScreen extends StatelessWidget {
  const _GroupDetailScreen({required this.group, required this.members});
  final _Group group;
  final List<_Envelope> members;

  @override
  Widget build(BuildContext context) {
    final total = members.fold<double>(0, (s, e) => s + e.balance);
    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: members.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Card(
              child: ListTile(
                title: const Text('Total'),
                trailing: Text(
                  '£${total.toStringAsFixed(2)}',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
            );
          }
          final e = members[i - 1];
          return Card(
            child: ListTile(
              title: Text(e.name),
              subtitle: Text('Target £${e.target.toStringAsFixed(0)}'),
              trailing: Text('£${e.balance.toStringAsFixed(2)}'),
            ),
          );
        },
      ),
    );
  }
}
