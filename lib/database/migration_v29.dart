import 'package:sqflite_common/sqlite_api.dart';

/// Schema v29 — user data ownership & account isolation.
///
/// Adds `uuid`, `owner_id` and `updated_at` to the 12 user-owned tables,
/// creates `local_account` (single-row ownership record) and
/// `sync_queue` (change log for future sync), and installs triggers that
/// populate uuid/owner on insert, maintain `updated_at`, and append
/// change events — so existing write paths need no modification.
///
/// All operations are idempotent (`PRAGMA table_info` guards, IF NOT
/// EXISTS) and run inside sqflite's upgrade transaction — a failed or
/// interrupted migration rolls back cleanly and retries on next open.
class MigrationV29 {
  MigrationV29._();

  /// Tables whose rows belong to the installation's data owner.
  /// Shared reference tables (fish_types, achievements) and caches
  /// (tide_cache) are intentionally excluded.
  static const List<String> userOwnedTables = [
    'catches',
    'catch_media',
    'fishing_trips',
    'trip_media',
    'trip_journal',
    'journal_media',
    'favourite_spots',
    'environmental_conditions',
    'user_achievements',
    'lures',
    'baits',
    'fishing_buddies',
  ];

  /// User-owned tables lacking an updated_at column before v29.
  /// (trip_journal and environmental_conditions already have one.)
  static const Set<String> _needsUpdatedAt = {
    'catches',
    'catch_media',
    'fishing_trips',
    'trip_media',
    'journal_media',
    'favourite_spots',
    'user_achievements',
    'lures',
    'baits',
    'fishing_buddies',
  };

  /// RFC-4122 v4 UUID built in pure SQL — randomblob is evaluated per
  /// row, so a single UPDATE backfills distinct uuids.
  static const String uuidExpression =
      "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || "
      "'-4' || substr(lower(hex(randomblob(2))), 2) || '-' || "
      "substr('89ab', (abs(random()) % 4) + 1, 1) || "
      "substr(lower(hex(randomblob(2))), 2) || '-' || "
      "lower(hex(randomblob(6)))";

  static const String _now = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";

  /// Full v28 → v29 migration. Runs inside sqflite's onUpgrade
  /// transaction on the live database, and is also invoked on staged
  /// restore files before they are promoted.
  static Future<void> migrate(DatabaseExecutor db) async {
    for (final table in userOwnedTables) {
      if (!await _tableExists(db, table)) continue;
      await _addColumnIfMissing(db, table, 'uuid', 'TEXT');
      await _addColumnIfMissing(db, table, 'owner_id', 'TEXT');
      if (_needsUpdatedAt.contains(table)) {
        await _addColumnIfMissing(db, table, 'updated_at', 'TEXT');
      }
    }
    await createOwnershipTables(db);
    await backfillIdentityColumns(db);
    await createIndexes(db);
    await createTriggers(db);
  }

