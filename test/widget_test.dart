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
