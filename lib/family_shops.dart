import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'listing.dart';
import 'world_art.dart';

class PublicFamilyShop {
  PublicFamilyShop.fromMap(Map<String, dynamic> row)
    : id = row['shop_id'] as String, name = row['shop_name'] as String,
      cities = List<String>.from(row['cities'] as List? ?? []),
      listingCount = (row['listing_count'] as num).toInt(),
      theme = row['theme'] as String? ?? 'mint', front = row['front'] as String? ?? 'classic',
      balloons = row['balloons'] == true, flowers = row['flowers'] == true, awning = row['awning'] == true;
  final String id, name, theme, front;
  final List<String> cities;
  final int listingCount;
  final bool balloons, flowers, awning;
  String get cityLabel => cities.isEmpty ? 'Місто не зазначено' : cities.join(', ');
}

abstract class FamilyShopsRepository {
  static const pageSize = 24;
  Future<List<PublicFamilyShop>> browse(String term, int offset);
  Future<List<Listing>> listings(String shopId, int offset);
}

class SupabaseFamilyShopsRepository implements FamilyShopsRepository {
  SupabaseFamilyShopsRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<PublicFamilyShop>> browse(String term, int offset) async {
    final rows = await client.rpc('browse_family_shops', params: {
      'search_term': term, 'page_size': FamilyShopsRepository.pageSize, 'page_offset': offset,
    });
    return (rows as List).map((row) => PublicFamilyShop.fromMap(Map<String, dynamic>.from(row as Map))).toList();
  }
  @override
  Future<List<Listing>> listings(String shopId, int offset) async {
    final rows = await client.rpc('family_shop_listings', params: {
      'target_shop': shopId, 'page_size': FamilyShopsRepository.pageSize, 'page_offset': offset,
    });
    return (rows as List).map((row) => Listing.fromMap(Map<String, dynamic>.from(row as Map))).toList();
  }
}

class FamilyShopsScreen extends StatefulWidget {
  const FamilyShopsScreen({super.key, required this.repository, required this.listingBuilder});
  final FamilyShopsRepository repository;
  final Widget Function(Listing) listingBuilder;
  @override
  State<FamilyShopsScreen> createState() => _FamilyShopsScreenState();
}

class _FamilyShopsScreenState extends State<FamilyShopsScreen> {
  final search = TextEditingController();
  List<PublicFamilyShop> items = [];
  bool loading = true, loadingMore = false, more = false, failedAppend = false;
  String activeTerm = '';
  String? error;
  int generation = 0, offset = 0;
  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { generation++; search.dispose(); super.dispose(); }

  Future<void> load({bool append = false}) async {
    if (append && (loading || loadingMore || !more)) return;
    final ticket = append ? generation : ++generation;
    if (!append) { activeTerm = search.text.trim(); offset = 0; }
    setState(() { error = null; failedAppend = append;
      if (append) { loadingMore = true; } else { loading = true; loadingMore = false; items = []; }
    });
    try {
      final rows = await widget.repository.browse(activeTerm, offset);
      if (!mounted || ticket != generation) return;
      setState(() {
        final combined = append ? [...items, ...rows] : rows;
        items = {for (final shop in combined) shop.id: shop}.values.toList();
        offset += rows.length; more = rows.length == FamilyShopsRepository.pageSize;
      });
    } catch (_) {
      if (mounted && ticket == generation) setState(() => error = 'Не вдалося завантажити крамнички. Перевірте інтернет і спробуйте ще раз.');
    } finally {
      if (mounted && ticket == generation) setState(() { loading = false; loadingMore = false; });
    }
  }

