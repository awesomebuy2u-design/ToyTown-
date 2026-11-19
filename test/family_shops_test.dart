import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/family_shops.dart';
import 'package:toytown/listing.dart';
import 'package:toytown/main.dart';

PublicFamilyShop shop(String id, {String city = 'Полтава'}) => PublicFamilyShop.fromMap({
  'shop_id': id, 'shop_name': 'Крамничка $id', 'cities': [city], 'listing_count': 1,
  'theme': 'lavender', 'front': 'stars', 'balloons': true, 'flowers': true, 'awning': true,
});
Listing toy(String id) => Listing.fromMap({'id': id, 'title': 'Іграшка $id',
  'description': 'Опис іграшки', 'city': 'Полтава', 'category': 'Інше', 'deal_type': 'gift'});

class FakeShops extends FamilyShopsRepository {
  Future<List<PublicFamilyShop>> Function(String, int) browseHandler = (_, __) async => [];
  Future<List<Listing>> Function(String, int) listingsHandler = (_, __) async => [];
  final searches = <(String, int)>[];
  final visits = <(String, int)>[];
  @override
  Future<List<PublicFamilyShop>> browse(String term, int offset) {
    searches.add((term, offset)); return browseHandler(term, offset);
  }
  @override
  Future<List<Listing>> listings(String id, int offset) {
    visits.add((id, offset)); return listingsHandler(id, offset);
  }
}

Widget screen(FakeShops repo, {double scale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
    disableAnimations: true, textScaler: TextScaler.linear(scale)), child: child!),
  home: FamilyShopsScreen(repository: repo, listingBuilder: (item) => ListingCard(item: item)));

Future<void> show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 500, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a real storefront opens its own listing and existing details screen', (tester) async {
    final repo = FakeShops()
      ..browseHandler = (_, __) async => [shop('A'), shop('B')]
      ..listingsHandler = (id, _) async => [toy('from-$id')];
    await tester.pumpWidget(screen(repo));
    await tester.pumpAndSettle();
    final visit = find.byKey(const ValueKey('visit-shop-B'));
    await show(tester, visit); await tester.tap(visit); await tester.pumpAndSettle();
    expect(repo.visits, [('B', 0)]);
    await show(tester, find.text('Переглянути оголошення'));
    expect(find.text('Іграшка from-A'), findsNothing);
    await tester.tap(find.text('Переглянути оголошення')); await tester.pumpAndSettle();
    expect(find.text('Фото не додано'), findsOneWidget);
    expect(find.text('Іграшка from-B'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('new city search cannot be overwritten by an older response', (tester) async {
    final old = Completer<List<PublicFamilyShop>>(), latest = Completer<List<PublicFamilyShop>>();
    final repo = FakeShops()..browseHandler = (term, _) => term.isEmpty ? old.future : latest.future;
    await tester.pumpWidget(screen(repo)); await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('shop-search')), 'Львів');
    await tester.testTextInput.receiveAction(TextInputAction.search); await tester.pump();
    latest.complete([shop('LVIV', city: 'Львів')]); await tester.pumpAndSettle();
    old.complete([shop('OLD')]); await tester.pumpAndSettle();
    expect(find.text('Крамничка LVIV'), findsOneWidget);
    expect(find.text('Крамничка OLD'), findsNothing);
    expect(repo.searches, [('', 0), ('Львів', 0)]);
  });

  testWidgets('directory paginates without dropping the current search', (tester) async {
    final repo = FakeShops()..browseHandler = (term, offset) async => offset == 0
      ? [for (var i = 0; i < 24; i++) shop('P$i')] : [shop('LAST')];
    await tester.pumpWidget(screen(repo)); await tester.pumpAndSettle();
    final more = find.byKey(const ValueKey('more-shops'));
    await show(tester, more); await tester.tap(more); await tester.pumpAndSettle();
    await show(tester, find.byKey(const ValueKey('visit-shop-LAST')));
    expect(repo.searches, [('', 0), ('', 24)]);
    expect(find.byKey(const ValueKey('more-shops')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('network failure offers retry and empty results show no invented shops', (tester) async {
    var fail = true;
    final repo = FakeShops()..browseHandler = (_, __) async {
      if (fail) throw StateError('offline'); return [];
    };
    await tester.pumpWidget(screen(repo)); await tester.pumpAndSettle();
    expect(find.text('Повторити'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Повторити')); await tester.pumpAndSettle();
    expect(find.textContaining('Крамничок поки не знайдено'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('storefronts support narrow phones and large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeShops()..browseHandler = (_, __) async => [shop('ABCDEF')];
    await tester.pumpWidget(screen(repo, scale: 2)); await tester.pumpAndSettle();
    final visit = find.byKey(const ValueKey('visit-shop-ABCDEF'));
    await show(tester, visit); await tester.tap(visit); await tester.pumpAndSettle();
    expect(find.textContaining('Зараз у цій крамничці'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
