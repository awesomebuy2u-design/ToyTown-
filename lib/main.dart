import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'toytown_world.dart';
import 'listing.dart';
import 'family_shops.dart';
import 'family_shops_map.dart';
import 'content_actions.dart';
import 'app_version.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const ToyTownApp());
}

bool get hasBackend => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
SupabaseClient? get db => hasBackend ? Supabase.instance.client : null;

class ToyTownApp extends StatelessWidget {
  const ToyTownApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ToyTown',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63D9)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF8F7FC),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
    ),
    home: const WorldScreen(),
  );
}

class WorldScreen extends StatelessWidget {
  const WorldScreen({super.key});

  void openOnline(BuildContext context, int tab, {bool shops = false}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => hasBackend ? AuthGate(initialTab: tab, shops: shops) : const SetupScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) => ToyTownWorld(
    client: db,
    openListings: () => openOnline(context, 0),
    openParent: () => openOnline(context, 4),
    openShops: () => openOnline(context, 0, shops: true),
    openMyListings: () => openOnline(context, 1),
    openChats: () => openOnline(context, 5),
    openOwnListing: (item) async {
      await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => ListingDetails(
        item: item, canContact: false,
        onDelete: () async { await db!.rpc('delete_own_listing', params: {'target_listing': item.id}); },
      )));
    },
  );
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.toys_rounded, size: 64, color: Color(0xFF6C63D9)),
        const SizedBox(height: 16),
        const Text('ToyTown', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Щоб запустити онлайн-версію, додайте URL та публічний ключ Supabase. Інструкція — у файлі SUPABASE_SETUP.md.',
          textAlign: TextAlign.center),
        const SizedBox(height: 18),
        const Chip(label: Text('Режим налаштування')),
      ]),
    )),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, this.initialTab = 0, this.shops = false});
  final int initialTab;
  final bool shops;
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: db!.auth.onAuthStateChange,
    builder: (context, snapshot) {
      final session = db!.auth.currentSession;
      return session == null ? const AuthScreen() : shops
        ? FamilyShopsScreen(repository: SupabaseFamilyShopsRepository(db!), listingBuilder: (item) => ListingCard(item: item))
        : HomeShell(initialTab: initialTab);
    },
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = false, busy = false;
  String? error;
  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      if (register) {
        await db!.auth.signUp(email: email.text.trim(), password: password.text);
      } else {
        await db!.auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } on AuthException catch (e) { setState(() => error = e.message); }
      catch (e) { setState(() => error = 'Не вдалося виконати запит: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.toys_rounded, size: 64, color: Color(0xFF6C63D9)),
        const SizedBox(height: 12),
        const Text('ToyTown', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const Text('Іграшки знаходять нових друзів', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль (від 8 символів)', border: OutlineInputBorder())),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 18),
        FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Зачекайте…' : register ? 'Створити обліковий запис дорослого' : 'Увійти')),
        TextButton(onPressed: () => setState(() { register = !register; error = null; }),
          child: Text(register ? 'Уже маєте обліковий запис? Увійти' : 'Створити обліковий запис')),
        const Text('Обліковий запис створює та контролює дорослий. Дитячі профілі не мають окремого входу.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    ))),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> {
  late int index = widget.initialTab;
  final pages = const [CatalogScreen(), MyShopScreen(), ModerationScreen(), MapScreen(), FamilyScreen(), ChatsScreen(), AgreementsScreen()];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ToyTown'), actions: [
      IconButton(tooltip: 'Про ToyTown', onPressed: () => showToyTownVersion(context), icon: const Icon(Icons.info_outline)),
      IconButton(tooltip: 'Вийти', onPressed: () => db!.auth.signOut(), icon: const Icon(Icons.logout))
    ]),
    body: pages[index],
    floatingActionButton: index == 1 ? FloatingActionButton.extended(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddListingScreen())),
      icon: const Icon(Icons.add), label: const Text('Додати іграшку')) : null,
    bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Каталог'),
      NavigationDestination(icon: Icon(Icons.toys_outlined), selectedIcon: Icon(Icons.toys), label: 'Моя крамничка'),
      NavigationDestination(icon: Icon(Icons.verified_user_outlined), selectedIcon: Icon(Icons.verified_user), label: 'Підтвердження'),
      NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Карта'),
      NavigationDestination(icon: Icon(Icons.family_restroom_outlined), selectedIcon: Icon(Icons.family_restroom), label: 'Родина'),
      NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Чати'),
      NavigationDestination(icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake), label: 'Угоди'),
    ]),
  );
}


