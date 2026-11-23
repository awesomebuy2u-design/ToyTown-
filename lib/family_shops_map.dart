import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'family_shops.dart';
import 'listing.dart';
import 'settlements.dart';

class FamilyShopsMapScreen extends StatefulWidget {
  const FamilyShopsMapScreen({super.key, required this.repository,
    required this.listingBuilder, this.loadSettlements = SettlementIndex.load,
    this.showTiles = true});

  final FamilyShopsRepository repository;
  final Widget Function(Listing) listingBuilder;
  final Future<SettlementIndex> Function() loadSettlements;
  final bool showTiles;

  @override
  State<FamilyShopsMapScreen> createState() => _FamilyShopsMapScreenState();
}

class _FamilyShopsMapScreenState extends State<FamilyShopsMapScreen> {
  final search = TextEditingController();
  final map = MapController();
  SettlementIndex? index;
  List<PublicFamilyShop> items = [];
  String activeTerm = '';
  String? error;
  int generation = 0, offset = 0, tileAttempt = 0;
  int? selectedCity;
  bool loading = true, loadingMore = false, more = false, failedAppend = false;
  bool tileError = false, tileErrorQueued = false, mapReady = false;

  @override
  void initState() { super.initState(); load(); }

  @override
  void dispose() {
    generation++;
    search.dispose();
    map.dispose();
    super.dispose();
  }

