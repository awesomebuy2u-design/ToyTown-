import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/main.dart';

void main() {
  testWidgets('deleting my message keeps the other family message', (tester) async {
    final removed = <String>[];
    final rows = <Map<String, dynamic>>[
      {'id':'mine', 'sender_user_id':'parent-a', 'body':'Моє повідомлення', 'created_at':'2026-11-23T12:00:00Z'},
      {'id':'other', 'sender_user_id':'parent-b', 'body':'Відповідь', 'created_at':'2026-11-23T12:01:00Z'},
    ];
    await tester.pumpWidget(MaterialApp(home: ConversationScreen(
      conversationId: 'conversation-1',
      title: 'Тестовий чат',
      currentUserId: 'parent-a',
      messageLoader: () async => List.of(rows),
      removeMessage: (id) async {
        removed.add(id);
        rows.removeWhere((row) => row['id'] == id);
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('Моє повідомлення'), findsOneWidget);
    expect(find.text('Відповідь'), findsOneWidget);
    expect(find.byTooltip('Видалити повідомлення'), findsOneWidget);
    await tester.tap(find.byTooltip('Видалити повідомлення'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Видалити'));
    await tester.pumpAndSettle();
    expect(removed, ['mine']);
    expect(find.text('Моє повідомлення'), findsNothing);
    expect(find.text('Відповідь'), findsOneWidget);
  });
}
