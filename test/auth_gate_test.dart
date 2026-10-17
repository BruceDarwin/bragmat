// AuthGate fail-closed tests.
//
// Builds without Supabase credentials must never open the app
// unauthenticated — a mis-built beta APK would otherwise silently bypass
// the gate and hide Settings > Account. The only bypass is the explicit
// debug-only DEV_AUTH_BYPASS dart-define (simulated here via the
// SupabaseConfig test seams; flutter test always runs in debug mode).

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bragmat/screens/auth_gate.dart';
import 'package:bragmat/services/auth_service.dart';
import 'package:bragmat/services/supabase_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SupabaseConfig.debugIsConfigured = null;
    SupabaseConfig.debugAuthBypass = null;
    AuthService.testInstance = null;
  });

  Widget gate() => const MaterialApp(
        home: AuthGate(child: Text('APP_CONTENT')),
      );

  testWidgets('missing credentials fail closed', (tester) async {
    await tester.pumpWidget(gate());

    expect(find.text('APP_CONTENT'), findsNothing);
    expect(find.text('Configuration Error'), findsOneWidget);
  });

  testWidgets('explicit dev bypass opens the app', (tester) async {
    SupabaseConfig.debugAuthBypass = true;
    await tester.pumpWidget(gate());

    expect(find.text('APP_CONTENT'), findsOneWidget);
  });

  testWidgets('revoked status shows Access Removed and blocks the app',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    SupabaseConfig.debugIsConfigured = true;
    final backend = FakeAuthBackend();
    final auth = AuthService.forBackend(backend);
    AuthService.testInstance = auth;
    await auth.start();
    await auth.signIn('tester@example.com', 'password');
    // Admin revokes; a forced check while the session is live.
    backend.approved = false;
    await auth.refresh(forceEntitlementCheck: true);
    expect(auth.status, AuthStatus.revoked);

    await tester.pumpWidget(gate());
    await tester.pump();

    expect(find.text('Access Removed'), findsOneWidget);
    expect(find.text('APP_CONTENT'), findsNothing);

    // Do NOT await dispose here: awaiting a broadcast
    // StreamSubscription.cancel() inside testWidgets' fake-async zone
    // leaves a pending zone task that never drains, hanging the test
    // runner. The zone teardown cleans up the subscription anyway.
    unawaited(auth.dispose());
    backend.dispose();
  });
}
