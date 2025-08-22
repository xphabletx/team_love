import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:uuid/uuid.dart';
import 'package:team_love_app/widgets/side_nav_drawer.dart';
import 'package:team_love_app/services/input_service.dart';
import 'package:team_love_app/services/calendar_events_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _uuid = const Uuid();
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _showMonthEvents = true;

  @override
  void initState() {
    super.initState();
    CalendarEvents.instance.addListener(_rebuild);
  }

  @override
  void dispose() {
    CalendarEvents.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  // Always show a clean YYYY-MM-DD (no time)
  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<CalEvent> _eventsForDay(DateTime day) =>
      CalendarEvents.instance.eventsOn(day);

  List<CalEvent> _eventsForMonth(DateTime month) {
    final last = DateTime(month.year, month.month + 1, 0);
    final set = <String>{};
    final out = <CalEvent>[];
    for (var d = 1; d <= last.day; d++) {
      final day = DateTime(month.year, month.month, d);
      for (final e in _eventsForDay(day)) {
        if (set.add(e.id)) out.add(e);
      }
    }
    return out;
  }

  // ---- editor (writes to service) ----
  Future<void> _showEventSheet({DateTime? date, CalEvent? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    DateTime selectedDate = _d(
      date ?? existing?.date ?? _selectedDay ?? _focusedDay,
    );
    String repeat = existing?.repeat ?? 'None';
    String reminder = existing?.reminder ?? 'None';
    final everyCtrl = TextEditingController(
      text: (existing?.every ?? 1).toString(),
    );

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
                  AppInputs.textField(
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
                  Row(
                    children: [
                      Expanded(
                        child: DropdownMenu<String>(
                          label: const Text('Repeat'),
                          initialSelection: repeat,
                          dropdownMenuEntries: const [
                            DropdownMenuEntry(value: 'None', label: 'None'),
                            DropdownMenuEntry(value: 'Daily', label: 'Daily'),
                            DropdownMenuEntry(value: 'Weekly', label: 'Weekly'),
                            DropdownMenuEntry(
                              value: 'Monthly',
                              label: 'Monthly',
                            ),
                            DropdownMenuEntry(value: 'Yearly', label: 'Yearly'),
                          ],
                          onSelected: (val) =>
                              setModalState(() => repeat = val ?? 'None'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (repeat != 'None')
                        SizedBox(
                          width: 80,
                          child: AppInputs.textField(
                            controller: everyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Every',
                            ),
                          ),
                        ),
                    ],
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
                      final every = int.tryParse(everyCtrl.text) ?? 1;
                      if (existing == null) {
                        CalendarEvents.instance.add(
                          CalEvent(
                            id: _uuid.v4(),
                            title: title,
                            date: selectedDate,
                            repeat: repeat,
                            every: repeat == 'None' ? 1 : every,
                            reminder: reminder,
                          ),
                        );
                      } else {
                        CalendarEvents.instance.upsert(
                          existing.copyWith(
                            title: title,
                            date: selectedDate,
                            repeat: repeat,
                            every: repeat == 'None' ? 1 : every,
                            reminder: reminder,
                          ),
                        );
                      }
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
        : <CalEvent>[];

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
      drawer: const Drawer(child: SideNavDrawer()),
      body: Column(
        children: [
          TableCalendar<CalEvent>(
            focusedDay: _focusedDay,
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarFormat: CalendarFormat.month,
            headerStyle: const HeaderStyle(formatButtonVisible: false),
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
                          '${_ymd(ev.date)} — Repeat: ${ev.repeat}'
                          '${ev.repeat == 'None' ? '' : ' every ${ev.every ?? 1}'}'
                          ' • Reminder: ${ev.reminder}',
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
