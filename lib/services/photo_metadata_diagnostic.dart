import 'dart:io';
import 'package:exif/exif.dart';

/// Temporary diagnostic tool for Stage 4A investigation.
/// 
/// Reads and displays all EXIF tags from a photo file to understand
/// what metadata is actually available in real photos from Moto G15.
/// 
/// This is a temporary tool for investigation only and should be removed
/// or disabled before the final production build.
class PhotoMetadataDiagnostic {
  /// Read all EXIF tags from a photo file and return as a map.
  static Future<Map<String, dynamic>> readAllExifTags(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final data = await readExifFromBytes(bytes);
      
      return data;
    } catch (e) {
      print('EXIF Diagnostic: Error reading EXIF data: $e');
      return {};
    }
  }

  /// Format EXIF data for display (for investigation purposes).
  static String formatExifData(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return 'No EXIF data found';
    }

    final buffer = StringBuffer();
    buffer.writeln('EXIF Data Summary:');
    buffer.writeln('==================');
    buffer.writeln('Total tags: ${data.length}');
    buffer.writeln();

    // Group by category
    final gpsTags = <String, dynamic>{};
    final dateTimeTags = <String, dynamic>{};
    final imageTags = <String, dynamic>{};
    final otherTags = <String, dynamic>{};

    data.forEach((key, value) {
      final keyUpper = key.toUpperCase();
      if (keyUpper.contains('GPS')) {
        gpsTags[key] = value;
      } else if (keyUpper.contains('DATE') || keyUpper.contains('TIME') || keyUpper.contains('OFFSET')) {
        dateTimeTags[key] = value;
      } else if (keyUpper.contains('IMAGE') || keyUpper.contains('PIXEL') || keyUpper.contains('ORIENTATION')) {
        imageTags[key] = value;
      } else {
        otherTags[key] = value;
      }
    });

    // GPS Tags
    if (gpsTags.isNotEmpty) {
      buffer.writeln('GPS Tags:');
      buffer.writeln('---------');
      gpsTags.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
      buffer.writeln();
    }

    // Date/Time Tags
    if (dateTimeTags.isNotEmpty) {
      buffer.writeln('Date/Time Tags:');
      buffer.writeln('--------------');
      dateTimeTags.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
      buffer.writeln();
    }

    // Image Tags
    if (imageTags.isNotEmpty) {
      buffer.writeln('Image Tags:');
      buffer.writeln('-----------');
      imageTags.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
      buffer.writeln();
    }

    // Other Tags
    if (otherTags.isNotEmpty) {
      buffer.writeln('Other Tags:');
      buffer.writeln('----------');
      otherTags.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Extract specific tags of interest for Stage 4A investigation.
  static Map<String, dynamic> extractTagsOfInterest(Map<String, dynamic> data) {
    final result = <String, dynamic>{};

    // GPS tags
    if (data.containsKey('GPSLatitude')) result['GPSLatitude'] = data['GPSLatitude'];
    if (data.containsKey('GPSLatitudeRef')) result['GPSLatitudeRef'] = data['GPSLatitudeRef'];
    if (data.containsKey('GPSLongitude')) result['GPSLongitude'] = data['GPSLongitude'];
    if (data.containsKey('GPSLongitudeRef')) result['GPSLongitudeRef'] = data['GPSLongitudeRef'];
    if (data.containsKey('GPSAltitude')) result['GPSAltitude'] = data['GPSAltitude'];
    if (data.containsKey('GPSDateStamp')) result['GPSDateStamp'] = data['GPSDateStamp'];
    if (data.containsKey('GPSTimeStamp')) result['GPSTimeStamp'] = data['GPSTimeStamp'];

    // Date/Time tags
    if (data.containsKey('DateTimeOriginal')) result['DateTimeOriginal'] = data['DateTimeOriginal'];
    if (data.containsKey('DateTimeDigitized')) result['DateTimeDigitized'] = data['DateTimeDigitized'];
    if (data.containsKey('DateTime')) result['DateTime'] = data['DateTime'];
    if (data.containsKey('OffsetTime')) result['OffsetTime'] = data['OffsetTime'];
    if (data.containsKey('OffsetTimeOriginal')) result['OffsetTimeOriginal'] = data['OffsetTimeOriginal'];
    if (data.containsKey('OffsetTimeDigitized')) result['OffsetTimeDigitized'] = data['OffsetTimeDigitized'];

    // Image tags
    if (data.containsKey('Orientation')) result['Orientation'] = data['Orientation'];
    if (data.containsKey('ImageWidth')) result['ImageWidth'] = data['ImageWidth'];
    if (data.containsKey('ImageHeight')) result['ImageHeight'] = data['ImageHeight'];

    return result;
  }

  /// Detect image format from file extension.
  static String detectImageFormat(String imagePath) {
    final extension = imagePath.toLowerCase().split('.').last;
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'JPEG';
      case 'heic':
      case 'heif':
        return 'HEIC/HEIF';
      case 'png':
        return 'PNG';
      case 'webp':
        return 'WebP';
      default:
        return 'Unknown ($extension)';
    }
  }
}
