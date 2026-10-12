import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bragmat/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthBackend backend;
  late AuthService auth;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAuthBackend();
    auth = AuthService.forBackend(backend);
  });

  tearDown(() async {
    await auth.dispose();
    backend.dispose();
    AuthService.testInstance = null;
  });

  group('AuthService — beta gate', () {
    test('signed out when no session', () async {
      await auth.start();
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.isSignedIn, false);
    });

    test('approved sign-in reaches signedIn and upserts profile', () async {
      await auth.start();
      await auth.signIn('tester@example.com', 'password');
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.email, 'tester@example.com');
      expect(backend.profileUpserted, true);
      // The approval is remembered for offline launches.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auth_ever_approved'), true);
    });

    test('uninvited sign-in lands on awaitingApproval', () async {
      backend.approved = false;
      await auth.start();
      await auth.signIn('stranger@example.com', 'password');
      expect(auth.status, AuthStatus.awaitingApproval);
      expect(backend.profileUpserted, false);
    });

    test('admin revocation signs out and marks revoked', () async {
      await auth.start();
      await auth.signIn('tester@example.com', 'password');
      expect(auth.status, AuthStatus.signedIn);

      backend.approved = false; // admin set status='revoked'
      await auth.refresh(forceEntitlementCheck: true);

      expect(auth.status, AuthStatus.revoked);
      expect(backend.hasSession, false);
    });

    test('offline check keeps an established session usable', () async {
      await auth.start();
      await auth.signIn('tester@example.com', 'password');
      expect(auth.status, AuthStatus.signedIn);

      backend.approved = null; // RPC unreachable — offline
      await auth.refresh(forceEntitlementCheck: true);

      expect(auth.status, AuthStatus.signedIn);
    });

    test('offline check never approves a brand-new session', () async {
      await auth.start();
      backend.approved = null; // check can't run
      await auth.signIn('tester@example.com', 'password');
      // Sign-in forced a check which failed offline → fail closed.
      expect(auth.status, AuthStatus.awaitingApproval);
    });

    test('entitlement check is throttled within the window', () async {
      await auth.start();
      await auth.signIn('tester@example.com', 'password');
      expect(auth.status, AuthStatus.signedIn);

      // Revoke server-side but do NOT force — throttle should skip the
      // check and keep the cached entitlement.
      backend.approved = false;
      await auth.refresh();

      expect(auth.status, AuthStatus.signedIn);
    });

    test('sign out clears session and remembered approval', () async {
      await auth.start();
      await auth.signIn('tester@example.com', 'password');
      await auth.signOut();

      expect(auth.status, AuthStatus.signedOut);
      expect(backend.hasSession, false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auth_ever_approved'), isNot(true));
    });

    test('account deletion request is flagged server-side', () async {
      await auth.start();
      await auth.signIn('tester@example.com', 'password');
      await auth.requestAccountDeletion();
      expect(backend.deletionRequested, true);
    });
  });
}
