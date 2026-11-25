import 'package:flutter_test/flutter_test.dart';
import '../lib/partner_catalog.dart';

void main() {
  test('only current exact matches from allowed hosts are sorted by price', () {
    final now = DateTime.utc(2026, 11, 25);
    PartnerOffer offer(String id, int price, {String model = '123',
      String host = 'shop.example', int hours = 1, bool stock = true}) =>
      PartnerOffer(id: id, store: 'Test', title: 'Toy', model: model,
        brand: 'LEGO', priceKopiykas: price,
        affiliateUrl: Uri.https(host, '/toy'),
        checkedAt: now.subtract(Duration(hours: hours)), inStock: stock);
    final results = matchingPartnerOffers(brand: ' lego ', model: '123',
      now: now, allowedHosts: {'shop.example'}, offers: [
        offer('expensive', 500), offer('cheap', 300),
        offer('wrong', 100, model: '124'),
        offer('stale', 100, hours: 25),
        offer('future', 100, hours: -1),
        offer('untrusted', 100, host: 'other.example'),
        offer('sold', 100, stock: false), offer('invalid', 0),
      ]);
    expect(results.map((o) => o.id), ['cheap', 'expensive']);
    expect(matchingPartnerOffers(brand: '', model: '123', offers: results,
      allowedHosts: {'shop.example'}, now: now), isEmpty);
  });
}
