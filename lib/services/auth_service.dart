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
    // Security-definer RPC: works even for revoked testers whose
    // profile UPDATE rights are gone.
    await _client.rpc('request_account_deletion');
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

  /// Test helper: emit a bare signed-out auth event (as a real backend
  /// may deliver after [signOut] returns or on external session loss).
  void emitSignedOut() {
    _userId = null;
    _email = null;
    _controller.add(null);
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

  /// Legacy device-wide approval flag (pre per-account history). Migrated
  /// to the first session's per-account key on the next refresh.
  static const _kEverApproved = 'auth_ever_approved';

  /// Per-account approval state: `auth_approval_state_<uid>` holds
  /// 'approved' or 'revoked'. Persists across sign-out so account
  /// switching can't inherit another account's entitlement and a
  /// returning revoked account still reaches Access Removed.
  static const _kApprovalStatePrefix = 'auth_approval_state_';
  static const _kApproved = 'approved';
  static const _kRevoked = 'revoked';
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
  /// app launch and foregrounding. Calls are serialized: a refresh that
  /// arrives while another is in flight is queued and re-runs afterwards,
  /// so auth events emitted mid-refresh (e.g. the sign-out a revocation
  /// triggers, or the sign-in event racing its own forced check) can
  /// never interleave and produce conflicting status transitions.
  Future<void> refresh({bool forceEntitlementCheck = false}) {
    _queuedForceCheck |= forceEntitlementCheck;
    if (_inFlightRefresh != null) {
      _refreshPending = true;
      return _inFlightRefresh!;
    }
    final future = _runRefreshes();
    _inFlightRefresh = future;
    return future;
  }

  Future<void>? _inFlightRefresh;
  bool _refreshPending = false;
  bool _queuedForceCheck = false;

  /// Set while a fresh session is about to get a forced entitlement
  /// check (sign-in / sign-up). A remembered revocation must not kill
  /// the new session before that check runs — the check is the
  /// authoritative verdict (a reinstated account must be able to sign
  /// back in).
  bool _forcedCheckPending = false;

  Future<void> _runRefreshes() async {
    try {
      do {
        _refreshPending = false;
        final force = _queuedForceCheck;
        _queuedForceCheck = false;
        await _refresh(force);
      } while (_refreshPending);
    } finally {
      _inFlightRefresh = null;
    }
  }

  Future<void> _refresh(bool forceEntitlementCheck) async {
    if (!_backend.hasSession) {
      // A confirmed revocation is terminal until the user acts: the
      // signOut that the revocation itself triggered (or an external
      // session loss) must not drop the status back to signedOut and
      // hide the Access Removed screen.
      if (_status != AuthStatus.revoked) {
        _setStatus(AuthStatus.signedOut);
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final uid = _backend.userId;
    final approvalKey = uid == null ? null : '$_kApprovalStatePrefix$uid';

    // One-time migration: attribute the legacy device-wide flag to the
    // session that first refreshes after the upgrade, then drop it so no
    // other account can inherit it.
    if (approvalKey != null && prefs.getBool(_kEverApproved) == true) {
      await prefs.setString(approvalKey, _kApproved);
      await prefs.remove(_kEverApproved);
    }
    final approvalState =
        approvalKey == null ? null : prefs.getString(approvalKey);

    final last = prefs.getInt(_kLastEntitlementCheck) ?? 0;
    final due = DateTime.now().millisecondsSinceEpoch - last >=
        _entitlementCheckInterval.inMilliseconds;

    if (forceEntitlementCheck || due) {
      final result = await _checkEntitlement();
      if (result == BetaCheckResult.offline) {
        // Offline: trust this account's remembered state — approved
        // sessions stay usable, confirmed revocations stay denied, and
        // a never-verified session fails closed. The check already ran
        // here, so a remembered revocation may kill the session.
        await _applyRememberedState(approvalState, revokeKillsSession: true);
        return;
      }
      await prefs.setInt(
          _kLastEntitlementCheck, DateTime.now().millisecondsSinceEpoch);
      if (result == BetaCheckResult.approved) {
        if (approvalKey != null) {
          await prefs.setString(approvalKey, _kApproved);
        }
        try {
          await _backend.upsertProfile('');
        } catch (_) {
          // Profile upsert is non-fatal — RLS allows it once approved,
          // and a transient failure must not block the app.
        }
        _setStatus(AuthStatus.signedIn);
      } else if (approvalState != null) {
        // Previously approved and now denied, or already marked revoked:
        // record it per account and surface Access Removed rather than
        // the never-approved Awaiting Invitation screen.
        if (approvalKey != null) {
          await prefs.setString(approvalKey, _kRevoked);
        }
        await _backend.signOut();
        _setStatus(AuthStatus.revoked);
      } else {
        // Never approved — nothing remembered for this account.
        _setStatus(AuthStatus.awaitingApproval);
      }
      return;
    }

    // Within throttle window: trust this account's remembered state.
    // While a forced check is pending (fresh sign-in/sign-up), a
    // remembered revocation only surfaces the status — killing the new
    // session now would also lock out a reinstated account before its
    // check can run.
    await _applyRememberedState(approvalState,
        revokeKillsSession: !_forcedCheckPending);
  }

  /// Applies the locally remembered approval state for the current
  /// account — used when the entitlement check can't run (offline or
  /// inside the throttle window). A remembered revocation denies access
  /// immediately rather than granting offline use on stale approval.
  Future<void> _applyRememberedState(
    String? approvalState, {
    required bool revokeKillsSession,
  }) async {
    switch (approvalState) {
      case _kApproved:
        _setStatus(AuthStatus.signedIn);
      case _kRevoked:
        if (revokeKillsSession) {
          await _backend.signOut();
        }
        _setStatus(AuthStatus.revoked);
      default:
        _setStatus(AuthStatus.awaitingApproval);
    }
  }

  Future<BetaCheckResult> _checkEntitlement() async {
    final approved = await _backend.isApprovedBeta();
    if (approved == null) {
      return BetaCheckResult.offline;
    }
    return approved ? BetaCheckResult.approved : BetaCheckResult.notApproved;
  }

  Future<void> signIn(String email, String password) async {
    _forcedCheckPending = true;
    try {
      await _backend.signIn(email, password);
      _pendingEmail = null;
      await refresh(forceEntitlementCheck: true);
    } finally {
      _forcedCheckPending = false;
    }
  }

  /// Creates the account. When email confirmation is enabled no session
  /// exists yet — status moves to [AuthStatus.emailVerificationPending]
  /// and the user verifies via the emailed link before signing in.
  Future<void> signUp(String email, String password) async {
    _forcedCheckPending = true;
    try {
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
    } finally {
      _forcedCheckPending = false;
    }
  }

  /// Sign out but keep all local data. Per-account approval history is
  /// deliberately kept: it belongs to the account, not the session, so
  /// a returning revoked account still reaches Access Removed and an
  /// approved account keeps its offline eligibility.
  Future<void> signOut() async {
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
