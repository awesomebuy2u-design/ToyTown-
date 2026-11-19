import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:toytown/main.dart';
import 'package:toytown/toytown_world.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('opens town and online setup', (tester) async {
    await tester.pumpWidget(const ToyTownApp());
    await tester.pumpAndSettle();
    expect(find.text('Містечко іграшок'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Кабінет батьків'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Кабінет батьків'));
    await tester.pumpAndSettle();
    expect(find.textContaining('додайте URL'), findsOneWidget);
  });

  testWidgets('village connects catalog, shop, pet and game and resets page scroll', (tester) async {
    var catalogVisits = 0;
    await tester.pumpWidget(MaterialApp(home: ToyTownWorld(
      openListings: () => catalogVisits++, openParent: () {})));
    await tester.pumpAndSettle();
    Future<void> visit(String destination) async {
      final target = find.byKey(ValueKey('village-door-$destination'));
      await tester.ensureVisible(target);
      await tester.pump();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    Future<void> town() async {
      await tester.tap(find.byType(NavigationDestination).first);
      await tester.pumpAndSettle();
    }
    await visit('toys');
    expect(catalogVisits, 1);
    await visit('shop');
    expect(find.text('Моя крамничка'), findsOneWidget);
    await town();
    await visit('pet');
    expect(find.text('Мій улюбленець'), findsOneWidget);
    await town();
    await visit('games');
    expect(find.text('Знайди пару'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final directoryShop = find.byKey(const ValueKey('village-link-shop'));
    await tester.scrollUntilVisible(directoryShop, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(directoryShop);
    await tester.pumpAndSettle();
    expect(find.text('Моя крамничка'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Моя крамничка')).dy, lessThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('assigned legacy progress does not appear in guest mode', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({
      'toytown.world.legacyFamily': 'family-a',
      'toytown.world.progress': jsonEncode({'stars': 9, 'careCount': 3, 'decorated': false}),
    });
    await tester.pumpWidget(MaterialApp(home: ToyTownWorld(openListings: () {}, openParent: () {})));
    await tester.pumpAndSettle();
    expect(find.text('ToyTown · ⭐ 0'), findsOneWidget);
    expect(find.textContaining('Гостьовий прогрес'), findsOneWidget);
  });
}
