import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/daily_pet_tasks.dart';

void main() {
  testWidgets('confirmed tasks cannot be claimed again and busy actions are disabled', (tester) async {
    final calls = <String>[];
    var completed = <String, bool>{};
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return DailyPetTasks(completed: completed, enabled: enabled, onAction: calls.add);
      },
    ))));
    await tester.tap(find.byKey(const ValueKey('daily-feed')));
    expect(calls, ['feed']);
    update(() { completed = {'feed': true}; });
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('daily-feed')));
    expect(calls, ['feed']);
    expect(find.text('Виконано 1 із 3 · по 1 ⭐ за завдання'), findsOneWidget);
    update(() { enabled = false; });
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('daily-play')));
    expect(calls, ['feed']);
    // Reloading authoritative next-day data reopens all tasks.
    update(() { completed = {}; enabled = true; });
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('daily-feed')));
    expect(calls, ['feed', 'feed']);
  });

  testWidgets('daily tasks fit narrow screens with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(2)), child: child!),
      home: Scaffold(body: ListView(padding: const EdgeInsets.all(20), children: [
        DailyPetTasks(completed: const {'feed': true, 'play': true, 'brush': true},
          enabled: true, onAction: (_) {}),
      ])),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Виконано 3 із 3 · по 1 ⭐ за завдання'), findsOneWidget);
  });
}
