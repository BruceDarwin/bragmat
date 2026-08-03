import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import 'package:path/path.dart' as path;
import '../services/photo_metadata_diagnostic.dart';

/// Temporary Stage 4A diagnostic utility for photo metadata investigation.
/// 
/// This is a developer-only tool to inspect EXIF metadata from photos
/// using the same Android photo-selection workflow as the production app.
/// 
/// NOT FOR PRODUCTION USE - Remove or disable before final release.
class PhotoMetadataDiagnosticScreen extends StatefulWidget {
  const PhotoMetadataDiagnosticScreen({super.key});

  @override
  State<PhotoMetadataDiagnosticScreen> createState() => _PhotoMetadataDiagnosticScreenState();
}

class _PhotoMetadataDiagnosticScreenState extends State<PhotoMetadataDiagnosticScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _labelController = TextEditingController();
  
  String? _currentImagePath;
  String? _currentSource;
  Map<String, dynamic>? _currentExifData;
  String? _diagnosticReport;
  
  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      
      if (pickedFile != null) {
        await _processPhoto(pickedFile.path, 'Camera');
      }
    } catch (e) {
      _showError('Error taking photo: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      
      if (pickedFile != null) {
        await _processPhoto(pickedFile.path, 'Gallery');
      }
    } catch (e) {
      _showError('Error picking photo: $e');
    }
  }

  Future<void> _retrieveLostData() async {
    try {
      final lostData = await _picker.retrieveLostData();
      
      if (lostData == null || lostData.isEmpty) {
        _showError('No lost data found');
        return;
      }
      
      if (lostData.file != null) {
        await _processPhoto(lostData.file!.path, 'Lost Data');
      } else if (lostData.files != null && lostData.files!.isNotEmpty) {
        await _processPhoto(lostData.files!.first.path, 'Lost Data');
      }
    } catch (e) {
      _showError('Error retrieving lost data: $e');
    }
  }

  Future<void> _processPhoto(String imagePath, String source) async {
    try {
      // Read EXIF data
      final exifData = await PhotoMetadataDiagnostic.readAllExifTags(imagePath);
      
      // Get file info
      final file = File(imagePath);
      final fileSize = await file.length();
      final isReadable = file.existsSync();
      
      setState(() {
        _currentImagePath = imagePath;
        _currentSource = source;
        _currentExifData = exifData;
        _diagnosticReport = null;
      });
      
      // Generate diagnostic report
      _generateReport(fileSize, isReadable);
    } catch (e) {
      _showError('Error processing photo: $e');
    }
  }

  void _generateReport(int fileSize, bool isReadable) {
    if (_currentImagePath == null || _currentExifData == null) return;
    
    final buffer = StringBuffer();
    final label = _labelController.text.trim().isEmpty ? 'Unlabeled' : _labelController.text.trim();
    
    buffer.writeln('=== Photo Metadata Diagnostic Report ===');
    buffer.writeln('Test Label: $label');
    buffer.writeln();
    
    // File Information
    buffer.writeln('--- File Information ---');
    buffer.writeln('Format: ${PhotoMetadataDiagnostic.detectImageFormat(_currentImagePath!)}');
    buffer.writeln('Source: $_currentSource');
    buffer.writeln('File Size: ${_formatFileSize(fileSize)}');
    buffer.writeln('Readable: ${isReadable ? "Yes" : "No"}');
    buffer.writeln();
    
    // Date and Time
    buffer.writeln('--- Date and Time ---');
    final dateTimeOriginal = _currentExifData!['DateTimeOriginal'];
    final dateTimeDigitized = _currentExifData!['DateTimeDigitized'];
    final dateTime = _currentExifData!['DateTime'];
    final offsetTimeOriginal = _currentExifData!['OffsetTimeOriginal'];
    final offsetTimeDigitized = _currentExifData!['OffsetTimeDigitized'];
    final offsetTime = _currentExifData!['OffsetTime'];
    
    buffer.writeln('DateTimeOriginal: ${dateTimeOriginal ?? "Not present"}');
    buffer.writeln('DateTimeDigitized: ${dateTimeDigitized ?? "Not present"}');
    buffer.writeln('DateTime: ${dateTime ?? "Not present"}');
    buffer.writeln('OffsetTimeOriginal: ${offsetTimeOriginal ?? "Not present"}');
    buffer.writeln('OffsetTimeDigitized: ${offsetTimeDigitized ?? "Not present"}');
    buffer.writeln('OffsetTime: ${offsetTime ?? "Not present"}');
    
    // Determine selected timestamp by priority
    String? selectedTimestamp;
    String selectedSource;
    if (dateTimeOriginal != null) {
      selectedTimestamp = dateTimeOriginal.toString();
      selectedSource = 'DateTimeOriginal';
    } else if (dateTimeDigitized != null) {
      selectedTimestamp = dateTimeDigitized.toString();
      selectedSource = 'DateTimeDigitized';
    } else if (dateTime != null) {
      selectedTimestamp = dateTime.toString();
      selectedSource = 'DateTime';
    } else {
      selectedTimestamp = null;
      selectedSource = 'None';
    }
    
    buffer.writeln('Selected Timestamp: ${selectedTimestamp ?? "None"}');
    buffer.writeln('Selected Source: $selectedSource');
    
    // Timezone status
    final hasTimezone = offsetTimeOriginal != null || offsetTimeDigitized != null || offsetTime != null;
    buffer.writeln('Timezone Present: ${hasTimezone ? "Yes" : "No"}');
    
    if (selectedTimestamp != null) {
      buffer.writeln('Parsed Date/Time: $selectedTimestamp');
      buffer.writeln('Confidence: EXIF');
    }
    
    buffer.writeln();
    
    // Location
    buffer.writeln('--- Location ---');
    final gpsLat = _currentExifData!['GPSLatitude'];
    final gpsLatRef = _currentExifData!['GPSLatitudeRef'];
    final gpsLon = _currentExifData!['GPSLongitude'];
    final gpsLonRef = _currentExifData!['GPSLongitudeRef'];
    
    buffer.writeln('GPSLatitude: ${gpsLat ?? "Not present"}');
    buffer.writeln('GPSLatitudeRef: ${gpsLatRef ?? "Not present"}');
    buffer.writeln('GPSLongitude: ${gpsLon ?? "Not present"}');
    buffer.writeln('GPSLongitudeRef: ${gpsLonRef ?? "Not present"}');
    
    // Parse GPS if available
    if (gpsLat != null && gpsLatRef != null && gpsLon != null && gpsLonRef != null) {
      try {
        final lat = _convertToDecimalDegrees(gpsLat, gpsLatRef);
        final lon = _convertToDecimalDegrees(gpsLon, gpsLonRef);
        buffer.writeln('Parsed Latitude: ${lat.toStringAsFixed(6)}');
        buffer.writeln('Parsed Longitude: ${lon.toStringAsFixed(6)}');
        buffer.writeln('Validation Status: Valid');
      } catch (e) {
        buffer.writeln('Parsed Latitude: Error - $e');
        buffer.writeln('Parsed Longitude: Error - $e');
        buffer.writeln('Validation Status: Malformed');
      }
    } else {
      buffer.writeln('Parsed Latitude: Not available');
      buffer.writeln('Parsed Longitude: Not available');
      buffer.writeln('Validation Status: ${gpsLat != null || gpsLon != null ? "Incomplete" : "Absent"}');
    }
    
    buffer.writeln();
    buffer.writeln('=== End of Report ===');
    
    setState(() {
      _diagnosticReport = buffer.toString();
    });
  }

  double _convertToDecimalDegrees(dynamic value, dynamic ref) {
    if (value is! List || value.length != 3) return 0.0;
    
    final degrees = value[0] is num ? value[0].toDouble() : 0.0;
    final minutes = value[1] is num ? value[1].toDouble() : 0.0;
    final seconds = value[2] is num ? value[2].toDouble() : 0.0;
    
    final decimal = degrees + (minutes / 60) + (seconds / 3600);
    
    if (ref == 'S' || ref == 'W') {
      return -decimal;
    }
    return decimal;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _copyReport() async {
    if (_diagnosticReport == null) return;
    
    await Clipboard.setData(ClipboardData(text: _diagnosticReport!));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Diagnostic report copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Metadata Diagnostic'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.content_copy),
            onPressed: _diagnosticReport != null ? _copyReport : null,
            tooltip: 'Copy Report',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Warning banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Development tool for Stage 4A investigation only. '
                      'Do not use in production.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Test label
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Test Label',
                hintText: 'e.g., Moto camera — location enabled',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // Photo selection buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _retrieveLostData,
              icon: const Icon(Icons.restore),
              label: const Text('Retrieve Lost Data'),
            ),
            const SizedBox(height: 24),
            
            // Diagnostic results
            if (_currentExifData != null) ...[
              const Divider(),
              const SizedBox(height: 16),
              _buildDiagnosticDisplay(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticDisplay() {
    if (_currentExifData == null) return const SizedBox();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File Information
        _buildSection('File Information', [
          _buildRow('Format', PhotoMetadataDiagnostic.detectImageFormat(_currentImagePath!)),
          _buildRow('Source', _currentSource ?? 'Unknown'),
          _buildRow('File Size', _formatFileSize(File(_currentImagePath!).lengthSync())),
          _buildRow('Readable', File(_currentImagePath!).existsSync() ? 'Yes' : 'No'),
        ]),
        
        const SizedBox(height: 16),
        
        // Date and Time
        _buildSection('Date and Time', [
          _buildRow('DateTimeOriginal', _currentExifData!['DateTimeOriginal']?.toString() ?? 'Not present'),
          _buildRow('DateTimeDigitized', _currentExifData!['DateTimeDigitized']?.toString() ?? 'Not present'),
          _buildRow('DateTime', _currentExifData!['DateTime']?.toString() ?? 'Not present'),
          _buildRow('OffsetTimeOriginal', _currentExifData!['OffsetTimeOriginal']?.toString() ?? 'Not present'),
          _buildRow('OffsetTimeDigitized', _currentExifData!['OffsetTimeDigitized']?.toString() ?? 'Not present'),
          _buildRow('OffsetTime', _currentExifData!['OffsetTime']?.toString() ?? 'Not present'),
        ]),
        
        const SizedBox(height: 16),
        
        // Location
        _buildSection('Location', [
          _buildRow('GPSLatitude', _currentExifData!['GPSLatitude']?.toString() ?? 'Not present'),
          _buildRow('GPSLatitudeRef', _currentExifData!['GPSLatitudeRef']?.toString() ?? 'Not present'),
          _buildRow('GPSLongitude', _currentExifData!['GPSLongitude']?.toString() ?? 'Not present'),
          _buildRow('GPSLongitudeRef', _currentExifData!['GPSLongitudeRef']?.toString() ?? 'Not present'),
        ]),
        
        const SizedBox(height: 16),
        
        // Copy report button
        ElevatedButton.icon(
          onPressed: _copyReport,
          icon: const Icon(Icons.content_copy),
          label: const Text('Copy Diagnostic Report'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