  /// New tables introduced at v29. Safe on both upgrade and fresh
  /// install paths.
  static Future<void> createOwnershipTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_account (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        owner_id TEXT,
        claimed_at TEXT,
        claim_backup_name TEXT,
        claim_db_counts TEXT
      )
    ''');
    await db.execute(
        'INSERT OR IGNORE INTO local_account (id, owner_id) VALUES (1, NULL)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        local_id INTEGER,
        record_uuid TEXT,
        operation TEXT NOT NULL
          CHECK (operation IN ('insert', 'update', 'delete')),
        changed_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_table ON sync_queue(table_name, seq)');
  }

  /// uuid + updated_at backfill for pre-existing rows. owner_id stays
  /// NULL — existing data remains unowned until the explicit claim.
  static Future<void> backfillIdentityColumns(DatabaseExecutor db) async {
    for (final table in userOwnedTables) {
      if (!await _columnExists(db, table, 'uuid')) continue;
      await db.execute(
          'UPDATE $table SET uuid = $uuidExpression WHERE uuid IS NULL');
      if (_needsUpdatedAt.contains(table) ||
          await _columnExists(db, table, 'updated_at')) {
        final backfill =
            await _columnExists(db, table, 'created_at')
                ? 'COALESCE(created_at, $_now)'
                : _now;
        await db.execute(
            'UPDATE $table SET updated_at = $backfill '
            'WHERE updated_at IS NULL');
      }
    }
  }

  /// Partial unique index per table — uuids must be unique once present.
  static Future<void> createIndexes(DatabaseExecutor db) async {
    for (final table in userOwnedTables) {
      if (!await _columnExists(db, table, 'uuid')) continue;
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_uuid '
          'ON $table(uuid) WHERE uuid IS NOT NULL');
    }
  }

  static const List<String> _triggerSuffixes = ['ai', 'touch', 'qu', 'qd'];

  /// Triggers per user-owned table:
  /// - ai    : AFTER INSERT — fills uuid/owner_id/updated_at when NULL,
  ///           then records the insert in sync_queue (uuid resolved
  ///           post-update inside the same trigger).
  /// - touch : AFTER UPDATE — maintains updated_at, skipping updates
  ///           that already set it (e.g. the ai trigger or explicit
  ///           values supplied by a future sync restore).
  /// - qu/qd : AFTER UPDATE/DELETE — record change events; deletes keep
  ///           the uuid as a tombstone.
  static Future<void> createTriggers(DatabaseExecutor db) async {
    for (final t in userOwnedTables) {
      if (!await _tableExists(db, t)) continue;
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_ai AFTER INSERT ON $t
        BEGIN
          UPDATE $t SET
            uuid = COALESCE(NEW.uuid, $uuidExpression),
            owner_id = COALESCE(NEW.owner_id,
                (SELECT owner_id FROM local_account WHERE id = 1)),
            updated_at = COALESCE(NEW.updated_at, $_now)
          WHERE id = NEW.id;
          INSERT INTO sync_queue
              (table_name, local_id, record_uuid, operation, changed_at)
          SELECT '$t', NEW.id, uuid, 'insert', $_now
          FROM $t WHERE id = NEW.id;
        END
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_touch AFTER UPDATE ON $t
        WHEN NEW.updated_at IS OLD.updated_at
        BEGIN
          UPDATE $t SET updated_at = $_now WHERE id = NEW.id;
        END
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_qu AFTER UPDATE ON $t
        BEGIN
          INSERT INTO sync_queue
              (table_name, local_id, record_uuid, operation, changed_at)
          SELECT '$t', NEW.id, uuid, 'update', $_now
          FROM $t WHERE id = NEW.id;
        END
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_qd AFTER DELETE ON $t
        BEGIN
          INSERT INTO sync_queue
              (table_name, local_id, record_uuid, operation, changed_at)
          VALUES ('$t', OLD.id, OLD.uuid, 'delete', $_now);
        END
      ''');
    }
  }

  static Future<void> dropTriggers(DatabaseExecutor db) async {
    for (final t in userOwnedTables) {
      for (final s in _triggerSuffixes) {
        await db.execute('DROP TRIGGER IF EXISTS trg_${t}_$s');
      }
    }
  }

  /// Runs [fn] with the ownership triggers suspended, then recreates
  /// them. Used by bulk operations (claim, restore stamping) that must
  /// not churn updated_at or flood sync_queue. Call inside a
  /// transaction so the drop/recreate is atomic with the work.
  static Future<T> withoutTriggers<T>(
      DatabaseExecutor db, Future<T> Function() fn) async {
    await dropTriggers(db);
    try {
      return await fn();
    } finally {
      await createTriggers(db);
    }
  }

  /// Bound queue growth without losing information sync will need:
  /// only superseded insert/update events are dropped (the newest one
  /// per record survives). Delete tombstones are ALWAYS kept — they are
  /// the only record that a row was removed and cannot be recovered.
  static Future<int> compactSyncQueue(DatabaseExecutor db) async {
    return await db.rawDelete('''
      DELETE FROM sync_queue
      WHERE operation != 'delete' AND seq NOT IN (
        SELECT MAX(seq) FROM sync_queue
        WHERE operation != 'delete'
        GROUP BY table_name, COALESCE(record_uuid, CAST(local_id AS TEXT))
      )
    ''');
  }

  /// Per-table row counts for the 12 user-owned tables — used by claim
  /// validation and reporting.
  static Future<Map<String, int>> userTableCounts(
      DatabaseExecutor db) async {
    final counts = <String, int>{};
    for (final table in userOwnedTables) {
      if (!await _tableExists(db, table)) {
        counts[table] = 0;
        continue;
      }
      final rows =
          await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      counts[table] = (rows.first['c'] as int?) ?? 0;
    }
    return counts;
  }

  /// Declared and undeclared relationships to check for orphans.
  /// (child table, child FK column, parent table, parent PK column)
  static const List<(String, String, String, String)> _relations = [
    ('catch_media', 'catch_id', 'catches', 'id'),
    ('trip_media', 'trip_id', 'fishing_trips', 'id'),
    ('trip_journal', 'trip_id', 'fishing_trips', 'id'),
    ('journal_media', 'journal_entry_id', 'trip_journal', 'id'),
    ('user_achievements', 'achievement_id', 'achievements', 'id'),
    ('environmental_conditions', 'catch_id', 'catches', 'id'),
    ('environmental_conditions', 'trip_id', 'fishing_trips', 'id'),
    ('catches', 'trip_id', 'fishing_trips', 'id'),
    ('catches', 'fishing_buddy_id', 'fishing_buddies', 'id'),
    ('catches', 'lure_id', 'lures', 'id'),
    ('catches', 'bait_id', 'baits', 'id'),
  ];

  /// Orphan audit across declared and undeclared relationships.
  /// Returns a list of human-readable findings (empty = clean).
  /// FK enforcement stays OFF in 4B — this reports, it does not enforce.
  static Future<List<String>> orphanAudit(DatabaseExecutor db) async {
    final findings = <String>[];
    for (final (child, fk, parent, pk) in _relations) {
      if (!await _tableExists(db, child) ||
          !await _tableExists(db, parent) ||
          !await _columnExists(db, child, fk)) {
        continue;
      }
      final rows = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM $child '
          'WHERE $fk IS NOT NULL AND $fk NOT IN (SELECT $pk FROM $parent)');
      final count = (rows.first['c'] as int?) ?? 0;
      if (count > 0) {
        findings.add('$child.$fk: $count row(s) reference missing '
            '$parent.$pk');
      }
    }
    return findings;
  }

  /// Distinct non-null owner_ids across user tables — used to detect
  /// ambiguous ownership in backup files.
  static Future<Set<String>> distinctRowOwners(DatabaseExecutor db) async {
    final owners = <String>{};
    for (final table in userOwnedTables) {
      if (!await _columnExists(db, table, 'owner_id')) continue;
      final rows = await db.rawQuery(
          'SELECT DISTINCT owner_id FROM $table WHERE owner_id IS NOT NULL');
      for (final row in rows) {
        final v = row['owner_id'];
        if (v is String && v.isNotEmpty) owners.add(v);
      }
    }
    return owners;
  }

  static Future<bool> _columnExists(
      DatabaseExecutor db, String table, String column) async {
    try {
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      return cols.any((c) => c['name'] == column);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _tableExists(
      DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table]);
    return rows.isNotEmpty;
  }

  static Future<void> _addColumnIfMissing(DatabaseExecutor db,
      String table, String column, String type) async {
    if (!await _columnExists(db, table, column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  /// Exposed for callers that need the guarded column check
  /// (e.g. OwnershipService reading local_account on a pre-v29 file).
  static Future<bool> columnExists(
          DatabaseExecutor db, String table, String column) =>
      _columnExists(db, table, column);

  static Future<bool> tableExists(DatabaseExecutor db, String table) =>
      _tableExists(db, table);
}
