// lib/models/income_schedule.dart
import 'dart:convert';

enum IncomeFrequency {
  none, // ad-hoc only
  weekly,
  biweekly, // every 2 weeks
  fourWeekly, // every 4 weeks
  monthly,
  lastWeekdayOfMonth,
}

class IncomeSchedule {
  IncomeSchedule({
    required this.id,
    required this.source,
    required this.amount,
    required this.frequency,
    this.anchorDay, // e.g., 28 for monthly date; or weekday index for weekly
    this.note,
  });

  final String id;
  String source;
  double amount;
  IncomeFrequency frequency;
  int? anchorDay; // interpretation depends on frequency
  String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'amount': amount,
    'frequency': frequency.name,
    'anchorDay': anchorDay,
    'note': note,
  };

  factory IncomeSchedule.fromJson(Map<String, dynamic> m) => IncomeSchedule(
    id: m['id'] as String,
    source: (m['source'] as String?) ?? '',
    amount: (m['amount'] as num?)?.toDouble() ?? 0,
    frequency: IncomeFrequency.values.firstWhere(
      (e) => e.name == (m['frequency'] as String? ?? 'none'),
      orElse: () => IncomeFrequency.none,
    ),
    anchorDay: m['anchorDay'] as int?,
    note: m['note'] as String?,
  );

  static List<IncomeSchedule> listFromJson(String raw) {
    final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return data.map(IncomeSchedule.fromJson).toList();
  }

  static String listToJson(List<IncomeSchedule> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }
}
