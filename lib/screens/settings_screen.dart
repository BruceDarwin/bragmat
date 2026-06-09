import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
                  _buildComingSoonMenuItem(Icons.file_download, 'Import Catches'),
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
