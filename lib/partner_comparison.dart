import 'package:flutter/material.dart';
import 'partner_catalog.dart';

/// Presentation only: mount exclusively inside a server-authorized guardian route.
/// This widget does not itself establish or verify authorization.
class PartnerComparison extends StatelessWidget {
  const PartnerComparison({super.key, required this.offers,
    required this.brand, required this.model, required this.allowedHosts,
    required this.now, required this.openOffer});
  final List<PartnerOffer> offers;
  final String brand, model;
  final Set<String> allowedHosts;
  final DateTime now;
  final ValueChanged<PartnerOffer> openOffer;

  @override
  Widget build(BuildContext context) {
    final matches = matchingPartnerOffers(brand: brand, model: model,
      offers: offers, allowedHosts: allowedHosts, now: now);
    if (matches.isEmpty) return const SizedBox.shrink();
    String price(int amount) => '${(amount / 100).toStringAsFixed(2).replaceAll('.', ',')} грн';
    return Card(child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Нова іграшка · від ${price(matches.first.priceKopiykas)}',
          style: Theme.of(context).textTheme.titleMedium),
        const Text('Партнерські пропозиції. ToyTown може отримати комісію.'),
        for (final offer in matches.take(3)) ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(offer.store),
          subtitle: Text(price(offer.priceKopiykas)),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => openOffer(offer)),
        const Text('Остаточну ціну та наявність перевіряйте у магазині.'),
      ])));
  }
}
