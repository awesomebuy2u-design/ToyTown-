import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/world_art.dart';

void main() {
  testWidgets('shop themes paint differently while preserving purchased decor', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pictures = <List<int>>[];
    for (final theme in ['mint', 'lavender', 'sunset']) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          disableAnimations: true), child: child!),
        home: Scaffold(body: RepaintBoundary(key: key, child: ShopScene(
          theme: theme, balloons: true, flowers: true, awning: true))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final data = bytes!.buffer.asUint8List();
        pictures.add(data);
        await Directory('build/previews').create(recursive: true);
        await File('build/previews/shop-$theme.png').writeAsBytes(data);
        image.dispose();
      });
    }
    expect(pictures[0], isNot(orderedEquals(pictures[1])));
    expect(pictures[1], isNot(orderedEquals(pictures[2])));
  });

  testWidgets('new pet reactions respect reduced motion', (tester) async {
    for (final activity in ['feed', 'play', 'brush']) {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          disableAnimations: true), child: child!),
        home: Scaffold(body: PetScene(kind: 'dog', name: 'Друг', grown: true,
          hat: false, bow: false, outfit: 'none', activity: activity,
          reaction: ['feed', 'play', 'brush'].indexOf(activity) + 1)),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
