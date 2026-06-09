import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../database/database_helper.dart';
import '../models/catch.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _fishTypes = [];
  List<Catch> _catches = [];

  @override
  void initState() {
    super.initState();
    _loadFishTypes();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    final catches = await DatabaseHelper.instance.getCatches();
    final fishTypes = await DatabaseHelper.instance.getFishTypes();
    setState(() {
      _catches = catches;
      _fishTypes = fishTypes;
    });
  }

  Future<void> _loadFishTypes() async {
    final types = await DatabaseHelper.instance.getFishTypes();
    setState(() {
      _fishTypes = types;
    });
  }

  Future<void> _showAddFishTypeDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Fish Type'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Fish Type Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      // Check for duplicates (case-insensitive, ignoring extra spaces)
      final normalized = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final exists = _fishTypes.any((type) =>
        type.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == normalized);

      if (!exists) {
        final result = await DatabaseHelper.instance.insertFishType(name);
        if (result != -1) {
          _loadFishTypes();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fish type added')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fish type already exists')),
          );
        }
      }
    }
  }

  Future<void> _showEditFishTypeDialog(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Fish Type'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Fish Type Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();
      if (newName != oldName) {
        // Check for duplicates (case-insensitive, ignoring extra spaces)
        final normalized = newName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final exists = _fishTypes.any((type) =>
          type.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == normalized && type != oldName);

        if (!exists) {
          await DatabaseHelper.instance.updateFishType(oldName, newName);
          _loadFishTypes();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fish type updated')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fish type already exists')),
            );
          }
        }
      }
    }
  }

  Future<void> _showDeleteFishTypeDialog(String name) async {
    final isUsed = await DatabaseHelper.instance.isFishTypeUsed(name);
    if (isUsed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: fish type is in use')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Fish Type'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.deleteFishType(name);
      _loadFishTypes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fish type deleted')),
        );
      }
    }
  }

  Future<void> _exportCatchesToCSV() async {
    debugPrint('=== Export Catches to CSV started ===');
    
    try {
      final catches = await DatabaseHelper.instance.getCatches();
      debugPrint('Retrieved ${catches.length} catches from database');
      
      if (catches.isEmpty) {
        debugPrint('No catches to export');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No catches to export')),
          );
        }
        return;
      }

      // Get downloads directory
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        debugPrint('ERROR: Could not access downloads directory');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access downloads directory')),
          );
        }
        return;
      }
      debugPrint('Downloads directory: ${directory.path}');

      // Create CSV content
      final csvContent = StringBuffer();
      // Header row
      csvContent.writeln('Fish Type,Size (cm),Date Caught,Location,Notes,Photo Path,Photo Date/Time,Latitude,Longitude');
      
      // Data rows
      for (final catch_ in catches) {
        final fishType = _escapeCSV(catch_.fishType);
        final size = catch_.lengthCm.toString();
        final dateCaught = catch_.dateCaught?.toString().split(' ')[0] ?? catch_.createdAt.toString().split(' ')[0];
        final location = _escapeCSV(catch_.location ?? '');
        final notes = _escapeCSV(catch_.notes ?? '');
        final photoPath = _escapeCSV(catch_.imagePath ?? '');
        final photoDateTime = catch_.photoDateTime?.toString() ?? '';
        final latitude = catch_.latitude?.toString() ?? '';
        final longitude = catch_.longitude?.toString() ?? '';
        
        csvContent.writeln('$fishType,$size,$dateCaught,$location,$notes,$photoPath,$photoDateTime,$latitude,$longitude');
      }

      // Generate filename with timestamp
      final timestamp = DateTime.now().toString().replaceAll(':', '-').replaceAll(' ', '_').split('.')[0];
      final filename = 'bragmat_catches_$timestamp.csv';
      final filePath = '${directory.path}/$filename';
      debugPrint('Export file path: $filePath');
      
      // Write file
      final file = File(filePath);
      await file.writeAsString(csvContent.toString());
      debugPrint('File written successfully');

      // Verify file exists
      if (await file.exists()) {
        debugPrint('File verified to exist at: $filePath');
        final fileSize = await file.length();
        debugPrint('File size: $fileSize bytes');
      } else {
        debugPrint('ERROR: File does not exist after write');
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export Successful'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CSV file exported successfully.'),
                const SizedBox(height: 8),
                const Text('File path:'),
                const SizedBox(height: 4),
                SelectableText(
                  filePath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  debugPrint('Initiating share action for: $filePath');
                  await Share.shareXFiles(
                    [XFile(filePath)],
                    subject: 'Bragmat Catches Export',
                    text: 'Exported $filename',
                  );
                  debugPrint('Share action completed');
                },
                child: const Text('Share CSV'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('ERROR: Export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
    debugPrint('=== Export Catches to CSV completed ===');
  }

  String _escapeCSV(String value) {
    // Escape values that contain commas, quotes, or newlines
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _importCatchesFromCSV() async {
    debugPrint('=== Import Catches from CSV started ===');
    
    try {
      // Pick CSV file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.isEmpty) {
        debugPrint('No file selected');
        return;
      }

      final file = result.files.first;
      debugPrint('Selected file: ${file.name}');
      
      if (file.path == null) {
        debugPrint('ERROR: File path is null');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file')),
          );
        }
        return;
      }

      // Read file
      final csvFile = File(file.path!);
      final csvContent = await csvFile.readAsString();
      debugPrint('File read successfully');

      // Parse CSV
      final lines = csvContent.split('\n');
      if (lines.isEmpty) {
        debugPrint('ERROR: File is empty');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File is empty')),
          );
        }
        return;
      }

      // Get existing catches for duplicate detection
      final existingCatches = await DatabaseHelper.instance.getCatches();
      debugPrint('Existing catches: ${existingCatches.length}');

      // Statistics
      int rowsRead = 0;
      int catchesImported = 0;
      int rowsSkipped = 0;
      List<String> errors = [];

      // Skip header row
      final dataLines = lines.skip(1).toList();
      rowsRead = dataLines.length;

      for (int i = 0; i < dataLines.length; i++) {
        final line = dataLines[i].trim();
        if (line.isEmpty) {
          rowsSkipped++;
          continue;
        }

        // Parse CSV line (handle quoted values)
        final values = _parseCSVLine(line);
        
        if (values.length < 2) {
          errors.add('Row ${i + 2}: Invalid format (expected at least 2 columns)');
          rowsSkipped++;
          continue;
        }

        // Extract fields
        final fishType = values[0].trim();
        final size = int.tryParse(values[1].trim()) ?? 0;
        final dateCaughtStr = values.length > 2 ? values[2].trim() : '';
        final location = values.length > 3 ? values[3].trim() : '';
        final notes = values.length > 4 ? values[4].trim() : '';
        final photoPath = values.length > 5 ? values[5].trim() : '';
        final photoDateTimeStr = values.length > 6 ? values[6].trim() : '';
        final latitudeStr = values.length > 7 ? values[7].trim() : '';
        final longitudeStr = values.length > 8 ? values[8].trim() : '';

        // Validate required fields
        if (fishType.isEmpty) {
          errors.add('Row ${i + 2}: Fish type is required');
          rowsSkipped++;
          continue;
        }

        // Parse date
        DateTime? dateCaught;
        if (dateCaughtStr.isNotEmpty) {
          try {
            dateCaught = DateTime.parse(dateCaughtStr);
          } catch (e) {
            debugPrint('Row ${i + 2}: Could not parse date: $dateCaughtStr');
          }
        }

        // Parse photo date/time
        DateTime? photoDateTime;
        if (photoDateTimeStr.isNotEmpty) {
          try {
            photoDateTime = DateTime.parse(photoDateTimeStr);
          } catch (e) {
            debugPrint('Row ${i + 2}: Could not parse photo date/time: $photoDateTimeStr');
          }
        }

        // Parse coordinates
        double? latitude;
        if (latitudeStr.isNotEmpty) {
          latitude = double.tryParse(latitudeStr);
        }
        double? longitude;
        if (longitudeStr.isNotEmpty) {
          longitude = double.tryParse(longitudeStr);
        }

        // Check for duplicates (fish type + size + date combination)
        final isDuplicate = existingCatches.any((existing) {
          final existingDate = existing.dateCaught ?? existing.createdAt;
          final importDate = dateCaught ?? DateTime.now();
          return existing.fishType == fishType &&
                 existing.lengthCm == size &&
                 existingDate.year == importDate.year &&
                 existingDate.month == importDate.month &&
                 existingDate.day == importDate.day;
        });

        if (isDuplicate) {
          errors.add('Row ${i + 2}: Duplicate catch (fish type: $fishType, size: $size)');
          rowsSkipped++;
          continue;
        }

        // Create catch object
        final newCatch = Catch(
          fishType: fishType,
          lengthCm: size,
          notes: notes.isEmpty ? null : notes,
          createdAt: DateTime.now(),
          dateCaught: dateCaught,
          imagePath: photoPath.isEmpty ? null : photoPath,
          photoDateTime: photoDateTime,
          latitude: latitude,
          longitude: longitude,
          location: location.isEmpty ? null : location,
        );

        // Insert into database
        await DatabaseHelper.instance.insertCatch(newCatch);
        catchesImported++;
        debugPrint('Imported catch: $fishType');
      }

      debugPrint('Import complete: $catchesImported imported, $rowsSkipped skipped, ${errors.length} errors');

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import Complete'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rows read: $rowsRead'),
                Text('Catches imported: $catchesImported'),
                Text('Rows skipped: $rowsSkipped'),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: errors.length > 10 ? 10 : errors.length,
                      itemBuilder: (context, index) => Text(
                        errors[index],
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ),
                  if (errors.length > 10)
                    Text('... and ${errors.length - 10} more errors', style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadStatistics(); // Refresh statistics
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('ERROR: Import failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
    debugPrint('=== Import Catches from CSV completed ===');
  }

  List<String> _parseCSVLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Escaped quote
          buffer.write('"');
          i++;
        } else {
          // Toggle quote mode
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // End of value
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    
    // Add last value
    values.add(buffer.toString());
    
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final mostRecentCatch = _catches.isNotEmpty
        ? _catches.reduce((a, b) {
            final aDate = a.dateCaught ?? a.createdAt;
            final bDate = b.dateCaught ?? b.createdAt;
            return aDate.isAfter(bDate) ? a : b;
          })
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App Information Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App Information',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('App Name', 'Bragmat'),
                  _buildInfoRow('Version', '1.0.0'),
                  _buildInfoRow('Build Number', '1'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Statistics Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Statistics',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('Total Catches', '${_catches.length}'),
                  _buildInfoRow('Total Fish Types', '${_fishTypes.length}'),
                  _buildInfoRow(
                    'Most Recent Catch',
                    mostRecentCatch != null
                        ? '${mostRecentCatch.dateCaught?.toString().split(' ')[0] ?? mostRecentCatch.createdAt.toString().split(' ')[0]}'
                        : 'No catches yet',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Fish Types Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fish Types',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showAddFishTypeDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Fish Type'),
                  ),
                  const SizedBox(height: 16),
                  if (_fishTypes.isEmpty)
                    const Text('No fish types yet'),
                  ..._fishTypes.map((fishType) {
                    return ListTile(
                      title: Text(fishType),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showEditFishTypeDialog(fishType),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _showDeleteFishTypeDialog(fishType),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Data Management Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data Management',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.file_upload),
                    title: const Text('Export Catches'),
                    onTap: _exportCatchesToCSV,
                  ),
                  ListTile(
                    leading: const Icon(Icons.file_download),
                    title: const Text('Import Catches'),
                    onTap: _importCatchesFromCSV,
                  ),
                  _buildComingSoonMenuItem(Icons.backup, 'Backup and Restore'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // About Bragmat Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About Bragmat',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Bragmat helps anglers record, manage and review their fishing catches.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Website: Coming Soon',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Developer Section
          Card(
            child: ExpansionTile(
              title: Text(
                'Developer',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('SQLite Database Version', '1'),
                      _buildInfoRow('Catches Table Records', '${_catches.length}'),
                      _buildInfoRow('Fish Types Table Records', '${_fishTypes.length}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComingSoonMenuItem(IconData icon, String label) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Text(
        'Coming Soon',
        style: TextStyle(
          color: Colors.grey,
          fontSize: 12,
        ),
      ),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coming Soon')),
        );
      },
    );
  }
}
