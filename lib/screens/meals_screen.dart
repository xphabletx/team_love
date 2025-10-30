// lib/screens/meals_screen.dart
import 'package:flutter/material.dart';
import '../widgets/side_nav_drawer.dart';
import 'meals_day_screen.dart'; // provides MealsStore, DayMeals, MealEntry, MealType

class MealsScreen extends StatefulWidget {
  const MealsScreen({super.key});

  @override
  State<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends State<MealsScreen> {
  final _expandedKeys = <String>{}; // yyyy-MM-dd for expanded rows

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  Future<void> _ensureLoaded() async {
    await MealsStore.instance.ensureLoaded();
    if (mounted) setState(() {});
  }

  // Date helpers (no intl dep)
  static const _wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = [
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
  String _fmtDate(DateTime d) =>
      '${_wk[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';
  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  /// Built-in holiday-style picker: tap start, tap end, span is highlighted.
  Future<DateTimeRange?> _pickRange({
    DateTime? initialStart,
    DateTime? initialEnd,
  }) async {
    final today = _d(DateTime.now());
    final firstDate = today;
    final lastDate = today.add(const Duration(days: 31));

    final result = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: (initialStart != null && initialEnd != null)
          ? DateTimeRange(start: _d(initialStart), end: _d(initialEnd))
          : null,
      helpText: 'Select meal plan start and end',
      saveText: 'Done',
    );
    if (result == null) return null;

    final start = _d(result.start);
    final end = _d(result.end);
    final len = end.difference(start).inDays + 1;
    if (start.isBefore(today)) return null;
    if (len > 31) return null;
    return DateTimeRange(start: start, end: end);
  }

  Future<void> _createNewPlan() async {
    final r = await _pickRange();
    if (r == null) return;

    await MealsStore.instance.setPlan(r.start, r.end, wipeOld: true);
    if (!mounted) return;
    setState(() {
      _expandedKeys
        ..clear()
        ..add(_key(r.start));
    });
  }

  Future<void> _changePlan() async {
    final store = MealsStore.instance;
    final prevStart = store.planStart;
    final prevEnd = store.planEnd;

    final r = await _pickRange(initialStart: prevStart, initialEnd: prevEnd);
    if (r == null) return;

    bool proceed = true;
    if (prevStart != null && prevEnd != null) {
      final removed = <DateTime>[];
      for (
        var cur = prevStart;
        !cur.isAfter(prevEnd);
        cur = cur.add(const Duration(days: 1))
      ) {
        if (cur.isBefore(r.start) || cur.isAfter(r.end)) removed.add(cur);
      }
      if (removed.isNotEmpty) {
        if (!mounted) return; // guard context before dialog
        proceed =
            await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Remove ${removed.length} day(s) from the plan?'),
                content: const Text(
                  'Only days outside the new range will be deleted. Overlapping days are kept.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ) ??
            false;
      }
    }
    if (!proceed) return;

    await store.setPlan(r.start, r.end, wipeOld: false);
    if (!mounted) return;
    setState(() {
      final valid = store.datesInPlan.map(_key).toSet();
      _expandedKeys.removeWhere((k) => !valid.contains(k));
      if (_expandedKeys.isEmpty && valid.isNotEmpty) {
        _expandedKeys.add(valid.first);
      }
    });
  }

  void _openFab() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('New plan'),
              subtitle: const Text(
                'Wipes current meal data (keeps calendar events)',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _createNewPlan();
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Change plan dates'),
              subtitle: const Text(
                'Keep overlap; confirm before removing others',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _changePlan();
              },
            ),
          ],
        ),
      ),
    );
  }

  // Collapsed row helpers
  String _truncate(String s, int maxChars) =>
      s.length <= maxChars ? s : '${s.substring(0, maxChars).trim()}…';

  String _collapsedLine(List<MealEntry> list, {int maxChars = 80}) {
    if (list.isEmpty) return '—';
    final items = <String>[];
    for (final e in list) {
      items.addAll(e.items);
    }
    if (items.isEmpty) return '—';
    return _truncate(items.join(', '), maxChars);
  }

  String _collapsedSubtitle(DayMeals dm) {
    final lunchLine = _collapsedLine(dm.lunch, maxChars: 80);
    final dinnerLine = _collapsedLine(dm.dinner, maxChars: 80);
    return 'Lunch: $lunchLine\nDinner: $dinnerLine';
  }

  bool _hasData(List<MealEntry> list) {
    for (final e in list) {
      if (e.items.isNotEmpty) return true;
    }
    return false;
  }

  String _statusSubtitle(DayMeals dm) {
    final lunchOk = _hasData(dm.lunch);
    final dinnerOk = _hasData(dm.dinner);
    final lunch = lunchOk ? 'Lunch: ✅' : 'Lunch: —';
    final dinner = dinnerOk ? 'Dinner: ✅' : 'Dinner: —';
    // compact single line; tweak separators if you prefer
    return '$lunch  •  $dinner';
  }

  Widget _buildMealTile({
    required String emoji,
    required String title,
    required DayMeals dayMeals,
    required bool isLunch,
    required DateTime date,
  }) {
    final entries = isLunch ? dayMeals.lunch : dayMeals.dinner;
    String summary() {
      if (entries.isEmpty) return '—';
      final items = <String>[];
      for (final e in entries) {
        items.addAll(e.items);
      }
      if (items.isEmpty) return '—';
      final str = items.join(', ');
      return str.length > 90 ? '${str.substring(0, 90).trim()}…' : str;
    }

    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MealsDayScreen(
                  date: date,
                  initialAddFor: isLunch ? MealType.lunch : MealType.dinner,
                ),
              ),
            );
            if (mounted) setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 6),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(summary(), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateRow(DateTime date) {
    final store = MealsStore.instance;
    final key = _key(date);
    final dm = store.dayForDate(date);
    final expanded = _expandedKeys.contains(key);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(_fmtDate(date)),
            subtitle: Text(
              _statusSubtitle(dm),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            trailing: IconButton(
              tooltip: expanded ? 'Collapse' : 'Expand',
              icon: Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              ),
              onPressed: () {
                setState(
                  () => expanded
                      ? _expandedKeys.remove(key)
                      : _expandedKeys.add(key),
                );
              },
            ),
            onTap: () => setState(
              () =>
                  expanded ? _expandedKeys.remove(key) : _expandedKeys.add(key),
            ),
          ),
          AnimatedCrossFade(
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 180),
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  _buildMealTile(
                    emoji: '🥗',
                    title: 'Lunch',
                    dayMeals: dm,
                    isLunch: true,
                    date: date,
                  ),
                  const SizedBox(width: 12),
                  _buildMealTile(
                    emoji: '🍽️',
                    title: 'Dinner',
                    dayMeals: dm,
                    isLunch: false,
                    date: date,
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = MealsStore.instance;
    final hasPlan = store.planStart != null && store.planEnd != null;
    final dates = store.datesInPlan;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meals'),
        actions: [
          IconButton(
            tooltip: hasPlan ? 'Change dates' : 'Create plan',
            icon: const Icon(Icons.event_outlined),
            onPressed: hasPlan ? _changePlan : _createNewPlan,
          ),
        ],
      ),
      drawer: const SideNavDrawer(),
      body: !hasPlan
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.restaurant_menu_outlined, size: 56),
                    const SizedBox(height: 12),
                    const Text('No meal plan yet'),
                    const SizedBox(height: 6),
                    const Text(
                      'Create a date range to start planning meals.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Create Plan'),
                      onPressed: _createNewPlan,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              itemCount: dates.length,
              itemBuilder: (ctx, i) => _buildDateRow(dates[i]),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openFab,
        child: const Icon(Icons.add),
      ),
    );
  }
}
