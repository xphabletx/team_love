// lib/screens/account_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/side_nav_drawer.dart';
import '../services/username_service.dart';
import '../services/ledger_service.dart';
import '../services/calendar_events_service.dart';
import '../models/account.dart';
import '../models/income_schedule.dart';
import '../services/auth_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final newUsernameCtrl = TextEditingController();
  bool busy = false;
  String? message;

  // Data
  List<Account> _accounts = [];
  List<IncomeSchedule> _incomes = [];

  // Include/exclude per account for totals (stored locally)
  Map<String, bool> _includeInTotals = {};

  final _svc = LedgerService.instance;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    newUsernameCtrl.dispose();
    super.dispose();
  }

  // -------------------- LOAD/SAVE HELPERS --------------------

  Future<void> _refresh() async {
    final acc = await _svc.listAccounts();
    final inc = await _svc.listIncomeSchedules();
    final include = await _loadIncludePrefs(acc);
    if (!mounted) return;
    setState(() {
      _accounts = acc;
      _incomes = inc;
      _includeInTotals = include;
    });
  }

  Future<Map<String, bool>> _loadIncludePrefs(List<Account> accs) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('_acct_include_totals_v1') ?? [];
    final map = <String, bool>{};
    for (final s in raw) {
      final parts = s.split('|');
      if (parts.length == 2) {
        map[parts[0]] = parts[1] == '1';
      }
    }
    for (final a in accs) {
      map.putIfAbsent(a.id, () => true);
    }
    await _saveIncludePrefs(map);
    return map;
  }

  Future<void> _saveIncludePrefs(Map<String, bool> m) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = m.entries
        .map((e) => '${e.key}|${e.value ? '1' : '0'}')
        .toList();
    await prefs.setStringList('_acct_include_totals_v1', raw);
  }

  // -------------------- PROFILE EDIT --------------------
  Future<void> _updateDisplayName() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final ctrl = TextEditingController(text: u.displayName ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update display name'),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final name = ctrl.text.trim();
    await u.updateDisplayName(name);
    await u.reload(); // refresh local auth user
    if (mounted) setState(() {});
  }

  // Last weekday-of-month helper (Mon–Fri)
  DateTime _lastWeekdayOfMonth(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0);
    switch (lastDay.weekday) {
      case DateTime.saturday:
        return lastDay.subtract(const Duration(days: 1));
      case DateTime.sunday:
        return lastDay.subtract(const Duration(days: 2));
      default:
        return lastDay;
    }
  }

  double get _displayedTotalBalance {
    double total = 0;
    for (final a in _accounts) {
      final include = _includeInTotals[a.id] ?? true;
      if (include) total += a.balance;
    }
    return total;
  }

  Future<void> _toggleInclude(Account a, bool include) async {
    setState(() => _includeInTotals[a.id] = include);
    await _saveIncludePrefs(_includeInTotals);
  }

  // -------------------- USERNAME --------------------

  Future<void> _changeUsername() async {
    final newU = newUsernameCtrl.text.trim();
    if (newU.isEmpty) {
      setState(() => message = 'Enter a username.');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final email = FirebaseAuth.instance.currentUser?.email;
      if (email == null) {
        setState(() => message = 'Not signed in.');
        return;
      }
      await UsernameService.instance.claimUsername(
        username: newU,
        email: email,
      );
      setState(() => message = 'Username updated!');
    } on FormatException catch (e) {
      setState(() => message = e.message);
    } on StateError catch (e) {
      setState(() => message = e.message);
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      setState(() => busy = false);
    }
  }

  // -------------------- ACCOUNTS UI --------------------

  Future<void> _addOrEditAccount({Account? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final balCtrl = TextEditingController(
      text: existing == null ? '' : existing.balance.toStringAsFixed(2),
    );

    bool include = existing == null
        ? true
        : (_includeInTotals[existing.id] ?? true);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                existing == null ? 'Add account' : 'Edit account',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Account name'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Current balance',
                  prefixText: '£ ',
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include in totals'),
                value: include,
                onChanged: (v) => setSB(() => include = v),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final bal =
                      double.tryParse(balCtrl.text.replaceAll(',', '')) ?? 0;
                  if (name.isEmpty) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    return;
                  }
                  final list = [..._accounts];
                  if (existing == null) {
                    final id = DateTime.now().microsecondsSinceEpoch.toString();
                    list.add(Account(id: id, name: name, balance: bal));
                    await _svc.saveAccounts(list);
                    _includeInTotals[id] = include;
                    await _saveIncludePrefs(_includeInTotals);
                  } else {
                    existing.name = name;
                    existing.balance = bal;
                    await _svc.saveAccounts(list);
                    _includeInTotals[existing.id] = include;
                    await _saveIncludePrefs(_includeInTotals);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _refresh();
                },
                child: Text(existing == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount(Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text('Delete “${a.name}”? This does not remove transactions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final list = [..._accounts]..removeWhere((x) => x.id == a.id);
    await _svc.saveAccounts(list);
    _includeInTotals.remove(a.id);
    await _saveIncludePrefs(_includeInTotals);
    _refresh();
  }

  // -------------------- INCOME UI (now calendar-linked) --------------------

  /// Map IncomeFrequency -> Calendar repeat + every
  ({String repeat, int every}) _calRepeatFor(IncomeFrequency f) {
    switch (f) {
      case IncomeFrequency.none:
        return (repeat: 'None', every: 1);
      case IncomeFrequency.weekly:
        return (repeat: 'Weekly', every: 1);
      case IncomeFrequency.biweekly:
        return (repeat: 'Weekly', every: 2);
      case IncomeFrequency.fourWeekly:
        return (repeat: 'Weekly', every: 4);
      case IncomeFrequency.monthly:
        return (repeat: 'Monthly', every: 1);
      case IncomeFrequency.lastWeekdayOfMonth:
        // Stored as Monthly; we’ll tag meta["lastWeekdayOfMonth"]=true
        return (repeat: 'Monthly', every: 1);
    }
  }

  /// Create/Update the calendar event that mirrors an income schedule.
  void _upsertIncomeCalendarEvent({
    required IncomeSchedule inc,
    DateTime? chosenAnchorDate,
  }) {
    final evId = 'income:${inc.id}';
    final map = _calRepeatFor(inc.frequency);

    // Pick a date to anchor the repeat:
    DateTime baseDate;
    final now = DateTime.now();
    if (inc.frequency == IncomeFrequency.none) {
      // ad-hoc: only create an event if user picked an anchor date
      if (chosenAnchorDate == null) {
        // If an ad-hoc income had a previous event, remove it.
        CalendarEvents.instance.remove(evId);
        return;
      }
      baseDate = DateTime(
        chosenAnchorDate.year,
        chosenAnchorDate.month,
        chosenAnchorDate.day,
      );
    } else if (inc.frequency == IncomeFrequency.monthly) {
      final day = inc.anchorDay ?? chosenAnchorDate?.day ?? now.day;
      baseDate = DateTime(now.year, now.month, day);
    } else if (inc.frequency == IncomeFrequency.lastWeekdayOfMonth) {
      // We’ll store as Monthly and mark meta so the calendar service can compute last weekday.
      // Anchor on this month’s last weekday.
      baseDate = _lastWeekdayOfMonth(now.year, now.month);
    } else {
      // weekly/biweekly/fourWeekly: use chosenAnchorDate if provided, otherwise today
      final d = chosenAnchorDate ?? now;
      baseDate = DateTime(d.year, d.month, d.day);
    }

    CalendarEvents.instance.upsert(
      CalEvent(
        id: evId,
        title: 'Income: ${inc.source}',
        date: baseDate,
        repeat: map.repeat,
        every: map.every,
        reminder: 'None',
        meta: {
          'type': 'income',
          'amount': inc.amount,
          if (inc.frequency == IncomeFrequency.lastWeekdayOfMonth)
            'lastWeekdayOfMonth': true,
        },
      ),
    );
  }

  Future<void> _addOrEditIncome({IncomeSchedule? existing}) async {
    final sourceCtrl = TextEditingController(text: existing?.source ?? '');
    final amountCtrl = TextEditingController(
      text: existing == null ? '' : existing.amount.toStringAsFixed(2),
    );

    IncomeFrequency freq = existing?.frequency ?? IncomeFrequency.none;
    int? anchorDay = existing?.anchorDay;
    DateTime? anchorDate; // chosen via calendar

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                existing == null ? 'Add income stream' : 'Edit income stream',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sourceCtrl,
                decoration: const InputDecoration(labelText: 'Source'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount (can be 0.00)',
                  prefixText: '£ ',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<IncomeFrequency>(
                value: freq,
                onChanged: (v) => setSB(() => freq = v ?? IncomeFrequency.none),
                items: const [
                  DropdownMenuItem(
                    value: IncomeFrequency.none,
                    child: Text('Ad-hoc (no schedule)'),
                  ),
                  DropdownMenuItem(
                    value: IncomeFrequency.weekly,
                    child: Text('Weekly'),
                  ),
                  DropdownMenuItem(
                    value: IncomeFrequency.biweekly,
                    child: Text('Every 2 weeks'),
                  ),
                  DropdownMenuItem(
                    value: IncomeFrequency.fourWeekly,
                    child: Text('Every 4 weeks'),
                  ),
                  DropdownMenuItem(
                    value: IncomeFrequency.monthly,
                    child: Text('Monthly (specific date)'),
                  ),
                  DropdownMenuItem(
                    value: IncomeFrequency.lastWeekdayOfMonth,
                    child: Text('Last weekday of month'),
                  ),
                ],
                decoration: const InputDecoration(labelText: 'Frequency'),
              ),
              const SizedBox(height: 12),

              // Anchor date picker (fills anchorDay for monthly & stores chosen date)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(
                    anchorDate != null
                        ? 'Anchor: ${anchorDate!.year}-${anchorDate!.month.toString().padLeft(2, '0')}-${anchorDate!.day.toString().padLeft(2, '0')}'
                        : (anchorDay != null
                              ? 'Anchor day: $anchorDay'
                              : 'Set anchor date (optional)'),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setSB(() {
                        anchorDate = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                        );
                        anchorDay = picked.day; // for monthly schedule logic
                      });
                    }
                  },
                ),
              ),

              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final src = sourceCtrl.text.trim();
                  final amt =
                      double.tryParse(amountCtrl.text.replaceAll(',', '')) ??
                      0.0;
                  if (src.isEmpty) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    return;
                  }
                  final list = [..._incomes];
                  IncomeSchedule target;
                  if (existing == null) {
                    final id = DateTime.now().microsecondsSinceEpoch.toString();
                    target = IncomeSchedule(
                      id: id,
                      source: src,
                      amount: amt,
                      frequency: freq,
                      anchorDay: anchorDay,
                    );
                    list.add(target);
                  } else {
                    existing.source = src;
                    existing.amount = amt;
                    existing.frequency = freq;
                    existing.anchorDay = anchorDay;
                    target = existing;
                  }
                  await _svc.saveIncomeSchedules(list);

                  // 🔗 Mirror into calendar
                  _upsertIncomeCalendarEvent(
                    inc: target,
                    chosenAnchorDate: anchorDate,
                  );

                  if (ctx.mounted) Navigator.pop(ctx);
                  _refresh();
                },
                child: Text(existing == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteIncome(IncomeSchedule inc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete income?'),
        content: Text('Delete “${inc.source}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final list = [..._incomes]..removeWhere((x) => x.id == inc.id);
    await _svc.saveIncomeSchedules(list);

    // 🔗 Remove mirrored calendar event
    CalendarEvents.instance.remove('income:${inc.id}');

    _refresh();
  }

  // -------------------- BUILD --------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      drawer: const SideNavDrawer(),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Inside your AccountScreen build(), near the top of ListView children:
            // Profile header
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                leading: CircleAvatar(
                  child: Builder(
                    builder: (_) {
                      final u = FirebaseAuth.instance.currentUser;
                      final txt = (u?.displayName?.trim().isNotEmpty == true)
                          ? u!.displayName!.trim()[0].toUpperCase()
                          : (u?.email?.trim().isNotEmpty == true
                                ? u!.email![0].toUpperCase()
                                : '?');
                      return Text(txt);
                    },
                  ),
                ),
                title: Builder(
                  builder: (_) {
                    final u = FirebaseAuth.instance.currentUser;
                    return Text(
                      u?.displayName?.isNotEmpty == true
                          ? u!.displayName!
                          : 'No name set',
                    );
                  },
                ),
                subtitle: Builder(
                  builder: (_) {
                    final u = FirebaseAuth.instance.currentUser;
                    return Text(u?.email ?? '—');
                  },
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Edit name',
                      onPressed: _updateDisplayName,
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      tooltip: 'Sign out',
                      onPressed: () => AuthService.instance.signOut(),
                      icon: const Icon(Icons.logout),
                    ),
                  ],
                ),
              ),
            ),
            // Balances
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined),
                const SizedBox(width: 8),
                Text(
                  'Total balance: £${_displayedTotalBalance.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Add account',
                  onPressed: () => _addOrEditAccount(),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_accounts.isEmpty)
              const Text('No accounts yet.')
            else
              ..._accounts.map(
                (a) => ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(a.name),
                  subtitle: Text('£${a.balance.toStringAsFixed(2)}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _addOrEditAccount(existing: a);
                      if (v == 'del') _deleteAccount(a);
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'del', child: Text('Delete')),
                    ],
                  ),
                ),
              ),
            if (_accounts.isNotEmpty) ...[
              const SizedBox(height: 4),
              ..._accounts.map(
                (a) => SwitchListTile(
                  title: Text('Include “${a.name}” in totals'),
                  value: _includeInTotals[a.id] ?? true,
                  onChanged: (v) => _toggleInclude(a, v),
                ),
              ),
            ],

            const Divider(height: 32),

            // Income schedules
            Row(
              children: [
                const Icon(Icons.payments_outlined),
                const SizedBox(width: 8),
                Text('Income', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Add income',
                  onPressed: () => _addOrEditIncome(),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_incomes.isEmpty)
              const Text('No income schedules yet.')
            else
              ..._incomes.map(
                (i) => ListTile(
                  leading: const Icon(Icons.attach_money),
                  title: Text('${i.source} • £${i.amount.toStringAsFixed(2)}'),
                  subtitle: Text(_freqLabel(i)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _addOrEditIncome(existing: i);
                      if (v == 'del') _deleteIncome(i);
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'del', child: Text('Delete')),
                    ],
                  ),
                ),
              ),

            const Divider(height: 32),

            // Username
            Text(
              'Change username',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newUsernameCtrl,
              decoration: const InputDecoration(
                labelText: 'New username',
                helperText: 'a–z, 0–9, . _ - (3–20 chars)',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: busy ? null : _changeUsername,
              child: const Text('Update'),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _freqLabel(IncomeSchedule i) {
    switch (i.frequency) {
      case IncomeFrequency.none:
        return 'Ad-hoc';
      case IncomeFrequency.weekly:
        return 'Weekly';
      case IncomeFrequency.biweekly:
        return 'Every 2 weeks';
      case IncomeFrequency.fourWeekly:
        return 'Every 4 weeks';
      case IncomeFrequency.monthly:
        return 'Monthly${i.anchorDay != null ? ' on ${i.anchorDay}' : ''}';
      case IncomeFrequency.lastWeekdayOfMonth:
        return 'Last weekday of month';
    }
  }
}
