import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/world_art.dart';

void main() {
  testWidgets('pet and clothes fit a narrow phone screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      home: const Scaffold(body: Padding(padding: EdgeInsets.all(20),
        child: PetScene(kind: 'bunny', name: 'Друг', grown: true,
          hat: true, bow: true, outfit: 'mint'))),
    ));
    await tester.pumpAndSettle();
    final scene = tester.getRect(find.byType(PetScene));
    final sprite = tester.getRect(find.byType(Image));
    expect(sprite.left, greaterThanOrEqualTo(scene.left));
    expect(sprite.right, lessThanOrEqualTo(scene.right));
    expect(find.text('Друг'), findsOneWidget);
    expect(find.byIcon(Icons.local_florist_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pet assets and wardrobe render with reduced motion and shop decor', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key=GlobalKey();
    for(final kind in ['dog','cat','bunny']) {
      await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(
        data:MediaQuery.of(context).copyWith(disableAnimations:true),child:child!),
        home:RepaintBoundary(key:key,child:Scaffold(backgroundColor:const Color(0xFFFBF6EE),
          body:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
            PetScene(kind:kind,name:'Дружок',grown:true,hat:true,bow:true,outfit:'mint'),
            const SizedBox(height:16),
            const ShopScene(balloons:true,flowers:true,awning:true),
          ]))))));
      await tester.runAsync(() => precacheImage(AssetImage('assets/pets/$kind.webp'),tester.element(find.byType(PetScene))));
      await tester.pumpAndSettle();
      expect(tester.takeException(),isNull);
      await tester.tap(find.byType(PetScene));
      await tester.pumpAndSettle();
      expect(tester.takeException(),isNull);
      final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image=await boundary.toImage(pixelRatio:1);
        final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
        await Directory('build/previews').create(recursive:true);
        await File('build/previews/$kind.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
