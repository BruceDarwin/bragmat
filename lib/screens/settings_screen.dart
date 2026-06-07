import 'package:flutter/material.dart';
import '../database/database_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _fishTypes = [];

  @override
  void initState() {
    super.initState();
    _loadFishTypes();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manage Fish Types',
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
        ],
      ),
    );
  }
}
