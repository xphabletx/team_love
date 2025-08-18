import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:uuid/uuid.dart';
import 'package:team_love_app/widgets/side_nav_drawer.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // Master list of events (first/start occurrence + repeat/reminder metadata)
  final List<_Event> _events = [];
  final _uuid = const Uuid();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _showMonthEvents = true;

  // ---- date helpers
  DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ---- recurrence check for a single day
  bool _occursOn(_Event e, DateTime day) {
    final start = _d(e.date);
    final target = _d(day);
    if (target.isBefore(start)) return false;
    if (_sameDay(start, target)) return true;

    switch (e.repeat) {
      case 'Daily':
        return true; // every day after start
      case 'Weekly':
        return target.difference(start).inDays % 7 == 0;
      case 'Biweekly':
        return target.difference(start).inDays % 14 == 0;
      case 'Monthly':
        // naive same-day-of-month rule
        return start.day == target.day;
      case 'Yearly':
        return start.month == target.month && start.day == target.day;
      default:
        return false; // 'None'
    }
  }

  // ---- collections for UI
  List<_Event> _eventsForDay(DateTime day) =>
      _events.where((e) => _occursOn(e, day)).toList();

  List<_Event> _eventsForMonth(DateTime month) {
    final last = DateTime(month.year, month.month + 1, 0);
    // include an event once if it occurs on any day within this month
    return _events.where((e) {
      for (int d = 1; d <= last.day; d++) {
        if (_occursOn(e, DateTime(month.year, month.month, d))) return true;
      }
      return false;
    }).toList();
  }

  // ---- editor
  Future<void> _showEventSheet({DateTime? date, _Event? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    DateTime selectedDate = _d(
      date ?? existing?.date ?? _selectedDay ?? _focusedDay,
    );
    String repeat = existing?.repeat ?? 'None';
    String reminder = existing?.reminder ?? 'None';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.9,
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing == null ? 'Add Event' : 'Edit Event',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text(
                      '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: sheetCtx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = _d(picked));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<String>(
                    label: const Text('Repeat'),
                    initialSelection: repeat,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 'None', label: 'None'),
                      DropdownMenuEntry(value: 'Daily', label: 'Daily'),
                      DropdownMenuEntry(value: 'Weekly', label: 'Weekly'),
                      DropdownMenuEntry(
                        value: 'Biweekly',
                        label: 'Every 2 weeks',
                      ),
                      DropdownMenuEntry(value: 'Monthly', label: 'Monthly'),
                      DropdownMenuEntry(value: 'Yearly', label: 'Yearly'),
                    ],
                    onSelected: (val) =>
                        setModalState(() => repeat = val ?? 'None'),
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<String>(
                    label: const Text('Reminder'),
                    initialSelection: reminder,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 'None', label: 'None'),
                      DropdownMenuEntry(value: '5m', label: '5 minutes before'),
                      DropdownMenuEntry(
                        value: '15m',
                        label: '15 minutes before',
                      ),
                      DropdownMenuEntry(
                        value: '30m',
                        label: '30 minutes before',
                      ),
                      DropdownMenuEntry(value: '1h', label: '1 hour before'),
                      DropdownMenuEntry(value: '1d', label: '1 day before'),
                    ],
                    onSelected: (val) =>
                        setModalState(() => reminder = val ?? 'None'),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      final title = titleCtrl.text.trim();
                      if (title.isEmpty) {
                        Navigator.of(sheetCtx).pop();
                        return;
                      }
                      setState(() {
                        if (existing == null) {
                          _events.add(
                            _Event(
                              id: _uuid.v4(),
                              title: title,
                              date: selectedDate,
                              repeat: repeat,
                              reminder: reminder,
                            ),
                          );
                        } else {
                          existing
                            ..title = title
                            ..date = selectedDate
                            ..repeat = repeat
                            ..reminder = reminder;
                        }
                      });
                      Navigator.of(sheetCtx).pop();
                    },
                    child: Text(
                      existing == null ? 'Add Event' : 'Save Changes',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleEvents = _showMonthEvents
        ? _eventsForMonth(_focusedDay)
        : _selectedDay != null
        ? _eventsForDay(_selectedDay!)
        : <_Event>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Menu',
          ),
        ),
      ),

      // 👉 Use your SideNavDrawer widget
      // If SideNavDrawer already returns a Drawer, you can use `drawer: const SideNavDrawer(),`
      // Most commonly it's drawer *content*, so we wrap it:
      drawer: const Drawer(child: SideNavDrawer()),

      body: Column(
        children: [
          TableCalendar<_Event>(
            focusedDay: _focusedDay,
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarFormat: CalendarFormat.month,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
            ), // no "2 weeks" button
            eventLoader: _eventsForDay,
            selectedDayPredicate: (day) =>
                _selectedDay != null && _d(day) == _d(_selectedDay!),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = _d(selected);
                _focusedDay = focused;
                _showMonthEvents = false;
              });
            },
            onDayLongPressed: (selected, focused) {
              setState(() {
                _selectedDay = _d(selected);
                _focusedDay = focused;
                _showMonthEvents = false;
              });
              _showEventSheet(date: selected);
            },
            onPageChanged: (focused) {
              setState(() {
                _focusedDay = focused;
                _selectedDay = null;
                _showMonthEvents = true;
              });
            },
          ),
          Row(
            children: [
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _showMonthEvents = true;
                    _selectedDay = null;
                  });
                },
                child: const Text('Show All Month Events'),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: visibleEvents.isEmpty
                ? const Center(child: Text('No events'))
                : ListView.builder(
                    itemCount: visibleEvents.length,
                    itemBuilder: (ctx, i) {
                      final ev = visibleEvents[i];
                      return ListTile(
                        title: Text(ev.title),
                        subtitle: Text(
                          '${_d(ev.date)} — Repeat: ${ev.repeat}, Reminder: ${ev.reminder}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        onTap: () =>
                            _showEventSheet(date: ev.date, existing: ev),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEventSheet(date: _selectedDay ?? _d(_focusedDay)),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Event {
  final String id;
  String title;
  DateTime date; // first occurrence (start date)
  String repeat; // None / Daily / Weekly / Biweekly / Monthly / Yearly
  String reminder; // metadata only

  _Event({
    required this.id,
    required this.title,
    required this.date,
    required this.repeat,
    required this.reminder,
  });
}
