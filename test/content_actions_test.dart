import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toytown/content_actions.dart';
import 'package:toytown/listing.dart';
import 'package:toytown/main.dart';

Widget screen(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
      'only outgoing messages offer removal and cancellation keeps the message',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(screen(Column(children: [
      ConversationMessageBubble(
          body: 'Моє повідомлення',
          createdAt: '2026-11-21T12:00:00Z',
          mine: true,
          onDelete: () async {
            calls++;
          }),
      ConversationMessageBubble(
          body: 'Відповідь родини',
          createdAt: '2026-11-21T12:01:00Z',
          mine: false,
          onDelete: () async {
            calls++;
          }),
    ])));
    expect(find.byTooltip('Видалити повідомлення'), findsOneWidget);
    await tester.tap(find.byTooltip('Видалити повідомлення'));
    await tester.pumpAndSettle();
    expect(find.textContaining('для обох родин'), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.text('Скасувати'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Моє повідомлення'), findsOneWidget);
    await tester.tap(find.byTooltip('Видалити повідомлення'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Видалити'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets(
      'confirmed removal sends one request and recovers from a network failure',
      (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(screen(ContentDeleteButton(
        kind: DeletableContent.message,
        onDelete: () {
          calls++;
          return calls == 1 ? pending.future : Future.value();
        })));
    await tester.tap(find.text('Видалити повідомлення'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Видалити'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
        tester
            .widget<ButtonStyleButton>(
                find.byWidgetPredicate((widget) => widget is ButtonStyleButton))
            .onPressed,
        isNull);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не вдалося видалити.'), findsOneWidget);
    await tester.tap(find.text('Видалити повідомлення'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Видалити'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Повідомлення видалено.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an active agreement leaves the listing and explains how to continue',
      (tester) async {
    await tester.pumpWidget(screen(ContentDeleteButton(
        kind: DeletableContent.listing,
        onDelete: () async {
          throw const PostgrestException(
              message: 'LISTING_HAS_ACTIVE_AGREEMENT', code: '55000');
        })));
    await tester.tap(find.text('Видалити оголошення'));
    await tester.pumpAndSettle();
    expect(find.textContaining('історія угод залишаться'), findsOneWidget);
    await tester.tap(find.text('Видалити'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Спочатку завершіть або скасуйте'), findsOneWidget);
    expect(find.text('Оголошення видалено.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'my shop refreshes after persisted deletion and stays deleted on reopening',
      (tester) async {
    final rows = [
      Listing.fromMap({'id': 'A', 'title': 'Моя іграшка', 'status': 'approved'})
    ];
    final removed = <String>[];
    Widget shop() => screen(MyShopScreen(
        loadListings: () async => List.of(rows),
        deleteListing: (id) async {
          removed.add(id);
          rows.removeWhere((row) => row.id == id);
        }));
    await tester.pumpWidget(shop());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Видалити оголошення'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Скасувати'));
    await tester.pumpAndSettle();
    expect(removed, isEmpty);
    expect(find.text('Моя іграшка'), findsOneWidget);
    await tester.tap(find.text('Видалити оголошення'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Видалити'));
    await tester.pumpAndSettle();
    expect(removed, ['A']);
    expect(find.text('Моя іграшка'), findsNothing);
    expect(find.text('Ваша крамничка порожня'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(shop());
    await tester.pumpAndSettle();
    expect(find.text('Моя іграшка'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'deleting an opened listing refreshes the shop without reopening it',
      (tester) async {
    final rows = [
      Listing.fromMap({'id': 'detail-A', 'title': 'Ведмедик на полиці', 'status': 'approved'})
    ];
    final removed = <String>[];
    await tester.pumpWidget(screen(MyShopScreen(
      loadListings: () async => List.of(rows),
      deleteListing: (id) async {
        removed.add(id);
        rows.removeWhere((item) => item.id == id);
      },
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Переглянути оголошення'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Переглянути оголошення'));
    await tester.pumpAndSettle();
    expect(find.text('Ведмедик на полиці'), findsWidgets);
    await tester.tap(find.text('Видалити оголошення'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Видалити'));
    await tester.pumpAndSettle();
    expect(removed, ['detail-A']);
    expect(find.text('Ведмедик на полиці'), findsNothing);
    expect(find.text('Ваша крамничка порожня'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public listing cards have no removal action', (tester) async {
    await tester.pumpWidget(screen(ListingCard(
        item: Listing.fromMap({'id': 'B', 'title': 'Чужа іграшка'}))));
    await tester.pumpAndSettle();
    expect(find.byType(ContentDeleteButton), findsNothing);
  });
}
