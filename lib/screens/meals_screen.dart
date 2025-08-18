import 'package:flutter/material.dart';
import 'meals_day_screen.dart';

class MealsScreen extends StatefulWidget {
  const MealsScreen({super.key});

  @override
  State<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends State<MealsScreen> {
  final _days = const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meals')),
      body: ListView.separated(
        itemCount: _days.length,
        separatorBuilder: (_, __) => const Divider(height: 0),
        itemBuilder: (ctx, i) {
          final day = _days[i];
          final dm = MealsStore.instance.day(day);

          String formatEntries(List<MealEntry> list) {
            if (list.isEmpty) return '—';
            return list
                .map((e) {
                  final who = e.sharedDinner ? '[shared]' : e.userName;
                  final items = e.items.isEmpty
                      ? ''
                      : ' - ${e.items.join(', ')}';
                  return '$who$items';
                })
                .join('\n');
          }

          return ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(day),
            subtitle: Text(
              'Lunch:\n${formatEntries(dm.lunch)}\n\nDinner:\n${formatEntries(dm.dinner)}',
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => MealsDayScreen(dayName: day)),
              );
              setState(() {}); // refresh overview after returning
            },
          );
        },
      ),
    );
  }
}
