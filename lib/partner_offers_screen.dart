import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'partner_catalog.dart';
import 'partner_comparison.dart';

class _ApprovedOffer {
  const _ApprovedOffer(this.offer, this.host);
  final PartnerOffer offer;
  final String host;

  static _ApprovedOffer? parse(Map row, DateTime now) {
    final link = Uri.tryParse(row['affiliate_url']?.toString() ?? '');
    final time = DateTime.tryParse(row['checked_at']?.toString() ?? '');
    final host = row['allowed_host'];
    final amount = row['price_kopiykas'];
    if (host is! String ||
        amount is! int ||
        amount <= 0 ||
        link == null ||
        link.scheme != 'https' ||
        link.userInfo.isNotEmpty ||
        link.hasPort ||
        link.host != host ||
        time == null ||
        now.isBefore(time) ||
        now.difference(time) > const Duration(hours: 24) ||
        row['in_stock'] != true) return null;
    return _ApprovedOffer(
      PartnerOffer(
        id: row['id'].toString(),
        store: row['store'].toString(),
        title: row['title'].toString(),
        brand: row['brand']?.toString() ?? '',
        model: row['model']?.toString() ?? '',
        priceKopiykas: amount,
        affiliateUrl: link,
        checkedAt: time,
        inStock: true,
      ),
      host,
    );
  }
}

Future<List<_ApprovedOffer>> _load(
  SupabaseClient client, {
  String? listing,
  String term = '',
  int offset = 0,
}) async {
  final rows = await client.rpc(
    'partner_offers',
    params: {
      'target_listing': listing,
      'search_term': term,
      'page_offset': offset,
    },
  ) as List;
  final current = DateTime.now();
  return rows
      .whereType<Map>()
      .map((row) => _ApprovedOffer.parse(row, current))
      .whereType<_ApprovedOffer>()
      .toList();
}

Future<void> _open(
  BuildContext context,
  SupabaseClient client,
  PartnerOffer offer,
) async {
  try {
    if (DateTime.now().difference(offer.checkedAt) >
            const Duration(hours: 24) ||
        await client.rpc('touch_guardian') != true ||
        !context.mounted) return;
    if (await launchUrl(
      offer.affiliateUrl,
      mode: LaunchMode.externalApplication,
    )) return;
  } catch (_) {}
  if (context.mounted)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не вдалося відкрити магазин. Повторіть спробу.'),
      ),
    );
}

class ListingPartnerOffers extends StatefulWidget {
  const ListingPartnerOffers({
    super.key,
    required this.client,
    required this.listingId,
  });
  final SupabaseClient client;
  final String listingId;
  @override
  State<ListingPartnerOffers> createState() => _ListingPartnerOffersState();
}

class _ListingPartnerOffersState extends State<ListingPartnerOffers> {
  late final offers = _load(widget.client, listing: widget.listingId);
  @override
  Widget build(BuildContext context) => FutureBuilder<List<_ApprovedOffer>>(
        future: offers,
        builder: (_, snapshot) {
          final matches = snapshot.data;
          if (matches == null || matches.isEmpty)
            return const SizedBox.shrink();
          return PartnerComparison(
            offers: matches.map((r) => r.offer).toList(),
            brand: matches.first.offer.brand,
            model: matches.first.offer.model,
            allowedHosts: matches.map((r) => r.host).toSet(),
            now: DateTime.now(),
            openOffer: (offer) => _open(context, widget.client, offer),
          );
        },
      );
}

class PartnerOffersScreen extends StatefulWidget {
  const PartnerOffersScreen({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<PartnerOffersScreen> createState() => _PartnerOffersScreenState();
}

class _PartnerOffersScreenState extends State<PartnerOffersScreen> {
  final search = TextEditingController();
  final offers = <_ApprovedOffer>[];
  String submitted = '';
  bool busy = false, more = false, failed = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool next = false}) async {
    final ticket = ++generation;
    if (!next) {
      submitted = search.text.trim();
      offers.clear();
    }
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final page = await _load(
        widget.client,
        term: submitted,
        offset: offers.length,
      );
      if (mounted && ticket == generation)
        setState(() {
          offers.addAll(page);
          more = page.length == 30;
        });
    } catch (_) {
      if (mounted && ticket == generation) setState(() => failed = true);
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Партнерські магазини')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => load(),
              decoration: InputDecoration(
                labelText: 'Іграшка або магазин',
                suffixIcon: IconButton(
                  tooltip: 'Шукати',
                  onPressed: () => load(),
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (busy) const LinearProgressIndicator(),
            if (failed)
              TextButton(
                onPressed: () => load(next: offers.isNotEmpty),
                child: const Text('Не вдалося завантажити. Повторити'),
              ),
            if (!failed && !busy && offers.isEmpty)
              const Text('Актуальних партнерських пропозицій поки немає.'),
            if (offers.isNotEmpty)
              const Text(
                'Ціни у гривнях. ToyTown може отримати комісію за покупку.',
              ),
            for (final row in offers)
              ListTile(
                title: Text(row.offer.title),
                subtitle: Text(
                  '${row.offer.store} · ${(row.offer.priceKopiykas / 100).toStringAsFixed(2)} грн',
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _open(context, widget.client, row.offer),
              ),
            if (more && !busy && !failed)
              TextButton(
                onPressed: () => load(next: true),
                child: const Text('Ще пропозиції'),
              ),
          ],
        ),
      );
}