Future<List<Listing>> fetchListings({bool mine = false}) async {
  final user = db!.auth.currentUser!;
  var query = db!.from('listings').select();
  if (mine) {
    final memberships = await db!.from('family_members').select('family_id').eq('user_id', user.id);
    if (memberships.isEmpty) return [];
    query = db!.from('listings').select().inFilter('family_id', memberships.map((row) => row['family_id']).toList()).isFilter('deleted_at', null);
  } else {
    query = db!.from('public_listings').select();
  }
  final rows = await query.order('created_at', ascending: false);
  return rows.map<Listing>((e) => Listing.fromMap(e)).toList();
}

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late Future<List<Listing>> future;
  final search = TextEditingController();
  String category = 'Усі категорії';
  String deal = 'Усі формати';

  @override
  void initState() {
    super.initState();
    future = fetchListings();
  }

  Future<void> refresh() async => setState(() { future = fetchListings(); });

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Listing>>(
    future: future,
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Помилка завантаження: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final term = search.text.trim().toLowerCase();
      final items = snap.data!.where((item) {
        final matchesText = term.isEmpty ||
          item.title.toLowerCase().contains(term) ||
          item.description.toLowerCase().contains(term) ||
          item.city.toLowerCase().contains(term);
        final matchesCategory = category == 'Усі категорії' || item.category == category;
        final matchesDeal = deal == 'Усі формати' ||
          (deal == 'Дарування' && item.dealType == 'gift') ||
          (deal == 'Обмін' && item.dealType == 'exchange') ||
          (deal == 'Продаж' && item.dealType == 'sale');
        return matchesText && matchesCategory && matchesDeal;
      }).toList();
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(children: [
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyShopsScreen(
              repository: SupabaseFamilyShopsRepository(db!), listingBuilder: (item) => ListingCard(item: item)))),
            icon: const Icon(Icons.holiday_village_rounded), label: const Text('Крамнички родин'))),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedListingsScreen())),
            icon: const Icon(Icons.bookmark_outline), label: const Text('Збережені оголошення'))),
          TextField(controller: search, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search),
              hintText: 'Пошук іграшок або міста', border: const OutlineInputBorder(),
              suffixIcon: search.text.isEmpty ? null : IconButton(
                icon: const Icon(Icons.clear), onPressed: () { search.clear(); setState(() {}); })),),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(value: category,
              decoration: const InputDecoration(labelText: 'Категорія', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
              items: ['Усі категорії','Конструктори','Ляльки','Машинки','Настільні ігри','М’які іграшки','Інше'].map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => category = v ?? 'Усі категорії'))),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(value: deal,
              decoration: const InputDecoration(labelText: 'Формат', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
              items: ['Усі формати','Дарування','Обмін','Продаж'].map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => deal = v ?? 'Усі формати'))),
          ]),
        ])),
        Expanded(child: RefreshIndicator(onRefresh: refresh, child: items.isEmpty
          ? ListView(children: const [SizedBox(height: 70), EmptyState(icon: Icons.search_off, title: 'Нічого не знайдено', subtitle: 'Змініть пошуковий запит або фільтри.')])
          : ListView.separated(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => ListingCard(item: items[i])))),
      ]);
    },
  );
}

class MyShopScreen extends StatefulWidget {
  const MyShopScreen({super.key, this.loadListings, this.deleteListing});
  final Future<List<Listing>> Function()? loadListings;
  final Future<void> Function(String)? deleteListing;
  @override
  State<MyShopScreen> createState() => _MyShopScreenState();
}
class _MyShopScreenState extends State<MyShopScreen> {
  late Future<List<Listing>> future;
  Future<List<Listing>> load() => widget.loadListings?.call() ?? fetchListings(mine: true);
  @override
  void initState() { super.initState(); future = load(); }
  Future<void> refresh() async => setState(() { future = load(); });
  Future<void> deleteListing(String id) async {
    if (widget.deleteListing != null) {
      await widget.deleteListing!(id);
    } else {
      await db!.rpc('delete_own_listing', params: {'target_listing': id});
    }
    if (mounted) await refresh();
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Listing>>(
    future: future,
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Спочатку створіть профіль родини у вкладці «Родина». ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Мої оголошення', style: Theme.of(context).textTheme.titleLarge)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Керуйте іграшками родини. Кнопка видалення є на картці та всередині оголошення.')),
        Expanded(child: RefreshIndicator(onRefresh: refresh, child: snap.data!.isEmpty
        ? ListView(children: const [SizedBox(height: 120), EmptyState(icon: Icons.add_box_outlined, title: 'Ваша крамничка порожня', subtitle: 'Додайте першу іграшку — вона з’явиться після батьківського підтвердження.')])
        : ListView.separated(padding: const EdgeInsets.all(16), itemCount: snap.data!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) {
            final item = snap.data![i];
            return ListingCard(key: ValueKey(item.id), item: item, showStatus: true,
              onDelete: () => deleteListing(item.id), onChanged: refresh);
          }))),
      ]);
    },
  );
}

