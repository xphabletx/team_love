// lib/models/budget_snapshot.dart
import 'dart:convert';

class SnapshotItem {
  SnapshotItem({
    required this.id,
    required this.name,
    this.parentId,
    this.amount, // only set on leaves
  });

  final String id;
  String name;
  String? parentId;
  double? amount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'amount': amount,
  };

  factory SnapshotItem.fromJson(Map<String, dynamic> m) => SnapshotItem(
    id: m['id'] as String,
    name: (m['name'] as String?) ?? '',
    parentId: m['parentId'] as String?,
    amount: (m['amount'] as num?)?.toDouble(),
  );
}

class BudgetSnapshot {
  BudgetSnapshot({
    required this.monthKey, // "YYYY-MM"
    required this.items, // parents + leaves (amount only on leaves)
  });

  final String monthKey;
  final List<SnapshotItem> items;

  Map<String, dynamic> toJson() => {
    'monthKey': monthKey,
    'items': items.map((e) => e.toJson()).toList(),
  };

  factory BudgetSnapshot.fromJson(Map<String, dynamic> m) => BudgetSnapshot(
    monthKey: (m['monthKey'] as String),
    items: ((m['items'] as List?) ?? [])
        .map((e) => SnapshotItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );

  static BudgetSnapshot? tryParse(String? raw) {
    if (raw == null) return null;
    return BudgetSnapshot.fromJson(
      (jsonDecode(raw) as Map).cast<String, dynamic>(),
    );
  }

  static String toRaw(BudgetSnapshot s) => jsonEncode(s.toJson());

  List<SnapshotItem> roots() => items.where((e) => e.parentId == null).toList();
  List<SnapshotItem> childrenOf(String id) =>
      items.where((e) => e.parentId == id).toList();

  double sumFor(String id) {
    final kids = childrenOf(id);
    if (kids.isEmpty) {
      return items.firstWhere((x) => x.id == id).amount ?? 0.0;
    }
    double t = 0;
    for (final k in kids) {
      t += sumFor(k.id);
    }
    return t;
  }

  double get totalOutgoings {
    double t = 0;
    for (final r in roots()) {
      t += sumFor(r.id);
    }
    return t;
  }
}
