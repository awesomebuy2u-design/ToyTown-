import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'listing.dart';

class ShopShelfLayout {
  const ShopShelfLayout({this.shelfCount = 3, this.placements = const {}});
  final int shelfCount;
  final Map<String, int> placements;

  factory ShopShelfLayout.fromMap(Map<String, dynamic> row) {
    final count = ((row['shelf_count'] as num?)?.toInt() ?? 3)
        .clamp(1, 3)
        .toInt();
    final positions = <String, int>{};
    if (row['placements'] is Map) {
      for (final entry in (row['placements'] as Map).entries) {
        if (entry.key is String && entry.value is num) {
          positions[entry.key as String] = (entry.value as num)
              .toInt()
              .clamp(0, count - 1)
              .toInt();
        }
      }
    }
    return ShopShelfLayout(shelfCount: count, placements: positions);
  }
  int shelfFor(String id, int index) =>
      placements[id]?.clamp(0, shelfCount - 1).toInt() ?? index % shelfCount;
  Map<String, dynamic> toMap() => {
    'shelf_count': shelfCount,
    'placements': placements,
  };
}

abstract class ShopShelvesRepository {
  String get accountId;
  Future<List<Listing>> toys(String familyId);
  Future<ShopShelfLayout> load(String familyId);
  Future<void> save(String familyId, ShopShelfLayout layout);
  Future<String> photo(String path);
}

class SupabaseShopShelvesRepository implements ShopShelvesRepository {
  SupabaseShopShelvesRepository(this.client);
  final SupabaseClient client;
  @override
  String get accountId => client.auth.currentUser?.id ?? '';
  @override
  Future<List<Listing>> toys(String familyId) async {
    final rows = await client
        .from('listings')
        .select()
        .eq('family_id', familyId)
        .eq('status', 'approved')
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .order('id')
        .limit(200);
    return rows.map<Listing>((row) => Listing.fromMap(row)).toList();
  }

  @override
  Future<ShopShelfLayout> load(String familyId) async =>
      ShopShelfLayout.fromMap(
        Map<String, dynamic>.from(
          await client.rpc(
                'family_shop_layout',
                params: {'target_shop': familyId},
              )
              as Map,
        ),
      );
  @override
  Future<void> save(String familyId, ShopShelfLayout layout) async {
    await client.from('family_shop_layouts').upsert({
      'family_id': familyId,
      ...layout.toMap(),
    });
  }

  @override
  Future<String> photo(String path) =>
      client.storage.from('listing-images').createSignedUrl(path, 60);
}

Color shelfWall(String theme) => switch (theme) {
  'lavender' => const Color(0xFFF3EAFE),
  'sunset' => const Color(0xFFFFF0D9),
  _ => const Color(0xFFE8FAF1),
};

/// The shelves contain actual approved listings, or an explicitly labelled demo.
class ShelfCabinet extends StatelessWidget {
  const ShelfCabinet({
    super.key,
    required this.items,
    this.layout = const ShopShelfLayout(),
    this.theme = 'mint',
    this.front = 'classic',
    this.balloons = false,
    this.flowers = false,
    this.awning = false,
    this.editable = false,
    this.onMove,
    this.onAdd,
    this.onOpen,
    this.loadPhoto,
  });
  final List<Listing> items;
  final ShopShelfLayout layout;
  final String theme, front;
  final bool balloons, flowers, awning, editable;
  final void Function(String, int)? onMove;
  final ValueChanged<int>? onAdd;
  final ValueChanged<Listing>? onOpen;
  final Future<String> Function(String)? loadPhoto;

