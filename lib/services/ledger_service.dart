// lib/services/ledger_service.dart
import 'package:shared_preferences/shared_preferences.dart';

import '../models/budget_snapshot.dart';
import '../models/ledger_entry.dart';
import '../models/income_schedule.dart';
import '../models/account.dart';

class LedgerService {
  LedgerService._();
  static final instance = LedgerService._();

  // Prefs keys
  static const _kSnapPrefix = 'teamlove_snapshot_'; // + YYYY-MM
  static const _kEntries = 'teamlove_ledger_entries_v1';
  static const _kIncome = 'teamlove_income_schedules_v1';
  static const _kAccounts = 'teamlove_accounts_v1';

  // ---------- Helpers ----------
  String monthKeyFromDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  // ---------- Snapshots ----------
  Future<BudgetSnapshot?> loadSnapshot(String monthKey) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('$_kSnapPrefix$monthKey');
    return BudgetSnapshot.tryParse(raw);
  }

  Future<void> saveSnapshot(BudgetSnapshot s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('$_kSnapPrefix${s.monthKey}', BudgetSnapshot.toRaw(s));
  }

  Future<BudgetSnapshot> createSnapshotFromBudgetRows(
    List<dynamic> rows,
    String monthKey,
  ) async {
    final parents = <String, SnapshotItem>{};
    final children = <SnapshotItem>[];

    for (final r in rows) {
      final cat = r.cat;
      final id = cat.id as String;
      final name = cat.name as String;
      final parentId = cat.parentId as String?;
      final isParent = r.isParent as bool;
      final amount = (r.amount as num).toDouble();

      if (parentId == null) {
        parents[id] = SnapshotItem(id: id, name: name, parentId: null);
      } else {
        children.add(
          SnapshotItem(id: id, name: name, parentId: parentId, amount: amount),
        );
      }
    }

    final items = <SnapshotItem>[];
    items.addAll(parents.values);
    items.addAll(children);

    final snap = BudgetSnapshot(monthKey: monthKey, items: items);
    await saveSnapshot(snap);
    return snap;
  }

  Future<BudgetSnapshot?> ensureSnapshotForMonth({
    required String monthKey,
    required List<dynamic> moneyRows,
  }) async {
    final existing = await loadSnapshot(monthKey);
    if (existing != null) return existing;
    if (moneyRows.isEmpty) return null;
    return createSnapshotFromBudgetRows(moneyRows, monthKey);
  }

  // ---------- Ledger Entries ----------
  Future<List<LedgerEntry>> listEntries({String? monthKey}) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kEntries);
    if (raw == null) return [];
    final all = LedgerEntry.listFromJson(raw);
    if (monthKey == null) return all;
    return all.where((e) => e.monthKey == monthKey).toList();
  }

  Future<void> addEntry(LedgerEntry e) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kEntries);
    final list = raw == null ? <LedgerEntry>[] : LedgerEntry.listFromJson(raw);
    list.add(e);
    await p.setString(_kEntries, LedgerEntry.listToJson(list));
  }

  // ---------- Income Schedules ----------
  Future<List<IncomeSchedule>> listIncomeSchedules() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kIncome);
    if (raw == null) return [];
    return IncomeSchedule.listFromJson(raw);
  }

  Future<void> saveIncomeSchedules(List<IncomeSchedule> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kIncome, IncomeSchedule.listToJson(list));
  }

  // ---------- Accounts ----------
  Future<List<Account>> listAccounts() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kAccounts);
    if (raw == null) return [];
    return Account.listFromJson(raw);
  }

  Future<void> saveAccounts(List<Account> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccounts, Account.listToJson(list));
  }

  Future<double> totalBalance() async {
    final acc = await listAccounts();
    return acc.fold<double>(0, (p, a) => p + a.balance);
  }

  // ---------- Status totals ----------
  Future<StatusTotals> computeStatus(String monthKey) async {
    final entries = await listEntries(monthKey: monthKey);
    double inSum = 0, outSum = 0;
    for (final e in entries) {
      switch (e.type) {
        case LedgerType.income:
          inSum += e.amount;
          break;
        case LedgerType.payment:
        case LedgerType.envelopeWithdraw:
          outSum += e.amount;
          break;
        case LedgerType.envelopeDeposit:
        case LedgerType.transfer:
          break;
      }
    }
    return StatusTotals(
      moneyIn: inSum,
      moneyOut: outSum,
      remaining: inSum - outSum,
    );
  }
}

class StatusTotals {
  StatusTotals({
    required this.moneyIn,
    required this.moneyOut,
    required this.remaining,
  });

  final double moneyIn;
  final double moneyOut;
  final double remaining;
}
