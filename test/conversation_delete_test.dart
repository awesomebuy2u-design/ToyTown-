import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/main.dart';

void main() {
  testWidgets(
    'the chat list removes a whole conversation only after confirmation',
    (tester) async {
      final rows = <Map<String, dynamic>>[
        {
          'id': 'chat-a',
          'created_at': '2026-11-23T12:00:00Z',
          'listing': {'title': 'Розмова щодо ведмедика'},
        },
      ];
      final removed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatsScreen(
              loadConversations: () async => List.of(rows),
              clearConversation: (id) async {
                removed.add(id);
                rows.removeWhere((row) => row['id'] == id);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Видалити чат у мене'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Переписка співрозмовника та угоди залишаться'),
        findsOneWidget,
      );
      await tester.tap(find.text('Скасувати'));
      await tester.pumpAndSettle();
      expect(removed, isEmpty);
      expect(find.text('Розмова щодо ведмедика'), findsOneWidget);
      await tester.tap(find.byTooltip('Видалити чат у мене'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Видалити'));
      await tester.pumpAndSettle();
      expect(removed, ['chat-a']);
      expect(find.text('Поки немає розмов'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'whole chat removal is available inside a conversation with incoming messages',
    (tester) async {
      var cleared = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConversationScreen(
                      conversationId: 'chat-b',
                      title: 'Чат з іншою родиною',
                      currentUserId: 'parent-a',
                      clearChat: () async {
                        cleared = true;
                      },
                      messageLoader: () async => [
                        {
                          'id': 'a',
                          'sender_user_id': 'parent-a',
                          'body': 'Моє повідомлення',
                          'created_at': '2026-11-23T12:00:00Z',
                        },
                        {
                          'id': 'b',
                          'sender_user_id': 'parent-b',
                          'body': 'Відповідь співрозмовника',
                          'created_at': '2026-11-23T12:01:00Z',
                        },
                      ],
                    ),
                  ),
                ),
                child: const Text('Відкрити чат'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Відкрити чат'));
      await tester.pumpAndSettle();
      expect(find.text('Моє повідомлення'), findsOneWidget);
      expect(find.text('Відповідь співрозмовника'), findsOneWidget);
      expect(find.text('Видалити повідомлення'), findsOneWidget);
      await tester.tap(find.byTooltip('Видалити чат у мене'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Видалити'));
      await tester.pumpAndSettle();
      expect(cleared, isTrue);
      expect(find.text('Відкрити чат'), findsOneWidget);
      expect(find.text('Відповідь співрозмовника'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
