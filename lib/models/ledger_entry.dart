// lib/models/ledger_entry.dart
import 'dart:convert';

enum LedgerType {
  income,
  payment, // bills / category spend
  envelopeDeposit,
  envelopeWithdraw,
  transfer,
}

class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.date, // ISO (yyyy-MM-dd)
    required this.monthKey, // yyyy-MM
    required this.type,
    required this.amount, // positive numbers
    this.accountId,
    this.categoryId,
    this.envelopeId,
    this.counterAccountId,
    this.note,
  });

  final String id;
  final String date;
  final String monthKey;
  final LedgerType type;
  final double amount;

  final String? accountId;
  final String? categoryId; // Money (budget) category leaf
  final String? envelopeId; // Envelope id
  final String? counterAccountId; // for transfers
  final String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'monthKey': monthKey,
    'type': type.name,
    'amount': amount,
    'accountId': accountId,
    'categoryId': categoryId,
    'envelopeId': envelopeId,
    'counterAccountId': counterAccountId,
    'note': note,
  };

  factory LedgerEntry.fromJson(Map<String, dynamic> m) => LedgerEntry(
    id: m['id'] as String,
    date: m['date'] as String,
    monthKey: m['monthKey'] as String,
    type: LedgerType.values.firstWhere((e) => e.name == (m['type'] as String)),
    amount: (m['amount'] as num).toDouble(),
    accountId: m['accountId'] as String?,
    categoryId: m['categoryId'] as String?,
    envelopeId: m['envelopeId'] as String?,
    counterAccountId: m['counterAccountId'] as String?,
    note: m['note'] as String?,
  );

  static List<LedgerEntry> listFromJson(String raw) {
    final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return data.map(LedgerEntry.fromJson).toList();
  }

  static String listToJson(List<LedgerEntry> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }
}