class ListingCard extends StatefulWidget {
  final Listing item; final bool showStatus;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onChanged;
  const ListingCard({super.key, required this.item, this.showStatus = false, this.onDelete, this.onChanged});
  @override
  State<ListingCard> createState() => _ListingCardState();
}
class _ListingCardState extends State<ListingCard> {
  bool saved = false, saving = false;
  @override
  void initState() { super.initState(); if (!widget.showStatus) _loadSaved(); }
  Future<void> _loadSaved() async {
    try {
      final member = await db!.from('family_members').select('family_id').eq('user_id', db!.auth.currentUser!.id).maybeSingle();
      if (member == null) return;
      final row = await db!.from('saved_listings').select('listing_id').eq('family_id', member['family_id']).eq('listing_id', widget.item.id).maybeSingle();
      if (mounted) setState(() => saved = row != null);
    } catch (_) {}
  }
  Future<void> _toggleSaved() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final member = await db!.from('family_members').select('family_id').eq('user_id', db!.auth.currentUser!.id).maybeSingle();
      if (member == null) throw Exception('Спочатку створіть профіль родини у вкладці «Родина».');
      if (saved) {
        await db!.from('saved_listings').delete().eq('family_id', member['family_id']).eq('listing_id', widget.item.id);
      } else {
        await db!.from('saved_listings').insert({'family_id': member['family_id'], 'listing_id': widget.item.id});
      }
      if (mounted) setState(() => saved = !saved);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не вдалося зберегти: $e')));
    } finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) {
    final item = widget.item; final showStatus = widget.showStatus;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.toys, color: Color(0xFF6C63D9)), const SizedBox(width: 8), Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))), if (showStatus) StatusChip(status: item.status), if (!showStatus) IconButton(tooltip: saved ? 'Прибрати зі збереженого' : 'Зберегти', onPressed: saving ? null : _toggleSaved, icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, color: saved ? const Color(0xFF6C63D9) : null))]),
      if (showStatus && widget.onDelete != null) ContentDeleteButton(
        key: ValueKey('delete-listing-${item.id}'), kind: DeletableContent.listing, onDelete: widget.onDelete!),
      const SizedBox(height: 8), Text(item.description),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [Chip(label: Text(item.category)), Chip(label: Text(item.city)), Chip(label: Text(item.dealType == 'gift' ? 'Дарують' : item.dealType == 'exchange' ? 'Обмін' : 'Продаж'))]),
      TextButton.icon(
        onPressed: () async {
          final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
            builder: (_) => ListingDetails(item: item, canContact: !showStatus, onDelete: widget.onDelete),
          ));
          if (deleted == true && context.mounted) await widget.onChanged?.call();
        },
        icon: const Icon(Icons.open_in_new),
        label: const Text('Переглянути оголошення'),
      ),
      if (!showStatus) Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:()=>_startListingChat(context,item),icon:const Icon(Icons.chat_bubble_outline),label:const Text('Написати родині'))),
    ])));
  }
}

class SavedListingsScreen extends StatefulWidget {
  const SavedListingsScreen({super.key});
  @override
  State<SavedListingsScreen> createState() => _SavedListingsScreenState();
}
class _SavedListingsScreenState extends State<SavedListingsScreen> {
  late Future<List<Listing>> future;
  @override
  void initState() { super.initState(); future = _load(); }
  Future<List<Listing>> _load() async {
    final member = await db!.from('family_members').select('family_id').eq('user_id', db!.auth.currentUser!.id).maybeSingle();
    if (member == null) return [];
    final rows = await db!.from('saved_listings').select('listing_id').eq('family_id', member['family_id']);
    final ids = rows.map((r) => r['listing_id'].toString()).toList();
    if (ids.isEmpty) return [];
    final listings = await db!.from('public_listings').select().inFilter('id', ids).order('created_at', ascending: false);
    return listings.map<Listing>((r) => Listing.fromMap(r)).toList();
  }
  Future<void> refresh() async => setState(() { future = _load(); });
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Збережені оголошення')), body: FutureBuilder<List<Listing>>(
    future: future, builder: (context, snap) {
      if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Не вдалося завантажити збережене: ${snap.error}')));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(onRefresh: refresh, child: snap.data!.isEmpty
        ? ListView(children: const [SizedBox(height: 90), EmptyState(icon: Icons.bookmark_border, title: 'Поки нічого не збережено', subtitle: 'Натискайте значок закладки в каталозі, щоб повернутися до оголошення пізніше.')])
        : ListView.separated(padding: const EdgeInsets.all(16), itemCount: snap.data!.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => ListingCard(item: snap.data![i])));
    }));
}

class ListingDetails extends StatefulWidget {
  const ListingDetails({super.key, required this.item, required this.canContact, this.onDelete});

  final Listing item;
  final bool canContact;
  final Future<void> Function()? onDelete;

  @override
  State<ListingDetails> createState() => _ListingDetailsState();
}

class _ListingDetailsState extends State<ListingDetails> {
  late Future<String>? photo = loadPhoto();
  bool ownsListing = false;

  @override
  void initState() { super.initState(); ownsListing = widget.onDelete != null; if (!ownsListing) checkOwner(); }
  Future<void> checkOwner() async {
    if (db?.auth.currentUser == null) return;
    try {
      final members = await db!.from('family_members').select('family_id').eq('user_id', db!.auth.currentUser!.id);
      if (members.isEmpty) return;
      final row = await db!.from('listings').select('id').eq('id', widget.item.id).inFilter('family_id', members.map((member) => member['family_id']).toList()).isFilter('deleted_at', null).maybeSingle();
      if (mounted) setState(() => ownsListing = row != null);
    } catch (_) { /* Ownership is never inferred after a failed request. */ }
  }
  Future<void> removeListing() async {
    if (widget.onDelete != null) { await widget.onDelete!(); }
    else { await db!.rpc('delete_own_listing', params: {'target_listing': widget.item.id}); }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<String>? loadPhoto() {
    final path = widget.item.photoPath;
    if (path == null || path.isEmpty) return null;
    return db!.storage.from('listing-images').createSignedUrl(path, 60);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final format = switch (item.dealType) {
      'gift' => 'Дарують',
      'exchange' => 'Обмін',
      _ => 'Продаж',
    };
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (photo != null)
              FutureBuilder<String>(
                future: photo,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return TextButton(
                      onPressed: () => setState(() { photo = loadPhoto(); }),
                      child: const Text('Не вдалося завантажити фото. Повторити'),
                    );
                  }
                  final url = snapshot.data;
                  if (url == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Image.network(
                    url,
                    height: 260,
                    fit: BoxFit.contain,
                    semanticLabel: 'Фото іграшки',
                    errorBuilder: (_, __, ___) => TextButton(
                      onPressed: () => setState(() { photo = loadPhoto(); }),
                      child: const Text('Не вдалося відкрити фото. Повторити'),
                    ),
                  );
                },
              )
            else
              const Text('Фото не додано'),
            const SizedBox(height: 16),
            Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
            Text([item.category, item.city, format].join(' · ')),
            if (item.dealType == 'sale' && item.price != null)
              Text('${item.price} грн'),
            const SizedBox(height: 12),
            Text(item.description),
            if (widget.canContact && !ownsListing)
              FilledButton.icon(
                onPressed: () => _startListingChat(context, item),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Написати родині'),
              ),
          ],
        ),
      ),
      bottomNavigationBar: ownsListing ? SafeArea(child: Padding(padding: const EdgeInsets.all(12),
        child: ContentDeleteButton(kind: DeletableContent.listing, onDelete: removeListing))) : null,
    );
  }
}

