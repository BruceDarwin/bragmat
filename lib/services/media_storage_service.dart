import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Service for managing persistent media storage for photographs.
/// 
/// This service handles copying photographs from temporary picker locations
/// to persistent application-controlled storage using getApplicationSupportDirectory().
/// Files are organized by entity type (catch, trip, journal, lure) with
/// collision-resistant filenames.
class MediaStorageService {
  static const String _mediaDirName = 'bragmat';
  static const String _photosDirName = 'media';
  
  static Directory? _mediaDirectory;
  static Directory? _testDirectory; // For testing only
  
  /// Set a custom directory for testing purposes.
  /// This allows tests to inject a temporary directory instead of using
  /// the actual application support directory.
  static void setTestDirectory(Directory dir) {
    _testDirectory = dir;
    _mediaDirectory = null; // Reset cached directory
  }
  
  /// Clear the test directory (for testing cleanup).
  static void clearTestDirectory() {
    _testDirectory = null;
    _mediaDirectory = null;
  }
  
  /// Get the application-specific media directory.
  /// Creates the directory structure if it doesn't exist.
  /// Uses test directory if set, otherwise uses getApplicationSupportDirectory().
  static Future<Directory> getMediaDirectory() async {
    if (_mediaDirectory != null) {
      return _mediaDirectory!;
    }
    
    Directory baseDir;
    if (_testDirectory != null) {
      baseDir = _testDirectory!;
    } else {
      baseDir = await getApplicationSupportDirectory();
    }
    
    final mediaDir = Directory(path.join(baseDir.path, _mediaDirName, _photosDirName));
    
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    
    _mediaDirectory = mediaDir;
    return mediaDir;
  }
  
  /// Get the directory for a specific entity type.
  static Future<Directory> getEntityDirectory(String entityType) async {
    final mediaDir = await getMediaDirectory();
    final entityDir = Directory(path.join(mediaDir.path, entityType));
    
    if (!await entityDir.exists()) {
      await entityDir.create(recursive: true);
    }
    
    return entityDir;
  }
  
  /// Generate a collision-resistant filename.
  /// 
  /// Format: {entityType}_{entityId}_{role}_{random}.{ext}
  /// Example: catch_123_primary_abc123.jpg
  static String generateFilename(
    String entityType,
    int entityId,
    String role,
    String extension,
  ) {
    final random = Random.secure();
    final bytes = List<int>.generate(6, (_) => random.nextInt(256));
    final suffix = base64Url.encode(bytes).replaceAll('/', '_').replaceAll('-', '_');
    final filename = '${entityType}_${entityId}_${role}_$suffix.$extension';
    return filename;
  }
  
  /// Copy a photo file to persistent storage.
  /// 
  /// Returns the new file path if successful, null if failed.
  /// Preserves original file bytes and EXIF metadata.
  /// Updates database only after successful copy.
  static Future<String?> copyPhotoToStorage(
    String sourcePath,
    String entityType,
    int entityId,
    String role,
  ) async {
    try {
      // Verify source file exists
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return null;
      }
      
      // Get entity directory
      final entityDir = await getEntityDirectory(entityType);
      
      // Get file extension
      var extension = path.extension(sourcePath).replaceFirst('.', '');
      if (extension.isEmpty) {
        // Default to jpg if no extension
        extension = 'jpg';
      }
      
      // Generate unique filename
      String filename;
      File targetFile;
      int attempts = 0;
      const maxAttempts = 10;
      
      do {
        filename = generateFilename(entityType, entityId, role, extension);
        targetFile = File(path.join(entityDir.path, filename));
        attempts++;
      } while (await targetFile.exists() && attempts < maxAttempts);
      
      // If still colliding after max attempts, add timestamp
      if (await targetFile.exists()) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        filename = '${entityType}_${entityId}_${role}_$timestamp.$extension';
        targetFile = File(path.join(entityDir.path, filename));
      }
      
      // Copy file byte-for-byte to preserve EXIF
      await sourceFile.copy(targetFile.path);
      
      // Verify copy was successful
      if (!await targetFile.exists()) {
        return null;
      }
      
      // Verify file size matches
      final sourceSize = await sourceFile.length();
      final targetSize = await targetFile.length();
      if (sourceSize != targetSize) {
        // Copy incomplete, delete target
        await targetFile.delete();
        return null;
      }
      
      return targetFile.path;
    } catch (e) {
      // Log error for debugging (throttled in release builds)
      debugPrint('MediaStorageService: Error copying photo');
      return null;
    }
  }
  
  /// Check if a file exists at the given path.
  /// 
  /// Supports both absolute paths and relative paths.
  /// Relative paths are resolved against the media directory.
  static Future<bool> fileExists(String filePath) async {
    try {
      // Check if path is absolute or relative
      if (path.isAbsolute(filePath)) {
        return File(filePath).exists();
      } else {
        // Relative path - resolve against media directory
        final mediaDir = await getMediaDirectory();
        final fullPath = path.join(mediaDir.path, filePath);
        return File(fullPath).exists();
      }
    } catch (e) {
      return false;
    }
  }
  
  /// Get the full path for a relative path.
  /// 
  /// If the path is absolute, returns it as-is.
  /// If the path is relative, resolves it against the media directory.
  static Future<String> resolvePath(String filePath) async {
    if (path.isAbsolute(filePath)) {
      return filePath;
    }
    
    final mediaDir = await getMediaDirectory();
    return path.join(mediaDir.path, filePath);
  }
  
  /// Convert an absolute path to a relative path if it's within the media directory.
  /// 
  /// Returns the original path if it's not within the media directory.
  static Future<String> toRelativePath(String absolutePath) async {
    try {
      final mediaDir = await getMediaDirectory();
      final mediaDirPath = mediaDir.path;
      
      if (absolutePath.startsWith(mediaDirPath)) {
        return absolutePath.substring(mediaDirPath.length + 1);
      }
      
      return absolutePath;
    } catch (e) {
      return absolutePath;
    }
  }
  
  /// Delete a photo file from storage.
  /// 
  /// Returns true if successful, false otherwise.
  /// Does not delete database records.
  static Future<bool> deletePhoto(String filePath) async {
    try {
      final fullPath = await resolvePath(filePath);
      final file = File(fullPath);
      
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('MediaStorageService: Error deleting photo');
      return false;
    }
  }
  
  /// Get the size of a photo file in bytes.
  /// 
  /// Returns 0 if file doesn't exist or on error.
  static Future<int> getFileSize(String filePath) async {
    try {
      final fullPath = await resolvePath(filePath);
      final file = File(fullPath);
      
      if (await file.exists()) {
        return await file.length();
      }
      
      return 0;
    } catch (e) {
      return 0;
    }
  }
  
  /// Clear the media directory (for testing purposes only).
  /// 
  /// WARNING: This deletes all stored photos.
  /// Use with extreme caution.
  static Future<void> clearMediaDirectory() async {
    try {
      final mediaDir = await getMediaDirectory();
      if (await mediaDir.exists()) {
        await mediaDir.delete(recursive: true);
        _mediaDirectory = null;
      }
    } catch (e) {
      debugPrint('MediaStorageService: Error clearing media directory');
    }
  }
}
