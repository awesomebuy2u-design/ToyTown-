import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/town_village.dart';

Widget reduced(Widget child, {double scale = 1}) => MaterialApp(
  builder: (context, content) => MediaQuery(data: MediaQuery.of(context).copyWith(
    disableAnimations: true, textScaler: TextScaler.linear(scale)), child: content!),
  home: Scaffold(body: child));

void main() {
  testWidgets('each village building opens its own destination', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final opened = <String>[];
    await tester.pumpWidget(reduced(Padding(padding: const EdgeInsets.all(16), child: VillageMap(
      openToys: () => opened.add('toys'), openShop: () => opened.add('shop'),
      openPet: () => opened.add('pet'), openGames: () => opened.add('games'),
      theme: 'mint', front: 'classic', balloons: false, flowers: false, awning: false))));
    await tester.pumpAndSettle();
    for (final destination in ['toys', 'shop', 'pet', 'games']) {
      await tester.tap(find.byKey(ValueKey('village-door-$destination')));
      await tester.pumpAndSettle();
    }
    expect(opened, ['toys', 'shop', 'pet', 'games']);
    expect(tester.takeException(), isNull);
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