  Future<void> load({bool append = false, bool refresh = false}) async {
    if (append && (loading || loadingMore || !more)) return;
    final ticket = append ? generation : ++generation;
    if (!append) {
      if (!refresh) activeTerm = search.text.trim();
      offset = 0;
    }
    setState(() {
      error = null;
      failedAppend = append;
      if (append) {
        loadingMore = true;
      } else {
        loading = true; loadingMore = false; items = []; selectedCity = null;
      }
    });
    try {
      final results = await Future.wait<Object>([
        if (index == null) widget.loadSettlements(),
        widget.repository.browse(activeTerm, offset),
      ]);
      if (!mounted || ticket != generation) return;
      final rows = results.last as List<PublicFamilyShop>;
      setState(() {
        if (index == null) index = results.first as SettlementIndex;
        items = {for (final shop in [...items, ...rows]) shop.id: shop}.values.toList();
        offset += rows.length;
        more = rows.length == FamilyShopsRepository.pageSize;
      });
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() => error = 'Не вдалося завантажити крамнички. Перевірте інтернет і спробуйте ще раз.');
      }
    } finally {
      if (mounted && ticket == generation) setState(() { loading = false; loadingMore = false; });
    }
  }

  void selectCity(ShopCity city) {
    setState(() => selectedCity = city.place.id);
    if (mapReady) map.move(city.place.point, 9);
  }

  void showUkraine() {
    if (mapReady) map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(const LatLng(44, 22), const LatLng(52.5, 40.5)),
      padding: const EdgeInsets.all(12)));
  }

  void tilesFailed() {
    if (!mounted || tileError || tileErrorQueued) return;
    tileErrorQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tileErrorQueued = false;
      if (mounted) setState(() => tileError = true);
    });
  }

  void visit(PublicFamilyShop shop) => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => FamilyShopScreen(shop: shop, repository: widget.repository,
      listingBuilder: widget.listingBuilder)));

  @override
  Widget build(BuildContext context) {
    final cities = index == null ? <ShopCity>[] : groupShopsByCity(items, index!);
    ShopCity? selected;
    for (final city in cities) {
      if (city.place.id == selectedCity) selected = city;
    }
    final visible = selected?.shops.values.toList() ?? items;
    final located = {for (final city in cities) ...city.shops.keys};
    return SafeArea(child: RefreshIndicator(
      onRefresh: () => load(refresh: true),
      child: ListView(key: const ValueKey('map-shop-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16), children: [
          Text('Крамнички на мапі України', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Позначки показують центри міст і сіл, без точних адрес родин. Натисни на позначку або назву міста, щоб обрати крамничку.'),
          const SizedBox(height: 12),
          TextField(key: const ValueKey('map-search'), controller: search, maxLength: 100,
            textInputAction: TextInputAction.search, onSubmitted: (_) => load(),
            decoration: InputDecoration(labelText: 'Місто, село або назва крамнички',
              border: const OutlineInputBorder(), suffixIcon: IconButton(
                tooltip: 'Шукати на мапі', onPressed: () => load(), icon: const Icon(Icons.search)))),
          Wrap(spacing: 8, children: [
            TextButton.icon(onPressed: () {
              search.clear(); load();
              showUkraine();
            }, icon: const Icon(Icons.public), label: const Text('Уся Україна')),
            TextButton.icon(onPressed: () => load(refresh: true),
              icon: const Icon(Icons.refresh), label: const Text('Оновити крамнички')),
          ]),
          SizedBox(height: 280, child: ClipRRect(borderRadius: BorderRadius.circular(20), child: FlutterMap(
            mapController: map,
            options: MapOptions(initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds(const LatLng(44, 22), const LatLng(52.5, 40.5)),
                padding: const EdgeInsets.all(12)),
              minZoom: 4, maxZoom: 12, onMapReady: () => mapReady = true),
            children: [
              if (widget.showTiles) TileLayer(key: ValueKey('map-tiles-$tileAttempt'),
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ua.toytown.app',
                errorTileCallback: (_, __, ___) => tilesFailed()),
              MarkerLayer(markers: [for (final city in cities) Marker(
                point: city.place.point, width: 52, height: 52,
                child: Semantics(button: true, label: '${city.label}: крамничок ${city.shops.length}',
                  child: Tooltip(message: '${city.label} · ${city.shops.length}', child: Material(
                    color: selectedCity == city.place.id ? const Color(0xFF286F61) : const Color(0xFF6C63D9),
                    shape: const CircleBorder(), child: InkWell(customBorder: const CircleBorder(),
                      key: ValueKey('map-city-${city.place.id}'), onTap: () => selectCity(city),
                      child: Center(child: Text('${city.shops.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))))))),
              )]),
              const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
            ],
          ))),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Орієнтири населених пунктів: GeoNames · CC BY 4.0', style: TextStyle(fontSize: 12))),
          if (tileError) ...[
            const Text('Фон мапи не завантажився. Міста та крамнички доступні нижче.'),
            TextButton(onPressed: () => setState(() { tileError = false; tileAttempt++; }),
              child: const Text('Завантажити мапу знову')),
          ],
          if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (error != null) ...[
            Text(error!),
            TextButton(onPressed: () => load(append: failedAppend, refresh: true), child: const Text('Повторити')),
          ],
          if (!loading && items.isNotEmpty) ...[
            Text('Завантажено крамничок: ${items.length}'),
            if (more) const Text('Щоб побачити наступні крамнички на мапі, натисни «Ще крамнички».'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final city in cities) ChoiceChip(
              key: ValueKey('map-city-choice-${city.place.id}'),
              label: Text('${city.label} · ${city.shops.length}'),
              selected: selectedCity == city.place.id,
              onSelected: (value) {
                if (value) { selectCity(city); } else { setState(() => selectedCity = null); }
              })]),
            if (located.length < items.length) const Padding(padding: EdgeInsets.only(top: 8), child: Text(
              'Для частини населених пунктів орієнтир не визначено. Ці крамнички доступні у загальному списку.')),
            const SizedBox(height: 12),
            if (selected != null) TextButton(onPressed: () => setState(() => selectedCity = null),
              child: const Text('Показати всі завантажені крамнички')),
            Text(selected == null ? 'Крамнички родин' : 'Крамнички: ${selected.label}',
              style: Theme.of(context).textTheme.titleMedium),
          ],
          if (!loading && error == null && items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('Крамничок не знайдено. Спробуй інший населений пункт. На мапі з’являються крамнички з підтвердженими оголошеннями.')),
          for (final shop in visible) Padding(padding: const EdgeInsets.only(top: 8), child: Card(child: Padding(
            padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(shop.name, style: Theme.of(context).textTheme.titleMedium),
              Text(shop.cityLabel), Text('Опублікованих іграшок: ${shop.listingCount}'),
              const SizedBox(height: 8),
              FilledButton.tonal(key: ValueKey('map-visit-shop-${shop.id}'),
                onPressed: () => visit(shop), child: const Text('Відвідати крамничку')),
            ])))),
          if (loadingMore) const Center(child: CircularProgressIndicator()),
          if (!loading && !loadingMore && more) TextButton(key: const ValueKey('map-more-shops'),
            onPressed: () => load(append: true), child: const Text('Ще крамнички')),
        ],
      ),
    ));
  }
}
