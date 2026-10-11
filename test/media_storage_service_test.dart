import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:bragmat/services/media_storage_service.dart';

void main() {
  group('MediaStorageService', () {
    late Directory testDir;
    late File testFile;

    setUp(() async {
      // Create a temporary directory for testing
      testDir = await Directory.systemTemp.createTemp('media_storage_test_');
      
      // Inject test directory into MediaStorageService
      MediaStorageService.setTestDirectory(testDir);
      
      // Create a test image file
      testFile = File(path.join(testDir.path, 'test_image.jpg'));
      await testFile.writeAsBytes(List<int>.generate(1024, (i) => i % 256));
    });

    tearDown(() async {
      // Clear test directory from MediaStorageService
      MediaStorageService.clearTestDirectory();
      
      // Clean up test directory
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('getMediaDirectory creates directory structure', () async {
      final mediaDir = await MediaStorageService.getMediaDirectory();
      expect(mediaDir, isNotNull);
      expect(await mediaDir.exists(), isTrue);
      expect(mediaDir.path.contains('media'), isTrue);
    });

    test('generateFilename creates collision-resistant names', () {
      final filename1 = MediaStorageService.generateFilename('catch', 123, 'primary', 'jpg');
      final filename2 = MediaStorageService.generateFilename('catch', 123, 'primary', 'jpg');
      
      // Filenames should be different due to random suffix
      expect(filename1, isNot(equals(filename2)));
      
      // Filenames should follow the pattern
      expect(filename1, matches(r'^catch_123_primary_[a-zA-Z0-9_]+\.jpg$'));
      expect(filename2, matches(r'^catch_123_primary_[a-zA-Z0-9_]+\.jpg$'));
    });

    test('generateFilename handles different entity types', () {
      final catchFilename = MediaStorageService.generateFilename('catch', 123, 'primary', 'jpg');
      final tripFilename = MediaStorageService.generateFilename('trip', 456, 'cover', 'png');
      final journalFilename = MediaStorageService.generateFilename('journal', 789, 'other', 'jpg');
      
      expect(catchFilename, startsWith('catch_123_'));
      expect(tripFilename, startsWith('trip_456_'));
      expect(journalFilename, startsWith('journal_789_'));
    });

    test('copyPhotoToStorage returns null for non-existent source file', () async {
      final result = await MediaStorageService.copyPhotoToStorage(
        '/non/existent/path.jpg',
        'catch',
        123,
        'primary',
      );
      
      expect(result, isNull);
    });

    test('copyPhotoToStorage copies file successfully', () async {
      final result = await MediaStorageService.copyPhotoToStorage(
        testFile.path,
        'catch',
        123,
        'primary',
      );
      
      expect(result, isNotNull);
      expect(await File(result!).exists(), isTrue);
      
      // Verify file size matches
      final originalSize = await testFile.length();
      final copiedSize = await File(result).length();
      expect(copiedSize, equals(originalSize));
    });

    test('copyPhotoToStorage preserves file extension', () async {
      final result = await MediaStorageService.copyPhotoToStorage(
        testFile.path,
        'catch',
        123,
        'primary',
      );
      
      expect(result, isNotNull);
      expect(result, endsWith('.jpg'));
    });

    test('copyPhotoToStorage preserves EXIF data (byte-for-byte copy)', () async {
      // Create a file with specific byte pattern
      final testBytes = List<int>.generate(2048, (i) => (i * 17) % 256);
      await testFile.writeAsBytes(testBytes);
      
      final result = await MediaStorageService.copyPhotoToStorage(
        testFile.path,
        'catch',
        123,
        'primary',
      );
      
      expect(result, isNotNull);
      
      // Read copied file and verify bytes match
      final copiedFile = File(result!);
      final copiedBytes = await copiedFile.readAsBytes();
      
      expect(copiedBytes.length, equals(testBytes.length));
      expect(copiedBytes, equals(testBytes));
    });

    test('copyPhotoToStorage handles files without extension', () async {
      // Create a file without extension
      final noExtFile = File(path.join(testDir.path, 'test_image'));
      await noExtFile.writeAsBytes(List<int>.generate(512, (i) => i % 256));
      
      final result = await MediaStorageService.copyPhotoToStorage(
        noExtFile.path,
        'catch',
        123,
        'primary',
      );
      
      expect(result, isNotNull);
      // Should default to .jpg extension
      expect(result, endsWith('.jpg'));
      expect(await File(result!).exists(), isTrue);
    });

    test('fileExists returns true for existing file', () async {
      expect(await testFile.exists(), isTrue);
      final exists = await MediaStorageService.fileExists(testFile.path);
      expect(exists, isTrue);
    });

    test('fileExists returns false for non-existent file', () async {
      final nonExistent = File(path.join(testDir.path, 'non_existent.jpg'));
      expect(await nonExistent.exists(), isFalse);
      final exists = await MediaStorageService.fileExists(nonExistent.path);
      expect(exists, isFalse);
    });

    test('resolvePath handles absolute paths', () async {
      final absolutePath = testFile.path;
      final resolved = await MediaStorageService.resolvePath(absolutePath);
      expect(resolved, equals(absolutePath));
    });

    test('resolvePath handles relative paths', () async {
      // First copy a file to get a relative path
      final copiedPath = await MediaStorageService.copyPhotoToStorage(
        testFile.path,
        'catch',
        123,
        'primary',
      );
      
      expect(copiedPath, isNotNull);
      
      // Convert to relative path
      final relativePath = await MediaStorageService.toRelativePath(copiedPath!);
      expect(relativePath, isNot(equals(copiedPath)));
      
      // Resolve back to absolute
      final resolved = await MediaStorageService.resolvePath(relativePath);
      expect(resolved, equals(copiedPath));
    });

    test('toRelativePath converts paths within media directory', () async {
      final mediaDir = await MediaStorageService.getMediaDirectory();
      final absolutePath = path.join(mediaDir.path, 'catch', 'test.jpg');
      
      final relativePath = await MediaStorageService.toRelativePath(absolutePath);
      
      // If the path is within media directory, it should be relative
      expect(relativePath, isNot(equals(absolutePath)));
      expect(relativePath, contains('catch'));
    });

    test('deletePhoto removes file successfully', () async {
      // First copy a file
      final copiedPath = await MediaStorageService.copyPhotoToStorage(
        testFile.path,
        'catch',
        123,
        'primary',
      );
      
      expect(copiedPath, isNotNull);
      expect(await File(copiedPath!).exists(), isTrue);
      
      // Delete the file
      final deleted = await MediaStorageService.deletePhoto(copiedPath);
      expect(deleted, isTrue);
      expect(await File(copiedPath).exists(), isFalse);
    });

    test('deletePhoto returns false for non-existent file', () async {
      final deleted = await MediaStorageService.deletePhoto('/non/existent/path.jpg');
      expect(deleted, isFalse);
    });

    test('getFileSize returns correct size', () async {
      final size = await MediaStorageService.getFileSize(testFile.path);
      expect(size, equals(1024));
    });

    test('getFileSize returns 0 for non-existent file', () async {
      final size = await MediaStorageService.getFileSize('/non/existent/path.jpg');
      expect(size, equals(0));
    });

    test('filename collision resistance with multiple copies', () async {
      // Copy the same file multiple times
      final paths = <String>[];
      for (int i = 0; i < 5; i++) {
        final result = await MediaStorageService.copyPhotoToStorage(
          testFile.path,
          'catch',
          123,
          'primary',
        );
        expect(result, isNotNull);
        paths.add(result!);
      }
      
      // All paths should be different
      final uniquePaths = paths.toSet();
      expect(uniquePaths.length, equals(paths.length));
      
      // All files should exist
      for (final path in paths) {
        expect(await File(path).exists(), isTrue);
      }
    });
  });
}
