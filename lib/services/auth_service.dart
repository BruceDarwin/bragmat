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

  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> signOut();
  Future<void> requestPasswordReset(String email, String redirectTo);

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
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signUp(String email, String password) async {
    await _client.auth.signUp(email: email, password: password);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> requestPasswordReset(String email, String redirectTo) {
    return _client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
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
  final _controller = StreamController<String?>.broadcast();

  @override
  bool get hasSession => _userId != null;

  @override
  String? get userId => _userId;

  @override
  String? get email => _email;

  @override
  Stream<String?> get authStateChanges => _controller.stream;

  @override
  Future<void> signIn(String email, String password) async {
    _userId = 'uid-$email';
    _email = email;
    _controller.add(_userId);
  }

  @override
  Future<void> signUp(String email, String password) => signIn(email, password);

  @override
  Future<void> signOut() async {
    _userId = null;
    _email = null;
    _controller.add(null);
  }

  @override
  Future<void> requestPasswordReset(String email, String redirectTo) async {}

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

  void dispose() => _controller.close();
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

  String? get userId => _backend.userId;
  String? get email => _backend.email;
  bool get isSignedIn =>
      _status == AuthStatus.signedIn ||
      _status == AuthStatus.awaitingApproval;

  StreamSubscription<String?>? _authSub;

  static const _kLastEntitlementCheck = 'auth_last_entitlement_check_ms';
  static const _kEverApproved = 'auth_ever_approved';
  static const _entitlementCheckInterval = Duration(hours: 1);

  /// Start listening and resolve initial status. Safe to call once.
  Future<void> start() async {
    _authSub?.cancel();
    _authSub = _backend.authStateChanges.listen((_) => refresh());
    await refresh();
  }

  @override
  Future<void> dispose() async {
    await _authSub?.cancel();
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
    await refresh(forceEntitlementCheck: true);
  }

  Future<void> signUp(String email, String password) async {
    await _backend.signUp(email, password);
    await refresh(forceEntitlementCheck: true);
  }

  /// Sign out but keep all local data.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEverApproved);
    await _backend.signOut();
    _setStatus(AuthStatus.signedOut);
  }

  Future<void> requestPasswordReset(String email) =>
      _backend.requestPasswordReset(email, SupabaseConfig.resetRedirectUrl);

  Future<void> requestAccountDeletion() => _backend.requestAccountDeletion();

  void _setStatus(AuthStatus status) {
    if (_status == status) {
      return;
    }
    _status = status;
    notifyListeners();
  }
}