Future<void> _startListingChat(BuildContext context, Listing item) async {
  try { final id=await db!.rpc('start_listing_conversation',params:{'target_listing':item.id});
    if(context.mounted) await Navigator.push(context,MaterialPageRoute(builder:(_)=>ConversationScreen(conversationId:id.toString(),title:item.title)));
  } catch(e) { if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Не вдалося відкрити чат: $e'))); }
}

class StatusChip extends StatelessWidget {
  final String status; const StatusChip({super.key, required this.status});
  @override
  Widget build(BuildContext context) => Chip(label: Text(status == 'approved' ? 'Опубліковано' : status == 'rejected' ? 'Відхилено' : 'На перевірці'));
}

class AddListingScreen extends StatefulWidget {
  const AddListingScreen({super.key});
  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}
class _AddListingScreenState extends State<AddListingScreen> {
  final title = TextEditingController(), description = TextEditingController(), city = TextEditingController();
  String category = 'Конструктори', condition = 'used', deal = 'gift';
  bool busy = false; XFile? photo;
  Future<void> pickPhoto() async { photo = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82, maxWidth: 1400); setState(() {}); }
  Future<void> save() async {
    if (title.text.trim().isEmpty || city.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вкажіть назву і місто.'))); return; }
    setState(() => busy = true);
    try {
      final member = await db!.from('family_members').select('family_id').eq('user_id', db!.auth.currentUser!.id).maybeSingle();
      if (member == null) throw Exception('Спочатку створіть профіль родини у вкладці «Родина».');
      String? photoUrl;
      if (photo != null) {
        final bytes = await photo!.readAsBytes();
        final path = '${member['family_id']}/${DateTime.now().millisecondsSinceEpoch}_${photo!.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
        await db!.storage.from('listing-images').uploadBinary(path, bytes);
        photoUrl = path;
      }
      await db!.from('listings').insert({
        'family_id': member['family_id'], 'title': title.text.trim(),
        'description': description.text.trim(), 'category': category,
        'condition': condition, 'deal_type': deal, 'city': city.text.trim(),
        'photo_path': photoUrl, 'status': 'pending'
      });
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оголошення надіслано батькам на підтвердження.'))); Navigator.pop(context); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { title.dispose(); description.dispose(); city.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Нова іграшка')), body: ListView(padding: const EdgeInsets.all(16), children: [
    TextField(controller: title, decoration: const InputDecoration(labelText: 'Назва іграшки', border: OutlineInputBorder())),
    const SizedBox(height: 12), TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Опис', border: OutlineInputBorder())),
    const SizedBox(height: 12), TextField(controller: city, decoration: const InputDecoration(labelText: 'Місто (без адреси)', border: OutlineInputBorder())),
    const SizedBox(height: 12), DropdownButtonFormField(value: category, decoration: const InputDecoration(labelText: 'Категорія'), items: ['Конструктори','Ляльки','Машинки','Настільні ігри','М’які іграшки','Інше'].map((v)=>DropdownMenuItem(value:v, child:Text(v))).toList(), onChanged:(v)=>setState(()=>category=v!)),
    const SizedBox(height: 12), DropdownButtonFormField(value: condition, decoration: const InputDecoration(labelText: 'Стан'), items: const [DropdownMenuItem(value:'new', child:Text('Нова')), DropdownMenuItem(value:'used', child:Text('Вживана'))], onChanged:(v)=>setState(()=>condition=v!)),
    const SizedBox(height: 12), DropdownButtonFormField(value: deal, decoration: const InputDecoration(labelText: 'Формат'), items: const [DropdownMenuItem(value:'gift', child:Text('Дарування')), DropdownMenuItem(value:'exchange', child:Text('Обмін')), DropdownMenuItem(value:'sale', child:Text('Продаж'))], onChanged:(v)=>setState(()=>deal=v!)),
    const SizedBox(height: 12), OutlinedButton.icon(onPressed: pickPhoto, icon: const Icon(Icons.photo), label: Text(photo == null ? 'Додати фото' : 'Фото вибрано')),
    const SizedBox(height: 8), FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Збереження…' : 'Надіслати на підтвердження')),
    const SizedBox(height: 12), const Text('Оголошення не публікується автоматично. Воно очікує перевірки дорослим.', style: TextStyle(color: Colors.black54)),
  ]));
}


