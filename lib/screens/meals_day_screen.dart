// lib/screens/meals_day_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Updates:
//  • MealEntry now stores an `ingredients` list so we can reuse what you typed.
//  • "Add items to shopping list" now shows a selector with two tabs (Meal /
//    Ingredients), checkboxes, remembers selections while toggling, floating
//    Save button, and a "discard or save" prompt if backing out.
//  • Entry rendering shows meal items as BOLD bullet points.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/input_service.dart';
import '../services/shopping_service.dart';
import '../services/calendar_events_service.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// MealsStore (local, offline-first)
/// ───────────────────────────────────────────────────────────────────────────
class MealsStore {
  MealsStore._();
  static final MealsStore instance = MealsStore._();

  // Legacy week buckets (kept)
  final Map<String, DayMeals> _byDay = {
    for (final d in const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ])
      d: DayMeals(),
  };
  DayMeals day(String dayName) => _byDay[dayName] ??= DayMeals();

  // New by-date storage (yyyy-MM-dd)
  final Map<String, DayMeals> _byDate = <String, DayMeals>{};

  DateTime? planStart; // date-only
  DateTime? planEnd; // date-only

  bool syncToCalendar = false; // persistent opt-in
  List<String> customSuggestions = <String>[];

  // Pref keys
  static const _prefsKeySync = 'teamlove_meals_syncToCalendar_v1';
  static const _prefsKeyCustom = 'teamlove_meals_custom_suggestions_v1';
  static const _prefsKeyWeek = 'teamlove_meals_week_state_v1';
  static const _prefsKeyPlanRange = 'teamlove_meals_plan_range_v1';
  static const _prefsKeyPlanMeals = 'teamlove_meals_plan_meals_v1';

  bool _loaded = false;

  // Helpers
  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
  static String _key(DateTime x) =>
      '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

  DayMeals dayForDate(DateTime date) {
    final k = _key(_d(date));
    return _byDate.putIfAbsent(k, () => DayMeals());
  }

  List<DateTime> get datesInPlan {
    if (planStart == null || planEnd == null) return const [];
    final start = _d(planStart!);
    final end = _d(planEnd!);
    if (end.isBefore(start)) return const [];
    final days = <DateTime>[];
    for (
      var i = 0, cur = start;
      !cur.isAfter(end);
      i++, cur = start.add(Duration(days: i))
    ) {
      days.add(cur);
    }
    return days;
  }

  // Load & save
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    syncToCalendar = prefs.getBool(_prefsKeySync) ?? false;
    customSuggestions = prefs.getStringList(_prefsKeyCustom) ?? const [];

    // Legacy week
    final rawWeek = prefs.getString(_prefsKeyWeek);
    if (rawWeek != null && rawWeek.isNotEmpty) {
      try {
        final obj = jsonDecode(rawWeek) as Map<String, dynamic>;
        _byDay
          ..clear()
          ..addAll(
            obj.map(
              (k, v) =>
                  MapEntry(k, DayMeals.fromJson(v as Map<String, dynamic>)),
            ),
          );
      } catch (_) {}
    }

    // Plan range
    final rawRange = prefs.getString(_prefsKeyPlanRange);
    if (rawRange != null && rawRange.isNotEmpty) {
      try {
        final obj = jsonDecode(rawRange) as Map<String, dynamic>;
        final s = obj['start'] as String?;
        final e = obj['end'] as String?;
        if (s != null && e != null) {
          planStart = DateTime.tryParse(s);
          planEnd = DateTime.tryParse(e);
          if (planStart != null) planStart = _d(planStart!);
          if (planEnd != null) planEnd = _d(planEnd!);
        }
      } catch (_) {}
    }

    // Plan meals
    final rawPlanMeals = prefs.getString(_prefsKeyPlanMeals);
    if (rawPlanMeals != null && rawPlanMeals.isNotEmpty) {
      try {
        final obj = jsonDecode(rawPlanMeals) as Map<String, dynamic>;
        _byDate
          ..clear()
          ..addAll(
            obj.map(
              (k, v) =>
                  MapEntry(k, DayMeals.fromJson(v as Map<String, dynamic>)),
            ),
          );
      } catch (_) {}
    }

    _loaded = true;
  }

  Future<void> _savePlanRange(SharedPreferences prefs) async {
    final data = jsonEncode({
      'start': planStart == null ? null : _key(planStart!),
      'end': planEnd == null ? null : _key(planEnd!),
    });
    await prefs.setString(_prefsKeyPlanRange, data);
  }

  Future<void> saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final weekJson = jsonEncode(_byDay.map((k, v) => MapEntry(k, v.toJson())));
    await prefs.setString(_prefsKeyWeek, weekJson);
    final planJson = jsonEncode(_byDate.map((k, v) => MapEntry(k, v.toJson())));
    await prefs.setString(_prefsKeyPlanMeals, planJson);
    await _savePlanRange(prefs);
    await prefs.setStringList(_prefsKeyCustom, customSuggestions);
    await prefs.setBool(_prefsKeySync, syncToCalendar);
  }

  Future<void> setSyncToCalendar(bool value) async {
    syncToCalendar = value;
    await saveState();
  }

  // Plan editing
  Future<void> setPlan(
    DateTime start,
    DateTime end, {
    bool wipeOld = false,
  }) async {
    start = _d(start);
    end = _d(end);

    final today = _d(DateTime.now());
    if (start.isBefore(today)) {
      throw ArgumentError('Start date cannot be in the past.');
    }
    if (end.isBefore(start)) {
      throw ArgumentError('End date must be after start date.');
    }
    final length = end.difference(start).inDays + 1;
    if (length > 31) {
      throw ArgumentError('Plan cannot exceed 31 days.');
    }

    if (wipeOld) {
      _byDate.clear();
    } else {
      _removeDatesOutsideRange(start, end);
    }

    planStart = start;
    planEnd = end;
    await saveState();
  }

  void _removeDatesOutsideRange(DateTime start, DateTime end) {
    final keysToRemove = <String>[];
    for (final k in _byDate.keys) {
      final parts = k.split('-');
      if (parts.length != 3) continue;
      final d = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      if (d.isBefore(start) || d.isAfter(end)) keysToRemove.add(k);
    }
    for (final k in keysToRemove) {
      _byDate.remove(k);
    }
  }
}

