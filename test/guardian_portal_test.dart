import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toytown/guardian_portal.dart';

class PortalFixture {
  final pending = Completer<void>();
  final revoked = <String?>[];
  bool delay = false;
  static const url = 'https://toytown.example';
  late final account = client();
  SupabaseClient client([String? proof]) => SupabaseClient(
        url,
        'public-test-key',
        accessToken: () async => 'test-only',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        headers: {if (proof != null) 'x-toytown-guardian': proof},
        httpClient: MockClient((request) async {
          Object? result;
          switch (request.url.pathSegments.last) {
            case 'guardian_has_pin':
            case 'touch_guardian':
              result = true;
            case 'unlock_guardian':
              if (delay) await pending.future;
              result = {
                'token': 'test-proof',
                'expires_at': DateTime.now()
                    .add(const Duration(minutes: 30))
                    .toUtc()
                    .toIso8601String(),
              };
            case 'lock_guardian':
              revoked.add(request.headers['x-toytown-guardian']);
            default:
              throw StateError('Unexpected request');
          }
          return http.Response(jsonEncode(result), 200,
              request: request,
              headers: {
                'content-type': 'application/json',
                'content-length': jsonEncode(result).length.toString()
              });
        }),
      );

  Future<void> enter(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: GuardianPortal(
      account: account,
      scopedClient: client,
      url: url,
      publishableKey: 'key',
      home: (ctx) => Scaffold(
          body: TextButton(
        child: const Text('Відкрити угоду'),
        onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
          builder: (detail) => Scaffold(
              body: TextButton(
            child: const Text('Приватна угода'),
            onPressed: () => showDialog<void>(
                context: detail,
                useRootNavigator: false,
                builder: (_) =>
                    const AlertDialog(title: Text('Підтвердити передачу'))),
          )),
        )),
      )),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Увести PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.text('Увійти'));
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final background in [true, false]) {
    testWidgets(
        'Lock removes nested agreement and confirmation (background=$background)',
        (tester) async {
      final fixture = PortalFixture();
      await fixture.enter(tester);
      await tester.tap(find.text('Відкрити угоду'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Приватна угода'));
      await tester.pumpAndSettle();
      expect(find.text('Підтвердити передачу'), findsOneWidget);
      if (background) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else {
        await tester.pump(const Duration(minutes: 5, seconds: 1));
      }
      await tester.pumpAndSettle();
      expect(find.text('Увести PIN'), findsOneWidget);
      expect(find.text('Приватна угода', skipOffstage: false), findsNothing);
      expect(
          find.text('Підтвердити передачу', skipOffstage: false), findsNothing);
      expect(fixture.revoked, ['test-proof']);
    });
  }
  testWidgets('A late PIN response after backgrounding is revoked',
      (tester) async {
    final fixture = PortalFixture()..delay = true;
    await fixture.enter(tester);
    expect(find.text('Перевірка…'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    fixture.pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Увести PIN'), findsOneWidget);
    expect(find.text('Відкрити угоду', skipOffstage: false), findsNothing);
    expect(fixture.revoked, ['test-proof']);
  });
}