class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});
  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  late Future<List<Map<String, dynamic>>> future;
  bool busy = false;
  @override
  void initState() { super.initState(); future = loadPending(); }

  Future<List<Map<String, dynamic>>> loadPending() async {
    final userId = db!.auth.currentUser!.id;
    final member = await db!.from('family_members').select('family_id').eq('user_id', userId).maybeSingle();
    if (member == null) return [];
    final rows = await db!.from('listings').select('id,title,description,city,category,deal_type,photo_path,created_at')
      .eq('family_id', member['family_id']).eq('status', 'pending').order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> decide(Map<String, dynamic> item, bool approve) async {
    setState(() => busy = true);
    try {
      await db!.rpc('approve_listing', params: {
        'target_listing': item['id'], 'approve': approve,
        'note': approve ? 'Підтверджено дорослим у застосунку' : 'Відхилено дорослим у застосунку',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Оголошення опубліковано.' : 'Оголошення відхилено.')));
      setState(() { future = loadPending(); });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не вдалося змінити статус: $e')));
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: future,
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Помилка завантаження черги: ${snap.error}')));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.isEmpty) return const EmptyState(icon: Icons.verified_user, title: 'Немає оголошень на перевірці', subtitle: 'Нові оголошення родини з’являться тут перед публікацією.');
      return RefreshIndicator(onRefresh: () async => setState(() { future = loadPending(); }), child: ListView.separated(
        padding: const EdgeInsets.all(16), itemCount: snap.data!.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final item = snap.data![i];
          return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 6), Text(item['description'] ?? ''),
            const SizedBox(height: 8), Wrap(spacing: 8, children: [Chip(label: Text(item['category'] ?? 'Інше')), Chip(label: Text(item['city'] ?? ''))]),
            const SizedBox(height: 8), const Text('Переконайтеся, що опис і фото не містять персональних даних дитини або домашньої адреси.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12), Row(children: [Expanded(child: OutlinedButton(onPressed: busy ? null : () => decide(item, false), child: const Text('Відхилити'))), const SizedBox(width: 10), Expanded(child: FilledButton(onPressed: busy ? null : () => decide(item, true), child: const Text('Підтвердити')))]),
          ])));
        },
      ));
    },
  );
}

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}
class _FamilyScreenState extends State<FamilyScreen> {
  final familyName = TextEditingController(), guardianName = TextEditingController(), city = TextEditingController();
  final childNickname = TextEditingController();
  String childAgeBand = '6_8';
  bool busy = false, childBusy = false; Map<String,dynamic>? profile;
  List<Map<String,dynamic>> children = [];
  List<Map<String,dynamic>> notifications = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try { final id = db!.auth.currentUser!.id; final row = await db!.from('family_members').select('family_id, families(name, city, guardian_name)').eq('user_id', id).maybeSingle();
      if (row != null) {
        profile = row; final f = row['families'];
        familyName.text = f['name'] ?? ''; city.text = f['city'] ?? ''; guardianName.text = f['guardian_name'] ?? '';
        final childRows = await db!.from('child_profiles').select('id,nickname,age_band,created_at').eq('family_id', row['family_id']).order('created_at');
        children = List<Map<String,dynamic>>.from(childRows);
        final noticeRows = await db!.from('family_notifications').select('id,title,body,kind,is_read,created_at').eq('family_id', row['family_id']).order('created_at', ascending: false).limit(30);
        notifications = List<Map<String,dynamic>>.from(noticeRows);
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }
  Future<void> save() async {
    if (familyName.text.trim().isEmpty || guardianName.text.trim().isEmpty || city.text.trim().isEmpty) return;
    setState(()=>busy=true);
    try {
      final user = db!.auth.currentUser!;
      if (profile == null) {
        final f = await db!.from('families').insert({'name':familyName.text.trim(),'guardian_name':guardianName.text.trim(),'city':city.text.trim(),'created_by':user.id}).select('id').single();
        await db!.from('family_members').insert({'family_id':f['id'],'user_id':user.id,'role':'guardian'});
      } else {
        await db!.from('families').update({'name':familyName.text.trim(),'guardian_name':guardianName.text.trim(),'city':city.text.trim()}).eq('id',profile!['family_id']);
      }
      await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Профіль родини збережено.')));
    } catch(e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); }
    finally { if(mounted)setState(()=>busy=false); }
  }
  Future<void> addChild() async {
    final familyId = profile?['family_id'];
    if (familyId == null || childNickname.text.trim().isEmpty) return;
    setState(() => childBusy = true);
    try {
      await db!.from('child_profiles').insert({'family_id': familyId, 'nickname': childNickname.text.trim(), 'age_band': childAgeBand});
      childNickname.clear(); await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дитячий профіль додано.')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не вдалося додати профіль: $e'))); }
    finally { if (mounted) setState(() => childBusy = false); }
  }
  Future<void> markNotificationRead(String id) async {
    try { await db!.from('family_notifications').update({'is_read': true}).eq('id', id); await load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не вдалося оновити сповіщення: $e'))); }
  }
  Future<void> deleteChild(String id) async {
    try { await db!.from('child_profiles').delete().eq('id', id); await load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не вдалося видалити профіль: $e'))); }
  }
  @override
  void dispose(){familyName.dispose();guardianName.dispose();city.dispose();childNickname.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Профіль родини',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
    const SizedBox(height:8), const Text('Дані дорослого залишаються приватними. Не вказуйте домашню адресу.'),
    const SizedBox(height:16), TextField(controller:guardianName,decoration:const InputDecoration(labelText:'Ім’я дорослого',border:OutlineInputBorder())),
    const SizedBox(height:12), TextField(controller:familyName,decoration:const InputDecoration(labelText:'Назва родини / крамнички',border:OutlineInputBorder())),
    const SizedBox(height:12), TextField(controller:city,decoration:const InputDecoration(labelText:'Місто',border:OutlineInputBorder())),
    const SizedBox(height:16), FilledButton(onPressed:busy?null:save,child:Text(busy?'Збереження…':'Зберегти профіль')),
    if (profile != null) ...[
      const SizedBox(height:24), const Text('Сповіщення родини',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      const SizedBox(height:8),
      if (notifications.isEmpty) const Text('Поки немає сповіщень.'),
      ...notifications.map((n)=>Card(child:ListTile(leading:Icon(n['kind']=='approved'?Icons.check_circle:n['kind']=='rejected'?Icons.info_outline:Icons.notifications_active,color:n['is_read']==true?Colors.grey:const Color(0xFF6C63D9)),title:Text(n['title']??''),subtitle:Text(n['body']??''),trailing:n['is_read']==true?null:IconButton(tooltip:'Позначити прочитаним',icon:const Icon(Icons.done),onPressed:()=>markNotificationRead(n['id'].toString()))))),
      const SizedBox(height:24), const Text('Дитячі профілі',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      const SizedBox(height:6), const Text('Використовуйте лише псевдонім. Не додавайте прізвище, дату народження чи інші персональні дані.'),
      const SizedBox(height:12), TextField(controller:childNickname,maxLength:32,decoration:const InputDecoration(labelText:'Псевдонім дитини',border:OutlineInputBorder())),
      const SizedBox(height:8), DropdownButtonFormField<String>(value:childAgeBand,decoration:const InputDecoration(labelText:'Вікова група'),items:const [DropdownMenuItem(value:'under_6',child:Text('До 6 років')),DropdownMenuItem(value:'6_8',child:Text('6–8 років')),DropdownMenuItem(value:'9_12',child:Text('9–12 років')),DropdownMenuItem(value:'13_17',child:Text('13–17 років'))],onChanged:(v)=>setState(()=>childAgeBand=v??'6_8')),
      const SizedBox(height:8), FilledButton.tonal(onPressed:childBusy?null:addChild,child:Text(childBusy?'Додавання…':'Додати дитячий профіль')),
      const SizedBox(height:8), ...children.map((c)=>Card(child:ListTile(title:Text(c['nickname']??''),subtitle:Text(switch(c['age_band']){'under_6'=>'До 6 років','6_8'=>'6–8 років','9_12'=>'9–12 років','13_17'=>'13–17 років',_=>'Вікова група'}),trailing:IconButton(tooltip:'Видалити',icon:const Icon(Icons.delete_outline),onPressed:()=>deleteChild(c['id'].toString()))))),
    ],
    const SizedBox(height:20), const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Батьківське підтвердження: усі нові оголошення мають статус «На перевірці». Публікація доступна лише після окремого схвалення дорослим через захищену серверну дію.'))),
  ]);
}


class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, this.loadConversations, this.clearConversation});
  final Future<List<Map<String, dynamic>>> Function()? loadConversations;
  final Future<void> Function(String)? clearConversation;
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}
class _ChatsScreenState extends State<ChatsScreen> {
  bool busy = false;
  List<Map<String,dynamic>> chats = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      if (widget.loadConversations != null) {
        final rows = await widget.loadConversations!();
        if (mounted) setState(() => chats = rows);
        return;
      }
      final rows = await db!.from('family_conversations').select('id,listing_id,created_at,updated_at,family_a,family_b,listing:listings(title)').order('updated_at', ascending:false);
      final states = await db!.from('conversation_user_state').select('conversation_id,hidden').eq('user_id', db!.auth.currentUser!.id);
      final hidden = {for (final row in states) if (row['hidden'] == true) row['conversation_id']};
      if (mounted) setState(() => chats = List<Map<String,dynamic>>.from(rows).where((row) => !hidden.contains(row['id'])).toList());
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Не вдалося завантажити чати: $e'))); }
  }
  Future<void> clearConversation(String id) async {
    if (widget.clearConversation != null) { await widget.clearConversation!(id); }
    else { await db!.rpc('clear_own_conversation', params: {'target_conversation': id}); }
    if (mounted) await load();
  }
  Future<void> startChat() async {
    final listing = TextEditingController();
    final id = await showDialog<String>(context:context,builder:(context)=>AlertDialog(
      title:const Text('Почати розмову'),
      content:TextField(controller:listing,decoration:const InputDecoration(labelText:'ID оголошення',hintText:'Вставте ID оголошення')),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Скасувати')),FilledButton(onPressed:()=>Navigator.pop(context,listing.text.trim()),child:const Text('Продовжити'))],
    ));
    listing.dispose();
    if (id == null || id.isEmpty) return;
    setState(()=>busy=true);
    try {
      final result = await db!.rpc('start_listing_conversation',params:{'target_listing':id});
      await load();
      if (!mounted) return;
      final conversationId = result.toString();
      await Navigator.push(context,MaterialPageRoute(builder:(_)=>ConversationScreen(conversationId:conversationId,title:'Розмова щодо оголошення')));
      await load();
    } catch(e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Не вдалося створити розмову: $e'))); }
    finally { if (mounted) setState(()=>busy=false); }
  }
  @override
  Widget build(BuildContext context)=>RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
    Row(children:[const Expanded(child:Text('Приватні чати',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold))),FilledButton.icon(onPressed:busy?null:startChat,icon:const Icon(Icons.add_comment),label:const Text('Новий чат'))]),
    const SizedBox(height:8),const Text('Листування доступне лише дорослим учасникам родин. Не надсилайте адресу, телефон дитини або інші персональні дані.'),
    const SizedBox(height:16),
    if(chats.isEmpty) const EmptyState(icon:Icons.forum_outlined,title:'Поки немає розмов',subtitle:'Відкрийте оголошення в каталозі та натисніть «Написати родині».'),
    ...chats.map((c)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.forum_outlined)),title:Text((c['listing'] is Map ? c['listing']['title'] : null) ?? 'Домовленість між родинами'),subtitle:Text('Створено: ${c['created_at'].toString().substring(0,10)}'),
      trailing: ContentDeleteButton(kind: DeletableContent.conversation, compact: true, onDelete: () => clearConversation(c['id'].toString())),
      onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ConversationScreen(conversationId:c['id'].toString(),title:(c['listing'] is Map ? c['listing']['title'] : null) ?? 'Розмова'))).then((_)=>load())))),
  ]));
}

