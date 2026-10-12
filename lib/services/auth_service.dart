import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Account/session state exposed to the UI.
enum AuthStatus {
  /// Still resolving (initialising or waiting on a network check).
  unknown,

  /// No Supabase session.
  signedOut,

  /// Signed in and approved for beta access.
  signedIn,

  /// Signed in but the account email is not on the beta allowlist.
  awaitingApproval,

  /// Previously approved, now revoked by an admin. Local data is kept;
  /// only cloud identity is removed.
  revoked,

  /// Account created but the confirmation email has not been verified
  /// yet (Supabase email confirmation is enabled). No session exists.
  emailVerificationPending,
}

/// Result of a beta-entitlement check.
enum BetaCheckResult { approved, notApproved, revoked, offline }

/// Minimal surface the app needs from an auth backend. [SupabaseAuthBackend]
/// is the production implementation; [FakeAuthBackend] is used by tests.
abstract class AuthBackend {
  /// Whether a persisted session already exists.
  bool get hasSession;

  /// The current user's id, or null when signed out.
  String? get userId;

  /// The current user's email, or null when signed out.
  String? get email;

  /// Emits when the auth session changes (sign in/out, token refresh,
  /// password-recovery sessions).
  Stream<String?> get authStateChanges;

  /// Emits when a password-recovery deep link created a recovery session
  /// — the UI should then offer the new-password screen.
  Stream<void> get passwordRecoveryEvents;

  Future<void> signIn(String email, String password);

  /// Returns true when a session was created immediately (email
  /// confirmation disabled); false when a confirmation email was sent
  /// and no session exists yet.
  Future<bool> signUp(String email, String password, String redirectTo);

  Future<void> signOut();
  Future<void> requestPasswordReset(String email, String redirectTo);

  /// Resend the signup-confirmation email.
  Future<void> resendConfirmation(String email, String redirectTo);

  /// Set a new password during a password-recovery session.
  Future<void> updatePassword(String newPassword);

  /// Server-side beta-entitlement check (RPC `is_approved_beta`).
  /// Returns null when the check could not be performed (offline etc).
  Future<bool?> isApprovedBeta();

  /// Create/update the caller's profile row. RLS only allows this for
  /// approved testers — server-enforced invitation.
  Future<void> upsertProfile(String displayName);

  /// Flag the profile for deletion by an admin (eventual deletion policy).
  Future<void> requestAccountDeletion();
}

/// Production backend over the Supabase client.
class SupabaseAuthBackend implements AuthBackend {
  SupabaseAuthBackend(this._client);

  final SupabaseClient _client;

  @override
  bool get hasSession => _client.auth.currentSession != null;

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  String? get email => _client.auth.currentUser?.email;

  @override
  Stream<String?> get authStateChanges =>
      _client.auth.onAuthStateChange.map((e) => e.session?.user.id);

  @override
  Stream<void> get passwordRecoveryEvents => _client.auth.onAuthStateChange
      .where((e) => e.event == AuthChangeEvent.passwordRecovery)
      .map((_) {});

