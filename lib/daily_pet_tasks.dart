import 'package:flutter/material.dart';

/// Server-confirmed daily tasks. The client never calculates the star reward.
class DailyPetTasks extends StatelessWidget {
  const DailyPetTasks({super.key, required this.completed, required this.enabled,
    required this.onAction});

  final Map<String, bool> completed;
  final bool enabled;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final done = ['feed', 'play', 'brush'].where((id) => completed[id] == true).length;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Пригоди на сьогодні', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Виконано $done із 3 · по 1 ⭐ за завдання'),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: done / 3,
            semanticsLabel: 'Щоденні завдання', semanticsValue: '$done із 3'),
          const SizedBox(height: 12),
          for (final task in const [
            ('feed', 'Нагодувати друга', Icons.restaurant_rounded),
            ('play', 'Погратися з другом', Icons.sports_tennis_rounded),
            ('brush', 'Причесати друга', Icons.brush_rounded),
          ]) Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
              key: ValueKey('daily-${task.$1}'),
              onPressed: enabled && completed[task.$1] != true ? () => onAction(task.$1) : null,
              icon: Icon(completed[task.$1] == true ? Icons.check_circle_outline : task.$3),
              label: Text(completed[task.$1] == true ? '${task.$2} · виконано' : task.$2),
            )),
          ),
          Text(done == 3 ? 'Усе готово! Друг радіє твоїй турботі ♡' : 'Нові завдання щодня за київським часом.'),
        ]),
      ),
    );
  }
}
