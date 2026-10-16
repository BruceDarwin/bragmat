import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:bragmat/models/backup_manifest.dart';
import 'package:bragmat/services/media_storage_service.dart';
import 'package:bragmat/services/zip_backup_service.dart';
import 'package:bragmat/services/backup_file_service.dart';
import 'package:bragmat/database/database_helper.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('MediaStorageService - portable paths', () {
    late Directory testDir;
    late Directory mediaDir;

    setUp(() async {
      testDir = Directory.systemTemp.createTempSync('bragmat_media_test_');
      MediaStorageService.setTestDirectory(testDir);
      mediaDir = await MediaStorageService.getMediaDirectory();
    });

    tearDown(() async {
      MediaStorageService.clearTestDirectory();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('copyPhotoToStorage returns a relative path in the canonical dir',
        () async {
      final source = File(path.join(testDir.path, 'source_photo.jpg'));
      await source.writeAsBytes([10, 20, 30, 40]);

      final stored = await MediaStorageService.copyPhotoToStorage(
          source.path, 'catch', 7, 'primary');

      expect(stored, isNotNull);
      expect(path.isAbsolute(stored!), isFalse);
      expect(stored, startsWith('catches/'));

      final onDisk = File(path.joinAll([mediaDir.path, ...stored.split('/')]));
      expect(await onDisk.exists(), isTrue);
      expect(await onDisk.readAsBytes(), [10, 20, 30, 40]);
    });

    test('copyPhotoToStorage maps entity types to plural subdirs', () async {
      final source = File(path.join(testDir.path, 'lure.jpg'));
      await source.writeAsBytes([1]);

      final lure = await MediaStorageService.copyPhotoToStorage(
          source.path, 'lure', 3, 'primary');
      final journal = await MediaStorageService.copyPhotoToStorage(
          source.path, 'journal', 1, 'primary');
      final trip = await MediaStorageService.copyPhotoToStorage(
          source.path, 'trip', 2, 'primary');

      expect(lure, startsWith('lures/'));
      expect(journal, startsWith('journals/'));
      expect(trip, startsWith('trips/'));
    });

    test('canonicalizeRelPath maps legacy singular prefixes', () {
      expect(MediaStorageService.canonicalizeRelPath('catch/a.jpg'),
          'catches/a.jpg');
      expect(MediaStorageService.canonicalizeRelPath('lure/b.png'),
          'lures/b.png');
      expect(MediaStorageService.canonicalizeRelPath('trip/c.jpg'),
          'trips/c.jpg');
      expect(MediaStorageService.canonicalizeRelPath('journal/d.jpg'),
          'journals/d.jpg');
      expect(MediaStorageService.canonicalizeRelPath('catches/a.jpg'),
          'catches/a.jpg');
      expect(MediaStorageService.canonicalizeRelPath('bare.jpg'), 'bare.jpg');
    });

    test('resolvePath and fileExists fall back to canonical subdirs',
        () async {
      final file = File(path.join(mediaDir.path, 'catches', 'photo.jpg'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes([5, 6, 7]);

      // Legacy `catch/` reference still resolves to the canonical file.
      expect(await MediaStorageService.fileExists('catch/photo.jpg'), isTrue);
      final resolved = await MediaStorageService.resolvePath('catch/photo.jpg');
      expect(resolved, file.path);

      expect(await MediaStorageService.fileExists('catches/photo.jpg'), isTrue);
      expect(await MediaStorageService.fileExists('catch/nope.jpg'), isFalse);
    });

    test('migrateLegacyStorage moves singular dirs and reports renames',
        () async {
      final legacyCatch =
          File(path.join(mediaDir.path, 'catch', 'old_photo.jpg'));
      await legacyCatch.parent.create(recursive: true);
      await legacyCatch.writeAsBytes([1, 1, 1]);
      final legacyLure = File(path.join(mediaDir.path, 'lure', 'lure.jpg'));
      await legacyLure.parent.create(recursive: true);
      await legacyLure.writeAsBytes([2, 2]);

      // Name conflict with different content must keep both files.
      final canonDup =
          File(path.join(mediaDir.path, 'catches', 'dup.jpg'));
      await canonDup.parent.create(recursive: true);
      await canonDup.writeAsBytes([9]);
      final legacyDup = File(path.join(mediaDir.path, 'catch', 'dup.jpg'));
      await legacyDup.writeAsBytes([8, 8]);
      // Identical-content duplicate is dropped, not renamed.
      final canonSame =
          File(path.join(mediaDir.path, 'catches', 'same.jpg'));
      await canonSame.writeAsBytes([7]);
      final legacySame = File(path.join(mediaDir.path, 'catch', 'same.jpg'));
      await legacySame.writeAsBytes([7]);

      final renames = await MediaStorageService.migrateLegacyStorage();

      expect(renames['catch/old_photo.jpg'], 'catches/old_photo.jpg');
      expect(renames['lure/lure.jpg'], 'lures/lure.jpg');
      expect(renames['catch/dup.jpg'], 'catches/dup_m1.jpg');
      expect(renames['catch/same.jpg'], 'catches/same.jpg');

      expect(await legacyCatch.exists(), isFalse);
      expect(
          await File(path.join(mediaDir.path, 'catches', 'old_photo.jpg'))
              .exists(),
          isTrue);
      // Distinct content preserved under the _m1 name; identical dropped.
      expect(
          await File(path.join(mediaDir.path, 'catches', 'dup_m1.jpg'))
              .readAsBytes(),
          [8, 8]);
      expect(await canonDup.readAsBytes(), [9]);
      expect(
          await File(path.join(mediaDir.path, 'catches', 'same.jpg'))
              .readAsBytes(),
          [7]);
    });
  });

  group('DatabaseHelper - migrateMediaPaths', () {
    late Directory testDir;
    late Directory mediaDir;
    late String dbPath;

    setUp(() async {
      testDir = Directory.systemTemp.createTempSync('bragmat_dbmig_test_');
      MediaStorageService.setTestDirectory(testDir);
      mediaDir = await MediaStorageService.getMediaDirectory();
      dbPath = path.join(testDir.path, 'bragmat.db');
      DatabaseHelper.setTestDatabasePath(dbPath);
    });

    tearDown(() async {
      await DatabaseHelper.instance.closeDatabase();
      DatabaseHelper.clearTestDatabasePath();
      MediaStorageService.clearTestDirectory();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('rewrites legacy prefixes, rename map and absolute media paths',
        () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('catches', {'fish_type': 'Test'});
      final absUnderMedia =
          path.join(mediaDir.path, 'catches', 'abs.jpg');
      await db.insert('catch_media', {
        'catch_id': 1,
        'file_path': 'catch/legacy.jpg',
        'created_at': 'x',
      });
      await db.insert('catch_media', {
        'catch_id': 1,
        'file_path': absUnderMedia,
        'created_at': 'x',
      });
      await db.insert('catch_media', {
        'catch_id': 1,
        'file_path': '/data/user/0/com.example.bragmat/cache/gone.jpg',
        'created_at': 'x',
      });
      await db.update(
          'catches', {'lure_photo_path': 'lure/l.png', 'image_path': 'trip/t.png'},
          where: 'id = 1');

      final updated = await DatabaseHelper.instance.migrateMediaPaths(
        mediaDir.path,
        {'catch/moved.jpg': 'catches/moved_m1.jpg'},
      );

      final rows =
          await db.query('catch_media', columns: ['file_path']);
      final refs = rows.map((r) => r['file_path'] as String).toList();
      expect(refs, contains('catches/legacy.jpg'));
      expect(refs, contains('catches/abs.jpg'));
      // Foreign absolute paths are left for backup/restore repair.
      expect(
          refs,
          contains(
              '/data/user/0/com.example.bragmat/cache/gone.jpg'));

      final catchRow = await db.query('catches',
          columns: ['lure_photo_path', 'image_path'], where: 'id = 1');
      expect(catchRow.single['lure_photo_path'], 'lures/l.png');
      expect(catchRow.single['image_path'], 'trips/t.png');
      // legacy prefix, abs-under-media, lure + image refs = 4 updates
      expect(updated, 4);
    });
  });

  group('Backup creation - path correctness', () {
    late Directory testDir;
    late Directory mediaDir;
    late Directory outputDir;
    late String dbPath;

    setUp(() async {
      testDir = Directory.systemTemp.createTempSync('bragmat_create_test_');
      MediaStorageService.setTestDirectory(testDir);
      mediaDir = await MediaStorageService.getMediaDirectory();
      outputDir = Directory(path.join(testDir.path, 'out'));
      await outputDir.create(recursive: true);
      dbPath = path.join(testDir.path, 'live.db');
      DatabaseHelper.setTestDatabasePath(dbPath);
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      await DatabaseHelper.instance.closeDatabase();
      DatabaseHelper.clearTestDatabasePath();
      MediaStorageService.clearTestDirectory();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    Future<File> mediaFile(String rel, List<int> bytes) async {
      final f = File(path.joinAll([mediaDir.path, ...rel.split('/')]));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
      return f;
    }

    Future<void> insertCatchMedia(String ref) async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('catch_media',
          {'catch_id': 1, 'file_path': ref, 'created_at': 'x'});
    }

    /// Extracts the snapshot database and media entries from a backup ZIP.
    Future<(Database, Map<String, ArchiveFile>)> extractBackup(
        String zipPath) async {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final entries = {for (final f in archive.files) f.name: f};
      final dbBytes = entries['database.sqlite']!.content as List<int>;
      final dbFile = File(path.join(testDir.path, 'extracted.db'));
      await dbFile.writeAsBytes(dbBytes);
      final db = await openDatabase(dbFile.path);
      return (db, entries);
    }

    Future<List<String>> snapshotMediaRefs(Database db) async {
      final rows = await db.query('catch_media', columns: ['file_path']);
      return rows.map((r) => r['file_path'] as String).toList();
    }

    test('relative references archive and stay unchanged', () async {
      await mediaFile('catches/photo.jpg', [1, 2, 3]);
      await insertCatchMedia('catches/photo.jpg');

      final zipPath =
          await ZipBackupService.createBackup(outputDirectory: outputDir.path);
      final (db, entries) = await extractBackup(zipPath);

      expect(entries.containsKey('media/catches/photo.jpg'), isTrue);
      expect(await snapshotMediaRefs(db), ['catches/photo.jpg']);
      await db.close();
    });

    test('absolute media-dir references are relativized and archived',
        () async {
      final f = await mediaFile('catches/abs.jpg', [4, 5]);
      await insertCatchMedia(f.path);

      final zipPath =
          await ZipBackupService.createBackup(outputDirectory: outputDir.path);
      final (db, entries) = await extractBackup(zipPath);

      expect(entries.containsKey('media/catches/abs.jpg'), isTrue);
      expect(await snapshotMediaRefs(db), ['catches/abs.jpg']);
      await db.close();
    });

    test('absolute picker-cache paths archive under the entity subdir',
        () async {
      // Simulate an image-picker cache file still readable at backup time.
      final cacheDir = Directory(path.join(testDir.path, 'cache'));
      await cacheDir.create(recursive: true);
      final cacheFile = File(path.join(cacheDir.path, 'scaled_pic.jpg'));
      await cacheFile.writeAsBytes([9, 9, 9]);
      await insertCatchMedia(cacheFile.path);

      final zipPath =
          await ZipBackupService.createBackup(outputDirectory: outputDir.path);
      final (db, entries) = await extractBackup(zipPath);

      expect(entries.containsKey('media/catches/scaled_pic.jpg'), isTrue);
      expect(await snapshotMediaRefs(db), ['catches/scaled_pic.jpg']);
      await db.close();
    });

    test('legacy catch/ prefix resolves against canonical storage',
        () async {
      // File was moved to catches/ but the DB still says catch/.
      await mediaFile('catches/legacy.jpg', [6, 6]);
      await insertCatchMedia('catch/legacy.jpg');

      final zipPath =
          await ZipBackupService.createBackup(outputDirectory: outputDir.path);
      final (db, entries) = await extractBackup(zipPath);

      expect(entries.containsKey('media/catches/legacy.jpg'), isTrue);
      expect(await snapshotMediaRefs(db), ['catches/legacy.jpg']);
      await db.close();
    });

    test('unreadable references count as missing and stay untouched',
        () async {
      await insertCatchMedia('/somewhere/definitely/not/here.jpg');
      await insertCatchMedia('catches/not_there.jpg');

      final zipPath =
          await ZipBackupService.createBackup(outputDirectory: outputDir.path);
      final (db, entries) = await extractBackup(zipPath);

      final manifest = BackupManifest.fromMap(
          jsonDecode(utf8.decode(
              entries['manifest.json']!.content as List<int>))
              as Map<String, dynamic>);
      expect(manifest.statistics.missingPhotos, 2);
      expect(await snapshotMediaRefs(db),
          containsAllInOrder(
              ['/somewhere/definitely/not/here.jpg', 'catches/not_there.jpg']));
      await db.close();
    });

    test('basename collisions keep distinct files under _cN names',
        () async {
      // Two different photos with the same basename.
      final inMedia = await mediaFile('catches/dup.jpg', [1, 1, 1]);
      final elsewhere = File(path.join(testDir.path, 'elsewhere', 'dup.jpg'));
      await elsewhere.parent.create(recursive: true);
      await elsewhere.writeAsBytes([2, 2, 2]);
      await insertCatchMedia(inMedia.path); // absolute -> catches/dup.jpg
      await insertCatchMedia(elsewhere.path); // absolute -> catches/dup_c1.jpg

      final zipPath =
          await ZipBackupService.createBackup(outputDirectory: outputDir.path);
      final (db, entries) = await extractBackup(zipPath);

      final archived = entries.keys
          .where((k) => k.startsWith('media/catches/dup'))
          .toList()
        ..sort();
      expect(archived, ['media/catches/dup.jpg', 'media/catches/dup_c1.jpg']);
      expect(entries['media/catches/dup.jpg']!.content, [1, 1, 1]);
      expect(entries['media/catches/dup_c1.jpg']!.content, [2, 2, 2]);

      final refs = await snapshotMediaRefs(db);
      expect(refs.toSet(), {'catches/dup.jpg', 'catches/dup_c1.jpg'});
      await db.close();
    });

    test('byte-identical duplicates share a single archive entry',
        () async {
      await mediaFile('catches/shared.jpg', [3, 3]);
      await insertCatchMedia('catches/shared.jpg');
      await insertCatchMedia('catches/shared.jpg');

      final zipPath =
          await ZipBackupService.createBackup(outputDirectory: outputDir.path);
      final (db, entries) = await extractBackup(zipPath);

      expect(
          entries.keys.where((k) => k.contains('shared.jpg')).length, 1);
      expect(await snapshotMediaRefs(db),
          ['catches/shared.jpg', 'catches/shared.jpg']);
      await db.close();
    });

    test('create-backup/restore round trip restores all media', () async {
      await mediaFile('catches/rt.jpg', [1, 2]);
      await mediaFile('journals/j.jpg', [3, 4]);
      await insertCatchMedia('catches/rt.jpg');
      final db = await DatabaseHelper.instance.database;
      await db.insert('journal_media',
          {'journal_entry_id': 1, 'file_path': 'journals/j.jpg',
           'created_at': 'x'});

      final zipPath =
          await ZipBackupService.createBackup(outputDirectory: outputDir.path);

      // Restore into a fresh database + media dir.
      final restoreDir =
          Directory(path.join(testDir.path, 'restore_media'));
      await restoreDir.create(recursive: true);
      final targetDbPath = path.join(testDir.path, 'restored.db');
      await File(targetDbPath).writeAsBytes(await File(dbPath).readAsBytes());
      await DatabaseHelper.instance.closeDatabase();

      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: restoreDir,
      );

      expect(result.referencedMediaMissing, 0);
      expect(result.ambiguousMediaRefs, 0);
      expect(
          await File(path.join(restoreDir.path, 'catches', 'rt.jpg'))
              .readAsBytes(),
          [1, 2]);
      expect(
          await File(path.join(restoreDir.path, 'journals', 'j.jpg'))
              .readAsBytes(),
          [3, 4]);
    });
  });

  group('Restore - legacy path compatibility', () {
    late Directory testDir;
    late Directory mediaDir;
    late String targetDbPath;
    int stagingCounter = 0;

    setUp(() async {
      testDir = Directory.systemTemp.createTempSync('bragmat_legacy_test_');
      MediaStorageService.setTestDirectory(testDir);
      mediaDir = await MediaStorageService.getMediaDirectory();
      targetDbPath = path.join(testDir.path, 'target.db');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      MediaStorageService.clearTestDirectory();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    Future<String> buildLegacyZip({
      List<String> mediaRefs = const [],
      Map<String, List<int>> mediaFiles = const {},
    }) async {
      stagingCounter++;
      final dbFile = File(
          path.join(testDir.path, 'zip_db_$stagingCounter.db'));
      final db = await openDatabase(dbFile.path, version: 28,
          onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE catches (id INTEGER PRIMARY KEY, fish_type TEXT,'
            ' lure_photo_path TEXT, image_path TEXT)');
        await db.execute(
            'CREATE TABLE fishing_trips (id INTEGER PRIMARY KEY, name TEXT)');
        await db.execute(
            'CREATE TABLE catch_media (id INTEGER PRIMARY KEY,'
            ' catch_id INTEGER, file_path TEXT)');
        await db.execute(
            'CREATE TABLE trip_media (id INTEGER PRIMARY KEY,'
            ' trip_id INTEGER, file_path TEXT)');
        await db.execute(
            'CREATE TABLE journal_media (id INTEGER PRIMARY KEY,'
            ' journal_entry_id INTEGER, file_path TEXT)');
      });
      await db.insert('catches', {'fish_type': 'Barramundi'});
      for (final ref in mediaRefs) {
        await db.insert('catch_media', {'catch_id': 1, 'file_path': ref});
      }
      await db.close();

      final manifest = BackupManifest.create(
        bragmatVersion: '1.0.0+8',
        databaseSchemaVersion: 28,
        platform: 'android',
        contents: BackupContents(
          database: true,
          media: BackupMediaCounts(
              catches: mediaRefs.length,
              trips: 0,
              journals: 0,
              lures: 0),
          settings: false,
        ),
        statistics: BackupStatistics(
            catches: 1, trips: 0,
            photos: mediaRefs.length, missingPhotos: 0),
      );

      final archive = Archive();
      final manifestBytes = utf8.encode(jsonEncode(manifest.toMap()));
      archive.addFile(
          ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('database.sqlite', dbBytes.length, dbBytes));
      for (final entry in mediaFiles.entries) {
        archive.addFile(
            ArchiveFile(entry.key, entry.value.length, entry.value));
      }
      final zipPath = path.join(testDir.path, 'legacy_$stagingCounter.zip');
      await File(zipPath).writeAsBytes(ZipEncoder().encode(archive)!);
      await dbFile.delete();
      return zipPath;
    }

    Future<List<String>> restoredRefs() async {
      final db = await openDatabase(targetDbPath, readOnly: true);
      try {
        final rows = await db.query('catch_media', columns: ['file_path']);
        return rows.map((r) => r['file_path'] as String).toList();
      } finally {
        await db.close();
      }
    }

    test('absolute cache paths resolve by basename into the archive',
        () async {
      final zipPath = await buildLegacyZip(
        mediaRefs: [
          '/data/user/0/com.example.bragmat/cache/scaled_pic.jpg',
          'C:\\cache\\scaled_other.jpg',
        ],
        mediaFiles: {
          'media/catches/scaled_pic.jpg': [1],
          'media/catches/scaled_other.jpg': [2],
        },
      );

      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      expect(result.referencedMediaMissing, 0);
      expect(result.mediaPathsRepaired, 2);
      expect(result.ambiguousMediaRefs, 0);
      final refs = await restoredRefs();
      expect(refs,
          containsAll(['catches/scaled_pic.jpg', 'catches/scaled_other.jpg']));
    });

    test('legacy catch/ prefix resolves to catches/', () async {
      final zipPath = await buildLegacyZip(
        mediaRefs: ['catch/old_photo.jpg'],
        mediaFiles: {'media/catches/old_photo.jpg': [7, 7]},
      );

      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      expect(result.referencedMediaMissing, 0);
      expect(result.mediaPathsRepaired, 1);
      expect(await restoredRefs(), ['catches/old_photo.jpg']);
      expect(
          await File(path.join(mediaDir.path, 'catches', 'old_photo.jpg'))
              .readAsBytes(),
          [7, 7]);
    });

    test('ambiguous basenames are reported, never silently attached',
        () async {
      final zipPath = await buildLegacyZip(
        mediaRefs: ['/data/cache/shared.jpg'],
        mediaFiles: {
          'media/catches/shared.jpg': [1],
          'media/journals/shared.jpg': [2],
        },
      );

      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      expect(result.ambiguousMediaRefs, 1);
      expect(result.referencedMediaMissing, 1);
      expect(result.mediaPathsRepaired, 0);
      // The stale reference is left untouched — both files are still
      // restored to disk so nothing is lost.
      expect(await restoredRefs(), ['/data/cache/shared.jpg']);
      expect(
          await File(path.join(mediaDir.path, 'catches', 'shared.jpg'))
              .exists(),
          isTrue);
      expect(
          await File(path.join(mediaDir.path, 'journals', 'shared.jpg'))
              .exists(),
          isTrue);
    });

    test('unresolvable references report missing without repair', () async {
      final zipPath = await buildLegacyZip(
        mediaRefs: ['/data/cache/not_in_archive.jpg'],
        mediaFiles: {'media/catches/other.jpg': [3]},
      );

      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      expect(result.referencedMediaMissing, 1);
      expect(result.mediaPathsRepaired, 0);
      expect(await restoredRefs(), ['/data/cache/not_in_archive.jpg']);
    });
  });

  group('BackupFileService - picker cancellation', () {
    tearDown(() {
      BackupFileService.debugPickerOverride = null;
      BackupFileService.debugExporterOverride = null;
    });

    test('pickBackupZip returns null when the user cancels', () async {
      BackupFileService.debugPickerOverride = () async => null;
      expect(await BackupFileService.pickBackupZip(), isNull);
    });

    test('pickBackupZip returns the picked local path', () async {
      BackupFileService.debugPickerOverride =
          () async => '/tmp/picked.zip';
      expect(await BackupFileService.pickBackupZip(), '/tmp/picked.zip');
    });

    test('exportBackup reports cancellation', () async {
      String? seenPath;
      String? seenName;
      BackupFileService.debugExporterOverride = (p, n) async {
        seenPath = p;
        seenName = n;
        return false;
      };
      expect(await BackupFileService.exportBackup('/a/b.zip', 'b.zip'),
          isFalse);
      expect(seenPath, '/a/b.zip');
      expect(seenName, 'b.zip');
    });
  });
}