  Widget toy(Listing item) {
    final tile = SizedBox(
      width: 116,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShelfToy(
            key: ValueKey('shelf-toy-${item.id}'),
            item: item,
            onTap: onOpen == null ? null : () => onOpen!(item),
            loadPhoto: loadPhoto,
          ),
          if (editable)
            PopupMenuButton<int>(
              key: ValueKey('move-toy-${item.id}'),
              tooltip: 'Переставити ${item.title}',
              onSelected: (shelf) => onMove?.call(item.id, shelf),
              itemBuilder: (_) => [
        for (var shelf = 0; shelf < layout.shelfCount; shelf++)
                  PopupMenuItem(
                    value: shelf,
                    child: Text('Полиця №${shelf + 1}'),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Переставити', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
    if (!editable) return tile;
    return LongPressDraggable<String>(
      data: item.id,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 116, child: _ShelfToy(item: item)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('toy-shelf-cabinet'),
    padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, shelfWall(theme), shelfWall(theme)],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFD9A96F), width: 7),
      boxShadow: const [
        BoxShadow(
          color: Color(0x223E3022),
          offset: Offset(0, 7),
          blurRadius: 12,
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                'Крамничка іграшок',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF38685A),
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (front != 'classic' || balloons || flowers || awning)
                Text(
                  '${front == 'stars'
                      ? '⭐ ⭐ ⭐ '
                      : front == 'clouds'
                      ? '☁️ ☁️ ☁️ '
                      : ''}${balloons ? '🎈 ' : ''}${flowers ? '🌷 ' : ''}${awning ? '🎪' : ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFE5A83C)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${items.length} ${items.length == 1 ? 'іграшка' : 'іграшок'} на вітрині',
                textAlign: TextAlign.center,
                softWrap: true,
                style: const TextStyle(
                  color: Color(0xFF6A567B),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFE5A83C)),
          ],
        ),
        for (var shelf = 0; shelf < layout.shelfCount; shelf++)
          DragTarget<String>(
            onWillAcceptWithDetails: (details) =>
                editable && items.any((item) => item.id == details.data),
            onAcceptWithDetails: (details) => onMove?.call(details.data, shelf),
            builder: (context, candidates, rejected) => Container(
              key: ValueKey('toy-shelf-$shelf'),
              margin: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: candidates.isEmpty
                      ? [Colors.white.withValues(alpha: .9), const Color(0xFFFFF4DE)]
                      : [const Color(0xFFD9F9E6), const Color(0xFFB6DFCC)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFD59A61), width: 13),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Полиця ${shelf + 1}',
                    style: const TextStyle(
                      color: Color(0xFF725540),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (![
                    for (var i = 0; i < items.length; i++)
                      if (layout.shelfFor(items[i].id, i) == shelf) items[i],
                  ].isNotEmpty)
                    const SizedBox(
                      height: 88,
                      child: Center(
                        child: Text(
                          'Місце для іграшок',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  if (onAdd != null)
                    OutlinedButton.icon(
                      key: ValueKey('shelf-add-$shelf'),
                      onPressed: () => onAdd!(shelf),
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Додати іграшку'),
                    ),
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    spacing: 8,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        if (layout.shelfFor(items[i].id, i) == shelf)
                          toy(items[i]),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _ShelfToy extends StatefulWidget {
  const _ShelfToy({super.key, required this.item, this.onTap, this.loadPhoto});
  final Listing item;
  final VoidCallback? onTap;
  final Future<String> Function(String)? loadPhoto;
  @override
  State<_ShelfToy> createState() => _ShelfToyState();
}

class _ShelfToyState extends State<_ShelfToy> {
  Future<String>? image;
  @override
  void initState() {
    super.initState();
    loadImage();
  }

  @override
  void didUpdateWidget(covariant _ShelfToy old) {
    super.didUpdateWidget(old);
    if (old.item.photoPath != widget.item.photoPath ||
        old.loadPhoto != widget.loadPhoto)
      loadImage();
  }

  void loadImage() {
    final path = widget.item.photoPath;
    image = path == null || path.isEmpty ? null : widget.loadPhoto?.call(path);
  }

  Widget illustration() => CustomPaint(
    painter: _ToyPainter(widget.item.title),
    size: const Size(92, 80),
  );
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .85),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 80,
              child: image == null
                  ? illustration()
                  : FutureBuilder<String>(
                      future: image,
                      builder: (context, snapshot) => snapshot.hasData
                          ? Image.network(
                              snapshot.data!,
                              fit: BoxFit.contain,
                              semanticLabel: widget.item.title,
                              errorBuilder: (_, __, ___) => illustration(),
                            )
                          : illustration(),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ToyPainter extends CustomPainter {
  _ToyPainter(this.title);
  final String title;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 90);
    final p = Paint();
    canvas.drawOval(
      const Rect.fromLTWH(12, 77, 76, 9),
      p..color = const Color(0x224E3725),
    );
    final lower = title.toLowerCase();
    final kind = lower.contains('ведм')
        ? 0
        : lower.contains('машин')
        ? 1
        : lower.contains('ракет')
        ? 2
        : title.runes.fold(0, (a, b) => a + b) % 4;
    if (kind == 0) {
      p.color = const Color(0xFFC68F62);
      for (final centre in const [
        Offset(29, 19),
        Offset(71, 19),
        Offset(24, 59),
        Offset(76, 59),
        Offset(32, 77),
        Offset(68, 77),
      ]) {
        canvas.drawCircle(centre, 12, p);
      }
      canvas.drawOval(const Rect.fromLTWH(28, 36, 44, 46), p);
      canvas.drawCircle(
        const Offset(50, 31),
        25,
        p..color = const Color(0xFFE8B988),
      );
      canvas.drawOval(
        const Rect.fromLTWH(36, 32, 28, 20),
        p..color = const Color(0xFFFFE5BF),
      );
      canvas.drawCircle(
        const Offset(50, 35),
        4,
        p..color = const Color(0xFF634934),
      );
      for (final x in [40.0, 60.0]) canvas.drawCircle(Offset(x, 25), 3, p);
      canvas.drawCircle(
        const Offset(50, 62),
        12,
        p..color = const Color(0xFFFFDAB0),
      );
    } else if (kind == 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(9, 42, 82, 31),
          const Radius.circular(10),
        ),
        p..color = const Color(0xFFEE8B85),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(29, 24, 44, 33),
          const Radius.circular(10),
        ),
        p..color = const Color(0xFFF3B3A1),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(36, 29, 29, 17),
          const Radius.circular(5),
        ),
        p..color = const Color(0xFFD6F0F5),
      );
      for (final x in [28.0, 74.0]) {
        canvas.drawCircle(
          Offset(x, 73),
          12,
          p..color = const Color(0xFF4D6474),
        );
        canvas.drawCircle(Offset(x, 73), 5, p..color = const Color(0xFFFFE4AC));
      }
    } else if (kind == 2) {
      final rocket = Path()
        ..moveTo(50, 4)
        ..quadraticBezierTo(78, 28, 68, 69)
        ..lineTo(32, 69)
        ..quadraticBezierTo(22, 28, 50, 4);
      canvas.drawPath(rocket, p..color = const Color(0xFFACBDEA));
      canvas.drawCircle(
        const Offset(50, 35),
        13,
        p..color = const Color(0xFFFFF8DE),
      );
      canvas.drawCircle(
        const Offset(50, 35),
        8,
        p..color = const Color(0xFF7EBBC9),
      );
      canvas.drawPath(
        Path()
          ..moveTo(33, 53)
          ..lineTo(17, 78)
          ..lineTo(36, 69)
          ..close(),
        p..color = const Color(0xFFED9A91),
      );
      canvas.drawPath(
        Path()
          ..moveTo(67, 53)
          ..lineTo(83, 78)
          ..lineTo(64, 69)
          ..close(),
        p,
      );
      canvas.drawOval(
        const Rect.fromLTWH(42, 66, 16, 20),
        p..color = const Color(0xFFFFCF73),
      );
    } else {
      for (var i = 0; i < 5; i++) {
        final x = i < 3 ? 9 + i * 28.0 : 23 + (i - 3) * 28.0;
        final y = i < 3 ? 51.0 : 23.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, 27, 27),
            const Radius.circular(5),
          ),
          p
            ..color = [
              const Color(0xFF9DCAC0),
              const Color(0xFFFFD483),
              const Color(0xFFB6B1DC),
              const Color(0xFFEA9F9C),
              const Color(0xFF9FC7E5),
            ][i],
        );
        canvas.drawCircle(
          Offset(x + 13.5, y + 13.5),
          5,
          p..color = Colors.white54,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ToyPainter old) => old.title != title;
}

class OwnShopShelves extends StatefulWidget {
  const OwnShopShelves({
    super.key,
    this.repository,
    this.familyId,
    this.theme = 'mint',
    this.front = 'classic',
    this.balloons = false,
    this.flowers = false,
    this.awning = false,
    this.onOpen,
    this.onManage,
    this.onAdd,
    this.demo = false,
  });
  final ShopShelvesRepository? repository;
  final String? familyId;
  final String theme, front;
  final bool balloons, flowers, awning, demo;
  final Future<void> Function(Listing)? onOpen;
  final VoidCallback? onManage;
  final Future<void> Function(int)? onAdd;
  @override
  State<OwnShopShelves> createState() => _OwnShopShelvesState();
}

class _OwnShopShelvesState extends State<OwnShopShelves> {
  final storage = SharedPreferencesAsync();
  Future<void> draftWrite = Future.value();
  List<Listing> items = [];
  ShopShelfLayout layout = const ShopShelfLayout();
  bool loading = false, busy = false, dirty = false, preview = false;
  bool hasInventory = false;
  String? error, saved;
  String? loadedScope;
  int generation = 0;
  String get draftKey =>
      'toytown.shelves.${widget.repository!.accountId}.${widget.familyId}';
  bool get connected => widget.repository != null && widget.familyId != null;
  String? get currentScope =>
      connected ? '${widget.repository!.accountId}:${widget.familyId}' : null;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant OwnShopShelves old) {
    super.didUpdateWidget(old);
    if (loadedScope != currentScope) load();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> load() async {
    final ticket = ++generation;
    if (loadedScope != currentScope) {
      loadedScope = currentScope;
      setState(() {
        items = [];
        hasInventory = false;
        layout = const ShopShelfLayout();
        dirty = false;
        busy = false;
        saved = null;
        error = null;
      });
    }
    if (!connected) {
      setState(() => loading = false);
      return;
    }
    final key = draftKey;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await Future.wait<Object>([
        widget.repository!.toys(widget.familyId!),
        widget.repository!.load(widget.familyId!),
      ]);
      final draft = await storage.getString(key);
      if (!mounted || ticket != generation) return;
      final toys = values.first as List<Listing>;
      final loaded = draft == null
          ? values.last as ShopShelfLayout
          : ShopShelfLayout.fromMap(
              Map<String, dynamic>.from(jsonDecode(draft) as Map),
            );
      setState(() {
        items = toys;
        hasInventory = true;
        layout = ShopShelfLayout(
          shelfCount: loaded.shelfCount,
          placements: {
            for (final entry in loaded.placements.entries)
              if (toys.any((toy) => toy.id == entry.key))
                entry.key: entry.value,
          },
        );
        dirty = draft != null;
      });
    } catch (_) {
      if (mounted && ticket == generation)
        setState(
          () => error = 'Не вдалося завантажити полички. Спробуйте ще раз.',
        );
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  void change(ShopShelfLayout next) {
    if (busy || loading || !connected || !hasInventory) return;
    next = ShopShelfLayout(
      shelfCount: next.shelfCount,
      placements: {
        for (var i = 0; i < items.length; i++)
          items[i].id: next.shelfFor(items[i].id, i),
      },
    );
    setState(() {
      layout = next;
      dirty = true;
      saved = null;
    });
    final key = draftKey, value = jsonEncode(next.toMap());
    draftWrite = draftWrite.then((_) => storage.setString(key, value)).catchError((
      Object _,
    ) {
      if (mounted)
        setState(
          () => error =
              'Чернетку не вдалося зберегти на пристрої. Натисніть «Зберегти полички».',
        );
    });
  }

  void move(String id, int shelf) => change(
    ShopShelfLayout(
      shelfCount: layout.shelfCount,
      placements: {...layout.placements, id: shelf},
    ),
  );
  Future<void> save() async {
    if (busy || !dirty || !connected || !hasInventory) return;
    final ticket = generation, key = draftKey;
    final family = widget.familyId!,
        repository = widget.repository!,
        next = layout;
    setState(() {
      busy = true;
      error = null;
      saved = null;
    });
    try {
      await draftWrite;
      await repository.save(family, next);
      await storage.remove(key);
      if (mounted && ticket == generation)
        setState(() {
          dirty = false;
          saved = 'Полички збережено для родини та відвідувачів.';
        });
    } catch (_) {
      if (mounted && ticket == generation)
        setState(
          () => error =
              'Не вдалося зберегти полички. Чернетка залишилася на цьому пристрої. Спробуйте ще раз.',
        );
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.demo
        ? [
            for (final title in ['Ведмедик', 'Машинка', 'Ракета', 'Кубики'])
              Listing.fromMap({'id': title, 'title': title}),
          ]
        : items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.demo)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Приклад вітрини · після входу тут будуть ваші підтверджені іграшки.',
            ),
          ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) ...[
          Text(error!),
          TextButton(
            onPressed: busy ? null : load,
            child: const Text('Оновити полички'),
          ),
        ],
        ShelfCabinet(
          items: shown,
          layout: layout,
          theme: widget.theme,
          front: widget.front,
          balloons: widget.balloons,
          flowers: widget.flowers,
          awning: widget.awning,
          editable: connected && !loading && !busy && !preview && error == null,
          onMove: move,
          onAdd: connected && !loading && !busy && !preview && !widget.demo && widget.onAdd != null
              ? (shelf) async {
                  await widget.onAdd!(shelf);
                  if (mounted) await load();
                } : null,
          loadPhoto: widget.repository?.photo,
          onOpen:
              widget.demo ||
                  widget.onOpen == null ||
                  busy ||
                  loading ||
                  !hasInventory
              ? null
              : (item) async {
                  await widget.onOpen!(item);
                  if (mounted) await load();
                },
        ),
        if (connected && hasInventory) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('refresh-shop-shelves'),
              onPressed: loading || busy ? null : load,
              icon: const Icon(Icons.refresh),
              label: const Text('Оновити іграшки'),
            ),
          ),
        ],
        if (connected && !loading && hasInventory) ...[
          const SizedBox(height: 12),
          const Text(
            'Підтверджені іграшки можна перетягувати між поличками або натиснути «Переставити».',
          ),
          if (!preview)
            Wrap(
              spacing: 8,
              children: [
                for (var count = 1; count <= 3; count++)
                  ChoiceChip(
                    label: Text('$count ${count == 1 ? 'полиця' : 'полиці'}'),
                    selected: count == layout.shelfCount,
                    onSelected: busy
                        ? null
                        : (_) => change(
                            ShopShelfLayout(
                              shelfCount: count,
                              placements: {
                                for (final entry in layout.placements.entries)
                                  entry.key: entry.value
                                      .clamp(0, count - 1)
                                      .toInt(),
                              },
                            ),
                          ),
                  ),
              ],
            ),
          TextButton.icon(
            onPressed: busy ? null : () => setState(() => preview = !preview),
            icon: Icon(
              preview ? Icons.edit_outlined : Icons.visibility_outlined,
            ),
            label: Text(preview ? 'Редагувати полички' : 'Попередній перегляд'),
          ),
          if (dirty)
            const Text(
              'Є незбережені зміни · чернетка збережена на цьому пристрої.',
            ),
          FilledButton.icon(
            onPressed: dirty && !busy ? save : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(busy ? 'Збереження…' : 'Зберегти полички'),
          ),
          if (saved != null) Text(saved!),
          if (items.isEmpty)
            const Text(
              'Додайте іграшку та підтвердьте оголошення — вона з’явиться на поличці.',
            ),
        ],
      ],
    );
  }
}
