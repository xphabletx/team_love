// lib/screens/ledger_screen.dart
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../models/budget_snapshot.dart';
import '../models/ledger_entry.dart';
import '../models/income_schedule.dart';
import '../services/ledger_service.dart';

// This matches what BudgetScreen passes (we'll treat it dynamically)
class LedgerRowDTO {
  LedgerRowDTO({
    required this.id,
    required this.name,
    required this.isParent,
    required this.parentId,
    required this.amount,
  });

  final String id;
  final String name;
  final bool isParent;
  final String? parentId;
  final double amount;
}

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({
    super.key,
    required this.monthStart,
    required this.monthlyIncome, // unused in Phase 2, kept for compatibility
    required this.rows, // dynamic _RowData list from BudgetScreen
  });

  final DateTime monthStart;
  final double monthlyIncome;
  final List<dynamic> rows;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen>
    with SingleTickerProviderStateMixin {
  late DateTime _month;
  late String _monthKey;
  int _tab = 0; // 0=Status, 1=Summary, 2=All Tx

  double _balancesTotal = 0;

  BudgetSnapshot? _snapshot;
  StatusTotals? _totals;
  List<LedgerEntry> _entries = [];

  final _svc = LedgerService.instance;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.monthStart.year, widget.monthStart.month, 1);
    _monthKey = _svc.monthKeyFromDate(_month);
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    // Auto-import snapshot if missing AND we have Money rows
    var snap = await _svc.loadSnapshot(_monthKey);
    if (snap == null && widget.rows.isNotEmpty) {
      snap = await _svc.ensureSnapshotForMonth(
        monthKey: _monthKey,
        moneyRows: widget.rows,
      );
    }

    final ent = await _svc.listEntries(monthKey: _monthKey);
    final totals = await _svc.computeStatus(_monthKey);
    final balancesTotal = await _svc.totalBalance();

    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _entries = ent;
      _totals = totals;
      _balancesTotal = balancesTotal; // <-- add double _balancesTotal field
    });
  }

  Future<void> _importFromMoney() async {
    await _svc.createSnapshotFromBudgetRows(widget.rows, _monthKey);
    await _refreshAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Imported current Money into this month.')),
    );
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _monthKey = _svc.monthKeyFromDate(_month);
    });
    _refreshAll();
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

  // ---------- STATUS TAB ----------
  Widget _buildStatus() {
    final snap = _snapshot;
    final totals = _totals;

    return Column(
      children: [
        // Month chooser (responsive; no overflow)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Month controls in a compact Row
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    _monthLabel(_month),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    onPressed: () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),

              // Wallet total chip
              Chip(
                avatar: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                ),
                label: Text('£${_balancesTotal.toStringAsFixed(2)}'),
                visualDensity: VisualDensity.compact,
              ),

              // Import button (only when no snapshot exists)
              if (snap == null)
                FilledButton.tonal(
                  onPressed: _importFromMoney,
                  child: const Text('Import from Money'),
                ),
            ],
          ),
        ),

        // Overview pill — scroll-safe (prevents overflow)
        if (totals != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      'Money in: £${totals.moneyIn.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 16),
                    Text('Money out: £${totals.moneyOut.toStringAsFixed(2)}'),
                    const SizedBox(width: 16),
                    Text('Remaining: £${totals.remaining.toStringAsFixed(2)}'),
                  ],
                ),
              ),
            ),
          ),

        // Body: snapshot tree with % of money in
        Expanded(
          child: snap == null
              ? _emptySnap()
              : _SnapshotTree(snapshot: snap, moneyIn: totals?.moneyIn ?? 0),
        ),
      ],
    );
  }

  Widget _emptySnap() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.topic_outlined, size: 48),
          const SizedBox(height: 8),
          const Text(
            'No snapshot for this month',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text('Import from Money to start'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _importFromMoney,
            child: const Text('Import from Money'),
          ),
        ],
      ),
    );
  }

  // ---------- SUMMARY TAB (skeleton for Phase 2) ----------
  Widget _buildSummary() {
    // To-date uses _entries (actuals). Upcoming would read schedules (later)
    final inSum = _entries
        .where((e) => e.type == LedgerType.income)
        .fold<double>(0, (p, e) => p + e.amount);
    final outSum = _entries
        .where(
          (e) =>
              e.type == LedgerType.payment ||
              e.type == LedgerType.envelopeWithdraw,
        )
        .fold<double>(0, (p, e) => p + e.amount);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                _monthLabel(_month),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                onPressed: () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
              const Spacer(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _pill(context, 'To-date income', inSum),
              _pill(context, 'To-date outgoings', outSum),
              _pill(context, 'To-date net', inSum - outSum),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              Text(
                'To-date entries',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final e in _entries)
                ListTile(
                  dense: true,
                  leading: _typeIcon(e.type),
                  title: Text(_entryTitle(e)),
                  subtitle: Text(e.date),
                  trailing: Text('£${e.amount.toStringAsFixed(2)}'),
                ),
              const SizedBox(height: 16),
              Text(
                'Upcoming (from schedules) — coming next phase',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const ListTile(
                dense: true,
                title: Text('No upcoming items yet'),
                subtitle: Text('Add income schedules in the next step'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- ALL TRANSACTIONS TAB ----------
  Widget _buildAllTx() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                _monthLabel(_month),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                onPressed: () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Add test income',
                onPressed: _addTestIncome,
                icon: const Icon(Icons.add_card),
              ),
              IconButton(
                tooltip: 'Add test payment',
                onPressed: _addTestPayment,
                icon: const Icon(Icons.money_off),
              ),
            ],
          ),
        ),
        Expanded(
          child: _entries.isEmpty
              ? const Center(child: Text('No transactions yet'))
              : ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final e = _entries[i];
                    return ListTile(
                      leading: _typeIcon(e.type),
                      title: Text(_entryTitle(e)),
                      subtitle: Text(e.date),
                      trailing: Text('£${e.amount.toStringAsFixed(2)}'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Demo adders so you can see status move without other screens yet
  Future<void> _addTestIncome() async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final date = DateTime.now();
    final entry = LedgerEntry(
      id: id,
      date:
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      monthKey: _monthKey,
      type: LedgerType.income,
      amount: 1000,
      accountId: 'acct:main',
      note: 'Test income',
    );
    await _svc.addEntry(entry);
    await _refreshAll();
  }

  Future<void> _addTestPayment() async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final date = DateTime.now();
    final entry = LedgerEntry(
      id: id,
      date:
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      monthKey: _monthKey,
      type: LedgerType.payment,
      amount: 42.75,
      categoryId: 'sample',
      accountId: 'acct:main',
      note: 'Test bill',
    );
    await _svc.addEntry(entry);
    await _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 3-way switch (SegmentedButton)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.pie_chart_outline),
                label: Text('Status'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.view_day_outlined),
                label: Text('Summary'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.list_alt_outlined),
                label: Text('All Tx'),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),

        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [_buildStatus(), _buildSummary(), _buildAllTx()],
          ),
        ),
      ],
    );
  }

  // ---------- Utils ----------
  Widget _pill(BuildContext ctx, String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('£${value.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Icon _typeIcon(LedgerType t) {
    switch (t) {
      case LedgerType.income:
        return const Icon(Icons.arrow_downward, color: Colors.green);
      case LedgerType.payment:
        return const Icon(Icons.arrow_upward, color: Colors.red);
      case LedgerType.envelopeDeposit:
        return const Icon(Icons.move_to_inbox);
      case LedgerType.envelopeWithdraw:
        return const Icon(Icons.outbox_outlined);
      case LedgerType.transfer:
        return const Icon(Icons.swap_horiz);
    }
  }

  String _entryTitle(LedgerEntry e) {
    switch (e.type) {
      case LedgerType.income:
        return e.note ?? 'Income';
      case LedgerType.payment:
        return e.note ?? 'Payment';
      case LedgerType.envelopeDeposit:
        return e.note ?? 'Envelope deposit';
      case LedgerType.envelopeWithdraw:
        return e.note ?? 'Envelope withdrawal';
      case LedgerType.transfer:
        return e.note ?? 'Transfer';
    }
  }
}

