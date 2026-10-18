import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database_helper.dart';
import 'auth_service.dart';
import 'backup_envelope.dart';
import 'ownership_service.dart';
import 'supabase_config.dart';
import 'zip_backup_service.dart';

/// Cloud backup is not enabled (no recorded consent, or disabled).
class CloudBackupNotEnabledException implements Exception {
  @override
  String toString() => 'Cloud backup is not enabled';
}

/// The caller is not signed in — cloud backup requires an account.
class CloudBackupAuthException implements Exception {
  @override
  String toString() => 'Not signed in';
}

/// The signed-in account is not the owner of this installation's data —
/// uploading another account's (or unclaimed) records is never allowed.
class CloudBackupOwnershipException implements Exception {
  CloudBackupOwnershipException(this.reason);
  final String reason;
  @override
  String toString() => 'Cloud backup refused: $reason';
}

/// A remote object with the same name already exists (upsert is never
/// used — identical names must fail rather than overwrite).
class RemoteObjectExistsException implements Exception {
  RemoteObjectExistsException(this.name);
  final String name;
  @override
  String toString() => 'A cloud backup with this name already exists';
}

/// The storage backend refused the upload for capacity reasons.
class CloudQuotaExceededException implements Exception {
  @override
  String toString() => 'Cloud storage quota exceeded';
}

/// Downloaded/read-back bytes did not match the recorded digest.
class CloudIntegrityException implements Exception {
  @override
  String toString() => 'Cloud backup failed integrity verification';
}

/// The operation was cancelled by the user between stages.
class CloudBackupCancelledException implements Exception {
  const CloudBackupCancelledException();
  @override
  String toString() => 'Cancelled';
}

/// Cooperative cancellation token for long-running cloud operations.
class CloudBackupCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw const CloudBackupCancelledException();
  }
}

/// A remote backup entry as listed for the current user.
class RemoteBackupInfo {
  const RemoteBackupInfo({
    required this.name,
    required this.size,
    this.sha256Hex,
    this.createdAt,
  });

  /// Bare object name (no uid prefix) — e.g. `bragmat_backup_….bzp`.
  final String name;
  final int size;
  final String? sha256Hex;
  final DateTime? createdAt;
}

/// Result of a completed, verified cloud upload.
class CloudUploadResult {
  const CloudUploadResult({
    required this.remoteName,
    required this.sha256Hex,
    required this.size,
    required this.recoveryCode,
    required this.pruned,
  });
  final String remoteName;
  final String sha256Hex;
  final int size;

  /// Independent decryption secret — show ONCE, never store or log.
  final String recoveryCode;

  /// Remote names pruned by retention after this upload verified.
  final List<String> pruned;
}

/// Storage transport — the only part that talks to Supabase.
/// [SupabaseCloudBackupBackend] is production; [FakeCloudBackupBackend]
/// (in tests) needs no network.
abstract class CloudBackupBackend {
  /// Signed-in user id, or null when signed out.
  String? get userId;

  /// Upload [file] as [remoteName] under the caller's uid prefix.
  /// MUST NOT overwrite: identical names fail (upsert:false).
  /// Implementations throw [RemoteObjectExistsException] on collision
  /// and [CloudQuotaExceededException] on capacity errors.
  Future<void> upload(
    String remoteName,
    File file, {
    required Map<String, String> metadata,
  });

  /// List the caller's own backups (server-scoped to their prefix).
  Future<List<RemoteBackupInfo>> list();

  /// The sha256 recorded in the object's custom metadata at upload, or
  /// null when absent. NOTE: custom metadata does not appear in list
  /// responses — it must be fetched per object via the info endpoint.
  Future<String?> recordedSha256(String remoteName);

  /// Download [remoteName] (own prefix) into [dest].
  Future<void> download(String remoteName, File dest);

  /// Delete named objects from the caller's prefix via the Storage API
  /// (requires an approved account). Returns the number removed.
  Future<int> delete(List<String> remoteNames);

  /// Delete ALL of the caller's backups via the delete-backups Edge
  /// Function — works even after revocation (account closure path).
  Future<int> deleteAll();
}

/// Production backend over the Supabase client. Thin on purpose — all
/// logic lives in [CloudBackupService] so the fake covers everything.
class SupabaseCloudBackupBackend implements CloudBackupBackend {
  SupabaseCloudBackupBackend(this._client);
  final SupabaseClient _client;

  static const String bucket = 'backups';