  void visit(PublicFamilyShop shop) => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => FamilyShopScreen(shop: shop, repository: widget.repository, listingBuilder: widget.listingBuilder)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Крамнички родин', maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: SafeArea(child: RefreshIndicator(onRefresh: () => load(), child: ListView(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        const Text('Відвідуй крамнички та знаходь нові іграшки. Тут лише підтверджені оголошення.'),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('shop-search'), controller: search, maxLength: 100,
          textInputAction: TextInputAction.search, onSubmitted: (_) => load(),
          decoration: InputDecoration(labelText: 'Місто або назва крамнички', border: const OutlineInputBorder(),
            suffixIcon: IconButton(tooltip: 'Шукати крамнички', onPressed: () => load(), icon: const Icon(Icons.search)))),
        TextButton(onPressed: () { search.clear(); load(); }, child: const Text('Показати всі крамнички')),
        if (loading) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        if (error != null) ...[Text(error!), TextButton(onPressed: () => load(append: failedAppend), child: const Text('Повторити'))],
        if (!loading && error == null && items.isEmpty) const Padding(padding: EdgeInsets.all(24),
          child: Text('Крамничок поки не знайдено. Спробуйте інше місто. Крамничка з’являється після підтвердження першого оголошення.')),
        for (final shop in items) Card(margin: const EdgeInsets.only(bottom: 16), child: Padding(
          padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(shop.name, style: Theme.of(context).textTheme.titleLarge),
            Text(shop.cityLabel), Text('Опублікованих іграшок: ${shop.listingCount}'),
            const SizedBox(height: 8),
            Center(child: SizedBox(width: 200, child: ShopScene(theme: shop.theme, front: shop.front,
              balloons: shop.balloons, flowers: shop.flowers, awning: shop.awning, onTap: () => visit(shop)))),
            const SizedBox(height: 8),
            FilledButton.tonal(key: ValueKey('visit-shop-${shop.id}'), onPressed: () => visit(shop), child: const Text('Відвідати крамничку')),
          ]))),
        if (loadingMore) const Center(child: CircularProgressIndicator()),
        if (!loading && !loadingMore && more) TextButton(key: const ValueKey('more-shops'),
          onPressed: () => load(append: true), child: const Text('Ще крамнички')),
      ],
    ))),
  );
}

class FamilyShopScreen extends StatefulWidget {
  const FamilyShopScreen({super.key, required this.shop, required this.repository, required this.listingBuilder});
  final PublicFamilyShop shop;
  final FamilyShopsRepository repository;
  final Widget Function(Listing) listingBuilder;
  @override
  State<FamilyShopScreen> createState() => _FamilyShopScreenState();
}

class _FamilyShopScreenState extends State<FamilyShopScreen> {
  List<Listing> items = [];
  bool loading = true, loadingMore = false, more = false, failedAppend = false;
  String? error;
  int generation = 0, offset = 0;
  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { generation++; super.dispose(); }
  Future<void> load({bool append = false}) async {
    if (append && (loading || loadingMore || !more)) return;
    final ticket = append ? generation : ++generation;
    if (!append) offset = 0;
    setState(() { error = null; failedAppend = append;
      if (append) { loadingMore = true; } else { loading = true; loadingMore = false; items = []; }
    });
    try {
      final rows = await widget.repository.listings(widget.shop.id, offset);
      if (!mounted || ticket != generation) return;
      setState(() {
        final combined = append ? [...items, ...rows] : rows;
        items = {for (final item in combined) item.id: item}.values.toList();
        offset += rows.length; more = rows.length == FamilyShopsRepository.pageSize;
      });
    } catch (_) {
      if (mounted && ticket == generation) setState(() => error = 'Не вдалося завантажити іграшки. Перевірте інтернет і спробуйте ще раз.');
    } finally {
      if (mounted && ticket == generation) setState(() { loading = false; loadingMore = false; });
    }
  }
  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    return Scaffold(appBar: AppBar(title: Text(shop.name, maxLines: 1, overflow: TextOverflow.ellipsis)), body: SafeArea(
      child: RefreshIndicator(onRefresh: () => load(), child: ListView(
        physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
          Text(shop.cityLabel),
          Center(child: SizedBox(width: 220, child: ShopScene(theme: shop.theme, front: shop.front,
            balloons: shop.balloons, flowers: shop.flowers, awning: shop.awning))),
          const SizedBox(height: 12),
          Text('Опубліковані іграшки', style: Theme.of(context).textTheme.titleLarge),
          if (loading) const Center(child: CircularProgressIndicator()),
          if (error != null) ...[Text(error!), TextButton(onPressed: () => load(append: failedAppend), child: const Text('Повторити'))],
          if (!loading && error == null && items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Зараз у цій крамничці немає опублікованих іграшок. Оновіть список або поверніться до інших крамничок.')),
          for (final item in items) Padding(padding: const EdgeInsets.only(top: 12),
            child: KeyedSubtree(key: ValueKey('shop-listing-${item.id}'), child: widget.listingBuilder(item))),
          if (loadingMore) const Center(child: CircularProgressIndicator()),
          if (!loading && !loadingMore && more) TextButton(key: const ValueKey('more-shop-listings'),
            onPressed: () => load(append: true), child: const Text('Ще іграшки')),
        ],
      )),
    ));
  }
}