class ConversationScreen extends StatefulWidget {
  final String conversationId, title;
  const ConversationScreen({super.key,required this.conversationId,required this.title,
    this.messageLoader, this.clearChat, this.currentUserId});
  final Future<List<Map<String, dynamic>>> Function()? messageLoader;
  final Future<void> Function()? clearChat;
  final String? currentUserId;
  @override
  State<ConversationScreen> createState()=>_ConversationScreenState();
}
class _ConversationScreenState extends State<ConversationScreen> {
  final composer=TextEditingController();
  final deletedMessageIds = <String>{};
  List<Map<String,dynamic>> messages=[];
  bool sending=false,loading=true;
  @override
  void initState(){super.initState();load();}
  Future<void> load() async {
    try { final rows=widget.messageLoader != null ? await widget.messageLoader!()
      : await db!.from('family_messages').select('id,sender_user_id,body,created_at').eq('conversation_id',widget.conversationId).order('created_at');
      if(mounted)setState(()=>messages=List<Map<String,dynamic>>.from(rows)
        .where((message) => !deletedMessageIds.contains(message['id'].toString())).toList());
    } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Помилка завантаження: $e')));}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> createAgreement() async {
    final note = TextEditingController(text: 'Домовленість щодо іграшки з цієї розмови. Передачу узгоджують дорослі у громадському місці.');
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Нова домовленість'),
      content: TextField(controller: note, maxLines: 3, maxLength: 500, decoration: const InputDecoration(labelText: 'Умови домовленості')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Надіслати пропозицію'))],
    ));
    if (accepted != true) { note.dispose(); return; }
    try {
      await db!.rpc('create_exchange_agreement', params: {'target_conversation': widget.conversationId, 'agreement_note': note.text.trim()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пропозицію домовленості створено. Відкрийте вкладку «Угоди».')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не вдалося створити домовленість: $e'))); }
    finally { note.dispose(); }
  }

  Future<void> send() async {
    final body=composer.text.trim(); if(body.isEmpty||sending)return;
    setState(()=>sending=true);
    try { await db!.from('family_messages').insert({'conversation_id':widget.conversationId,'sender_user_id':db!.auth.currentUser!.id,'body':body}); composer.clear(); await load(); }
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Не вдалося надіслати: $e')));}
    finally{if(mounted)setState(()=>sending=false);}
  }
  Future<void> deleteMessage(String id) async {
    await db!.rpc('delete_own_message', params: {'target_message': id});
    if (mounted) setState(() {
      deletedMessageIds.add(id);
      messages.removeWhere((message) => message['id'].toString() == id);
    });
  }
  Future<void> clearChat() async {
    if (widget.clearChat != null) { await widget.clearChat!(); }
    else { await db!.rpc('clear_own_conversation', params: {'target_conversation': widget.conversationId}); }
    if (mounted) Navigator.of(context).pop();
  }
  @override
  void dispose(){composer.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){final myId=widget.currentUserId ?? db!.auth.currentUser!.id;return Scaffold(
    appBar:AppBar(title:Text(widget.title,maxLines:1,overflow:TextOverflow.ellipsis),actions:[
      IconButton(tooltip:'Створити домовленість',icon:const Icon(Icons.handshake_outlined),onPressed:createAgreement),PopupMenuButton<String>(tooltip:'Домовленість',onSelected:(v){composer.text=v;},itemBuilder:(_)=>const [PopupMenuItem(value:'Пропоную обмінятися цією іграшкою. Чи цікава вам така пропозиція?',child:Text('Запропонувати обмін')),PopupMenuItem(value:'Чи можемо домовитися про дарування цієї іграшки?',child:Text('Запропонувати дарування')),PopupMenuItem(value:'Чи зручна вам зустріч у громадському місці? Не надсилайте домашню адресу.',child:Text('Узгодити безпечну передачу'))]),IconButton(tooltip:'Оновити',onPressed:load,icon:const Icon(Icons.refresh))]),
    body:Column(children:[
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Align(alignment: Alignment.centerRight,
        child: ContentDeleteButton(kind: DeletableContent.conversation, onDelete: clearChat))),
      Expanded(child:loading?const Center(child:CircularProgressIndicator()):messages.isEmpty?const EmptyState(icon:Icons.chat_bubble_outline,title:'Почніть розмову',subtitle:'Домовляйтеся про іграшку лише як дорослі представники родин.'):ListView.builder(padding:const EdgeInsets.all(16),itemCount:messages.length,itemBuilder:(context,i){
      final m=messages[i]; final id=m['id'].toString();
      return ConversationMessageBubble(key:ValueKey(id), body:m['body']??'',
        createdAt:m['created_at'].toString(), mine:m['sender_user_id']==myId,
        onDelete:()=>deleteMessage(id));
    })),
    SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(12,8,12,12),child:Row(children:[Expanded(child:TextField(controller:composer,minLines:1,maxLines:4,maxLength:1000,decoration:const InputDecoration(hintText:'Повідомлення…',counterText:'',border:OutlineInputBorder()))),const SizedBox(width:8),IconButton.filled(onPressed:sending?null:send,icon:const Icon(Icons.send))]))),
  ]));}
}