/// Container for a day’s lunch/dinner entries.
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

/// One row user’s meal entry (or shared dinner)
class MealEntry {
  MealEntry({
    required this.userName,
    required this.items,
    this.sharedDinner = false,
    List<String>? ingredients,
  }) : ingredients = ingredients ?? <String>[];

  String userName; // 'you' / 'partner' / '[shared]' via sharedDinner
  final List<String> items; // meal items (displayed as bullets)
  final List<String> ingredients; // ingredient lines you typed earlier
  bool sharedDinner;

  int ingredientsAdded = 0; // count pushed to shopping list

  Map<String, dynamic> toJson() => {
    'userName': userName,
    'items': items,
    'ingredients': ingredients,
    'sharedDinner': sharedDinner,
    'ingredientsAdded': ingredientsAdded,
  };

  factory MealEntry.fromJson(Map<String, dynamic> m) => MealEntry(
    userName: m['userName'] as String? ?? 'you',
    items: (m['items'] as List<dynamic>? ?? const []).cast<String>().toList(),
    ingredients: (m['ingredients'] as List<dynamic>? ?? const [])
        .cast<String>()
        .toList(),
    sharedDinner: m['sharedDinner'] as bool? ?? false,
  )..ingredientsAdded = (m['ingredientsAdded'] as num?)?.toInt() ?? 0;
}

enum MealType { lunch, dinner }

class MealsDayScreen extends StatefulWidget {
  const MealsDayScreen({super.key, required this.date, this.initialAddFor});

  final DateTime date; // edits by date
  final MealType? initialAddFor;

  @override
  State<MealsDayScreen> createState() => _MealsDayScreenState();
}

