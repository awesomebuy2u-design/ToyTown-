import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/guardian_pin.dart';

void main() {
  testWidgets('PIN requires six digits and successful verification', (tester) async {
    bool? result;
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () async {
        result = await requestGuardianPin(context, (pin) async {
          calls++;
          return pin == '123456';
        });
      }, child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '111111');
    await tester.pump();
    await tester.tap(find.text('Увійти'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(result, isNull);
    expect(find.text('Доступ не підтверджено. Спробуйте пізніше.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.text('Увійти'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(result, true);
  });
}
