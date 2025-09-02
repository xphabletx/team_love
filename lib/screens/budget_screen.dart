// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/services.dart'; // Clipboard

import '../widgets/side_nav_drawer.dart';
import '../services/input_service.dart';
import '../services/calendar_events_service.dart';
import 'envelope_groups_screen.dart';
import 'ledger_screen.dart';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/workspace_session.dart';
import '../services/workspace_service.dart';

// prefs
const _prefsKeyBudgetCats = 'teamlove_budget_categories_v3'; // bumped
const _prefsKeyBudgetIncome = 'teamlove_budget_income_v3';

/// Hook to your ledger. Replace the stub as you wire spending.
class LedgerService {
  LedgerService._();
  static final instance = LedgerService._();

  double sumSpentForCategoryMonth(String categoryId, DateTime monthStart) {
    return 0; // stub – return real spent for this category & month
  }
}

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  // Firestore workspace-scoped storage (optional)
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _wsId; // current workspace id (null => local prefs mode)
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _catsSub;

  bool get _useFirestore => _wsId != null;

  Future<void> _saveIncome() async {
    if (_useFirestore) {
      await _metaDoc.set({
        'monthlyIncome': _monthlyIncome,
      }, SetOptions(merge: true));
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKeyBudgetIncome,
        jsonEncode({'monthlyIncome': _monthlyIncome}),
      );
    }
  }

  Future<void> _upsertCat(BudgetCategory c) async {
    if (!_useFirestore) return;
    await _catsCol.doc(c.id).set(c.toJson(), SetOptions(merge: true));
  }

  Future<void> _deleteCatsByIds(Iterable<String> ids) async {
    if (!_useFirestore) return;
    final batch = _db.batch();
    for (final id in ids) {
      batch.delete(_catsCol.doc(id));
    }
    await batch.commit();
  }

  // Collect ids: id + all descendants (based on current _cats list)
  Set<String> _collectDescendantIds(String id) {
    final out = <String>{};
    void walk(String x) {
      out.add(x);
      for (final k in _childrenOf(x)) {
        walk(k.id);
      }
    }

    walk(id);
    return out;
  }

  // ---- Firestore helpers (valid only when _wsId != null) ----
  CollectionReference<Map<String, dynamic>> get _catsCol =>
      _db.collection('workspaces').doc(_wsId).collection('budgetCategories');

  DocumentReference<Map<String, dynamic>> get _metaDoc =>
      _db.collection('workspaces').doc(_wsId).collection('budget').doc('meta');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final session = WorkspaceSession.of(context);
    final newId = session.workspaceId;

    if (newId == _wsId) return; // nothing changed

    // Tear down old listener if switching workspaces
    _catsSub?.cancel();
    _catsSub = null;
    _wsId = newId;

    if (_wsId == null) {
      // No workspace -> keep local prefs (existing behavior)
      return;
    }

    // --- Firestore mode: live-listen to categories for this workspace ---
    _catsSub = _catsCol.orderBy('name').snapshots().listen((snap) {
      final list = snap.docs
          .map((d) => BudgetCategory.fromJson(d.data()))
          .toList();
      setState(() {
        _cats
          ..clear()
          ..addAll(list);
      });
    });

    // Load meta (monthlyIncome)
    _metaDoc.get().then((doc) {
      final data = doc.data();
      if (data != null) {
        final mi = (data['monthlyIncome'] as num?)?.toDouble() ?? 0.0;
        setState(() {
          _monthlyIncome = mi;
          if (!_incomeFocus.hasFocus) {
            _incomeCtrl.text = mi == 0 ? '' : mi.toStringAsFixed(0);
          }
        });
      }
    });
  }

  // Main tabs: 0=Budget, 1=Ledger, 2=Envelopes, 3=Groups
  final PageController _page = PageController(initialPage: 0);
  int _tab = 0;

  // Use a distinct key per EnvelopeGroupsScreen to avoid duplicate GlobalKey errors.
  final GlobalKey<EnvelopeGroupsScreenState> _egKey1 =
      GlobalKey<EnvelopeGroupsScreenState>(); // for tab 2 (activeChildTab: 1)
  final GlobalKey<EnvelopeGroupsScreenState> _egKey2 =
      GlobalKey<EnvelopeGroupsScreenState>(); // for tab 3 (activeChildTab: 2)

  // ===== Budget state =====
  final List<BudgetCategory> _cats = [];
  final Map<String, bool> _expanded = {};
  double _monthlyIncome = 0;

  // Scrollers (freeze left column, scroll right table)
  final ScrollController _budgetVert = ScrollController();
  final ScrollController _budgetNamesVert = ScrollController();
  final ScrollController _budgetHoriz = ScrollController();

  // Persistent controllers & focus for money fields (avoid cursor jumps)
  final Map<String, TextEditingController> _amountCtrls = {};
  final Map<String, FocusNode> _amountFocus = {};
  final Map<String, Timer?> _moneyDebounce = {};

  // Inputs up top
  late final TextEditingController _incomeCtrl;
  final FocusNode _incomeFocus = FocusNode();
  Timer? _incomeDebounce;

  // Right-side column width (single Amount column)
  static const double _wAmount = 160;
  static const double _kTableWidth = _wAmount;

  // Month context
  DateTime _monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // ===== lifecycle =====
  @override
  void initState() {
    super.initState();
    _incomeCtrl = TextEditingController();

    _loadBudgetPrefs();

    // keep left names + right table in vertical sync
    _budgetVert.addListener(() {
      if (_budgetNamesVert.hasClients &&
          _budgetNamesVert.offset != _budgetVert.offset) {
        _budgetNamesVert.jumpTo(_budgetVert.offset);
      }
    });
    _budgetNamesVert.addListener(() {
      if (_budgetVert.hasClients &&
          _budgetVert.offset != _budgetNamesVert.offset) {
        _budgetVert.jumpTo(_budgetNamesVert.offset);
      }
    });
  }

  @override
  void dispose() {
    _catsSub?.cancel();
    // cancel timers
    _incomeDebounce?.cancel();
    for (final t in _moneyDebounce.values) {
      t?.cancel();
    }

    // dispose focus & controllers
    _incomeFocus.dispose();
    for (final f in _amountFocus.values) f.dispose();
    for (final c in _amountCtrls.values) c.dispose();
    _incomeCtrl.dispose();

    // dispose scroll/page controllers
    _page.dispose();
    _budgetVert.dispose();
    _budgetNamesVert.dispose();
    _budgetHoriz.dispose();

    super.dispose();
  }

  // ===== Helpers / persistence =====
  DateTime _ymd(DateTime d) => DateTime(d.year, d.month, d.day);
  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _loadBudgetPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // income
    final rawIncome = prefs.getString(_prefsKeyBudgetIncome);
    if (rawIncome != null) {
      try {
        final m = jsonDecode(rawIncome) as Map<String, dynamic>;
        _monthlyIncome = (m['monthlyIncome'] as num?)?.toDouble() ?? 0.0;
        if (!_incomeFocus.hasFocus) {
          _incomeCtrl.text = _monthlyIncome == 0
              ? ''
              : _monthlyIncome.toStringAsFixed(0);
        }
      } catch (_) {}
    }

    // categories
    final rawCats = prefs.getString(_prefsKeyBudgetCats);
    if (rawCats != null) {
      try {
        final list = (jsonDecode(rawCats) as List<dynamic>)
            .map((e) => BudgetCategory.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _cats
            ..clear()
            ..addAll(list);
        });
      } catch (_) {}
    } else {
      // Seed your requested sample
      final car = BudgetCategory(id: _newId(), name: 'Car');
      final home = BudgetCategory(id: _newId(), name: 'Home');
      final utilities = BudgetCategory(id: _newId(), name: 'Utilities');
      final envelopes = BudgetCategory(id: _newId(), name: 'Envelopes');
      _cats.addAll([car, home, utilities, envelopes]);

      _cats.addAll([
        BudgetCategory(
          id: _newId(),
          name: 'Insurance',
          parentId: car.id,
          spent: 50,
        ),
        BudgetCategory(
          id: _newId(),
          name: 'Furniture',
          parentId: home.id,
          spent: 75,
        ),
        BudgetCategory(
          id: _newId(),
          name: 'Electricity',
          parentId: utilities.id,
          spent: 100,
        ),
        BudgetCategory(
          id: _newId(),
          name: 'Recreation',
          parentId: envelopes.id,
          spent: 100,
        ),
        BudgetCategory(
          id: _newId(),
          name: 'Birthdays',
          parentId: envelopes.id,
          spent: 25,
        ),
      ]);
      await _saveBudgetPrefs();
    }

    setState(() {});
  }

  Future<void> _saveBudgetPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyBudgetCats,
      jsonEncode(_cats.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      _prefsKeyBudgetIncome,
      jsonEncode({'monthlyIncome': _monthlyIncome}),
    );
  }

  // Tree helpers
  List<BudgetCategory> _roots() =>
      _cats.where((c) => c.parentId == null).toList();
  List<BudgetCategory> _childrenOf(String id) =>
      _cats.where((c) => c.parentId == id).toList();
  bool _isRoot(String id) => _cats.any((c) => c.id == id && c.parentId == null);

  double _sumSpent(String id) {
    final kids = _childrenOf(id);
    if (kids.isEmpty) {
      // Manual amount for leaf. Swap for LedgerService when wired.
      return _cats.firstWhere((e) => e.id == id).spent ?? 0.0;
      // Or: return LedgerService.instance.sumSpentForCategoryMonth(id, _monthStart);
    }
    double total = 0;
    for (final k in kids) {
      total += _sumSpent(k.id);
    }
    return total;
  }

  // Summary numbers
  double get _totalOutgoings {
    double total = 0;
    for (final r in _roots()) {
      total += _sumSpent(r.id);
    }
    return total;
  }

  double get _remaining => (_monthlyIncome) - _totalOutgoings;

  // Month nav
  void _shiftMonth(int delta) {
    setState(() {
      _monthStart = DateTime(_monthStart.year, _monthStart.month + delta, 1);
    });
  }

  String _monthLabel(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  // ===== Add / Edit / Delete =====
  Future<void> _addRootCategory() async {
    await _editCategory(parentId: null);
  }

  Future<void> _addSubCategory(String parentId) async {
    // Enforce 2 levels only (parents are roots)
    if (!_isRoot(parentId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only one level of subcategories is allowed.'),
        ),
      );
      return;
    }
    await _editCategory(parentId: parentId);
  }

  Future<void> _editCategory({
    String? parentId,
    BudgetCategory? existing,
  }) async {
    final isParent = existing == null
        ? (parentId == null)
        : (existing.parentId == null);

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final amountCtrl = TextEditingController(
      text: (!isParent ? (existing?.spent ?? 0) : 0).toStringAsFixed(0),
    );

    DateTime? startDate = existing?.startDate;
    bool recurring = (existing?.repeat ?? 'None') != 'None';
    String repeatUnit = existing?.repeat ?? 'Monthly';
    const allowedRepeats = ['Daily', 'Weekly', 'Monthly', 'Yearly'];
    if (!allowedRepeats.contains(repeatUnit)) repeatUnit = 'Monthly';
    final everyCtrl = TextEditingController(
      text: (existing?.every ?? 1).toString(),
    );

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
                existing == null ? 'Add category' : 'Edit category',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              AppInputs.textField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: isParent ? 'Main category name' : 'Subcategory',
                ),
              ),
              const SizedBox(height: 12),
              if (!isParent) // children only
                AppInputs.textField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixText: '£ ',
                    labelText: 'Amount per month',
                  ),
                ),
              const SizedBox(height: 12),
              if (!isParent) // children only: schedule/recurring
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event),
                        label: Text(
                          startDate == null
                              ? 'Set start date (optional)'
                              : '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}',
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
                              () => startDate = DateTime(
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
              if (!isParent) ...[
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
                          DropdownMenuItem(
                            value: 'Weekly',
                            child: Text('weeks'),
                          ),
                          DropdownMenuItem(
                            value: 'Monthly',
                            child: Text('months'),
                          ),
                          DropdownMenuItem(
                            value: 'Yearly',
                            child: Text('years'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final name = AppInputs.toTitleCase(nameCtrl.text.trim());
                  if (name.isEmpty) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    return;
                  }

                  final amount = !isParent
                      ? double.tryParse(amountCtrl.text.replaceAll(',', ''))
                      : null;
                  final every = int.tryParse(everyCtrl.text) ?? 1;

                  if (existing == null) {
                    final cat = BudgetCategory(
                      id: _newId(),
                      name: name,
                      parentId: parentId,
                      spent: isParent ? null : amount,
                      startDate: isParent ? null : startDate,
                      repeat: isParent
                          ? 'None'
                          : (startDate != null && recurring
                                ? repeatUnit
                                : 'None'),
                      every: isParent
                          ? 1
                          : (startDate != null && recurring ? every : 1),
                    );
                    setState(() => _cats.add(cat));
                    if (_wsId != null) {
                      await _catsCol.doc(cat.id).set(cat.toJson());
                    } else {
                      await _saveBudgetPrefs();
                    }

                    // Mirror to Calendar for children only
                    if (cat.parentId != null &&
                        cat.startDate != null &&
                        cat.repeat != 'None') {
                      CalendarEvents.instance.upsert(
                        CalEvent(
                          id: 'budgetcat:${cat.id}',
                          title: 'Budget: ${cat.name}',
                          date: _ymd(cat.startDate!),
                          repeat: cat.repeat,
                          every: cat.every,
                          reminder: 'None',
                          meta: {'budgetCategoryId': cat.id},
                        ),
                      );
                    }
                  } else {
                    existing.name = name;
                    if (!isParent) {
                      existing.spent = amount;
                      existing.startDate = startDate;
                      existing.repeat = (startDate != null && recurring)
                          ? repeatUnit
                          : 'None';
                      existing.every = (startDate != null && recurring)
                          ? every
                          : 1;
                    } else {
                      // parent: strip schedule just in case
                      existing.spent = null;
                      existing.startDate = null;
                      existing.repeat = 'None';
                      existing.every = 1;
                    }

                    setState(() {});
                    await _saveBudgetPrefs();

                    if (existing.parentId != null &&
                        existing.startDate != null &&
                        existing.repeat != 'None') {
                      CalendarEvents.instance.upsert(
                        CalEvent(
                          id: 'budgetcat:${existing.id}',
                          title: 'Budget: ${existing.name}',
                          date: _ymd(existing.startDate!),
                          repeat: existing.repeat,
                          every: existing.every,
                          reminder: 'None',
                          meta: {'budgetCategoryId': existing.id},
                        ),
                      );
                    } else {
                      CalendarEvents.instance.remove(
                        'budgetcat:${existing.id}',
                      );
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(existing == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteCategory(BudgetCategory cat) async {
    void rm(String id) {
      final kids = _childrenOf(id);
      for (final k in kids) {
        rm(k.id);
      }
      _cats.removeWhere((c) => c.id == id);
      _expanded.remove(id);
      CalendarEvents.instance.remove('budgetcat:$id');
    }

    final dcount = _descendantCount(cat.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          dcount == 0
              ? 'Delete “${cat.name}”?'
              : 'Delete “${cat.name}” and $dcount subcategor${dcount == 1 ? 'y' : 'ies'}?',
        ),
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

    if (ok == true) {
      setState(() => rm(cat.id));
      final idsToDelete = _collectDescendantIds(cat.id);
      await _saveBudgetPrefs();
      await _deleteCatsByIds(idsToDelete);
    }
  }

  // Bulk delete support
  void _startBudgetDeleteMode() {
    setState(() {
      _budgetDeleteMode = true;
      _budgetSelected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Select items to delete. Use the red FAB to confirm, or back to cancel.',
        ),
      ),
    );
  }

  void _cancelBudgetDeleteMode() {
    setState(() {
      _budgetDeleteMode = false;
      _budgetSelected.clear();
    });
  }

  int _descendantCount(String id) {
    int count = 0;
    final kids = _childrenOf(id);
    for (final k in kids) {
      count += 1 + _descendantCount(k.id);
    }
    return count;
  }

  Future<void> _confirmDeleteSelected() async {
    if (_budgetSelected.isEmpty) {
      _cancelBudgetDeleteMode();
      return;
    }

    // build set: selected + all descendants
    final toDelete = <String>{};
    for (final id in _budgetSelected) {
      void addAll(String x) {
        toDelete.add(x);
        for (final k in _childrenOf(x)) {
          addAll(k.id);
        }
      }

      addAll(id);
    }

    int parentsWithKids = 0;
    int totalKids = 0;
    for (final id in _budgetSelected) {
      final c = _childrenOf(id);
      if (c.isNotEmpty) {
        parentsWithKids++;
        totalKids += _descendantCount(id);
      }
    }

    final msg = parentsWithKids == 0
        ? 'Delete ${toDelete.length} item(s)?'
        : 'Delete ${toDelete.length} item(s)?\n\n'
              'Includes $parentsWithKids main categor${parentsWithKids == 1 ? 'y' : 'ies'} '
              'with $totalKids subcategor${totalKids == 1 ? 'y' : 'ies'}.';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text(msg),
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

    setState(() {
      _cats.removeWhere((c) => toDelete.contains(c.id));
      for (final id in toDelete) {
        _expanded.remove(id);
        CalendarEvents.instance.remove('budgetcat:$id');
      }
      _budgetDeleteMode = false;
      _budgetSelected.clear();
    });
    await _saveBudgetPrefs();
    await _deleteCatsByIds(toDelete);
  }

  // ===== UI bits =====

  double _nameColWidth() {
    // Longest root name, clamped to ~12 chars (two lines max visual width)
    final roots = _roots();
    if (roots.isEmpty) return 200;
    int maxLen = roots
        .map((e) => math.min(12, e.name.length))
        .fold<int>(0, math.max);
    // 16px per char-ish + padding + affordance room
    final w = 16.0 * maxLen + 28.0 + 20.0;
    return w.clamp(160.0, 260.0);
  }

  TextEditingController _ctrlFor(
    Map<String, TextEditingController> bag,
    String key,
    String initial,
  ) {
    if (!bag.containsKey(key)) bag[key] = TextEditingController(text: initial);
    return bag[key]!;
  }

  Widget _moneyFieldDense({
    required TextEditingController controller,
    required ValueChanged<double> onChanged,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 36),
      child: TextField(
        controller: controller,
        maxLines: 1,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.left,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          prefixText: '£ ',
        ),
        onChanged: (s) =>
            onChanged(double.tryParse(s.replaceAll(',', '')) ?? 0),
      ),
    );
  }

  Widget _budgetSummaryBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                _monthLabel(_monthStart),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                onPressed: () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          SizedBox(
            width: 220,
            child: AppInputs.textField(
              controller: _incomeCtrl,
              focusNode: _incomeFocus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixText: '£ ',
                labelText: 'Monthly income',
              ),
              onChanged: (v) {
                _incomeDebounce?.cancel();
                _monthlyIncome = double.tryParse(v.replaceAll(',', '')) ?? 0.0;
                _incomeDebounce = Timer(
                  const Duration(milliseconds: 250),
                  () async {
                    await _saveIncome();
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
          ),
          _pill('Outgoings', _totalOutgoings),
          _pill('Remaining', _remaining, isWarning: _remaining < 0),
        ],
      ),
    );
  }

  Widget _pill(String label, double value, {bool isWarning = false}) {
    final color = isWarning
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final txt = isWarning
        ? Theme.of(context).colorScheme.onErrorContainer
        : Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontWeight: FontWeight.w600, color: txt),
          ),
          Text(
            '£${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: txt,
            ),
          ),
        ],
      ),
    );
  }

  Widget _budgetHeaderRow() {
    final nameW = _nameColWidth();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          // Frozen Category header
          SizedBox(
            width: nameW,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Category',
                style: Theme.of(context).textTheme.labelLarge,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),

          // Right header – scrolls with body (shared controller)
          Expanded(
            child: SingleChildScrollView(
              controller: _budgetHoriz,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: _kTableWidth,
                child: Row(
                  children: const [
                    SizedBox(
                      width: _wAmount,
                      child: Text(
                        'Amount',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_RowData> _buildBudgetRows() {
    final rows = <_RowData>[];

    void walk(BudgetCategory c, int depth) {
      final kids = _childrenOf(c.id);
      final isParent = _isRoot(c.id);
      final showKids = _expanded[c.id] ?? true;

      final spent = _sumSpent(c.id);

      rows.add(
        _RowData(cat: c, depth: depth, isParent: isParent, amount: spent),
      );

      if (isParent && showKids) {
        for (final k in kids) {
          walk(k, depth + 1);
        }
      }
    }

    for (final r in _roots()) {
      walk(r, 0);
    }
    return rows;
  }

  Widget _budgetLeftColumn(List<_RowData> rows) {
    final nameW = _nameColWidth();
    return SizedBox(
      width: nameW,
      child: ListView.builder(
        controller: _budgetNamesVert,
        itemCount: rows.length,
        itemBuilder: (ctx, i) {
          final r = rows[i];

          // NEW: treat “parent-ness” visually by root status, not by having kids.
          final isRoot = _isRoot(r.cat.id);
          final expanded = _expanded[r.cat.id] ?? true;
          final indent = r.depth * 16.0;
          final hasKids = _childrenOf(r.cat.id).isNotEmpty;

          return InkWell(
            onLongPress: () => _onLongPressCategory(r.cat, isRoot),
            child: Container(
              height: 48,
              padding: EdgeInsets.only(left: 12 + indent, right: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(ctx).dividerColor.withOpacity(0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: hasKids && !_budgetDeleteMode
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              expanded ? Icons.expand_less : Icons.expand_more,
                            ),
                            onPressed: () =>
                                setState(() => _expanded[r.cat.id] = !expanded),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: Text(
                      r.cat.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: TextStyle(
                        fontWeight: isRoot ? FontWeight.w700 : FontWeight.w400,
                        fontSize: isRoot ? 16 : 14,
                      ),
                    ),
                  ),
                  // Always allow adding a subcategory to a ROOT, even if it has none yet.
                  if (isRoot && !_budgetDeleteMode)
                    IconButton(
                      tooltip: 'Add subcategory',
                      icon: const Icon(Icons.add),
                      onPressed: () => _addSubCategory(r.cat.id),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _onLongPressCategory(BudgetCategory c, bool isRoot) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (!isRoot)
              ListTile(
                leading: const Icon(Icons.tune_outlined),
                title: const Text('Edit (amount/recurring)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editCategory(existing: c);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _renameCategory(c);
              },
            ),
            if (isRoot)
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add subcategory'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addSubCategory(c.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCategory(c);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _renameCategory(BudgetCategory c) {
    final ctrl = TextEditingController(text: c.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: AppInputs.textField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final v = ctrl.text.trim();
              if (v.isEmpty) {
                Navigator.pop(ctx);
                return;
              }
              setState(() => c.name = AppInputs.toTitleCase(v));
              await _saveBudgetPrefs();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _budgetRightTable(List<_RowData> rows) {
    return SingleChildScrollView(
      controller: _budgetHoriz,
      primary: false,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: _kTableWidth,
        child: ListView.builder(
          controller: _budgetVert,
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final r = rows[i];
            final isParent = r.isParent;

            return Container(
              height: 48,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(ctx).dividerColor.withOpacity(0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Amount (leaf editable; parent shows aggregate)
                  SizedBox(
                    width: _wAmount,
                    child: isParent
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '£${r.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : _moneyFieldDense(
                            controller: _ctrlFor(
                              _amountCtrls,
                              r.cat.id,
                              r.amount == 0 ? '' : r.amount.toStringAsFixed(2),
                            ),
                            onChanged: (v) async {
                              r.cat.spent = v;
                              setState(() {});
                              if (_useFirestore) {
                                await _upsertCat(r.cat);
                              } else {
                                await _saveBudgetPrefs();
                              }
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBudgetPage() {
    final rows = _buildBudgetRows();
    final nameW = _nameColWidth();

    return Column(
      children: [
        _budgetSummaryBar(),
        _budgetHeaderRow(),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: nameW, child: _budgetLeftColumn(rows)),
              Expanded(child: _budgetRightTable(rows)),
            ],
          ),
        ),
      ],
    );
  }

  // ===== CSV export (still works; Amount-only now) =====
  Future<void> _exportCsv({required bool shareAfter}) async {
    final buffer = StringBuffer();
    buffer.writeln('Month,Category,Amount');
    for (final r in _buildBudgetRows()) {
      buffer.writeln(
        '${_monthLabel(_monthStart)},'
        '"${r.cat.name.replaceAll('"', '""')}",'
        '${r.amount.toStringAsFixed(2)}',
      );
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/budget_${_monthStart.year}_${_monthStart.month.toString().padLeft(2, '0')}.csv',
    );
    await file.writeAsString(buffer.toString());
    if (shareAfter) {
      await Share.shareXFiles([XFile(file.path)], text: 'Budget export');
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Exported: ${file.path}')));
      }
    }
  }

  // ===== Build =====
  bool _budgetDeleteMode = false;
  final Set<String> _budgetSelected = <String>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: [WorkspaceInviteAction()],
      ),
      drawer: const SideNavDrawer(),
      body: PageView(
        controller: _page,
        onPageChanged: (i) => setState(() => _tab = i),
        children: [
          LedgerScreen(
            monthStart: _monthStart,
            monthlyIncome: _monthlyIncome,
            rows: _buildBudgetRows(),
          ),
          _buildBudgetPage(),
          EnvelopeGroupsScreen(key: _egKey1, activeChildTab: 1), // tab index 2
          EnvelopeGroupsScreen(key: _egKey2, activeChildTab: 2), // tab index 3
        ],
      ),

      // FAB per tab
      floatingActionButton: _tab == 1
          ? (_budgetDeleteMode
                ? FloatingActionButton.extended(
                    onPressed: _confirmDeleteSelected,
                    backgroundColor: Colors.red,
                    icon: const Icon(Icons.delete),
                    label: Text(
                      _budgetSelected.isEmpty
                          ? 'Delete selected'
                          : 'Delete (${_budgetSelected.length})',
                    ),
                  )
                : FloatingActionButton(
                    onPressed: _openBudgetFabSheet,
                    child: const Icon(Icons.add),
                  ))
          : (_tab == 2
                ? _egKey1.currentState?.buildFab()
                : _tab == 3
                ? _egKey2.currentState?.buildFab()
                : null),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: SegmentedButton<int>(
            showSelectedIcon: false, // no checkmark overlay
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.receipt_long)),
              ButtonSegment(value: 1, icon: Icon(Icons.calculate_outlined)),
              ButtonSegment(value: 2, icon: Icon(Icons.mail_outline)),
              ButtonSegment(value: 3, icon: Icon(Icons.dashboard_outlined)),
            ],
            selected: {_tab},
            onSelectionChanged: (s) {
              final i = s.first;
              setState(() => _tab = i);
              _page.animateToPage(
                i,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              );
            },
          ),
        ),
      ),
    );
  }

  // FAB options (Budget)
  void _openBudgetFabSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Add main budget category'),
              onTap: () {
                Navigator.pop(ctx);
                _addRootCategory();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete items'),
              onTap: () {
                Navigator.pop(ctx);
                _startBudgetDeleteMode();
              },
            ),
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Export CSV (file only)'),
              onTap: () {
                Navigator.pop(ctx);
                _exportCsv(shareAfter: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Export & send CSV'),
              onTap: () {
                Navigator.pop(ctx);
                _exportCsv(shareAfter: true);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Models =====
class BudgetCategory {
  BudgetCategory({
    required this.id,
    required this.name,
    this.parentId,
    this.spent,
    this.startDate,
    this.repeat = 'None',
    this.every = 1,
  });

  final String id;
  String name;
  String? parentId;
  double? spent;

  DateTime? startDate;
  String repeat; // None/Daily/Weekly/Monthly/Yearly
  int every; // repeat every N units

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'spent': spent,
    'startDate': startDate?.toIso8601String(),
    'repeat': repeat,
    'every': every,
  };

  factory BudgetCategory.fromJson(Map<String, dynamic> m) => BudgetCategory(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    parentId: m['parentId'] as String?,
    spent: (m['spent'] as num?)?.toDouble(),
    startDate: (m['startDate'] as String?) != null
        ? DateTime.tryParse(m['startDate'] as String)
        : null,
    repeat: m['repeat'] as String? ?? 'None',
    every: (m['every'] as num?)?.toInt() ?? 1,
  );
}

// Internal row model for rendering
class _RowData {
  _RowData({
    required this.cat,
    required this.depth,
    required this.isParent,
    required this.amount,
  });

  final BudgetCategory cat;
  final int depth;
  final bool isParent;
  final double amount;
}

class WorkspaceInviteAction extends StatelessWidget {
  const WorkspaceInviteAction({super.key});

  @override
  Widget build(BuildContext context) {
    final session = WorkspaceSession.of(context);
    final wsId = session.workspaceId;

    // No workspace → nothing to show.
    if (wsId == null) return const SizedBox.shrink();

    return StreamBuilder<WorkspaceLite?>(
      stream: WorkspaceService.instance.watchWorkspace(wsId),
      builder: (context, snap) {
        final ws = snap.data;
        if (ws == null) {
          return const SizedBox.shrink();
        }

        // Normalize nullable joinCode to a non-null String
        final join = ws.joinCode ?? '';

        return PopupMenuButton<String>(
          tooltip: 'Workspace',
          onSelected: (value) async {
            if (value == 'copy') {
              await Clipboard.setData(ClipboardData(text: join));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Join code copied')),
                );
              }
            } else if (value == 'share') {
              await Share.share('Join my Team Love workspace: $join');
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                ws.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'copy',
              child: Row(
                children: [
                  const Icon(Icons.copy, size: 18),
                  const SizedBox(width: 8),
                  Text('Copy join code (${join.isEmpty ? 'none' : join})'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'share',
              child: Row(
                children: const [
                  Icon(Icons.ios_share, size: 18),
                  SizedBox(width: 8),
                  Text('Share join code'),
                ],
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              avatar: const Icon(Icons.groups_outlined, size: 18),
              label: Text(ws.name, overflow: TextOverflow.ellipsis),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        );
      },
    );
  }
}
