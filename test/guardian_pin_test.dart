import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/guardian_pin.dart';

void main() {
  for (final validPin in ['0427', '123456']) {
    testWidgets('PIN accepts the verified ${validPin.length}-digit code', (
      tester,
    ) async {
      bool? result;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await requestGuardianPin(context, (pin) async {
                    calls++;
                    return pin == validPin;
                  });
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '111111');
      await tester.pump();
      await tester.tap(find.text('Увійти'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(result, isNull);
      expect(
        find.text('Доступ не підтверджено. Спробуйте пізніше.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), validPin);
      await tester.pump();
      await tester.tap(find.text('Увійти'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(result, true);
    });
  }
}
