import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import 'dart:io';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';
import '../models/favourite_spot.dart';
import '../services/backup_service.dart';
import '../services/preferences_service.dart';
import '../widgets/bragmat_section_card.dart';
import 'favourite_spots_screen.dart';
import 'achievements_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _fishTypes = [];
  List<Catch> _catches = [];
  List<FishingBuddy> _fishingBuddies = [];
  FishTypeSelectionMode _fishTypeSelectionMode = FishTypeSelectionMode.noDefault;
  String? _defaultFishType;

  @override
  void initState() {
    super.initState();
    _loadFishTypes();
    _loadStatistics();
    _loadFishingBuddies();
    _loadFishTypePreferences();
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

  Future<void> _loadFishingBuddies() async {
    final buddies = await DatabaseHelper.instance.getFishingBuddies();
    setState(() {
      _fishingBuddies = buddies;
    });
  }

  Future<void> _loadFishTypePreferences() async {
    final mode = await PreferencesService.getFishTypeSelectionMode();
    final defaultFishType = await PreferencesService.getDefaultFishType();
    setState(() {
      _fishTypeSelectionMode = mode;
      _defaultFishType = defaultFishType;
    });
  }

  Future<void> _setFishTypeSelectionMode(FishTypeSelectionMode mode) async {
    await PreferencesService.setFishTypeSelectionMode(mode);
    setState(() {
      _fishTypeSelectionMode = mode;
    });
  }

  Future<void> _setDefaultFishType(String? fishType) async {
    await PreferencesService.setDefaultFishType(fishType);
    setState(() {
      _defaultFishType = fishType;
    });
  }

  Future<void> _showFishTypesDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fish Types'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAddFishTypeDialog();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Fish Type'),
              ),
              const SizedBox(height: 16),
              if (_fishTypes.isEmpty)
                const Text('No fish types yet')
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _fishTypes.length,
                    itemBuilder: (context, index) {
                      final fishType = _fishTypes[index];
                      return ListTile(
                        title: Text(fishType),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.pop(context);
                                _showEditFishTypeDialog(fishType);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                Navigator.pop(context);
                                _showDeleteFishTypeDialog(fishType);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFishingBuddiesDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fishing Buddies'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAddFishingBuddyDialog();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Fishing Buddy'),
              ),
              const SizedBox(height: 16),
              if (_fishingBuddies.isEmpty)
                const Text('No fishing buddies yet')
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _fishingBuddies.length,
                    itemBuilder: (context, index) {
                      final buddy = _fishingBuddies[index];
                      return ListTile(
                        title: Text(buddy.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.pop(context);
                                _showEditFishingBuddyDialog(buddy);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                Navigator.pop(context);
                                _showDeleteFishingBuddyDialog(buddy);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showClearAllDataDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete all catches, fish types, fishing buddies, and favourite spots. This action cannot be undone.\n\nAre you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All Data'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.deleteAllCatches();
      await DatabaseHelper.instance.deleteAllFishTypes();
      await DatabaseHelper.instance.deleteAllFishingBuddies();
      // Delete all favourite spots
      final spots = await DatabaseHelper.instance.getFavouriteSpots();
      for (final spot in spots) {
        await DatabaseHelper.instance.deleteFavouriteSpot(spot.id!);
      }
      await DatabaseHelper.instance.deleteAllFishingTrips();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared')),
        );
        _loadStatistics();
        _loadFishTypes();
        _loadFishingBuddies();
      }
    }
  }

  Future<void> _showAboutDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Bragmat'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bragmat helps anglers record, manage and review their fishing catches.',
            ),
            SizedBox(height: 16),
            Text(
              'Version: 1.0.0',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Database Version: 1',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Website: Coming Soon',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDataSourcesDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Data Sources'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weather Data',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Open-Meteo Weather API'),
              Text('Free, non-commercial use'),
              SizedBox(height: 16),
              Text(
                'Tide Data',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Open-Meteo Marine API'),
              Text('Model-based sea level height including ocean tides'),
              SizedBox(height: 8),
              Text(
                'Important:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
              ),
              Text(
                'Tide data is model-based and indicative only.',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                'Not suitable for navigation.',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                'May be inaccurate in coastal areas, rivers, and estuaries.',
                style: TextStyle(color: Colors.orange),
              ),
              SizedBox(height: 8),
              Text(
                'Datum Difference:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
              ),
              Text(
                'Open-Meteo tide data is relative to mean sea level (MSL).',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                'Official tide tables use tide chart datum (LAT/MLLW).',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                'Open-Meteo is used only to estimate tide movement/stage.',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                'It is NOT equivalent to official tide table heights.',
                style: TextStyle(color: Colors.orange),
              ),
              SizedBox(height: 16),
              Text(
                'Moon & Sun Data',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Calculated using astronomical algorithms'),
              SizedBox(height: 16),
              Text(
                'Data Accuracy',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Manual observations always take precedence'),
              Text('API data is for reference only'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
      await _loadFishTypes();
      
      // Clean up preferences if the deleted fish type was in use
      await PreferencesService.clearDefaultFishTypeIfDeleted(_fishTypes);
      await PreferencesService.clearLastUsedFishTypeIfDeleted(_fishTypes);
      await _loadFishTypePreferences();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fish type deleted')),
        );
      }
    }
  }

  // Fishing Buddies CRUD
  Future<void> _showAddFishingBuddyDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Fishing Buddy'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Fishing Buddy Name'),
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
      final exists = _fishingBuddies.any((buddy) =>
        buddy.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == normalized);

      if (!exists) {
        final result = await DatabaseHelper.instance.insertFishingBuddy(name);
        if (result != -1) {
          _loadFishingBuddies();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fishing buddy added')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fishing buddy already exists')),
          );
        }
      }
    }
  }

  Future<void> _showEditFishingBuddyDialog(FishingBuddy buddy) async {
    final controller = TextEditingController(text: buddy.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Fishing Buddy'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Fishing Buddy Name'),
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
      if (newName != buddy.name) {
        // Check for duplicates (case-insensitive, ignoring extra spaces)
        final normalized = newName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final exists = _fishingBuddies.any((b) =>
          b.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == normalized && b.id != buddy.id);

        if (!exists) {
          await DatabaseHelper.instance.updateFishingBuddy(buddy.id!, newName);
          _loadFishingBuddies();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fishing buddy updated')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fishing buddy already exists')),
            );
          }
        }
      }
    }
  }

  Future<void> _showDeleteFishingBuddyDialog(FishingBuddy buddy) async {
    // Prevent deleting "Me"
    if (buddy.name == 'Me') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete "Me" fishing buddy')),
        );
      }
      return;
    }

    final isUsed = await DatabaseHelper.instance.isFishingBuddyUsed(buddy.id!);
    if (isUsed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: fishing buddy is in use')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Fishing Buddy'),
        content: Text('Are you sure you want to delete "${buddy.name}"?'),
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
      await DatabaseHelper.instance.deleteFishingBuddy(buddy.id!);
      _loadFishingBuddies();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fishing buddy deleted')),
        );
      }
    }
  }

  Future<void> _exportCatchesToCSV() async {
    try {
      final catches = await DatabaseHelper.instance.getCatches();
      
      if (catches.isEmpty) {
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access downloads directory')),
          );
        }
        return;
      }

      // Create CSV content
      final csvContent = StringBuffer();
      // Header row
      csvContent.writeln('Fish Type,Size (cm),Date Caught,Location,Notes,Photo Path,Photo Date/Time,Latitude,Longitude,Fishing Buddy,Fishing Trip');
      
      // Load fishing buddies for name lookup
      final fishingBuddies = await DatabaseHelper.instance.getFishingBuddies();
      final buddyMap = {for (var buddy in fishingBuddies) buddy.id!: buddy.name};
      
      // Load fishing trips for name lookup
      final fishingTrips = await DatabaseHelper.instance.getFishingTrips();
      final tripMap = {for (var trip in fishingTrips) trip.id!: trip.name};
      
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
        final fishingBuddy = catch_.fishingBuddyId != null
            ? _escapeCSV(buddyMap[catch_.fishingBuddyId] ?? 'Unknown')
            : '';
        final fishingTrip = catch_.tripId != null
            ? _escapeCSV(tripMap[catch_.tripId] ?? 'Unknown')
            : '';
        
        csvContent.writeln('$fishType,$size,$dateCaught,$location,$notes,$photoPath,$photoDateTime,$latitude,$longitude,$fishingBuddy,$fishingTrip');
      }

      // Generate filename with timestamp
      final timestamp = DateTime.now().toString().replaceAll(':', '-').replaceAll(' ', '_').split('.')[0];
      final filename = 'bragmat_catches_$timestamp.csv';
      final filePath = '${directory.path}/$filename';
      
      // Write file
      final file = File(filePath);
      await file.writeAsString(csvContent.toString());

      // Verify file exists
      if (await file.exists()) {
        final fileSize = await file.length();
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
                  await Share.shareXFiles(
                    [XFile(filePath)],
                    subject: 'Bragmat Catches Export',
                    text: 'Exported $filename',
                  );
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  String _escapeCSV(String value) {
    // Escape values that contain commas, quotes, or newlines
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  // Temporarily disabled due to file_picker build issue
  // Future<void> _importCatchesFromCSV() async {
  //   debugPrint('=== Import Catches from CSV started ===');
  //   
  //   try {
  //     // Pick CSV file
  //     final result = await FilePicker.platform.pickFiles(
  //       type: FileType.custom,
  //       allowedExtensions: ['csv'],
  //     );

  //     if (result == null || result.files.isEmpty) {
  //       debugPrint('No file selected');
  //       return;
  //     }

  //     final file = result.files.first;
  //     debugPrint('Selected file: ${file.name}');
  //     
  //     if (file.path == null) {
  //       debugPrint('ERROR: File path is null');
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text('Could not read file')),
  //         );
  //       }
  //       return;
  //     }

  //     // Read file
  //     final csvFile = File(file.path!);
  //     final csvContent = await csvFile.readAsString();
  //     debugPrint('File read successfully');

  //     // Parse CSV
  //     final lines = csvContent.split('\n');
  //     if (lines.isEmpty) {
  //       debugPrint('ERROR: File is empty');
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text('File is empty')),
  //         );
  //       }
  //       return;
  //     }

  //     // Get existing catches for duplicate detection
  //     final existingCatches = await DatabaseHelper.instance.getCatches();
  //     debugPrint('Existing catches: ${existingCatches.length}');

  //     // Statistics
  //     int rowsRead = 0;
  //     int catchesImported = 0;
  //     int rowsSkipped = 0;
  //     List<String> errors = [];

  //     // Skip header row
  //     final dataLines = lines.skip(1).toList();
  //     rowsRead = dataLines.length;

  //     for (int i = 0; i < dataLines.length; i++) {
  //       final line = dataLines[i].trim();
  //       if (line.isEmpty) {
  //         rowsSkipped++;
  //         continue;
  //       }

  //       // Parse CSV line (handle quoted values)
  //       final values = _parseCSVLine(line);
        
  //       if (values.length < 2) {
  //         errors.add('Row ${i + 2}: Invalid format (expected at least 2 columns)');
  //         rowsSkipped++;
  //         continue;
  //       }

  //       // Extract fields
  //       final fishType = values[0].trim();
  //       final size = int.tryParse(values[1].trim()) ?? 0;
  //       final dateCaughtStr = values.length > 2 ? values[2].trim() : '';
  //       final location = values.length > 3 ? values[3].trim() : '';
  //       final notes = values.length > 4 ? values[4].trim() : '';
  //       final photoPath = values.length > 5 ? values[5].trim() : '';
  //       final photoDateTimeStr = values.length > 6 ? values[6].trim() : '';
  //       final latitudeStr = values.length > 7 ? values[7].trim() : '';
  //       final longitudeStr = values.length > 8 ? values[8].trim() : '';
  //       final fishingBuddyStr = values.length > 9 ? values[9].trim() : '';

  //       // Validate required fields
  //       if (fishType.isEmpty) {
  //         errors.add('Row ${i + 2}: Fish type is required');
  //         rowsSkipped++;
  //         continue;
  //       }

  //       // Parse date
  //       DateTime? dateCaught;
  //       if (dateCaughtStr.isNotEmpty) {
  //         try {
  //           dateCaught = DateTime.parse(dateCaughtStr);
  //         } catch (e) {
  //           debugPrint('Row ${i + 2}: Could not parse date: $dateCaughtStr');
  //         }
  //       }

  //       // Parse photo date/time
  //       DateTime? photoDateTime;
  //       if (photoDateTimeStr.isNotEmpty) {
  //         try {
  //           photoDateTime = DateTime.parse(photoDateTimeStr);
  //         } catch (e) {
  //           debugPrint('Row ${i + 2}: Could not parse photo date/time: $photoDateTimeStr');
  //         }
  //       }

  //       // Parse coordinates
  //       double? latitude;
  //       if (latitudeStr.isNotEmpty) {
  //         latitude = double.tryParse(latitudeStr);
  //       }
  //       double? longitude;
  //       if (longitudeStr.isNotEmpty) {
  //         longitude = double.tryParse(longitudeStr);
  //       }

  //       // Handle fishing buddy
  //       int? fishingBuddyId;
  //       if (fishingBuddyStr.isNotEmpty) {
  //         // Look up fishing buddy by name
  //         final buddy = await DatabaseHelper.instance.getFishingBuddyByName(fishingBuddyStr);
  //         if (buddy != null) {
  //           fishingBuddyId = buddy.id;
  //         } else {
  //           // Create new fishing buddy if it doesn't exist
  //           final insertedId = await DatabaseHelper.instance.insertFishingBuddy(fishingBuddyStr);
  //           if (insertedId != -1) {
  //             fishingBuddyId = insertedId;
  //           }
  //         }
  //       } else {
  //         // Default to "Me" if no fishing buddy specified
  //         final meBuddy = await DatabaseHelper.instance.getMeFishingBuddy();
  //         fishingBuddyId = meBuddy?.id;
  //       }

  //       // Check for duplicates (fish type + size + date combination)
  //       final isDuplicate = existingCatches.any((existing) {
  //         final existingDate = existing.dateCaught ?? existing.createdAt;
  //         final importDate = dateCaught ?? DateTime.now();
  //         return existing.fishType == fishType &&
  //                existing.lengthCm == size &&
  //                existingDate.year == importDate.year &&
  //                existingDate.month == importDate.month &&
  //                existingDate.day == importDate.day;
  //       });

  //       if (isDuplicate) {
  //         errors.add('Row ${i + 2}: Duplicate catch (fish type: $fishType, size: $size)');
  //         rowsSkipped++;
  //         continue;
  //       }

  //       // Create catch object
  //       final newCatch = Catch(
  //         fishType: fishType,
  //         lengthCm: size,
  //         notes: notes.isEmpty ? null : notes,
  //         createdAt: DateTime.now(),
  //         dateCaught: dateCaught,
  //         imagePath: photoPath.isEmpty ? null : photoPath,
  //         photoDateTime: photoDateTime,
  //         latitude: latitude,
  //         longitude: longitude,
  //         location: location.isEmpty ? null : location,
  //         fishingBuddyId: fishingBuddyId,
  //       );

  //       // Insert into database
  //       await DatabaseHelper.instance.insertCatch(newCatch);
  //       catchesImported++;
  //       debugPrint('Imported catch: $fishType');
  //     }

  //     debugPrint('Import complete: $catchesImported imported, $rowsSkipped skipped, ${errors.length} errors');

  //     if (mounted) {
  //       showDialog(
  //         context: context,
  //         builder: (context) => AlertDialog(
  //           title: const Text('Import Complete'),
  //           content: Column(
  //             mainAxisSize: MainAxisSize.min,
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               Text('Rows read: $rowsRead'),
  //               Text('Catches imported: $catchesImported'),
  //               Text('Rows skipped: $rowsSkipped'),
  //               if (errors.isNotEmpty) ...[
  //                 const SizedBox(height: 8),
  //                 const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
  //                 const SizedBox(height: 4),
  //                 SizedBox(
  //                   height: 150,
  //                   child: ListView.builder(
  //                     shrinkWrap: true,
  //                     itemCount: errors.length > 10 ? 10 : errors.length,
  //                     itemBuilder: (context, index) => Text(
  //                       errors[index],
  //                       style: const TextStyle(fontSize: 12, color: Colors.red),
  //                     ),
  //                   ),
  //                 ),
  //                 if (errors.length > 10)
  //                   Text('... and ${errors.length - 10} more errors', style: const TextStyle(fontSize: 12)),
  //               ],
  //             ],
  //           ),
  //           actions: [
  //             TextButton(
  //               onPressed: () {
  //                 Navigator.pop(context);
  //                 _loadStatistics(); // Refresh statistics
  //               },
  //               child: const Text('OK'),
  //             ),
  //           ],
  //         ),
  //       );
  //     }
  //   } catch (e) {
  //     debugPrint('ERROR: Import failed: $e');
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('Import failed: $e')),
  //       );
  //     }
  //   }
  //   debugPrint('=== Import Catches from CSV completed ===');
  // }

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

  Future<void> _backupData() async {
    try {
      debugPrint('=== Backup Data Started ===');
      final filePath = await BackupService.exportBackup();
      debugPrint('Backup file created at: $filePath');
      
      final file = File(filePath);
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;
      final fileName = filePath.split('/').last;
      
      debugPrint('File exists: $fileExists');
      debugPrint('File size: $fileSize bytes');
      debugPrint('File name: $fileName');
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Backup Created'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Backup file created successfully.'),
                const SizedBox(height: 16),
                const Text('File name:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(
                  fileName,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('File path:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(
                  filePath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Text('File size: ${(fileSize / 1024).toStringAsFixed(2)} KB'),
                const SizedBox(height: 16),
                const Text(
                  'Note: If you cannot find this file in Downloads, use the Share button below to save it to another location.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await Share.shareXFiles(
                    [XFile(filePath)],
                    subject: 'Bragmat Backup',
                    text: 'Bragmat data backup',
                  );
                },
                child: const Text('Share Backup'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      
      debugPrint('=== Backup Data Completed ===');
    } catch (e) {
      debugPrint('Backup failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
  }

  Future<void> _testPhotoGPS() async {
    debugPrint('=== Test Photo GPS Started ===');
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile == null) {
      debugPrint('No photo selected');
      return;
    }
    
    debugPrint('Photo selected: ${pickedFile.path}');
    
    final file = File(pickedFile.path);
    final fileExists = await file.exists();
    final fileSize = fileExists ? await file.length() : 0;
    
    debugPrint('File exists: $fileExists');
    debugPrint('File size: $fileSize bytes');
    
    if (!fileExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found')),
        );
      }
      return;
    }
    
    // Read EXIF data
    Map<String, dynamic>? exifData;
    try {
      final bytes = await file.readAsBytes();
      exifData = await readExifFromBytes(bytes);
      debugPrint('EXIF data keys: ${exifData.keys.toList()}');
    } catch (e) {
      debugPrint('Error reading EXIF: $e');
      exifData = null;
    }
    
    // Extract GPS data
    double? latitude;
    double? longitude;
    String? dateTaken;
    List<String> gpsTags = [];
    
    if (exifData != null) {
      // Get date taken
      if (exifData.containsKey('DateTimeOriginal')) {
        dateTaken = exifData['DateTimeOriginal'].toString();
        debugPrint('DateTimeOriginal: $dateTaken');
      }
      
      // Get GPS tags
      final allGpsTags = exifData.entries.where((e) => e.key.startsWith('GPS')).toList();
      for (final tag in allGpsTags) {
        gpsTags.add('${tag.key}: ${tag.value}');
        debugPrint('GPS tag: ${tag.key} = ${tag.value}');
      }
      
      // Try to extract coordinates
      if (exifData.containsKey('GPSLatitude') && exifData.containsKey('GPSLongitude')) {
        final lat = exifData['GPSLatitude'];
        final latRef = exifData['GPSLatitudeRef'];
        final lon = exifData['GPSLongitude'];
        final lonRef = exifData['GPSLongitudeRef'];
        
        debugPrint('GPSLatitude: $lat');
        debugPrint('GPSLatitudeRef: $latRef');
        debugPrint('GPSLongitude: $lon');
        debugPrint('GPSLongitudeRef: $lonRef');
        
        if (lat != null && latRef != null && lon != null && lonRef != null) {
          latitude = _convertToDecimalDegrees(lat, latRef);
          longitude = _convertToDecimalDegrees(lon, lonRef);
          debugPrint('Extracted coordinates: $latitude, $longitude');
        }
      }
    }
    
    debugPrint('=== Test Photo GPS Completed ===');
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Photo GPS Test Results'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('File path:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(
                  pickedFile.path,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 12),
                Text('File size: ${(fileSize / 1024).toStringAsFixed(2)} KB'),
                const SizedBox(height: 12),
                const Text('EXIF metadata:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(exifData != null ? 'Yes (${exifData.length} tags)' : 'No'),
                const SizedBox(height: 12),
                if (dateTaken != null) ...[
                  const Text('Date taken:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(dateTaken),
                  const SizedBox(height: 12),
                ],
                const Text('GPS coordinates:', style: TextStyle(fontWeight: FontWeight.bold)),
                if (latitude != null && longitude != null) ...[
                  Text('Latitude: ${latitude.toStringAsFixed(6)}'),
                  Text('Longitude: ${longitude.toStringAsFixed(6)}'),
                ] else ...[
                  const Text('No GPS coordinates found'),
                  const SizedBox(height: 12),
                  const Text('GPS tags found:', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (gpsTags.isEmpty)
                    const Text('None')
                  else
                    ...gpsTags.map((tag) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(tag, style: const TextStyle(fontSize: 11)),
                    )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  double _convertToDecimalDegrees(dynamic value, dynamic ref) {
    if (value is! List) return 0.0;
    
    final degrees = _convertRational(value[0]);
    final minutes = _convertRational(value[1]);
    final seconds = _convertRational(value[2]);
    
    var decimal = degrees + (minutes / 60) + (seconds / 3600);
    
    if (ref == 'S' || ref == 'W') {
      decimal = -decimal;
    }
    
    return decimal;
  }

  double _convertRational(dynamic value) {
    if (value is List && value.length >= 2) {
      final numerator = value[0] is int ? value[0] as int : int.tryParse(value[0].toString()) ?? 0;
      final denominator = value[1] is int ? value[1] as int : int.tryParse(value[1].toString()) ?? 1;
      if (denominator != 0) {
        return numerator / denominator;
      }
    }
    return 0.0;
  }

  Future<void> _restoreData() async {
    // Show instructions dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To restore a backup:'),
            SizedBox(height: 8),
            Text('1. Copy your backup JSON file to the Downloads folder'),
            SizedBox(height: 4),
            Text('2. The file must be named: bragmat_backup_*.json'),
            SizedBox(height: 4),
            Text('3. The most recent backup will be used'),
            SizedBox(height: 16),
            Text('Warning: This will replace your current data if it exists.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      // Find backup file in downloads
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access downloads directory')),
          );
        }
        return;
      }

      // Find most recent backup file
      final files = directory.listSync().whereType<File>().toList();
      final backupFiles = files
          .where((f) => f.path.contains('bragmat_backup_') && f.path.endsWith('.json'))
          .toList();

      if (backupFiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No backup file found in Downloads folder')),
          );
        }
        return;
      }

      // Sort by last modified, most recent first
      backupFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final backupFile = backupFiles.first;

      // Check if database has data
      final existingCatches = await DatabaseHelper.instance.getCatches();
      final hasExistingData = existingCatches.isNotEmpty;

      // Show confirmation with file name
      final restoreConfirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Restore from this file?'),
              const SizedBox(height: 8),
              Text('File: ${backupFile.path.split('/').last}'),
              const SizedBox(height: 8),
              if (hasExistingData) ...[
                const Text(
                  'Warning: Your current data will be replaced.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );

      if (restoreConfirmed != true) {
        return;
      }

      await BackupService.restoreBackup(backupFile.path, overwrite: hasExistingData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully')),
        );
        // Reload data
        _loadStatistics();
        _loadFishTypes();
        _loadFishingBuddies();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preferences Section
          BragmatSectionCard(
            icon: Icons.tune,
            title: 'Preferences',
            children: [
              DropdownButtonFormField<FishTypeSelectionMode>(
                initialValue: _fishTypeSelectionMode,
                decoration: const InputDecoration(
                  labelText: 'Fish Type Selection Mode',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: FishTypeSelectionMode.noDefault,
                    child: Text('No Default'),
                  ),
                  DropdownMenuItem(
                    value: FishTypeSelectionMode.defaultFishType,
                    child: Text('Default Fish Type'),
                  ),
                  DropdownMenuItem(
                    value: FishTypeSelectionMode.rememberLastUsed,
                    child: Text('Remember Last Used Fish Type'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _setFishTypeSelectionMode(value);
                  }
                },
              ),
              if (_fishTypeSelectionMode == FishTypeSelectionMode.defaultFishType) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _defaultFishType,
                  decoration: const InputDecoration(
                    labelText: 'Default Fish Type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('None'),
                    ),
                    ..._fishTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    _setDefaultFishType(value);
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Manage Lists Section
          BragmatSectionCard(
            icon: Icons.list,
            title: 'Manage Lists',
            children: [
              ListTile(
                leading: const Icon(Icons.set_meal),
                title: const Text('Fish Types'),
                subtitle: Text('${_fishTypes.length} types'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showFishTypesDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Fishing Buddies'),
                subtitle: Text('${_fishingBuddies.length} buddies'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showFishingBuddiesDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.place),
                title: const Text('Favourite Fishing Spots'),
                subtitle: const Text('Manage your spots'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FavouriteSpotsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Data Management Section
          BragmatSectionCard(
            icon: Icons.storage,
            title: 'Data Management',
            children: [
              ListTile(
                leading: const Icon(Icons.backup),
                title: const Text('Backup Data'),
                subtitle: const Text('Create a backup of all your data'),
                onTap: _backupData,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore Data'),
                subtitle: const Text('Restore from a backup file'),
                onTap: _restoreData,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('Export CSV'),
                subtitle: const Text('Export catches to CSV file'),
                onTap: _exportCatchesToCSV,
              ),
              const Divider(height: 1),
              _buildComingSoonMenuItem(Icons.file_download, 'Import CSV (Coming Soon)'),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Clear All Data', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Permanently delete all catches and data', style: TextStyle(color: Colors.red)),
                onTap: _showClearAllDataDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // App Section
          BragmatSectionCard(
            icon: Icons.info,
            title: 'App',
            children: [
              ListTile(
                leading: const Icon(Icons.emoji_events),
                title: const Text('Achievements'),
                subtitle: const Text('View your fishing milestones'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AchievementsScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              _buildInfoRow('App Version', '1.0.0'),
              const Divider(height: 1),
              _buildInfoRow('Database Version', '1'),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('About Bragmat'),
                subtitle: const Text('Learn more about the app'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showAboutDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('Data Sources'),
                subtitle: const Text('Weather, tide, and environmental data'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showDataSourcesDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Developer Section (collapsed by default)
          BragmatSectionCard(
            icon: Icons.code,
            title: 'Developer',
            children: [
              ExpansionTile(
                title: const Text('Database Info'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow('Catches', '${_catches.length}'),
                        _buildInfoRow('Fish Types', '${_fishTypes.length}'),
                        _buildInfoRow('Fishing Buddies', '${_fishingBuddies.length}'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
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