  @override
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<bool> signUp(
      String email, String password, String redirectTo) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: redirectTo,
    );
    return response.session != null;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> requestPasswordReset(String email, String redirectTo) {
    return _client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
  }

  @override
  Future<void> resendConfirmation(String email, String redirectTo) {
    return _client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: redirectTo,
    );
  }

  @override
  Future<void> updatePassword(String newPassword) {
    return _client.auth
        .updateUser(UserAttributes(password: newPassword));
  }

  @override
  Future<bool?> isApprovedBeta() async {
    try {
      final result = await _client.rpc('is_approved_beta');
      return result == true;
    } catch (_) {
      return null; // offline or transient failure — never fatal
    }
  }

  @override
  Future<void> upsertProfile(String displayName) async {
    await _client.from('profiles').upsert({
      'id': userId,
      'email': email,
      'display_name': displayName,
      'last_seen_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> requestAccountDeletion() async {
    await _client.from('profiles').update({
      'deletion_requested_at': DateTime.now().toIso8601String(),
    }).eq('id', userId ?? '');
  }
}

/// In-memory backend for tests — no network, no Supabase.
class FakeAuthBackend implements AuthBackend {
  String? _userId;
  String? _email;
  bool? approved = true;
  var deletionRequested = false;
  var profileUpserted = false;
  var signUpCreatesSession = true;
  String? updatedPassword;
  final _controller = StreamController<String?>.broadcast();
  final _recoveryController = StreamController<void>.broadcast();

  @override
  bool get hasSession => _userId != null;

  @override
  String? get userId => _userId;

  @override
  String? get email => _email;

  @override
  Stream<String?> get authStateChanges => _controller.stream;

  @override
  Stream<void> get passwordRecoveryEvents => _recoveryController.stream;

  @override
  Future<void> signIn(String email, String password) async {
    _userId = 'uid-$email';
    _email = email;
    _controller.add(_userId);
  }

  @override
  Future<bool> signUp(
      String email, String password, String redirectTo) async {
    if (!signUpCreatesSession) {
      return false; // confirmation email sent, no session yet
    }
    await signIn(email, password);
    return true;
  }

  @override
  Future<void> signOut() async {
    _userId = null;
    _email = null;
    _controller.add(null);
  }

  @override
  Future<void> requestPasswordReset(String email, String redirectTo) async {}

  @override
  Future<void> resendConfirmation(String email, String redirectTo) async {}

  @override
  Future<void> updatePassword(String newPassword) async {
    updatedPassword = newPassword;
  }

  /// Test helper: simulate a recovery deep link creating a session.
  void emitPasswordRecovery(String email) {
    _userId = 'uid-$email';
    _email = email;
    _controller.add(_userId);
    _recoveryController.add(null);
  }

  @override
  Future<bool?> isApprovedBeta() async => approved;

  @override
  Future<void> upsertProfile(String displayName) async {
    profileUpserted = true;
  }

  @override
  Future<void> requestAccountDeletion() async {
    deletionRequested = true;
  }

  void dispose() {
    _controller.close();
    _recoveryController.close();
  }
}

/// Account service: wraps the auth backend, owns beta-entitlement state,
/// session persistence flags and the revocation policy.
class AuthService extends ChangeNotifier {
  AuthService._(this._backend);

  static AuthService? _instance;

  /// Override for tests.
  static AuthService? testInstance;

  static AuthService get instance {
    if (testInstance != null) {
      return testInstance!;
    }
    return _instance ??= AuthService._(
      SupabaseAuthBackend(Supabase.instance.client),
    );
  }

  /// Build a service over a fake backend (tests).
  factory AuthService.forBackend(AuthBackend backend) =>
      AuthService._(backend);

  /// Whether initialisation has been performed.
  static bool _initialized = false;

  /// Initialise Supabase when configured. No-op (returns false) when
  /// credentials are absent so dev/test builds run unaffected.
  static Future<bool> initialize() async {
    if (_initialized) {
      return SupabaseConfig.isConfigured;
    }
    if (!SupabaseConfig.isConfigured) {
      return false;
    }
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
    _initialized = true;
    return true;
  }

  final AuthBackend _backend;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  /// True while a password-recovery session is active — the UI should
  /// show the new-password screen until [updatePassword] or [signOut].
  bool get passwordRecoveryPending => _passwordRecoveryPending;
  bool _passwordRecoveryPending = false;

  String? get userId => _backend.userId;
  String? get email => _backend.email;

  /// Email of the account awaiting confirmation (no session exists yet).
  String? get pendingEmail => _pendingEmail;
  String? _pendingEmail;
  bool get isSignedIn =>
      _status == AuthStatus.signedIn ||
      _status == AuthStatus.awaitingApproval;

  StreamSubscription<String?>? _authSub;
  StreamSubscription<void>? _recoverySub;

  static const _kLastEntitlementCheck = 'auth_last_entitlement_check_ms';
  static const _kEverApproved = 'auth_ever_approved';
  static const _entitlementCheckInterval = Duration(hours: 1);

  /// Start listening and resolve initial status. Safe to call once.
  Future<void> start() async {
    _authSub?.cancel();
    _authSub = _backend.authStateChanges.listen((_) => refresh());
    _recoverySub?.cancel();
    _recoverySub = _backend.passwordRecoveryEvents.listen((_) {
      _passwordRecoveryPending = true;
      notifyListeners();
    });
    await refresh();
  }

  @override
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _recoverySub?.cancel();
    super.dispose();
  }

  /// Re-evaluate session + beta entitlement. Called on auth changes,
  /// app launch and foregrounding.
  Future<void> refresh({bool forceEntitlementCheck = false}) async {
    if (!_backend.hasSession) {
      _setStatus(AuthStatus.signedOut);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastEntitlementCheck) ?? 0;
    final due = DateTime.now().millisecondsSinceEpoch - last >=
        _entitlementCheckInterval.inMilliseconds;

    if (forceEntitlementCheck || due) {
      final result = await _checkEntitlement();
      if (result == BetaCheckResult.offline) {
        // Offline: a previously approved session stays usable; a session
        // never verified stays in awaiting-approval (fail closed for new
        // sign-ins, never lock out an established session).
        _setStatus(
          prefs.getBool(_kEverApproved) == true
              ? AuthStatus.signedIn
              : AuthStatus.awaitingApproval,
        );
        return;
      }
      await prefs.setInt(
          _kLastEntitlementCheck, DateTime.now().millisecondsSinceEpoch);
      if (result == BetaCheckResult.approved) {
        await prefs.setBool(_kEverApproved, true);
        try {
          await _backend.upsertProfile('');
        } catch (_) {
          // Profile upsert is non-fatal — RLS allows it once approved,
          // and a transient failure must not block the app.
        }
        _setStatus(AuthStatus.signedIn);
      } else {
        // Not on allowlist at all, or revoked after prior approval.
        final everApproved = prefs.getBool(_kEverApproved) == true;
        if (everApproved) {
          await prefs.setBool(_kEverApproved, false);
          await _backend.signOut();
          _setStatus(AuthStatus.revoked);
        } else {
          _setStatus(AuthStatus.awaitingApproval);
        }
      }
      return;
    }

    // Within throttle window: trust the cached entitlement.
    _setStatus(
      prefs.getBool(_kEverApproved) == true
          ? AuthStatus.signedIn
          : AuthStatus.awaitingApproval,
    );
  }

  Future<BetaCheckResult> _checkEntitlement() async {
    final approved = await _backend.isApprovedBeta();
    if (approved == null) {
      return BetaCheckResult.offline;
    }
    return approved ? BetaCheckResult.approved : BetaCheckResult.notApproved;
  }

  Future<void> signIn(String email, String password) async {
    await _backend.signIn(email, password);
    _pendingEmail = null;
    await refresh(forceEntitlementCheck: true);
  }

  /// Creates the account. When email confirmation is enabled no session
  /// exists yet — status moves to [AuthStatus.emailVerificationPending]
  /// and the user verifies via the emailed link before signing in.
  Future<void> signUp(String email, String password) async {
    final sessionCreated = await _backend.signUp(
      email,
      password,
      SupabaseConfig.authRedirectUrl,
    );
    if (!sessionCreated) {
      _pendingEmail = email;
      _setStatus(AuthStatus.emailVerificationPending);
      return;
    }
    await refresh(forceEntitlementCheck: true);
  }

  /// Sign out but keep all local data.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEverApproved);
    await _backend.signOut();
    _passwordRecoveryPending = false;
    _pendingEmail = null;
    _setStatus(AuthStatus.signedOut);
  }

  Future<void> requestPasswordReset(String email) =>
      _backend.requestPasswordReset(email, SupabaseConfig.authRedirectUrl);

  /// Resend the signup-confirmation email while verification is pending.
  Future<void> resendConfirmation() async {
    final email = _pendingEmail;
    if (email == null) {
      return;
    }
    await _backend.resendConfirmation(email, SupabaseConfig.authRedirectUrl);
  }

  /// Set a new password during a password-recovery session, then clear
  /// the recovery flag — the session continues as a normal sign-in.
  Future<void> updatePassword(String newPassword) async {
    await _backend.updatePassword(newPassword);
    _passwordRecoveryPending = false;
    await refresh(forceEntitlementCheck: true);
  }

  Future<void> requestAccountDeletion() => _backend.requestAccountDeletion();

  void _setStatus(AuthStatus status) {
    if (_status == status) {
      return;
    }
    _status = status;
    notifyListeners();
  }
}
