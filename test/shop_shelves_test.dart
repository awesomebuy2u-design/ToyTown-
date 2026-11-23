import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:toytown/listing.dart';
import 'package:toytown/main.dart';
import 'package:toytown/shop_shelves.dart';
import 'package:toytown/toytown_world.dart';

Listing toy(String id, String title) =>
    Listing.fromMap({'id': id, 'title': title, 'status': 'approved'});
final inventory = [
  toy('A', 'Ведмедик'),
  toy('B', 'Машинка'),
  toy('C', 'Ракета'),
];

class Shelves extends ShopShelvesRepository {
  Shelves({this.accountId = 'parent-a'});
  @override
  final String accountId;
  final saved = <String, ShopShelfLayout>{};
  bool failSave = false;
  @override
  Future<List<Listing>> toys(String familyId) async =>
      familyId == 'f' ? List.of(inventory) : [toy('G', 'Кубики')];
  @override
  Future<ShopShelfLayout> load(String familyId) async =>
      saved[familyId] ?? const ShopShelfLayout();
  @override
  Future<void> save(String familyId, ShopShelfLayout layout) async {
    if (failSave) throw StateError('offline');
    saved[familyId] = ShopShelfLayout.fromMap(layout.toMap());
  }

  @override
  Future<String> photo(String path) async => throw StateError('offline');
}

Widget screen(Shelves repository, {String family = 'f'}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: OwnShopShelves(repository: repository, familyId: family),
    ),
  ),
);

Future<void> moveBear(WidgetTester tester) async {
  final menu = find.byKey(const ValueKey('move-toy-A'));
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Полиця №2'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets(
    'a shelf draft survives reopening and publishing persists the arrangement',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = Shelves();
      await tester.pumpWidget(screen(repository));
      await tester.pumpAndSettle();
      await moveBear(tester);
      expect(
        tester
            .widget<ShelfCabinet>(find.byType(ShelfCabinet))
            .layout
            .placements['A'],
        1,
      );
      expect(repository.saved, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen(repository));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShelfCabinet>(find.byType(ShelfCabinet))
            .layout
            .placements['A'],
        1,
      );
      final save = find.text('Зберегти полички');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.saved['f']?.placements['A'], 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen(repository));
      await tester.pumpAndSettle();
      expect(find.textContaining('Є незбережені зміни'), findsNothing);
      expect(
        tester
            .widget<ShelfCabinet>(find.byType(ShelfCabinet))
            .layout
            .placements['A'],
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dragging moves a toy and a failed save preserves the editable draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = Shelves()..failSave = true;
      await tester.pumpWidget(screen(repository));
      await tester.pumpAndSettle();
      final from = tester.getCenter(find.byKey(const ValueKey('shelf-toy-A')));
      final to = tester.getCenter(find.byKey(const ValueKey('toy-shelf-2')));
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 650));
      await gesture.moveTo(to);
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShelfCabinet>(find.byType(ShelfCabinet))
            .layout
            .placements['A'],
        2,
      );
      await tester.ensureVisible(find.text('Зберегти полички'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Зберегти полички'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Не вдалося зберегти полички.'),
        findsOneWidget,
      );
      expect(repository.saved, isEmpty);
      repository.failSave = false;
      await tester.tap(find.text('Зберегти полички'));
      await tester.pumpAndSettle();
      expect(repository.saved['f']?.placements['A'], 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shelf drafts are separate for accounts and families', (
    tester,
  ) async {
    await tester.pumpWidget(screen(Shelves()));
    await tester.pumpAndSettle();
    await moveBear(tester);
    await tester.pumpWidget(screen(Shelves(accountId: 'parent-b')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ShelfCabinet>(find.byType(ShelfCabinet)).layout.placements,
      isEmpty,
    );
    await tester.pumpWidget(screen(Shelves(), family: 'g'));
    await tester.pumpAndSettle();
    expect(find.text('Ведмедик'), findsNothing);
    expect(find.text('Кубики'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'own listing details expose deletion and return to the refreshed shop',
    (tester) async {
      final rows = [toy('A', 'Моя іграшка')];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyShopScreen(
              loadListings: () async => List.of(rows),
              deleteListing: (id) async {
                rows.removeWhere((row) => row.id == id);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Переглянути оголошення'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переглянути оголошення'));
      await tester.pumpAndSettle();
      expect(find.text('Видалити оголошення').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Видалити оголошення'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Видалити'));
      await tester.pumpAndSettle();
      expect(rows, isEmpty);
      expect(find.text('Ваша крамничка порожня'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the game shop opens own listings and messages directly and shows the version',
    (tester) async {
      var listings = 0, chats = 0, catalog = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ToyTownWorld(
            openListings: () => catalog++,
            openParent: () {},
            openMyListings: () => listings++,
            openChats: () => chats++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shop-manage-listings')));
      await tester.tap(find.text('Повідомлення'));
      expect(listings, 1);
      expect(chats, 1);
      expect(catalog, 0);
      expect(find.byType(ShelfCabinet), findsOneWidget);
      await tester.tap(find.byTooltip('Про ToyTown'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1.0.15'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shelves render varied toys and fit a narrow phone with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ShelfCabinet(
                    items: inventory,
                    balloons: true,
                    flowers: true,
                    front: 'stars',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('toy-shelf-2')), findsOneWidget);
      expect(find.text('Ведмедик'), findsOneWidget);
      expect(find.text('Машинка'), findsOneWidget);
      expect(find.text('Ракета'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final rendered = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/previews').create(recursive: true);
        await File(
          'build/previews/shop-shelves.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        rendered.dispose();
      });
    },
  );
}