class _MealsDayScreenState extends State<MealsDayScreen> {
  DayMeals get _day => MealsStore.instance.dayForDate(widget.date);

  String get _title {
    final d = widget.date;
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${w[d.weekday - 1]} ${d.day} ${m[d.month - 1]}';
  }

  // Section expand/collapse
  bool _lunchExpanded = true;
  bool _dinnerExpanded = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await MealsStore.instance.ensureLoaded();
    if (!mounted) return;

    if (widget.initialAddFor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addMeal(isLunch: widget.initialAddFor == MealType.lunch);
      });
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Upsert a calendar event for this date+meal as **all-day** so time is hidden.
  Future<void> _mirrorToCalendar({required bool isLunch}) async {
    final entries = isLunch ? _day.lunch : _day.dinner;
    final items = <String>[];
    for (final e in entries) {
      items.addAll(e.items);
    }
    final text = items.isEmpty ? '—' : items.join(', ');
    final label = text.length > 120
        ? '${text.substring(0, 120).trim()}…'
        : text;

    final id = 'meal:${_dateKey(widget.date)}:${isLunch ? 'lunch' : 'dinner'}';
    final title = '${isLunch ? 'Lunch' : 'Dinner'}: $label';

    CalendarEvents.instance.upsert(
      CalEvent(
        id: id,
        title: title,
        date: DateTime(widget.date.year, widget.date.month, widget.date.day),
        repeat: 'None',
        every: 1,
        reminder: 'None',
        meta: {
          'type': 'meal',
          'mealType': isLunch ? 'lunch' : 'dinner',
          'date': _dateKey(widget.date),
          'allDay': true,
        },
      ),
    );
  }

  void _removeFromCalendar({required bool isLunch}) {
    final id = 'meal:${_dateKey(widget.date)}:${isLunch ? 'lunch' : 'dinner'}';
    CalendarEvents.instance.remove(id);
  }

  // Add / Edit bottom sheet
  Future<void> _addMeal({required bool isLunch}) async {
    await MealsStore.instance.ensureLoaded();
    if (!mounted) return;

    // persistent cal checkbox
    bool syncToCalendar = MealsStore.instance.syncToCalendar;

    // temp buffers while editing
    final mealItems = <String>[];
    final ingItems = <String>[];

    final mealCtrl = TextEditingController();
    final ingCtrl = TextEditingController();
    final mealFocus = FocusNode();
    final ingFocus = FocusNode();

    bool ingredientMode = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (ctx, controller) => ListView(
              controller: controller,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              children: [
                // Title + mode switch
                Row(
                  children: [
                    Text(
                      isLunch ? 'Add Lunch' : 'Add Dinner',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Meal')),
                        ButtonSegment(value: true, label: Text('Ingredients')),
                      ],
                      selected: {ingredientMode},
                      onSelectionChanged: (s) =>
                          setSB(() => ingredientMode = s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (!ingredientMode) ...[
                  // MEAL mode
                  Row(
                    children: [
                      Expanded(
                        child: AppInputs.textField(
                          controller: mealCtrl,
                          focusNode: mealFocus,
                          decoration: const InputDecoration(
                            labelText: 'Add meal item (e.g., Chicken Salad)',
                          ),
                          onChanged: (_) => setSB(() {}),
                          onSubmitted: (_) {
                            final t = mealCtrl.text.trim();
                            if (t.isEmpty) return;
                            setSB(() {
                              mealItems.add(t);
                              mealCtrl.clear();
                              mealFocus.requestFocus();
                            });
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          final t = mealCtrl.text.trim();
                          if (t.isEmpty) return;
                          setSB(() {
                            mealItems.add(t);
                            mealCtrl.clear();
                            mealFocus.requestFocus();
                          });
                        },
                      ),
                    ],
                  ),
                  if (mealItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: mealItems
                            .map(
                              (s) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '•  ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        s,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        softWrap: true,
                                        overflow: TextOverflow.visible,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          setSB(() => mealItems.remove(s)),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ] else ...[
                  // INGREDIENTS mode
                  Row(
                    children: [
                      Expanded(
                        child: AppInputs.textField(
                          controller: ingCtrl,
                          focusNode: ingFocus,
                          decoration: const InputDecoration(
                            labelText: 'Add ingredient (e.g., Romaine Lettuce)',
                          ),
                          onChanged: (_) => setSB(() {}),
                          onSubmitted: (_) {
                            final t = ingCtrl.text.trim();
                            if (t.isEmpty) return;
                            setSB(() {
                              ingItems.add(t);
                              ingCtrl.clear();
                              ingFocus.requestFocus();
                            });
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          final t = ingCtrl.text.trim();
                          if (t.isEmpty) return;
                          setSB(() {
                            ingItems.add(t);
                            ingCtrl.clear();
                            ingFocus.requestFocus();
                          });
                        },
                      ),
                    ],
                  ),
                  if (ingItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: ingItems
                            .map(
                              (s) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '•  ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        s,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        softWrap: true,
                                        overflow: TextOverflow.visible,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          setSB(() => ingItems.remove(s)),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 12),
                // Persistent calendar checkbox
                Row(
                  children: [
                    Checkbox(
                      value: syncToCalendar,
                      onChanged: (v) async {
                        final nv = v ?? false;
                        setSB(() => syncToCalendar = nv);
                        await MealsStore.instance.setSyncToCalendar(nv);
                      },
                    ),
                    const Expanded(child: Text('Add to calendar (persistent)')),
                  ],
                ),
                const SizedBox(height: 6),

                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      final navigator = Navigator.of(ctx);

                      // Merge into existing entry (only if user added meal items/ingredients)
                      final list = isLunch ? _day.lunch : _day.dinner;
                      // find or create entry for 'you'
                      final entry = list.firstWhere(
                        (e) => e.userName == 'you',
                        orElse: () => MealEntry(userName: 'you', items: []),
                      );
                      if (!list.contains(entry)) list.add(entry);

                      if (mealItems.isNotEmpty) {
                        entry.items.addAll(mealItems);
                      }
                      if (ingItems.isNotEmpty) {
                        // Store ingredients with the entry so we can select later
                        entry.ingredients.addAll(ingItems);
                      }

                      // Persist meals & preference
                      await MealsStore.instance.saveState();

                      // Create/Remove calendar event for THIS meal on THIS date.
                      if (syncToCalendar) {
                        await _mirrorToCalendar(isLunch: isLunch);
                      } else {
                        _removeFromCalendar(isLunch: isLunch);
                      }

                      if (mounted) setState(() {});
                      if (navigator.canPop()) navigator.pop();
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    mealCtrl.dispose();
    ingCtrl.dispose();
    mealFocus.dispose();
    ingFocus.dispose();
  }

  // New: selector for sending items to Shopping (checkbox, tabs, remembers)
  Future<void> _addItemsToShoppingSelector(MealEntry entry) async {
    final mealChoices = [...entry.items];
    final ingChoices = [...entry.ingredients];

    // nothing to choose?
    if (mealChoices.isEmpty && ingChoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items yet. Add meal or ingredient lines first.'),
        ),
      );
      return;
    }

    final selected = <String>{};
    bool showIngredients = false;

    bool hasUnsaved() => selected.isNotEmpty;

    Future<bool> confirmDiscard(BuildContext ctx) async {
      if (!hasUnsaved()) return true;
      final ok =
          await showDialog<bool>(
            context: ctx,
            builder: (dctx) => AlertDialog(
              title: const Text('Discard selections?'),
              content: const Text(
                'You have selected items. Save them to the shopping list or discard.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dctx, false),
                  child: const Text('Keep editing'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dctx, true),
                  child: const Text('Discard'),
                ),
              ],
            ),
          ) ??
          false;
      return ok;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) {
          final list = showIngredients ? ingChoices : mealChoices;

          Future<void> onSave() async {
            for (final name in selected) {
              ShoppingService.instance.add(name);
            }
            setState(() {
              entry.ingredientsAdded += selected.length;
            });
            await MealsStore.instance.saveState();
            if (mounted) Navigator.pop(ctx);
          }

          return WillPopScope(
            onWillPop: () async => await confirmDiscard(ctx),
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header + toggle
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Add items to shopping',
                          style: Theme.of(ctx).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        fit: FlexFit.loose,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Meal')),
                            ButtonSegment(
                              value: true,
                              label: Text('Ingredients'),
                            ),
                          ],
                          selected: {showIngredients},
                          onSelectionChanged: (s) =>
                              setSB(() => showIngredients = s.first),
                        ),
                      ),
                    ],
                  ),

                  // The selectable list
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final item = list[i];
                          final checked = selected.contains(item);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) {
                              setSB(() {
                                if (v == true) {
                                  selected.add(item);
                                } else {
                                  selected.remove(item);
                                }
                              });
                            },
                            title: Text(item),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Floating save button
                  Align(
                    alignment: Alignment.center,
                    child: FloatingActionButton.extended(
                      heroTag: 'add_items_save',
                      onPressed: selected.isEmpty ? null : onSave,
                      label: const Text('Save'),
                      icon: const Icon(Icons.check),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        children: [
          _sectionExpansion(
            emoji: '🥗',
            title: 'Lunch',
            expanded: _lunchExpanded,
            onToggle: () => setState(() => _lunchExpanded = !_lunchExpanded),
            onAdd: () => _addMeal(isLunch: true),
            children: _day.lunch.map(_buildEntryTile).toList(),
          ),
          const Divider(height: 0),
          _sectionExpansion(
            emoji: '🍽️',
            title: 'Dinner',
            expanded: _dinnerExpanded,
            onToggle: () => setState(() => _dinnerExpanded = !_dinnerExpanded),
            onAdd: () => _addMeal(isLunch: false),
            children: _day.dinner.map(_buildEntryTile).toList(),
          ),
          const SizedBox(height: 96),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Text('🖼️', style: TextStyle(fontSize: 22)),
                    title: const Text('Add image (gallery/camera/link)'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImageForDay();
                    },
                  ),
                  ListTile(
                    leading: const Text('📦', style: TextStyle(fontSize: 22)),
                    title: const Text('Scan barcode (Open Food Facts)'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _scanBarcodeForDay();
                    },
                  ),
                ],
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _sectionExpansion({
    required String emoji,
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required VoidCallback onAdd,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Text(emoji, style: const TextStyle(fontSize: 26)),
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Add $title item',
                  icon: const Icon(Icons.add),
                  onPressed: onAdd,
                ),
                IconButton(
                  tooltip: expanded ? 'Collapse' : 'Expand',
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                  onPressed: onToggle,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 160),
            firstChild: Column(children: children),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryTile(MealEntry e) {
    // Bullet list (bold) of meal items
    final bullets = e.items.isEmpty
        ? const [Text('—')]
        : e.items
              .map(
                (s) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '•  ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Text(
                        s,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )
              .toList();

    final subBits = <String>[];
    if (e.sharedDinner) subBits.add('[shared]');
    if (e.ingredients.isNotEmpty)
      subBits.add('Ingredients: ${e.ingredients.length}');
    if (e.ingredientsAdded > 0)
      subBits.add('• ${e.ingredientsAdded} added to shopping');

    return ListTile(
      leading: const Icon(Icons.restaurant_menu),
      title: Text(e.userName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...bullets,
          if (subBits.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subBits.join('  ')),
          ],
        ],
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Add items to shopping',
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: () => _addItemsToShoppingSelector(e),
          ),
          IconButton(
            tooltip: 'Delete entry',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              setState(() {
                _day.lunch.remove(e);
                _day.dinner.remove(e);
              });
              await MealsStore.instance.saveState();
            },
          ),
        ],
      ),
    );
  }

  void _pickImageForDay() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Image picker TODO (storage ready later)')),
    );
  }

  void _scanBarcodeForDay() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Barcode scan TODO (Open Food Facts)')),
    );
  }
}
