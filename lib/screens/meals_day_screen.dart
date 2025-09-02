import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/input_service.dart';
import '../services/shopping_service.dart';
import '../services/calendar_events_service.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// MealsStore: source of truth for plan range, meals by *date*, calendar
/// mirroring preference, and custom suggestions. Persists everything.
/// Keeps legacy week buckets so older screens continue working.
/// ───────────────────────────────────────────────────────────────────────────
class MealsStore {
  MealsStore._();
  static final MealsStore instance = MealsStore._();

  /// Pretend workspace users (replace with real consent later)
  final List<String> users = const ['you', 'partner'];

  // Legacy week buckets (keep so old code still works)
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

  // New: meals by *date* (yyyy-MM-dd)
  final Map<String, DayMeals> _byDate = <String, DayMeals>{};

  DateTime? planStart; // date-only
  DateTime? planEnd; // date-only

  bool syncToCalendar = false; // persistent opt-in
  List<String> customSuggestions =
      <String>[]; // persistent (kept for prefs shape)

  // Keys
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

/// Simple container for a day’s lunch/dinner entries.
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
  });

  String userName; // 'you' / 'partner' / '[shared]' via sharedDinner
  final List<String> items; // merged list of meal items
  bool sharedDinner;

  int ingredientsAdded = 0; // count pushed to shopping list

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
  )..ingredientsAdded = (m['ingredientsAdded'] as num?)?.toInt() ?? 0;
}

enum MealType { lunch, dinner }

class MealsDayScreen extends StatefulWidget {
  const MealsDayScreen({super.key, required this.date, this.initialAddFor});

  final DateTime date; // this screen always edits by date
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
        // Keep date-only (midnight) but mark as all-day via meta so UI hides time.
        date: DateTime(widget.date.year, widget.date.month, widget.date.day),
        repeat: 'None',
        every: 1,
        reminder: 'None',
        meta: {
          'type': 'meal',
          'mealType': isLunch ? 'lunch' : 'dinner',
          'date': _dateKey(widget.date),
          'allDay': true, // calendar UI can use this to suppress 00:00:00.000
        },
      ),
    );
  }

  /// Remove calendar event for this date+meal
  void _removeFromCalendar({required bool isLunch}) {
    final id = 'meal:${_dateKey(widget.date)}:${isLunch ? 'lunch' : 'dinner'}';
    CalendarEvents.instance.remove(id);
  }

  // Add / Edit bottom sheet (no suggestions; keeps Meal/Ingredients switch)
  Future<void> _addMeal({required bool isLunch}) async {
    await MealsStore.instance.ensureLoaded();
    if (!mounted) return; // guard context use after await

    // Workspace gate (hidden for now)
    const bool hasWorkspace = false;
    String selectedTag = 'You'; // only if hasWorkspace==true

    bool syncToCalendar = MealsStore.instance.syncToCalendar;

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

                // Workspace tags (hidden by default)
                if (hasWorkspace) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      children: ['You', 'Partner', 'Shared'].map((t) {
                        final on = selectedTag == t;
                        return ChoiceChip(
                          label: Text(t),
                          selected: on,
                          onSelected: (_) => setSB(() => selectedTag = t),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Ingredient mode shows a small meal summary
                if (ingredientMode && mealItems.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Meal: ${mealItems.join(', ')}',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

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
                      child: Wrap(
                        spacing: 6,
                        runSpacing: -8,
                        children: mealItems
                            .map(
                              (s) => InputChip(
                                label: Text(s),
                                onDeleted: () =>
                                    setSB(() => mealItems.remove(s)),
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
                      child: Wrap(
                        spacing: 6,
                        runSpacing: -8,
                        children: ingItems
                            .map(
                              (s) => InputChip(
                                label: Text(s),
                                onDeleted: () =>
                                    setSB(() => ingItems.remove(s)),
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
                    // Always enabled so you can toggle the checkbox and save.
                    onPressed: () async {
                      final navigator = Navigator.of(ctx);

                      // Merge into existing entry (only if user added meal items)
                      if (mealItems.isNotEmpty) {
                        final list = isLunch ? _day.lunch : _day.dinner;
                        final match = list.firstWhere(
                          (e) => e.userName == 'you',
                          orElse: () => MealEntry(
                            userName: 'you',
                            items: [],
                            sharedDinner: false,
                          ),
                        );
                        if (!list.contains(match)) list.add(match);
                        match.items.addAll(mealItems);
                      }

                      // Ingredients -> Shopping
                      for (final ing in ingItems) {
                        ShoppingService.instance.add(ing);
                      }
                      if (ingItems.isNotEmpty) {
                        final list = isLunch ? _day.lunch : _day.dinner;
                        if (list.isNotEmpty) {
                          list.first.ingredientsAdded += ingItems.length;
                        }
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

  Future<void> _addIngredientToShopping(MealEntry entry) async {
    final ctrl = TextEditingController();
    final focus = FocusNode();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) {
          void add(String name) async {
            final n = name.trim();
            if (n.isEmpty) return;
            ShoppingService.instance.add(n);
            if (!mounted) return;
            setState(() => entry.ingredientsAdded++);
            setSB(() {
              ctrl.clear();
              focus.requestFocus();
            });
            await MealsStore.instance.saveState();
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add ingredients to shopping list',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                AppInputs.textField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: 'Ingredient'),
                  onChanged: (_) =>
                      setSB(() {}), // kept for live validation feel
                  onSubmitted: add,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    ctrl.dispose();
    focus.dispose();
  }

  // FAB actions (UI stubs)
  void _openFab() {
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
        onPressed: _openFab,
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
    final subtitle = [
      if (e.sharedDinner) '[shared]',
      if (e.items.isNotEmpty) e.items.join(', '),
      if (e.ingredientsAdded > 0) '• ${e.ingredientsAdded} ingredients added',
    ].join('  ');

    return ListTile(
      leading: const Icon(Icons.restaurant_menu),
      title: Text(e.userName),
      subtitle: Text(subtitle),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Add ingredients to shopping',
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: () => _addIngredientToShopping(e),
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
}
