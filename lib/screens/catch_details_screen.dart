import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import 'add_catch_screen.dart';
import 'photo_viewer_screen.dart';

class CatchDetailsScreen extends StatefulWidget {
  final Catch catchItem;

  const CatchDetailsScreen({super.key, required this.catchItem});

  @override
  State<CatchDetailsScreen> createState() => _CatchDetailsScreenState();
}

class _CatchDetailsScreenState extends State<CatchDetailsScreen> {
  late Catch _catchItem;

  @override
  void initState() {
    super.initState();
    _catchItem = widget.catchItem;
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Catch'),
        content: Text('Are you sure you want to delete ${_catchItem.fishType}?'),
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

    if (confirmed == true && _catchItem.id != null) {
      await DatabaseHelper.instance.deleteCatch(_catchItem.id!);
      if (context.mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catch Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final edited = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddCatchScreen(catchToEdit: _catchItem),
                ),
              );
              if (edited is Catch && mounted) {
                setState(() {
                  _catchItem = edited;
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _showDeleteDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_catchItem.imagePath != null)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PhotoViewerScreen(imagePath: _catchItem.imagePath!),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_catchItem.imagePath!),
                    width: double.infinity,
                    height: 250,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (_catchItem.imagePath != null) const SizedBox(height: 20),
            Text(
              _catchItem.fishType,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_catchItem.dateCaught != null)
              _buildDetailRow('Date Caught',
                  '${_catchItem.dateCaught!.day}/${_catchItem.dateCaught!.month}/${_catchItem.dateCaught!.year}'),
            _buildDetailRow('Length', '${_catchItem.lengthCm} cm'),
            if (_catchItem.photoDateTime != null)
              _buildDetailRow('Photo Taken',
                  '${_catchItem.photoDateTime!.day}/${_catchItem.photoDateTime!.month}/${_catchItem.photoDateTime!.year} ${_catchItem.photoDateTime!.hour}:${_catchItem.photoDateTime!.minute.toString().padLeft(2, '0')}'),
            if (_catchItem.latitude != null && _catchItem.longitude != null)
              _buildDetailRow('Location',
                  '${_catchItem.latitude!.toStringAsFixed(6)}, ${_catchItem.longitude!.toStringAsFixed(6)}'),
            if (_catchItem.notes != null && _catchItem.notes!.isNotEmpty)
              _buildDetailRow('Notes', _catchItem.notes!),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}
