// AuthGate fail-closed tests.
//
// Builds without Supabase credentials must never open the app
// unauthenticated — a mis-built beta APK would otherwise silently bypass
// the gate and hide Settings > Account. The only bypass is the explicit
// debug-only DEV_AUTH_BYPASS dart-define (simulated here via the
// SupabaseConfig test seams; flutter test always runs in debug mode).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bragmat/screens/auth_gate.dart';
import 'package:bragmat/services/supabase_config.dart';

void main() {
  tearDown(() {
    SupabaseConfig.debugIsConfigured = null;
    SupabaseConfig.debugAuthBypass = null;
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
}
