import 'package:flutter/material.dart';

/// Simple shared calendar event store with recurrence.
/// Later you can back this with Firestore; keep the API the same.
class CalendarEvents extends ChangeNotifier {
  CalendarEvents._();
  static final CalendarEvents instance = CalendarEvents._();

  final List<CalEvent> _events = [];

  List<CalEvent> get events => List.unmodifiable(_events);

  void add(CalEvent e) {
    _events.add(e);
    notifyListeners();
  }

  void upsert(CalEvent e) {
    final i = _events.indexWhere((x) => x.id == e.id);
    if (i == -1) {
      _events.add(e);
    } else {
      _events[i] = e;
    }
    notifyListeners();
  }

  void remove(String id) {
    _events.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  /// Return all events that occur on a given day (considering recurrence).
  List<CalEvent> eventsOn(DateTime day) {
    return _events.where((e) => occursOn(e, day)).toList();
  }

  /// Does a given event occur on the target day?
  bool occursOn(CalEvent e, DateTime day) {
    final start = _asYmd(e.date);
    final target = _asYmd(day);
    if (target.isBefore(start)) return false;
    if (_sameDay(start, target)) return true;
    if (e.repeat == 'None') return false;

    final n = (e.every ?? 1).clamp(1, 10000);

    switch (e.repeat) {
      case 'Daily':
        return start.difference(target).inDays % n == 0
            ? (target.difference(start).inDays % n == 0)
            : (target.difference(start).inDays % n == 0);
      case 'Weekly':
        final days = target.difference(start).inDays;
        return days % (7 * n) == 0;
      case 'Monthly':
        // naive “same day-of-month every n months”
        final months =
            (target.year - start.year) * 12 + (target.month - start.month);
        return months >= 0 && months % n == 0 && start.day == target.day;
      case 'Yearly':
        final years = target.year - start.year;
        return years >= 0 &&
            years % n == 0 &&
            start.month == target.month &&
            start.day == target.day;
      default:
        return false;
    }
  }

  static DateTime _asYmd(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class CalEvent {
  CalEvent({
    required this.id,
    required this.title,
    required this.date,
    this.repeat = 'None', // None, Daily, Weekly, Monthly, Yearly
    this.every = 1, // repeat every N units (defaults to 1)
    this.reminder = 'None',
    this.meta, // optional payload (e.g., envelope id)
  });

  final String id;
  String title;
  DateTime date;
  String repeat;
  int? every;
  String reminder;
  Map<String, dynamic>? meta;

  CalEvent copyWith({
    String? id,
    String? title,
    DateTime? date,
    String? repeat,
    int? every,
    String? reminder,
    Map<String, dynamic>? meta,
  }) {
    return CalEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      repeat: repeat ?? this.repeat,
      every: every ?? this.every,
      reminder: reminder ?? this.reminder,
      meta: meta ?? this.meta,
    );
  }
}
