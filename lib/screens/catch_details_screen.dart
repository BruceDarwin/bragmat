import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';
import '../models/catch_media.dart';
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
  String? _fishingBuddyName;
  List<CatchMedia> _mediaItems = [];

  @override
  void initState() {
    super.initState();
    _catchItem = widget.catchItem;
    _loadFishingBuddyName();
    _loadMedia();
  }

  Future<void> _loadFishingBuddyName() async {
    if (_catchItem.fishingBuddyId != null) {
      final buddies = await DatabaseHelper.instance.getFishingBuddies();
      final buddy = buddies.firstWhere(
        (b) => b.id == _catchItem.fishingBuddyId,
        orElse: () => FishingBuddy(name: 'Unknown'),
      );
      if (mounted) {
        setState(() {
          _fishingBuddyName = buddy.name;
        });
      }
    }
  }

  Future<void> _loadMedia() async {
    if (_catchItem.id != null) {
      final media = await DatabaseHelper.instance.getMediaForCatch(_catchItem.id!);
      if (mounted) {
        setState(() {
          _mediaItems = media;
        });
      }
    }
  }

  Future<void> _deleteMedia(int mediaId) async {
    await DatabaseHelper.instance.deleteCatchMedia(mediaId);
    await _loadMedia();
  }

  Future<void> _setAsPrimary(int mediaId) async {
    await DatabaseHelper.instance.setPrimaryMedia(mediaId);
    await _loadMedia();
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_mediaItems.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _mediaItems.length,
                itemBuilder: (context, index) {
                  final media = _mediaItems[index];
                  return Stack(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PhotoViewerScreen(imagePath: media.filePath),
                            ),
                          );
                        },
                        child: Hero(
                          tag: 'catch_photo_${media.id}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(media.filePath),
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      if (media.role == 'primary')
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Primary',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: PopupMenuButton<String>(
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.more_vert,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          onSelected: (value) async {
                            if (value == 'delete') {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete Photo'),
                                  content: const Text('Are you sure you want to delete this photo?'),
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
                                await _deleteMedia(media.id!);
                              }
                            } else if (value == 'primary') {
                              await _setAsPrimary(media.id!);
                            }
                          },
                          itemBuilder: (context) => [
                            if (media.role != 'primary')
                              const PopupMenuItem(
                                value: 'primary',
                                child: Text('Set as Primary'),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _catchItem.fishType,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_fishingBuddyName != null && _fishingBuddyName != 'Me')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Caught by $_fishingBuddyName',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  _buildSection('Basic Info', [
                    if (_catchItem.dateCaught != null)
                      _buildDetailRow('Date Caught',
                          '${_catchItem.dateCaught!.day}/${_catchItem.dateCaught!.month}/${_catchItem.dateCaught!.year}'),
                    _buildDetailRow('Length', '${_catchItem.lengthCm} cm'),
                    if (_catchItem.photoDateTime != null)
                      _buildDetailRow('Photo Taken',
                          '${_catchItem.photoDateTime!.day}/${_catchItem.photoDateTime!.month}/${_catchItem.photoDateTime!.year} ${_catchItem.photoDateTime!.hour}:${_catchItem.photoDateTime!.minute.toString().padLeft(2, '0')}'),
                  ]),
                  if (_catchItem.location != null && _catchItem.location!.isNotEmpty ||
                      (_catchItem.latitude != null && _catchItem.longitude != null))
                    _buildSection('Location', [
                      if (_catchItem.location != null && _catchItem.location!.isNotEmpty)
                        _buildDetailRow('Location', _catchItem.location!),
                      if (_catchItem.latitude != null && _catchItem.longitude != null)
                        _buildDetailRow('GPS Location',
                            '${_catchItem.latitude!.toStringAsFixed(6)}, ${_catchItem.longitude!.toStringAsFixed(6)}'),
                    ]),
                  if (_catchItem.notes != null && _catchItem.notes!.isNotEmpty)
                    _buildSection('Notes', [
                      _buildDetailRow('Notes', _catchItem.notes!),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
        const SizedBox(height: 24),
      ],
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