  String get _prefix => '$userId/';

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<void> upload(
    String remoteName,
    File file, {
    required Map<String, String> metadata,
  }) async {
    try {
      await _client.storage.from(bucket).upload(
            '$_prefix$remoteName',
            file,
            fileOptions: FileOptions(upsert: false, metadata: metadata),
          );
    } on StorageException catch (e) {
      // statusCode is a String in storage-dart.
      if (e.statusCode == '413' || e.error == 'Payload too large') {
        throw CloudQuotaExceededException();
      }
      if (e.statusCode == '400' || e.statusCode == '409') {
        throw RemoteObjectExistsException(remoteName);
      }
      rethrow;
    }
  }

  @override
  Future<List<RemoteBackupInfo>> list() async {
    final objects =
        await _client.storage.from(bucket).list(path: _prefix);
    return [
      for (final o in objects)
        if (o.name.isNotEmpty)
          RemoteBackupInfo(
            name: o.name,
            size: (o.metadata?['size'] as num?)?.toInt() ?? 0,
            sha256Hex: o.metadata?['sha256'] as String?,
            createdAt: DateTime.tryParse(o.createdAt ?? ''),
          ),
    ];
  }

  @override
  Future<String?> recordedSha256(String remoteName) async {
    try {
      final info = await _client.storage
          .from(bucket)
          .info('$_prefix$remoteName');
      return info.metadata?['sha256'] as String?;
    } on StorageException catch (e) {
      // Object vanished between download and lookup — no digest to
      // verify against; the AEAD decrypt remains the hard boundary.
      if (e.statusCode == '400' || e.statusCode == '404') return null;
      rethrow;
    }
  }

  @override
  Future<void> download(String remoteName, File dest) async {
    final bytes =
        await _client.storage.from(bucket).download('$_prefix$remoteName');
    await dest.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<int> delete(List<String> remoteNames) async {
    final removed = await _client.storage
        .from(bucket)
        .remove([for (final n in remoteNames) '$_prefix$n']);
    return removed.length;
  }

  @override
  Future<int> deleteAll() async {
    final response = await _client.functions
        .invoke('delete-backups', body: {'reason': 'user_request'});
    final data = response.data;
    return (data is Map ? data['deleted'] as num? : null)?.toInt() ?? 0;
  }
}

/// Cloud backup orchestration — Stage 4C-3.
///
/// Pipeline: consent gate → local ZIP (existing pipeline, unchanged) →
/// BRGZ encrypt → upload (upsert:false) → read-back + SHA-256 verify →
/// keep-last-3 retention. Restore: list → download → digest check →
/// decrypt → existing ownership-protected staged restore.
///
/// All temporary files (ZIP, ciphertext, downloaded/decrypted copies)
/// live under the app's private support directory and are removed in
/// `finally` — success or failure.
///
/// SECURITY: passphrases, recovery codes and content are never logged.
class CloudBackupService {
  CloudBackupService._(this._backend);

  static CloudBackupService? testInstance;

  static CloudBackupService get instance =>
      testInstance ??= CloudBackupService._(
        SupabaseCloudBackupBackend(Supabase.instance.client),
      );

  factory CloudBackupService.forBackend(CloudBackupBackend backend) =>
      CloudBackupService._(backend);

  final CloudBackupBackend _backend;

  // ── Consent ──────────────────────────────────────────────────────────

  static const String consentVersion = '1.0';
  static const _kEnabled = 'cloud_backup_enabled';
  static const _kConsentAt = 'cloud_backup_consent_at';
  static const _kConsentVersion = 'cloud_backup_consent_version';