class AgreementsScreen extends StatefulWidget {
  const AgreementsScreen({super.key});
  @override
  State<AgreementsScreen> createState() => _AgreementsScreenState();
}
class _AgreementsScreenState extends State<AgreementsScreen> {
  late Future<List<Map<String,dynamic>>> future;
  @override
  void initState() { super.initState(); future = loadAgreements(); }
  Future<List<Map<String,dynamic>>> loadAgreements() async {
    final rows = await db!.from('exchange_agreements').select('id,conversation_id,listing_id,proposer_family,receiver_family,created_by,status,note,proposer_confirmed_at,receiver_confirmed_at,created_at').order('created_at', ascending:false);
    return List<Map<String,dynamic>>.from(rows);
  }
  Future<void> refresh() async => setState(() { future = loadAgreements(); });
  Future<void> act(String id, String rpc) async {
    final confirmed = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(rpc=='cancel_exchange_agreement'?'Скасувати домовленість?':rpc=='confirm_exchange_handover'?'Іграшку передано?':'Підтвердити дію?'),content:Text(rpc=='confirm_exchange_handover'?'Підтверджуйте лише фактичну передачу. Після підтвердження обома родинами оголошення зникне з каталогу.':'Зміна стане видимою іншій родині.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Назад')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Підтвердити'))]));
    if(confirmed!=true)return;
    try { await db!.rpc(rpc, params: {'target_agreement': id}); await refresh(); }
    catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Дію не виконано: $e'))); }
  }
  String statusLabel(String s) => switch(s) {'proposed'=>'Очікує відповіді','accepted'=>'Погоджено','completed'=>'Передачу підтверджено обома','rejected'=>'Відхилено','cancelled'=>'Скасовано',_=>s};
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,snap) {
    if(snap.hasError) return Center(child:Padding(padding:const EdgeInsets.all(20),child:Text('Не вдалося завантажити домовленості: ${snap.error}')));
    if(!snap.hasData) return const Center(child:CircularProgressIndicator());
    final rows=snap.data!;
    return RefreshIndicator(onRefresh:refresh,child:rows.isEmpty
      ? ListView(children:const [SizedBox(height:110),EmptyState(icon:Icons.handshake_outlined,title:'Домовленостей ще немає',subtitle:'У приватному чаті натисніть значок рукостискання, щоб надіслати пропозицію.')])
      : ListView(padding:const EdgeInsets.all(16),children:[const Text('Домовленості родини',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:6),const Text('Підтверджуйте передачу лише після фактичної зустрічі дорослих у безпечному громадському місці.'),const SizedBox(height:14),...rows.map((a){final status=a['status'] as String;final mine=a['created_by']==db!.auth.currentUser!.id;return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[const Icon(Icons.handshake_outlined,color:Color(0xFF6C63D9)),const SizedBox(width:8),Expanded(child:Text(statusLabel(status),style:const TextStyle(fontWeight:FontWeight.bold)))]),const SizedBox(height:8),Text(a['note']??'Домовленість щодо іграшки'),const SizedBox(height:6),Text('Створено: ${a['created_at'].toString().substring(0,10)}',style:const TextStyle(color:Colors.black54,fontSize:12)),if(status=='proposed'&&!mine) Align(alignment:Alignment.centerRight,child:Wrap(spacing:8,children:[TextButton(onPressed:()=>act(a['id'].toString(),'reject_exchange_agreement'),child:const Text('Відхилити')),FilledButton(onPressed:()=>act(a['id'].toString(),'accept_exchange_agreement'),child:const Text('Погодити'))])),if(status=='accepted'&&((mine&&a['proposer_confirmed_at']==null)||(!mine&&a['receiver_confirmed_at']==null))) Align(alignment:Alignment.centerRight,child:FilledButton.tonal(onPressed:()=>act(a['id'].toString(),'confirm_exchange_handover'),child:const Text('Підтвердити передачу'))),if((status=='proposed'||status=='accepted')&&a['proposer_confirmed_at']==null&&a['receiver_confirmed_at']==null) TextButton(onPressed:()=>act(a['id'].toString(),'cancel_exchange_agreement'),child:const Text('Скасувати домовленість')),if(status=='accepted') Text('Підтвердження: ${a['proposer_confirmed_at']==null?'ініціатор — очікується':'ініціатор — так'}; ${a['receiver_confirmed_at']==null?'інша родина — очікується':'інша родина — так'}',style:const TextStyle(fontSize:12,color:Colors.black54))])));})]));
  });
}

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});
  @override
  Widget build(BuildContext context) => FamilyShopsMapScreen(
    repository: SupabaseFamilyShopsRepository(db!),
    listingBuilder: (item) => ListingCard(item: item),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon; final String title, subtitle;
  const EmptyState({super.key,required this.icon,required this.title,required this.subtitle});
  @override
  Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
    Icon(icon,size:54,color:const Color(0xFF6C63D9)),const SizedBox(height:12),
    Text(title,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
    const SizedBox(height:6),Text(subtitle,textAlign:TextAlign.center,style:const TextStyle(color:Colors.black54)),
  ]));
}
