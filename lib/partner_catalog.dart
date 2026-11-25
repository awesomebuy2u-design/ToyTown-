/// Partner offers are intended for the verified guardian interface only.
class PartnerOffer {
  const PartnerOffer({required this.id, required this.store,
    required this.title, required this.model, required this.brand,
    required this.priceKopiykas, required this.affiliateUrl,
    required this.checkedAt, required this.inStock});
  final String id, store, title, model, brand;
  final int priceKopiykas;
  final Uri affiliateUrl;
  final DateTime checkedAt;
  final bool inStock;
}

String _normalize(String value) => value.toLowerCase().trim()
    .replaceAll(RegExp(r'\s+'), ' ');

/// Only exact brand/model matches qualify as equivalent new toys.
/// Unknown models must not be presented as identical products.
List<PartnerOffer> matchingPartnerOffers({
  required String brand, required String model,
  required Iterable<PartnerOffer> offers,
  required Set<String> allowedHosts, required DateTime now,
}) {
  final b = _normalize(brand), m = _normalize(model);
  if (b.isEmpty || m.isEmpty) return [];
  return offers.where((offer) {
    final age = now.difference(offer.checkedAt);
    return _normalize(offer.brand) == b && _normalize(offer.model) == m &&
      offer.inStock && offer.priceKopiykas > 0 &&
      !age.isNegative && age <= const Duration(hours: 24) &&
      offer.affiliateUrl.scheme == 'https' &&
      offer.affiliateUrl.userInfo.isEmpty &&
      allowedHosts.contains(offer.affiliateUrl.host);
  }).toList()..sort((a, b) => a.priceKopiykas.compareTo(b.priceKopiykas));
}