  /// Disabled by default — enabled only via [grantConsent].
  static Future<bool> get isEnabled async =>
      (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;

  /// Record explicit opt-in consent (versioned consent text).
  static Future<void> grantConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, true);
    await prefs.setString(_kConsentVersion, consentVersion);
    await prefs.setInt(
        _kConsentAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// Turn cloud backup off. Remote backups are left alone unless
  /// [deleteRemote] — which routes through the Edge Function so it also
  /// works after revocation.
  Future<int> disable({bool deleteRemote = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, false);
    if (!deleteRemote) return 0;
    try {
      return await _backend.deleteAll();
    } catch (_) {
      return -1; // remote cleanup failed — reportable, consent still off
    }
  }

  // ── Test seams ────────────────────────────────────────────────────────

  /// Overrides the ZIP producer (unit tests bypass the live DB).
  static Future<String> Function(String outputDir)? debugCreateBackup;

  /// Overrides the restore call (unit tests bypass the live DB/media).
  static Future<BackupRestoreResult> Function(String zipPath)?
      debugRestoreOverride;

  /// Overrides the private working directory root (unit tests).
  static Directory? debugWorkDir;

  /// Overrides the effective auth status (unit tests — production reads
  /// [AuthService.instance.status]). Ordinary cloud operations require
  /// [AuthStatus.signedIn]: a raw JWT alone is not sufficient — revoked
  /// and never-approved sessions with a still-valid token are denied.
  static AuthStatus? debugAuthStatus;

  /// Overrides the local-DB-owner lookup (unit tests — production reads
  /// `local_account` via the unguarded system handle).
  static Future<String?> Function()? debugLocalOwnerIdReader;

  /// Retention window — keep this many VERIFIED backups.
  static const int keepBackups = 3;

  // ── Operations ────────────────────────────────────────────────────────

  /// Create → encrypt → upload → verify → prune. Returns the upload
  /// result including the one-time recovery code.
  Future<CloudUploadResult> uploadNow({
    required String passphrase,
    String? recoveryCode,
    CloudBackupCancelToken? cancellation,
    void Function(String)? onProgress,
  }) async {
    await _requireEnabled();
    final uid = _requireApprovedAccess();
    await _requireOwner(uid);

    final work = await _workDir();
    try {
      onProgress?.call('Creating backup…');
      final create = debugCreateBackup ??
          (String dir) =>
              ZipBackupService.createBackup(outputDirectory: dir);
      final zipPath = await create(work.path);
      cancellation?.throwIfCancelled();

      onProgress?.call('Encrypting…');
      final remoteName = _remoteNameFor(File(zipPath));
      final encFile = File('${work.path}/$remoteName');
      final enc = await BackupEnvelope.encryptFile(
        input: File(zipPath),
        output: encFile,
        passphrase: passphrase,
        recoveryCode: recoveryCode,
      );
      cancellation?.throwIfCancelled();

      onProgress?.call('Uploading…');
      await _backend.upload(
        remoteName,
        encFile,
        metadata: {'sha256': enc.sha256Hex},
      );
      cancellation?.throwIfCancelled();

      onProgress?.call('Verifying upload…');
      await _verifyOrDelete(remoteName, enc.sha256Hex, work);
      cancellation?.throwIfCancelled();

      onProgress?.call('Applying retention…');
      final pruned = await _prune();

      return CloudUploadResult(
        remoteName: remoteName,
        sha256Hex: enc.sha256Hex,
        size: enc.size,
        recoveryCode: enc.recoveryCode,
        pruned: pruned,
      );
    } finally {
      await _cleanup(work);
    }
  }

  /// List the caller's remote backups, newest first.
  Future<List<RemoteBackupInfo>> listBackups() async {
    await _requireEnabled();
    _requireApprovedAccess();
    final list = await _backend.list();
    list.sort((a, b) => b.name.compareTo(a.name));
    return list;
  }

  /// Download → digest-check → decrypt → restore through the existing
  /// staged pipeline (which applies the ownership gate unchanged).
  ///
  /// [confirmUnownedRestore] and [createSafetyBackup] are the same
  /// owner-only hooks the local restore path uses: an unowned backup
  /// landing on an owned install needs explicit confirmation plus a
  /// verified safety backup first, and the restored records stay
  /// unclaimed until explicitly linked. Foreign-owner backups are
  /// refused outright by the staged pipeline.
  Future<BackupRestoreResult> restoreFromCloud({
    required String remoteName,
    String? passphrase,
    String? recoveryCode,
    Future<bool> Function()? confirmUnownedRestore,
    Future<String?> Function()? createSafetyBackup,
    CloudBackupCancelToken? cancellation,
    void Function(String)? onProgress,
  }) async {
    await _requireEnabled();
    _requireApprovedAccess();

    final work = await _workDir();
    final encFile = File('${work.path}/$remoteName');
    final zipFile =
        File('${work.path}/${remoteName.replaceAll(RegExp(r'\.bzp$'), '.zip')}');
    try {
      onProgress?.call('Downloading…');
      await _backend.download(remoteName, encFile);
      cancellation?.throwIfCancelled();

      // Digest check when the upload recorded one — a tampered or
      // truncated object aborts BEFORE decryption/restore. Custom
      // metadata is not in list responses; it must be fetched via the
      // object's info endpoint.
      final expectedSha = await _backend.recordedSha256(remoteName);
      if (expectedSha != null &&
          expectedSha != await BackupEnvelope.sha256OfFile(encFile)) {
        throw CloudIntegrityException();
      }
      cancellation?.throwIfCancelled();

      onProgress?.call('Decrypting…');
      await BackupEnvelope.decryptFile(
        input: encFile,
        output: zipFile,
        passphrase: passphrase,
        recoveryCode: recoveryCode,
      );
      cancellation?.throwIfCancelled();

      onProgress?.call('Restoring…');
      final restore = debugRestoreOverride ??
          (String path) => ZipBackupService.restoreBackup(
                zipPath: path,
                onProgress: onProgress,
                currentUserId: _backend.userId,
                confirmUnownedRestore: confirmUnownedRestore,
                createSafetyBackup: createSafetyBackup,
              );
      return await restore(zipFile.path);
    } finally {
      await _cleanup(work);
    }
  }

  /// Delete one remote backup (Storage API — approved accounts).
  Future<int> deleteBackup(String remoteName) async {
    await _requireEnabled();
    _requireApprovedAccess();
    return _backend.delete([remoteName]);
  }

  /// Delete every remote backup via the Edge Function — the restricted
  /// account-management exception that still works after revocation.
  /// Gated on a live session only, deliberately NOT on the approved
  /// status: a revoked user must retain the ability to remove their own
  /// cloud data. RLS and the Edge Function authorise independently.
  Future<int> deleteAllBackups() async {
    if (_backend.userId == null) throw CloudBackupAuthException();
    return _backend.deleteAll();
  }

  // ── internals ─────────────────────────────────────────────────────────

  static Future<void> _requireEnabled() async {
    if (!await isEnabled) throw CloudBackupNotEnabledException();
  }

  /// Ordinary cloud operations require an authenticated AND approved
  /// account — the entitlement-aware [AuthStatus], not just a JWT.
  String _requireApprovedAccess() {
    if (_effectiveAuthStatus() != AuthStatus.signedIn) {
      throw CloudBackupAuthException();
    }
    final uid = _backend.userId;
    if (uid == null) throw CloudBackupAuthException();
    return uid;
  }

  static AuthStatus _effectiveAuthStatus() {
    final override = debugAuthStatus;
    if (override != null) return override;
    // Without Supabase configuration there can be no approved session.
    if (!SupabaseConfig.isConfigured) return AuthStatus.signedOut;
    return AuthService.instance.status;
  }

  /// The local database must belong to the very account uploading it —
  /// unclaimed data and foreign-owned data can never reach the cloud.
  Future<void> _requireOwner(String uid) async {
    final owner = await _localOwnerId();
    if (owner == null) {
      throw CloudBackupOwnershipException(
          'local data is unclaimed — link it to your account first');
    }
    if (owner != uid) {
      throw CloudBackupOwnershipException(
          'local data belongs to a different account');
    }
  }

  static Future<String?> _localOwnerId() async {
    final reader = debugLocalOwnerIdReader;
    if (reader != null) return reader();
    final db = await DatabaseHelper.instance.systemDatabase;
    return OwnershipService.ownerIdFrom(db);
  }

  static String _remoteNameFor(File zip) {
    final base = zip.path.split(RegExp(r'[/\\]')).last;
    return base.endsWith('.zip')
        ? '${base.substring(0, base.length - 4)}.bzp'
        : '$base.bzp';
  }

  Future<Directory> _workDir() async {
    final root = debugWorkDir ??
        Directory(
            '${(await getApplicationSupportDirectory()).path}/cloud_backup_tmp');
    final dir = Directory(
        '${root.path}/${DateTime.now().microsecondsSinceEpoch}');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<void> _cleanup(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Cleanup failure is non-fatal; the dir is inside private storage.
    }
  }

  /// Verify the just-uploaded object by trusted read-back: download it
  /// and compare SHA-256 against the value recorded at encrypt time.
  /// On mismatch the unverified object is deleted and an integrity error
  /// is raised — retention NEVER runs on an unverified upload.
  Future<void> _verifyOrDelete(
      String remoteName, String expectedSha, Directory work) async {
    final verifyFile = File('${work.path}/verify.bzp');
    try {
      await _backend.download(remoteName, verifyFile);
      if (await BackupEnvelope.sha256OfFile(verifyFile) != expectedSha) {
        throw CloudIntegrityException();
      }
    } catch (e) {
      try {
        await _backend.delete([remoteName]);
      } catch (_) {
        // Best-effort removal of the unverified object.
      }
      rethrow;
    }
  }

  /// Keep the newest [keepBackups] verified backups; delete the rest.
  Future<List<String>> _prune() async {
    final list = await _backend.list();
    list.sort((a, b) => b.name.compareTo(a.name));
    if (list.length <= keepBackups) return const [];
    final excess = [for (final b in list.skip(keepBackups)) b.name];
    await _backend.delete(excess);
    return excess;
  }
}
