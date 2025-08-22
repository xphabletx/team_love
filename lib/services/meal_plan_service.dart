import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ===== Models ===============================================================

enum MealType { lunch, dinner }

class MealEntry {
  MealEntry({
    required this.userName,
    required this.items,
    this.sharedDinner = false,
    this.ingredientsAdded = 0,
  });

  String userName; // 'you' | 'partner' | etc (future: workspace users)
  List<String> items;
  bool sharedDinner;
  int ingredientsAdded;

  Map<String, dynamic> toJson() => {
    'userName': userName,
    'items': items,
    'sharedDinner': sharedDinner,
    'ingredientsAdded': ingredientsAdded,
  };

  factory MealEntry.fromJson(Map<String, dynamic> m) => MealEntry(
    userName: m['userName'] as String? ?? 'you',
    items: (m['items'] as List<dynamic>? ?? const []).cast<String>().toList(),
    sharedDinner: m['sharedDinner'] as bool? ?? false,
    ingredientsAdded: (m['ingredientsAdded'] as num?)?.toInt() ?? 0,
  );
}

class DayMeals {
  DayMeals({List<MealEntry>? lunch, List<MealEntry>? dinner})
    : lunch = lunch ?? <MealEntry>[],
      dinner = dinner ?? <MealEntry>[];

  final List<MealEntry> lunch;
  final List<MealEntry> dinner;

  Map<String, dynamic> toJson() => {
    'lunch': lunch.map((e) => e.toJson()).toList(),
    'dinner': dinner.map((e) => e.toJson()).toList(),
  };

