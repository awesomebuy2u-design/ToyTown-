import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/family_shops.dart';
import 'package:toytown/family_shops_map.dart';
import 'package:toytown/listing.dart';
import 'package:toytown/settlements.dart';

PublicFamilyShop shop(String id, {String city = 'Полтава'}) => PublicFamilyShop.fromMap({
  'shop_id': id, 'shop_name': 'Крамничка $id', 'cities': [city], 'listing_count': 1,
});

class MapShops extends FamilyShopsRepository {
  Future<List<PublicFamilyShop>> Function(String, int) handler = (_, __) async => [];
  final calls = <(String, int)>[];
  final visits = <String>[];
  @override
  Future<List<PublicFamilyShop>> browse(String term, int offset) {
    calls.add((term, offset));
    return handler(term, offset);
  }
  @override
  Future<List<Listing>> listings(String id, int offset) async {
    visits.add(id);
    return [Listing.fromMap({'id': id, 'title': 'Іграшка $id'})];
  }
}

Future<SettlementIndex> places() async => SettlementIndex.fromRows([
  [696643, 49.58925, 34.55367, 0, ['Полтава']],
  [703448, 50.45466, 30.5238, 0, ['Київ']],
]);

Widget screen(MapShops repo, {double scale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
    disableAnimations: true, textScaler: TextScaler.linear(scale)), child: child!),
  home: Scaffold(body: FamilyShopsMapScreen(repository: repo, loadSettlements: places,
    showTiles: false, listingBuilder: (item) => Text(item.title))));

Future<void> show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 450, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets('map groups real shops, filters by city and opens that family shop', (tester) async {
    final repo = MapShops()..handler = (_, __) async => [shop('A'), shop('B'), shop('C', city: 'Київ')];
    await tester.pumpWidget(screen(repo)); await tester.pumpAndSettle();
    expect(tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length, 2);
    final poltava = find.byKey(const ValueKey('map-city-choice-696643'));
    await show(tester, poltava); await tester.tap(poltava); await tester.pumpAndSettle();
    expect(find.text('Крамничка C'), findsNothing);
    final visit = find.byKey(const ValueKey('map-visit-shop-B'));
    await show(tester, visit); await tester.tap(visit); await tester.pumpAndSettle();
    expect(repo.visits, ['B']);
    await show(tester, find.text('Іграшка B'));
    expect(find.text('Іграшка A'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a map marker selects its city', (tester) async {
    final repo = MapShops()..handler = (_, __) async => [shop('A'), shop('B', city: 'Київ')];
    await tester.pumpWidget(screen(repo)); await tester.pumpAndSettle();
    final marker = find.byKey(const ValueKey('map-city-696643'));
    await show(tester, marker); await tester.tap(marker); await tester.pumpAndSettle();
    expect(find.text('Крамнички: Полтава'), findsOneWidget);
    expect(find.text('Крамничка B'), findsNothing);
  });

  testWidgets('late search response cannot overwrite the current map', (tester) async {
    final old = Completer<List<PublicFamilyShop>>(), current = Completer<List<PublicFamilyShop>>();
    final repo = MapShops()..handler = (term, _) => term.isEmpty ? old.future : current.future;
    await tester.pumpWidget(screen(repo)); await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('map-search')), 'Київ');
    await tester.testTextInput.receiveAction(TextInputAction.search); await tester.pump();
    current.complete([shop('NEW', city: 'Київ')]); await tester.pumpAndSettle();
    old.complete([shop('OLD')]); await tester.pumpAndSettle();
    expect(find.text('Крамничка NEW'), findsOneWidget);
    expect(find.text('Крамничка OLD'), findsNothing);
    final markers = tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
    expect(markers.length, 1);
    expect(markers.single.point.latitude, closeTo(50.45466, 0.001));
  });

  testWidgets('pagination retries the same page and keeps applied search and shops', (tester) async {
    var fail = true;
    final repo = MapShops()..handler = (term, offset) async {
      if (offset == 0) return [for (var i = 0; i < 24; i++) shop('P$i')];
      if (fail) throw StateError('offline');
      return [shop('P0'), shop('LAST')];
    };
    await tester.pumpWidget(screen(repo)); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('map-search')), 'Полтава');
    await tester.testTextInput.receiveAction(TextInputAction.search); await tester.pumpAndSettle();
    // Editing an unsubmitted draft must not change the query for the next page.
    await tester.enterText(find.byKey(const ValueKey('map-search')), 'Київ');
    final more = find.byKey(const ValueKey('map-more-shops'));
    await show(tester, more); await tester.tap(more); await tester.pumpAndSettle();
    expect(repo.calls.last, ('Полтава', 24));
    final retry = find.text('Повторити');
    await tester.scrollUntilVisible(retry, -450, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    fail = false;
    await tester.tap(retry); await tester.pumpAndSettle();
    expect(repo.calls.last, ('Полтава', 24));
    await show(tester, find.byKey(const ValueKey('map-visit-shop-LAST')));
    expect(find.byKey(const ValueKey('map-more-shops')), findsNothing);
    await tester.scrollUntilVisible(find.text('Завантажено крамничок: 25'), -450,
      scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    expect(find.text('Завантажено крамничок: 25'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and failed searches show no fabricated pins and can retry', (tester) async {
    var fail = true;
    final repo = MapShops()..handler = (_, __) async {
      if (fail) throw StateError('offline'); return [];
    };
    await tester.pumpWidget(screen(repo)); await tester.pumpAndSettle();
    expect(tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers, isEmpty);
    final retry = find.text('Повторити');
    await show(tester, retry); fail = false;
    await tester.tap(retry); await tester.pumpAndSettle();
    expect(find.textContaining('Крамничок не знайдено'), findsOneWidget);
    expect(tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers, isEmpty);
  });

  testWidgets('unmapped settlements remain visitable on a narrow phone with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = MapShops()..handler = (_, __) async => [shop('UNKNOWN', city: 'Невідоме село')];
    await tester.pumpWidget(screen(repo, scale: 2)); await tester.pumpAndSettle();
    expect(tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers, isEmpty);
    final visit = find.byKey(const ValueKey('map-visit-shop-UNKNOWN'));
    await show(tester, visit); await tester.tap(visit); await tester.pumpAndSettle();
    expect(repo.visits, ['UNKNOWN']);
    await show(tester, find.text('Іграшка UNKNOWN'));
    expect(tester.takeException(), isNull);
  });
}
