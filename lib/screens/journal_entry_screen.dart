import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../database/database_helper.dart';
import '../models/trip_journal.dart';
import '../models/journal_media.dart';
import 'photo_viewer_screen.dart';

class JournalEntryScreen extends StatefulWidget {
  final int tripId;
  final TripJournal? journalToEdit;

  const JournalEntryScreen({
    super.key,
    required this.tripId,
    this.journalToEdit,
  });

  @override
  State<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends State<JournalEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _journalDateTime;
  late String _journalType;
  late TextEditingController _titleController;
  late TextEditingController _entryTextController;
  List<JournalMedia> _media = [];
  final ImagePicker _imagePicker = ImagePicker();

  final List<String> _journalTypes = [
    'general',
    'fishing_report',
    'weather',
    'tide',
    'wildlife',
    'campsite',
    'boat_equipment',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.journalToEdit != null) {
      _journalDateTime = widget.journalToEdit!.journalDateTime;
      _journalType = widget.journalToEdit!.journalType;
      _titleController = TextEditingController(text: widget.journalToEdit!.title);
      _entryTextController = TextEditingController(text: widget.journalToEdit!.entryText);
      _loadMedia();
    } else {
      _journalDateTime = DateTime.now();
      _journalType = 'general';
      _titleController = TextEditingController();
      _entryTextController = TextEditingController();
    }
  }

  Future<void> _loadMedia() async {
    if (widget.journalToEdit?.id == null) return;
    final media = await DatabaseHelper.instance.getMediaForJournalEntry(widget.journalToEdit!.id!);
    if (mounted) {
      setState(() {
        _media = media;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _entryTextController.dispose();
    super.dispose();
  }

  Future<void> _saveJournal() async {
    if (!_formKey.currentState!.validate()) return;

    final journal = TripJournal(
      id: widget.journalToEdit?.id,
      tripId: widget.tripId,
      journalDateTime: _journalDateTime,
      journalType: _journalType,
      title: _titleController.text.trim(),
      entryText: _entryTextController.text.trim(),
      createdAt: widget.journalToEdit?.createdAt,
      updatedAt: DateTime.now(),
    );

    int journalId;
    if (widget.journalToEdit != null) {
      journalId = widget.journalToEdit!.id!;
      await DatabaseHelper.instance.updateTripJournal(journal);
    } else {
      journalId = await DatabaseHelper.instance.insertTripJournal(journal);
    }

    // Save media if this is a new entry or if media was added
    if (widget.journalToEdit == null && _media.isNotEmpty) {
      for (final media in _media) {
        await DatabaseHelper.instance.insertJournalMedia(
          media.copyWith(journalEntryId: journalId),
        );
      }
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteJournal() async {
    if (widget.journalToEdit == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Journal Entry'),
        content: const Text('Are you sure you want to delete this journal entry?'),
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

    if (confirmed == true && widget.journalToEdit!.id != null) {
      await DatabaseHelper.instance.deleteTripJournal(widget.journalToEdit!.id!);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> _selectDateTime() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1);
    final lastDate = DateTime(now.year + 1);

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _journalDateTime,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (selectedDate != null && mounted) {
      final selectedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_journalDateTime),
      );

      if (selectedTime != null) {
        setState(() {
          _journalDateTime = DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            selectedTime.hour,
            selectedTime.minute,
          );
        });
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _addPhoto() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final journalMedia = JournalMedia(
      journalEntryId: widget.journalToEdit?.id ?? 0,
      filePath: image.path,
      mediaType: 'photo',
      isPrimary: _media.isEmpty,
    );

    if (widget.journalToEdit != null) {
      await DatabaseHelper.instance.insertJournalMedia(journalMedia);
      await _loadMedia();
    } else {
      setState(() {
        _media.add(journalMedia);
      });
    }
  }

  Future<void> _deletePhoto(int mediaId) async {
    if (widget.journalToEdit != null) {
      await DatabaseHelper.instance.deleteJournalMedia(mediaId);
      await _loadMedia();
    } else {
      setState(() {
        _media.removeWhere((m) => m.id == mediaId);
      });
    }
  }

  Future<void> _setPrimaryPhoto(int mediaId) async {
    if (widget.journalToEdit != null) {
      await DatabaseHelper.instance.setPrimaryJournalMedia(mediaId);
      await _loadMedia();
    } else {
      setState(() {
        _media = _media.map((media) {
          return media.copyWith(isPrimary: media.id == mediaId);
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.journalToEdit != null ? 'Edit Journal Entry' : 'New Journal Entry'),
        actions: [
          if (widget.journalToEdit != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteJournal,
              tooltip: 'Delete',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Date/Time
            ListTile(
              title: const Text('Date & Time'),
              subtitle: Text(_formatDateTime(_journalDateTime)),
              leading: const Icon(Icons.calendar_today),
              trailing: const Icon(Icons.chevron_right),
              onTap: _selectDateTime,
            ),
            const Divider(),

            // Journal Type
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: DropdownButtonFormField<String>(
                value: _journalType,
                decoration: const InputDecoration(
                  labelText: 'Journal Type',
                  border: OutlineInputBorder(),
                ),
                items: _journalTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(TripJournal.getJournalTypeDisplayName(type)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _journalType = value;
                    });
                  }
                },
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
            ),

            // Entry Text
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: TextFormField(
                controller: _entryTextController,
                decoration: const InputDecoration(
                  labelText: 'Entry',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 8,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an entry';
                  }
                  return null;
                },
              ),
            ),

            // Photos Section
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Photos (${_media.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_a_photo),
                        onPressed: _addPhoto,
                        tooltip: 'Add Photo',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_media.isEmpty)
                    Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.photo_library,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No photos yet',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        ],
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _media.length,
                      itemBuilder: (context, index) {
                        final media = _media[index];
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
                                tag: 'journal_photo_${media.id}',
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(media.filePath),
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.image_not_supported),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            if (media.isPrimary)
                              Positioned(
                                top: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Primary',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 4,
                              right: 4,
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
                                    size: 16,
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
                                      await _deletePhoto(media.id!);
                                    }
                                  } else if (value == 'primary') {
                                    await _setPrimaryPhoto(media.id!);
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (!media.isPrimary)
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
                ],
              ),
            ),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveJournal,
                child: Text(widget.journalToEdit != null ? 'Update Entry' : 'Save Entry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