  factory DayMeals.fromJson(Map<String, dynamic> m) => DayMeals(
    lunch: (m['lunch'] as List<dynamic>? ?? const [])
        .map((e) => MealEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    dinner: (m['dinner'] as List<dynamic>? ?? const [])
        .map((e) => MealEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// ===== Service ==============================================================
/// Single source of truth for the meal plan. Persists to SharedPreferences so
/// hot reloads / app restarts restore automatically.
class MealPlanService extends ChangeNotifier {
  MealPlanService._();
  static final MealPlanService instance = MealPlanService._();

  // Persistence keys
  static const _kState = 'teamlove_meal_plan_state_v1';
  static const _kSuggestions = 'teamlove_meal_suggestions_v1';
  static const _kCalPref = 'teamlove_meal_cal_persistent_v1';

  // In-memory state
  DateTime? _start;
  DateTime? _end;
  final Map<String, DayMeals> _byKey =
      <String, DayMeals>{}; // yyyy-MM-dd -> DayMeals
  final Set<String> _customSuggestions = <String>{};
  bool _addToCalendarPersistent = false;
  bool _loaded = false;

  // Users visible in sheet (replace later with workspace users)
  final List<String> users = const ['you', 'partner'];

  // Public getters
  DateTime? get startDate => _start;
  DateTime? get endDate => _end;
  bool get addToCalendarPersistent => _addToCalendarPersistent;

  /// Returns a read-only copy of the custom suggestions.
  Set<String> get customSuggestions => {..._customSuggestions};

  /// Merge helper for screens that keep a big built-in list.
  /// Pass your monster list; this adds any locally-learned items on top.
  List<String> mergeSuggestions(List<String> builtIn) {
    final seen = <String>{};
    final out = <String>[];
    void addAll(Iterable<String> src) {
      for (final s in src) {
        final v = s.trim();
        if (v.isEmpty) continue;
        final k = v.toLowerCase();
        if (seen.add(k)) out.add(v);
      }
    }

    addAll(builtIn);
    addAll(_customSuggestions);
    return out;
  }

  /// Async one-time load
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kState);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _start = (m['start'] as String?) != null
            ? DateTime.tryParse(m['start'] as String)
            : null;
        _end = (m['end'] as String?) != null
            ? DateTime.tryParse(m['end'] as String)
            : null;
        final days = (m['days'] as Map<String, dynamic>? ?? const {});
        for (final entry in days.entries) {
          _byKey[entry.key] = DayMeals.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      } catch (_) {
        /* ignore bad json */
      }
    }
    _customSuggestions
      ..clear()
      ..addAll(
        (prefs.getStringList(_kSuggestions) ?? const [])
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
      );
    _addToCalendarPersistent = prefs.getBool(_kCalPref) ?? false;

    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'start': _start?.toIso8601String(),
      'end': _end?.toIso8601String(),
      'days': _byKey.map((k, v) => MapEntry(k, v.toJson())),
    });
    await prefs.setString(_kState, data);
    await prefs.setStringList(
      _kSuggestions,
      _customSuggestions.toList()..sort(),
    );
    await prefs.setBool(_kCalPref, _addToCalendarPersistent);
  }

  /// Utility: normalize to yyyy-MM-dd
  String keyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  DayMeals _ensureDay(DateTime date) {
    final k = keyOf(date);
    return _byKey.putIfAbsent(k, () => DayMeals());
  }

  DayMeals day(DateTime date) {
    final k = keyOf(date);
    return _byKey[k] ?? DayMeals();
  }

  /// Create (or replace) the active plan range. Does not wipe existing data
  /// unless you pass wipeOutside=true.
  Future<void> createPlan(
    DateTime start,
    DateTime end, {
    bool wipeOutside = false,
  }) async {
    await ensureLoaded();

    // enforce rules: cannot start before today except allow "today"
    final today = DateTime.now();
    final dayOnly = DateTime(today.year, today.month, today.day);
    if (start.isBefore(dayOnly)) start = dayOnly;

    // clamp max length to 31 days
    if (end.difference(start).inDays > 31) {
      end = start.add(const Duration(days: 31));
    }

    _start = DateTime(start.year, start.month, start.day);
    _end = DateTime(end.year, end.month, end.day);

    if (wipeOutside) {
      final toRemove = <String>[];
      for (final k in _byKey.keys) {
        final d = DateTime.parse(k);
        if (d.isBefore(_start!) || d.isAfter(_end!)) toRemove.add(k);
      }
      for (final k in toRemove) {
        _byKey.remove(k);
      }
    }

    await _save();
    notifyListeners();
  }

  /// Change the range, optionally dropping meals outside the new range.
  Future<void> changePlanRange(
    DateTime start,
    DateTime end, {
    required bool wipeOutside,
  }) async {
    await createPlan(start, end, wipeOutside: wipeOutside);
  }

  /// Remove plan dates + meals
  Future<void> resetPlan() async {
    await ensureLoaded();
    _start = null;
    _end = null;
    _byKey.clear();
    await _save();
    notifyListeners();
  }

  /// Add a meal entry to a date + type
  Future<void> addMeal({
    required DateTime date,
    required MealType type,
    required MealEntry entry,
    Iterable<String> learnedSuggestions = const [],
  }) async {
    await ensureLoaded();
    final dm = _ensureDay(date);
    final list = (type == MealType.lunch) ? dm.lunch : dm.dinner;
    list.add(entry);

    // learn any new items as suggestions
    for (final s in [...entry.items, ...learnedSuggestions]) {
      final t = s.trim();
      if (t.isEmpty) continue;
      _customSuggestions.add(t);
    }

    await _save();
    notifyListeners();
  }

  Future<void> deleteMeal({
    required DateTime date,
    required MealType type,
    required MealEntry entry,
  }) async {
    await ensureLoaded();
    final dm = _ensureDay(date);
    final list = (type == MealType.lunch) ? dm.lunch : dm.dinner;
    list.remove(entry);
    await _save();
    notifyListeners();
  }

  Future<void> incrementIngredientsAdded({
    required DateTime date,
    required MealType type,
    required MealEntry entry,
    int by = 1,
  }) async {
    await ensureLoaded();
    entry.ingredientsAdded += by;
    await _save();
    notifyListeners();
  }

  Future<void> setCalendarPersistent(bool on) async {
    _addToCalendarPersistent = on;
    await _save();
    notifyListeners();
  }

  /// For convenience in UIs that need all dates in range.
  List<DateTime> currentRangeDays() {
    if (_start == null || _end == null) return const [];
    final out = <DateTime>[];
    var d = _start!;
    while (!d.isAfter(_end!)) {
      out.add(d);
      d = d.add(const Duration(days: 1));
    }
    return out;
  }
}
