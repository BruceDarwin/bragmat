import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import 'add_catch_screen.dart';

class CatchDetailsScreen extends StatelessWidget {
  final Catch catchItem;

  const CatchDetailsScreen({super.key, required this.catchItem});

  Future<void> _showDeleteDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Catch'),
        content: Text('Are you sure you want to delete ${catchItem.fishType}?'),
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

    if (confirmed == true && catchItem.id != null) {
      await DatabaseHelper.instance.deleteCatch(catchItem.id!);
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
                  builder: (_) => AddCatchScreen(catchToEdit: catchItem),
                ),
              );
              if (edited != null && context.mounted) {
                Navigator.pop(context, true);
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
            if (catchItem.imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(catchItem.imagePath!),
                  width: double.infinity,
                  height: 250,
                  fit: BoxFit.cover,
                ),
              ),
            if (catchItem.imagePath != null) const SizedBox(height: 20),
            Text(
              catchItem.fishType,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (catchItem.dateCaught != null)
              _buildDetailRow('Date Caught',
                  '${catchItem.dateCaught!.day}/${catchItem.dateCaught!.month}/${catchItem.dateCaught!.year}'),
            _buildDetailRow('Length', '${catchItem.lengthCm} cm'),
            if (catchItem.photoDateTime != null)
              _buildDetailRow('Photo Taken',
                  '${catchItem.photoDateTime!.day}/${catchItem.photoDateTime!.month}/${catchItem.photoDateTime!.year} ${catchItem.photoDateTime!.hour}:${catchItem.photoDateTime!.minute.toString().padLeft(2, '0')}'),
            if (catchItem.latitude != null && catchItem.longitude != null)
              _buildDetailRow('Location',
                  '${catchItem.latitude!.toStringAsFixed(6)}, ${catchItem.longitude!.toStringAsFixed(6)}'),
            if (catchItem.notes != null && catchItem.notes!.isNotEmpty)
              _buildDetailRow('Notes', catchItem.notes!),
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
