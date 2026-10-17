// OwnershipService tests — explicit claim, idempotency, cross-account
// denial and the DB-layer access guard.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/database/migration_v29.dart';
import 'package:bragmat/services/ownership_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late String dbPath;

  setUp(() async {
    testDir = Directory.systemTemp.createTempSync('bragmat_owner_test_');
    dbPath = path.join(testDir.path, 'bragmat.db');
    DatabaseHelper.setTestDatabasePath(dbPath);
    // Fresh v29 database via _createDB.
    final db = await DatabaseHelper.instance.systemDatabase;
    await db.insert('catches', {'fish_type': 'Barra'});
    await db.insert('catches', {'fish_type': 'Jack'});
    await db.insert('lures', {'name': 'Spoon'});
    // _createDB seeds fishing_buddies 'Me' — it counts as an unowned row.
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    DatabaseHelper.setDataAccessDenied(false);
    OwnershipService.invalidate();
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('evaluate', () {
    test('unclaimed install with records stays unclaimed and arms the '
        'DB guard — no browsing before claim', () async {
      // The fixture database holds unowned rows.
      expect(await OwnershipService.evaluate(null),
          OwnershipState.unclaimed);
      expect(OwnershipService.hasUnownedData, isTrue);
      expect(
          () => DatabaseHelper.instance.database, throwsStateError);

      expect(await OwnershipService.evaluate('user-A'),
          OwnershipState.unclaimed);
      expect(OwnershipService.hasUnownedData, isTrue);
      // Guard stays armed — a different account cannot browse the
      // unclaimed records either.
      expect(
          () => DatabaseHelper.instance.database, throwsStateError);
      // System internals still work.
      expect(await DatabaseHelper.instance.systemDatabase, isNotNull);
    });

    test('empty database is established to the first signed-in account '
        '— establishment, not claim', () async {
      // Drain the fixture rows so the database is genuinely empty.
      final db = await DatabaseHelper.instance.systemDatabase;
      for (final table in MigrationV29.userOwnedTables) {
        await db.delete(table);
      }

      expect(await OwnershipService.evaluate('user-A'),
          OwnershipState.owner);
      expect(await OwnershipService.ownerIdFrom(db), 'user-A');
      // Guard stays disarmed — this account owns the (empty) install.
      expect(await DatabaseHelper.instance.database, isNotNull);
      // Establishment is auditable and distinct from a claim.
      final account = (await db.query('local_account')).first;
      expect(account['claimed_at'], isNotNull);
      expect(account['claim_backup_name'], isNull);
    });

    test('empty-database establishment is idempotent and refuses other '
        'accounts afterwards', () async {
      final db = await DatabaseHelper.instance.systemDatabase;
      for (final table in MigrationV29.userOwnedTables) {
        await db.delete(table);
      }

      expect(await OwnershipService.evaluate('user-A'),
          OwnershipState.owner);
      // Re-evaluation is a no-op.
      expect(await OwnershipService.evaluate('user-A'),
          OwnershipState.owner);
      // A different account is denied — an established empty install is
      // just as owned as a claimed one.
      expect(await OwnershipService.evaluate('user-B'),
          OwnershipState.denied);
    });
  });

  group('claim', () {
    test('assigns owner to every unowned row and records the claim',
        () async {
      final result = await OwnershipService.claim(
          userId: 'user-A', backupName: 'backup.zip');

      expect(result.rowsClaimed, 4); // 2 catches + 1 lure + 1 buddy
      expect(await OwnershipService.ownerIdFrom(
          await DatabaseHelper.instance.systemDatabase), 'user-A');

      final db = await DatabaseHelper.instance.systemDatabase;
      for (final table in ['catches', 'lures', 'fishing_buddies']) {
        final rows = await db.query(table, columns: ['owner_id']);
        expect(rows.every((r) => r['owner_id'] == 'user-A'), isTrue,
            reason: '$table not fully claimed');
      }
      final account = (await db.query('local_account')).first;
      expect(account['owner_id'], 'user-A');
      expect(account['claim_backup_name'], 'backup.zip');
      expect(account['claimed_at'], isNotNull);
    });

    test('claim requires a backup name and a user id', () async {
      expect(
          () => OwnershipService.claim(userId: 'u', backupName: ''),
          throwsArgumentError);
      expect(
          () => OwnershipService.claim(userId: '', backupName: 'b.zip'),
          throwsArgumentError);
    });

    test('re-claim by the same owner is a no-op', () async {
      await OwnershipService.claim(userId: 'user-A', backupName: 'b.zip');
      final again = await OwnershipService.claim(
          userId: 'user-A', backupName: 'b2.zip');
      expect(again.rowsClaimed, 0);
    });

    test('claim by a different owner is refused', () async {
      await OwnershipService.claim(userId: 'user-A', backupName: 'b.zip');
      expect(
          () => OwnershipService.claim(
              userId: 'user-B', backupName: 'b.zip'),
          throwsStateError);
    });

    test('claim reports pre-existing orphans but still succeeds',
        () async {
      final db = await DatabaseHelper.instance.systemDatabase;
      await MigrationV29.withoutTriggers(db, () async {
        await db.insert('catch_media',
            {'catch_id': 9999, 'file_path': 'x.jpg', 'created_at': 't'});
      });
      final result = await OwnershipService.claim(
          userId: 'user-A', backupName: 'b.zip');
      expect(result.orphanFindings, isNotEmpty);
      expect(result.orphanFindings.first, contains('catch_media'));
    });
  });

  group('account isolation', () {
    test('evaluate denies a different signed-in account', () async {
      await OwnershipService.claim(userId: 'user-A', backupName: 'b.zip');
      final state = await OwnershipService.evaluate('user-B');
      expect(state, OwnershipState.denied);
    });

    test('evaluate denies signed-out on a claimed install', () async {
      await OwnershipService.claim(userId: 'user-A', backupName: 'b.zip');
      expect(await OwnershipService.evaluate(null),
          OwnershipState.denied);
    });

    test('evaluate allows the owner', () async {
      await OwnershipService.claim(userId: 'user-A', backupName: 'b.zip');
      expect(await OwnershipService.evaluate('user-A'),
          OwnershipState.owner);
    });

    test('DB-layer guard blocks data access for a denied account',
        () async {
      await OwnershipService.claim(userId: 'user-A', backupName: 'b.zip');
      await OwnershipService.evaluate('user-B');
      // Public handle throws — background services and stray navigation
      // cannot reach the data.
      expect(() => DatabaseHelper.instance.database, throwsStateError);
      // System internals still work.
      expect(await DatabaseHelper.instance.systemDatabase, isNotNull);
      // Re-evaluation as the owner restores access.
      await OwnershipService.evaluate('user-A');
      expect(await DatabaseHelper.instance.database, isNotNull);
    });
  });
}
