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

    test('revoked user can still request account deletion', () async {
      await auth.start();
      await auth.signIn('tester@example.com', 'password');
      backend.approved = false;
      await auth.refresh(forceEntitlementCheck: true);
      expect(auth.status, AuthStatus.revoked);

      // The deletion RPC is callable regardless of beta status.
      await auth.requestAccountDeletion();
      expect(backend.deletionRequested, true);
    });

    test('sign-up without a session lands on emailVerificationPending', () async {
      backend.signUpCreatesSession = false; // email confirmation enabled
      await auth.start();
      await auth.signUp('new@example.com', 'password');

      expect(auth.status, AuthStatus.emailVerificationPending);
      expect(auth.pendingEmail, 'new@example.com');
      expect(backend.hasSession, false);
    });

    test('password-recovery event raises the recovery flag', () async {
      await auth.start();
      backend.emitPasswordRecovery('tester@example.com');
      await Future.delayed(Duration.zero);

      expect(auth.passwordRecoveryPending, true);
    });

    test('updatePassword clears recovery flag and resumes session', () async {
      await auth.start();
      backend.emitPasswordRecovery('tester@example.com');
      await Future.delayed(Duration.zero);

      await auth.updatePassword('newsecret');

      expect(backend.updatedPassword, 'newsecret');
      expect(auth.passwordRecoveryPending, false);
      expect(auth.status, AuthStatus.signedIn);
    });
  });

  group('AuthService — revocation scenarios from device testing', () {
    test('post-throttle refresh detects revocation and kills the live '
        'session (Access Removed path)', () async {
      await auth.start();
      await auth.signIn('tester@example.com', 'password');
      expect(auth.status, AuthStatus.signedIn);

      // Admin revokes while the session is live; age the last-check
      // timestamp past the 1-hour throttle so the next (unforced)
      // refresh — e.g. an app relaunch — actually checks.
      backend.approved = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('auth_last_entitlement_check_ms', 0);

      await auth.refresh();

      expect(auth.status, AuthStatus.revoked);
      expect(backend.hasSession, false);
      expect(prefs.getBool('auth_ever_approved'), isNot(true));
    });

    test('a trailing signed-out event must not override revoked', () async {
      await auth.start();
      await auth.signIn('tester@example.com', 'password');
      backend.approved = false;
      await auth.refresh(forceEntitlementCheck: true);
      expect(auth.status, AuthStatus.revoked);

      // Real backends may emit the signed-out auth event after the
      // revocation transition completes — it must not drop the user
      // back to the sign-in screen and lose the Access Removed state.
      backend.emitSignedOut();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(auth.status, AuthStatus.revoked);
    });

    test('DEFECT-1 symptom A: stale device-wide flag lets an unapproved '
        'account in when the check is unresolvable', () async {
      // Another account's earlier approval left the flag set.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auth_ever_approved', true);

      // This account was never approved; the entitlement RPC is
      // unreachable (offline or server error) at sign-in.
      backend.approved = null;
      await auth.start();
      await auth.signIn('stranger@example.com', 'password');

      // CURRENT (defective) behaviour: inherits the other account's
      // flag. After the per-account fix this must be awaitingApproval.
      expect(auth.status, AuthStatus.signedIn);
    });

    test('DEFECT-1 symptom B: sign-out erases approval memory, so a '
        'revoked user sees awaitingApproval instead of revoked',
        () async {
      await auth.start();
      await auth.signIn('tester@example.com', 'password');
      await auth.signOut(); // clears auth_ever_approved (current)

      backend.approved = false; // admin revoked meanwhile
      await auth.signIn('tester@example.com', 'password');

      // CURRENT (defective) behaviour: indistinguishable from a
      // never-invited account. After the fix, per-account approval
      // history should surface AuthStatus.revoked here.
      expect(auth.status, AuthStatus.awaitingApproval);
    });
  });
}
