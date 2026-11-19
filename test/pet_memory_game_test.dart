import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/pet_memory_game.dart';

Future<void> openGame(WidgetTester tester, ValueChanged<bool?> result) async {
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
    body: FilledButton(onPressed: () async {
      result(await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) =>
        const PetMemoryGame(petName: 'Дружок', canEarnReward: true))));
    }, child: const Text('Старт')),
  ))));
  await tester.tap(find.text('Старт'));
  await tester.pumpAndSettle();
}

String face(WidgetTester tester, int index) => tester.widget<Semantics>(
  find.byKey(ValueKey('memory-label-$index'))).properties.label!.split(': ').last;

Future<void> showItem(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 160, scrollable: find.byType(Scrollable).first);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pump();
}

Future<void> flip(WidgetTester tester, int index) async {
  await showItem(tester, find.byKey(ValueKey('memory-card-$index')));
  await tester.tap(find.byKey(ValueKey('memory-card-$index')));
  await tester.pump();
}

void main() {
  testWidgets('winning requires all pairs and finishing reports completion once', (tester) async {
    final results = <bool?>[];
    await openGame(tester, results.add);
    expect(find.byKey(const ValueKey('memory-finish')), findsNothing);
    // Learn the shuffled cards through the same visible faces as a player.
    final known = <String, List<int>>{};
    for (var i = 0; i < 6; i += 2) {
      await flip(tester, i);
      final a = face(tester, i);
      await flip(tester, i + 1);
      final b = face(tester, i + 1);
      known.putIfAbsent(a, () => []).add(i);
      known.putIfAbsent(b, () => []).add(i + 1);
      if (a != b) {
        // A third tap must not change either exposed face during a mismatch.
        final third = (i + 2) % 6;
        await flip(tester, third);
        expect(face(tester, i), a);
        expect(face(tester, i + 1), b);
        await tester.pump(const Duration(seconds: 1));
        expect(face(tester, i), 'перевернути');
      }
    }
    for (final pair in known.values) {
      final button = tester.widget<OutlinedButton>(find.byKey(ValueKey('memory-card-${pair[0]}')));
      if (button.onPressed != null) {
        await flip(tester, pair[0]);
        await flip(tester, pair[1]);
      }
    }
    expect(find.textContaining('Знайдено пар: 3 із 3'), findsOneWidget);
    expect(results, isEmpty);
    await showItem(tester, find.byKey(const ValueKey('memory-finish')));
    await tester.tap(find.byKey(const ValueKey('memory-finish')));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('leaving an unfinished game never grants completion', (tester) async {
    final results = <bool?>[];
    await openGame(tester, results.add);
    await flip(tester, 0);
    await flip(tester, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(results, [null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game remains usable on a narrow phone with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
      home: const PetMemoryGame(petName: 'Дружок', canEarnReward: false)));
    await tester.pumpAndSettle();
    await showItem(tester, find.byKey(const ValueKey('memory-card-5')));
    await flip(tester, 5);
    expect(face(tester, 5), isNot('перевернути'));
    expect(tester.takeException(), isNull);
  });
}
