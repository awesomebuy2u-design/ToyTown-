import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/family_shops.dart';
import 'package:toytown/settlements.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled gazetteer resolves cities and villages to settlement centres', () async {
    final places = await SettlementIndex.load();
    final poltava = places.resolve(' м. ПОЛТАВА ');
    expect(poltava?.id, 696643);
    expect(poltava!.point.latitude, closeTo(49.58925, 0.001));
    expect(poltava.point.longitude, closeTo(34.55367, 0.001));
    expect(places.resolve('Розсошенці')?.id, 11114903);
    expect(places.resolve('Київ')?.id, 703448);
    expect(places.resolve('Львів')?.id, 702550);
    expect(places.resolve('Сімферополь'), isNotNull);
    expect(places.resolve('Полтава, вулиця Перспективна 6'), isNull);
    expect(places.resolve('Невідоме місто'), isNull);
  });

  test('ambiguous non-capital names receive no guessed location', () {
    final places = SettlementIndex.fromRows([
      [1, 49.0, 31.0, 1, ['Мирне']],
      [2, 50.0, 32.0, 1, ['Мирне']],
      [3, 48.0, 33.0, 1, ["Кам'янка"]],
    ]);
    expect(places.resolve('Мирне'), isNull);
    expect(places.resolve('с. Кам’янка')?.id, 3);
    expect(places.resolve(''), isNull);
  });

  test('city groups count distinct loaded shops and do not invent map points', () {
    final places = SettlementIndex.fromRows([
      [1, 49.0, 31.0, 0, ['Полтава', 'Poltava']],
      [2, 50.0, 32.0, 0, ['Київ']],
    ]);
    PublicFamilyShop shop(String id, List<String> cities) => PublicFamilyShop.fromMap({
      'shop_id': id, 'shop_name': id, 'listing_count': 1, 'cities': cities,
    });
    final groups = groupShopsByCity([
      shop('A', ['Полтава', 'Poltava', 'Київ']), shop('A', ['Полтава']),
      shop('B', ['полтава']), shop('C', ['Невідоме місто']),
    ], places);
    expect(groups.length, 2);
    expect(groups.singleWhere((g) => g.place.id == 1).shops.keys, ['A', 'B']);
    expect(groups.singleWhere((g) => g.place.id == 2).shops.keys, ['A']);
  });
}
