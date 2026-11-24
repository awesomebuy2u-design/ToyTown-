import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toytown/town_village.dart';

Widget reduced(Widget child, {double scale = 1}) => MaterialApp(
  builder: (context, content) => MediaQuery(data: MediaQuery.of(context).copyWith(
    disableAnimations: true, textScaler: TextScaler.linear(scale)), child: content!),
  home: Scaffold(body: child));

void _noop() {}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('each village building opens its own destination', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final opened = <String>[];
    await tester.pumpWidget(reduced(Padding(padding: const EdgeInsets.all(16), child: VillageMap(
      openToys: () => opened.add('toys'), openShop: () => opened.add('shop'),
      openPet: () => opened.add('pet'), openGames: () => opened.add('games'),
      theme: 'mint', front: 'classic', balloons: false, flowers: false, awning: false))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('village-traveler')), findsOneWidget);
    for (final destination in ['toys', 'shop', 'pet', 'games']) {
      await tester.tap(find.byKey(ValueKey('village-door-$destination')));
      await tester.pumpAndSettle();
    }
    expect(opened, ['toys', 'shop', 'pet', 'games']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('traveler reaches the selected building before opening it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(
      padding: const EdgeInsets.all(16),
      child: VillageMap(openToys: () => opened++, openShop: () {},
        openPet: () {}, openGames: () {}, theme: 'mint', front: 'classic',
        balloons: false, flowers: false, awning: false),
    ))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('village-door-toys')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened, 0);
    await tester.pump(const Duration(milliseconds: 800));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('three village secrets can be discovered once each', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(reduced(Padding(
      padding: const EdgeInsets.all(16),
      child: VillageMap(openToys: () {}, openShop: () {}, openPet: () {},
        openGames: () {}, theme: 'mint', front: 'classic',
        balloons: false, flowers: false, awning: false),
    )));
    await tester.pumpAndSettle();
    expect(find.text('✨ Секрети: 0/3'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(ValueKey('village-secret-$i')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Знайдено секретів: ${i + 1} із 3.'), findsOneWidget);
      await tester.tap(find.text('Продовжити пригоду'));
      await tester.pumpAndSettle();
    }
    expect(find.text('✨ Секрети: 3/3'), findsOneWidget);
    expect(find.byKey(const ValueKey('village-explorer-badge')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('village-secret-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Знайдено секретів: 3 із 3.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovered secrets survive reopening the village', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget village() => reduced(Padding(
      padding: const EdgeInsets.all(16),
      child: VillageMap(openToys: () {}, openShop: () {}, openPet: () {},
        openGames: () {}, theme: 'mint', front: 'classic',
        balloons: false, flowers: false, awning: false),
    ));
    await tester.pumpWidget(village());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('village-secret-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продовжити пригоду'));
    await tester.pumpAndSettle();
    expect(find.text('✨ Секрети: 1/3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(village());
    await tester.pumpAndSettle();
    expect(find.text('✨ Секрети: 1/3'), findsOneWidget);
    expect(find.byKey(const ValueKey('village-explorer-badge')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kindness quest gives a persistent one-time achievement', (tester) async {
    Widget quest() => reduced(const SingleChildScrollView(child: PetKindnessQuest(
      petName: 'Пухнастик', openPet: _noop)));
    await tester.pumpWidget(quest());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('village-kindness-complete')));
    await tester.pumpAndSettle();
    expect(find.text('💛 Добрий друг ToyTown'), findsOneWidget);
    await tester.tap(find.text('Чудово!'));
    await tester.pumpAndSettle();
    expect(find.text('🏅 Добрий друг ToyTown'), findsOneWidget);
    expect(find.byKey(const ValueKey('village-kindness-complete')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(quest());
    await tester.pumpAndSettle();
    expect(find.text('🏅 Добрий друг ToyTown'), findsOneWidget);
    expect(find.byKey(const ValueKey('village-kindness-complete')), findsNothing);
  });

  testWidgets('daily pet activities persist and cannot repeat on same day', (tester) async {
    Widget activities() => reduced(const SingleChildScrollView(
      child: DailyPetActivities(petName: 'Пухнастик')));
    await tester.pumpWidget(activities());
    await tester.pumpAndSettle();
    expect(find.textContaining('Сьогодні виконано 0 із 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('village-daily-feed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pet-reaction-🐰🥕')), findsOneWidget);
    expect(find.text('Нагодовано'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('village-daily-play')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pet-reaction-🐰🎾')), findsOneWidget);
    expect(find.textContaining('Сьогодні виконано 2 із 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('village-daily-walk')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pet-reaction-🐰🌳')), findsOneWidget);
    expect(find.textContaining('Сьогодні виконано 3 із 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(activities());
    await tester.pumpAndSettle();
    expect(find.textContaining('Сьогодні виконано 3 із 3'), findsOneWidget);
    expect(find.text('Нагодовано'), findsOneWidget);
    expect(find.text('Погралися'), findsOneWidget);
    expect(find.text('Прогулялися'), findsOneWidget);
  });

  testWidgets('town fountain opens an adventure dialog and leads to games', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var games = 0;
    await tester.pumpWidget(reduced(Padding(
      padding: const EdgeInsets.all(16),
      child: VillageMap(openToys: () {}, openShop: () {}, openPet: () {},
        openGames: () => games++, theme: 'mint', front: 'classic',
        balloons: false, flowers: false, awning: false),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('village-fountain')));
    await tester.pumpAndSettle();
    expect(find.text('⛲ Фонтан бажань'), findsOneWidget);
    await tester.tap(find.text('До ігор'));
    await tester.pumpAndSettle();
    expect(games, 1);
    expect(find.text('⛲ Фонтан бажань'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps destinations usable and pending games disabled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final opened = <String>[];
    await tester.pumpWidget(reduced(ListView(padding: const EdgeInsets.all(20), children: [
      TownVillage(openToys: () => opened.add('toys'), openShop: () => opened.add('shop'),
        openPet: () => opened.add('pet'), openGames: null, theme: 'lavender', front: 'stars',
        balloons: true, flowers: true, awning: true, petName: 'Найкращий пухнастий друг'),
    ]), scale: 2));
    await tester.pumpAndSettle();
    for (final destination in ['toys', 'shop', 'pet', 'games']) {
      final target = find.byKey(ValueKey('village-door-$destination'));
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }
    expect(tester.widget<InkWell>(find.byKey(const ValueKey('village-door-games'))).onTap, isNull);
    for (final destination in ['toys', 'shop', 'pet', 'games']) {
      final target = find.byKey(ValueKey('village-link-$destination'));
      await tester.scrollUntilVisible(target, 180, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      if (destination != 'games') {
        await tester.tap(target);
        await tester.pumpAndSettle();
      } else {
        expect(tester.widget<ListTile>(target).onTap, isNull);
      }
      expect(tester.takeException(), isNull);
    }
    expect(opened, ['toys', 'shop', 'pet']);
  });

  testWidgets('village reflects saved shop colors and purchased decorations', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final images = <List<int>>[];
    for (final choice in [('mint', 'classic', false), ('lavender', 'stars', true), ('sunset', 'clouds', true)]) {
      final key = GlobalKey();
      await tester.pumpWidget(reduced(Padding(padding: const EdgeInsets.all(16), child:
        RepaintBoundary(key: key, child: VillageMap(openToys: () {}, openShop: () {},
          openPet: () {}, openGames: () {}, theme: choice.$1, front: choice.$2,
          balloons: choice.$3, flowers: choice.$3, awning: choice.$3)))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final data = bytes!.buffer.asUint8List();
        images.add(data);
        await Directory('build/previews').create(recursive: true);
        await File('build/previews/village-${choice.$1}.png').writeAsBytes(data);
        image.dispose();
      });
    }
    expect(images[0], isNot(orderedEquals(images[1])));
    expect(images[1], isNot(orderedEquals(images[2])));
  });
}
