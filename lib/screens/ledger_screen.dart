import 'package:flutter/material.dart';

import 'dart:math' as math;

// These match _RowData from budget_screen.dart, but we define a small DTO here
class LedgerRow {
  LedgerRow({
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
    required this.monthlyIncome,
    required this.rows,
  });

  final DateTime monthStart;
  final double monthlyIncome;
  // rows from Budget’s _buildBudgetRows()
  final List<dynamic> rows;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  late DateTime _month;
  final Map<String, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.monthStart.year, widget.monthStart.month, 1);
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

  double get _income => widget.monthlyIncome;

  // Build a flat list we can reason about here
  List<LedgerRow> _flatten() {
    // rows are _RowData(cat, depth, isParent, amount)
    final out = <LedgerRow>[];
    for (final r in widget.rows) {
      out.add(
        LedgerRow(
          id: r.cat.id,
          name: r.cat.name,
          isParent: r.isParent,
          parentId: r.cat.parentId,
          amount: r.amount.toDouble(),
        ),
      );
    }
    return out;
  }

  List<LedgerRow> get _parents => _flatten().where((e) => e.isParent).toList();

  List<LedgerRow> childrenOf(String id) =>
      _flatten().where((e) => e.parentId == id).toList();

  double pctOfIncome(double a) => _income <= 0 ? 0 : (a / _income) * 100;

  @override
  Widget build(BuildContext context) {
    final parents = _parents;
    final total = parents.fold<double>(0, (p, e) => p + e.amount);

    return Column(
      children: [
        // Header: month
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1, 1),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                _monthLabel(_month),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1, 1),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
              const Spacer(),
              Text(
                _income > 0
                    ? 'Income: £${_income.toStringAsFixed(2)}'
                    : 'Income not set',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        // Overview pill
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  'Outgoings: £${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 16),
                Text('Remaining: £${(_income - total).toStringAsFixed(2)}'),
              ],
            ),
          ),
        ),

        // Parent list with expandable children
        Expanded(
          child: ListView.separated(
            itemCount: parents.length,
            separatorBuilder: (_, __) => Divider(height: 1),
            itemBuilder: (ctx, i) {
              final p = parents[i];
              final kids = childrenOf(p.id);
              final expanded = _expanded[p.id] ?? false;
              final pct = pctOfIncome(p.amount);

              return Column(
                children: [
                  ListTile(
                    onTap: kids.isEmpty
                        ? null
                        : () => setState(() => _expanded[p.id] = !expanded),
                    leading: kids.isEmpty
                        ? const SizedBox(width: 24)
                        : Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                          ),
                    title: Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('£${p.amount.toStringAsFixed(2)}'),
                        if (_income > 0)
                          Text(
                            '${pct.toStringAsFixed(1)}% of income',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Theme.of(context).hintColor),
                          ),
                      ],
                    ),
                  ),
                  if (expanded)
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
                                  final pctIncome = pctOfIncome(k.amount);
                                  final pctOfParent = p.amount <= 0
                                      ? 0
                                      : (k.amount / p.amount) * 100;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('£${k.amount.toStringAsFixed(2)}'),
                                      if (_income > 0)
                                        Text(
                                          '${pctIncome.toStringAsFixed(1)}% of income · ${pctOfParent.toStringAsFixed(1)}% of ${p.name}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).hintColor,
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
          ),
        ),
      ],
    );
  }
}
