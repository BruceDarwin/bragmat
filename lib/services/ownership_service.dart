import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../database/migration_v29.dart';

/// Access state for the installation's local data.
enum OwnershipState {
  /// No owner recorded. Whether this is open depends on content:
  /// an empty database is freely usable (and bound to the first
  /// approved account that signs in), while a database holding
  /// unclaimed historical records is gated behind the
  /// ownership-resolution screen and the DB-layer guard.
  unclaimed,

  /// The signed-in account owns this installation's data.
  owner,

  /// Data belongs to a different account — access is refused at both
  /// the UI gate and the database access layer.
  denied,
}

/// Result of an ownership claim.
class ClaimResult {
  const ClaimResult({
    required this.ownerId,
    required this.rowsClaimed,
    required this.tableCounts,
    required this.backupName,
    this.orphanFindings = const [],
  });

  final String ownerId;
  final int rowsClaimed;
  final Map<String, int> tableCounts;
  final String backupName;

  /// Orphaned-record findings discovered during pre-claim validation.
  /// Reported, not fatal — pre-existing orphans are claimed along with
  /// everything else; they predate ownership and are not made worse.
  final List<String> orphanFindings;
}

/// Manages local data ownership for Stage 4B.
///
/// One local data owner per installation, recorded in the single-row
/// `local_account` table. Existing (pre-v29) data is unowned until the
/// explicit, backup-verified claim runs — nothing is auto-assigned on
/// sign-in.
///
/// [evaluate] also drives the DB-layer access guard
/// ([DatabaseHelper.setDataAccessDenied]) so a non-owner account cannot
/// reach records through background services or direct navigation —
/// only system internals (restore, migration, this service) bypass it.
class OwnershipService {
  OwnershipService._();

  /// Bumped whenever the cached evaluation is dropped — [AuthGate]
  /// listens so ownership changes that don't come through an auth
  /// transition (claim, restore) still rebuild the gate.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static String? _cachedUserId;
  static OwnershipState? _cachedState;
  static bool _cachedHasData = false;

  /// Whether the last evaluation found an unclaimed database holding
  /// user records — the condition that gates the app behind the
  /// ownership-resolution screen and arms the DB-layer guard.
  static bool get hasUnownedData => _cachedHasData;

  /// Evaluate access for [userId] (null = signed out) and enforce the
  /// DB-layer guard. Call after auth state changes.
  ///
  /// Side effects:
  /// - An unclaimed **empty** database is bound to [userId]
  ///   (transactional, idempotent) so the first record can never turn a
  ///   new install into an inaccessible unclaimed database. This is
  ///   *establishment*, not a claim — nothing exists to back up or lose.
  /// - An unclaimed database **with** records stays unclaimed and arms
  ///   [DatabaseHelper.setDataAccessDenied] alongside the UI gate.
  static Future<OwnershipState> evaluate(String? userId) async {
    if (_cachedUserId == userId && _cachedState != null) {
      return _cachedState!;
    }
    final db = await DatabaseHelper.instance.systemDatabase;
    final owner = await ownerIdFrom(db);
    var state = owner == null
        ? OwnershipState.unclaimed
        : (userId == owner ? OwnershipState.owner : OwnershipState.denied);

    _cachedHasData = false;
    if (state == OwnershipState.unclaimed) {
      final hasData = await _hasLocalData(db);
      if (!hasData && userId != null) {
        state = await _establishEmptyOwnership(db, userId)
            ? OwnershipState.owner
            : state;
      } else {
        _cachedHasData = hasData;
      }
    }

    DatabaseHelper.setDataAccessDenied(
        state == OwnershipState.denied || _cachedHasData);
    _cachedUserId = userId;
    _cachedState = state;
    return state;
  }

  /// Whether the database holds any user-owned records at all.
  static Future<bool> hasLocalData() async {
    final db = await DatabaseHelper.instance.systemDatabase;
    return _hasLocalData(db);
  }

  static Future<bool> _hasLocalData(DatabaseExecutor db) async {
    final counts = await MigrationV29.userTableCounts(db);
    return counts.values.any((c) => c > 0);
  }

  /// Bind an empty database to [userId]. Transactional and idempotent:
  /// the UPDATE is a no-op once an owner exists, and the emptiness check
  /// re-runs inside the transaction so records that appeared meanwhile
  /// (e.g. a restore) are never silently claimed — they fall back to
  /// the unclaimed resolution path instead.
  static Future<bool> _establishEmptyOwnership(
      Database db, String userId) async {
    var established = false;
    await db.transaction((txn) async {
      if (await _hasLocalData(txn)) return;
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = await txn.rawUpdate(
          'UPDATE local_account SET owner_id = ?, claimed_at = ?, '
          'claim_db_counts = ? WHERE id = 1 AND owner_id IS NULL',
          [
            userId,
            now,
            jsonEncode(const {'_established_empty': true}),
          ]);
      established = rows > 0;
    });
    return established;
  }

