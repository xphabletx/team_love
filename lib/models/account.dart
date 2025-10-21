// lib/models/account.dart
import 'dart:convert';

class Account {
  Account({
    required this.id,
    required this.name,
    required this.balance, // current balance (user-managed for now)
    this.note,
  });

  final String id;
  String name;
  double balance;
  String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'balance': balance,
    'note': note,
  };

  factory Account.fromJson(Map<String, dynamic> m) => Account(
    id: m['id'] as String,
    name: (m['name'] as String?) ?? '',
    balance: (m['balance'] as num?)?.toDouble() ?? 0,
    note: m['note'] as String?,
  );

  static List<Account> listFromJson(String raw) {
    final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return data.map(Account.fromJson).toList();
  }

  static String listToJson(List<Account> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}