// ===== Snapshot Tree widget =====
class _SnapshotTree extends StatefulWidget {
  const _SnapshotTree({required this.snapshot, required this.moneyIn});

  final BudgetSnapshot snapshot;
  final double moneyIn;

  @override
  State<_SnapshotTree> createState() => _SnapshotTreeState();
}

class _SnapshotTreeState extends State<_SnapshotTree> {
  final Map<String, bool> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;
    final roots = snap.roots();

    double pctOfIncome(double v) =>
        widget.moneyIn <= 0 ? 0 : (v / widget.moneyIn) * 100;

    return ListView.separated(
      itemCount: roots.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final p = roots[i];
        final kids = snap.childrenOf(p.id);
        final expanded = _expanded[p.id] ?? false;
        final total = snap.sumFor(p.id);
        final pct = pctOfIncome(total);

        return Column(
          children: [
            ListTile(
              onTap: kids.isEmpty
                  ? null
                  : () => setState(() => _expanded[p.id] = !expanded),
              leading: kids.isEmpty
                  ? const SizedBox(width: 24)
                  : Icon(expanded ? Icons.expand_less : Icons.expand_more),
              title: Text(
                p.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('£${total.toStringAsFixed(2)}'),
                  if (widget.moneyIn > 0)
                    Text(
                      '${pct.toStringAsFixed(1)}% of money in',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                ],
              ),
            ),
            if (expanded && kids.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Column(
                  children: [
                    for (final k in kids)
                      ListTile(
                        dense: true,
                        title: Text(k.name),
                        trailing: Builder(
                          builder: (_) {
                            final cAmt = k.amount ?? 0;
                            final pctIncome = pctOfIncome(cAmt);
                            final pctOfParent = total <= 0
                                ? 0
                                : (cAmt / total) * 100;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('£${cAmt.toStringAsFixed(2)}'),
                                if (widget.moneyIn > 0)
                                  Text(
                                    '${pctIncome.toStringAsFixed(1)}% of money in · ${pctOfParent.toStringAsFixed(1)}% of ${p.name}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context).hintColor,
                                        ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
