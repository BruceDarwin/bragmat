import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/trip_journal.dart';

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
    } else {
      _journalDateTime = DateTime.now();
      _journalType = 'general';
      _titleController = TextEditingController();
      _entryTextController = TextEditingController();
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

    if (widget.journalToEdit != null) {
      await DatabaseHelper.instance.updateTripJournal(journal);
    } else {
      await DatabaseHelper.instance.insertTripJournal(journal);
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
