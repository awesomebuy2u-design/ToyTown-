import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/guardian_pin.dart';

void main() {
  testWidgets('verification failure never grants guardian access', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () async {
        result = await requestGuardianPin(context, (_) async {
          throw StateError('offline');
        });
      }, child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.text('Увійти'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Не вдалося перевірити доступ.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.tap(find.text('До містечка'));
    await tester.pumpAndSettle();
    expect(result, false);
  });
}