  /// Drop the memoized evaluation (sign-in/out, claim, restore) and
  /// notify listeners so the gate re-evaluates immediately.
  static void invalidate() {
    _cachedUserId = null;
    _cachedState = null;
    _cachedHasData = false;
    changes.value++;
  }

  /// The installation's data owner, or null when unclaimed / pre-v29.
  /// Uses the unguarded system handle — safe on denied and on files
  /// that predate the local_account table.
  static Future<String?> currentOwnerId() async {
    final db = await DatabaseHelper.instance.systemDatabase;
    return ownerIdFrom(db);
  }

  /// owner_id from local_account on [db]; null if table/row/value
  /// absent (pre-v29 or unclaimed).
  static Future<String?> ownerIdFrom(DatabaseExecutor db) async {
    if (!await MigrationV29.tableExists(db, 'local_account')) {
      return null;
    }
    final rows = await db
        .query('local_account', columns: ['owner_id'], where: 'id = 1');
    if (rows.isEmpty) return null;
    final v = rows.first['owner_id'];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// Claim all unowned local rows for [userId].
  ///
  /// The caller must have produced a verified ZIP backup first and pass
  /// its [backupName] — the wizard creates it immediately before
  /// calling; the name is persisted in local_account for audit.
  ///
  /// Transactional + idempotent: same owner re-claim is a no-op; a
  /// different owner is refused (no transfer flow in 4B). Ownership
  /// triggers are suspended inside the transaction so the bulk UPDATE
  /// does not churn updated_at or flood sync_queue.
  static Future<ClaimResult> claim({
    required String userId,
    required String backupName,
    String? claimantEmail,
  }) async {
    if (userId.isEmpty) {
      throw ArgumentError('Cannot claim data for an empty user id');
    }
    if (backupName.isEmpty) {
      throw ArgumentError(
          'A verified backup must be created before claiming data');
    }
    final db = await DatabaseHelper.instance.systemDatabase;

    final existingOwner = await ownerIdFrom(db);
    if (existingOwner != null && existingOwner != userId) {
      throw StateError(
          'This device\'s data belongs to a different account. '
          'Ownership transfer is not supported.');
    }

    final preCounts = await MigrationV29.userTableCounts(db);
    // Orphans are reported for validation, not refused — real-world
    // v28 databases carry them (FK enforcement is off; declared
    // CASCADEs never ran). They get claimed like every other row.
    final orphans = await MigrationV29.orphanAudit(db);

    var rowsClaimed = 0;
    if (existingOwner == null) {
      await db.transaction((txn) async {
        rowsClaimed = await MigrationV29.withoutTriggers(txn, () async {
          var n = 0;
          for (final table in MigrationV29.userOwnedTables) {
            n += await txn.rawUpdate(
                'UPDATE $table SET owner_id = ? WHERE owner_id IS NULL',
                [userId]);
          }
          return n;
        });
        // The claimant's email is folded into the audit JSON so the
        // human identity behind the claim survives without a schema
        // change (claim_db_counts already carries the pre-claim counts).
        final audit = <String, Object?>{
          '_claimed_by': ?claimantEmail,
          'counts': preCounts,
        };
        await txn.rawUpdate(
            'UPDATE local_account SET owner_id = ?, claimed_at = ?, '
            'claim_backup_name = ?, claim_db_counts = ? WHERE id = 1',
            [
              userId,
              DateTime.now().toUtc().toIso8601String(),
              backupName,
              jsonEncode(audit),
            ]);
      });
    }

    // Post-claim validation: counts unchanged, no unowned rows left.
    final postCounts = await MigrationV29.userTableCounts(db);
    for (final table in MigrationV29.userOwnedTables) {
      if (postCounts[table] != preCounts[table]) {
        throw StateError('Claim validation failed: $table count changed '
            '(${preCounts[table]} -> ${postCounts[table]})');
      }
      if (!await MigrationV29.tableExists(db, table)) continue;
      final unclaimed = await txnCount(db,
          'SELECT COUNT(*) AS c FROM $table WHERE owner_id IS NULL');
      if (unclaimed != 0) {
        throw StateError(
            'Claim validation failed: $unclaimed unowned rows in $table');
      }
    }

    invalidate();
    await evaluate(userId);
    return ClaimResult(
      ownerId: userId,
      rowsClaimed: rowsClaimed,
      tableCounts: postCounts,
      backupName: backupName,
      orphanFindings: orphans,
    );
  }

  static Future<int> txnCount(DatabaseExecutor db, String sql) async {
    final rows = await db.rawQuery(sql);
    return (rows.first['c'] as int?) ?? 0;
  }
}
