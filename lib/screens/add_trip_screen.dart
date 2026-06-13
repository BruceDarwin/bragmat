import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/fishing_trip.dart';

class AddTripScreen extends StatefulWidget {
  final FishingTrip? tripToEdit;
  const AddTripScreen({super.key, this.tripToEdit});

  @override
  State<AddTripScreen> createState() => _AddTripScreenState();
}

class _AddTripScreenState extends State<AddTripScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    if (widget.tripToEdit != null) {
      _nameController.text = widget.tripToEdit!.name;
      _locationController.text = widget.tripToEdit!.location ?? '';
      _notesController.text = widget.tripToEdit!.notes ?? '';
      _startDate = widget.tripToEdit!.startDate;
      _endDate = widget.tripToEdit!.endDate;
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        // Ensure end date is not before start date
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  void _saveTrip() async {
    final name = _nameController.text.trim();
    final location = _locationController.text.trim();
    final notes = _notesController.text.trim();

    if (name.isEmpty) {
      return;
    }

    if (_startDate == null) {
      return;
    }

    if (widget.tripToEdit != null) {
      final updatedTrip = FishingTrip(
        id: widget.tripToEdit!.id,
        name: name,
        startDate: _startDate!,
        endDate: _endDate,
        location: location.isEmpty ? null : location,
        notes: notes.isEmpty ? null : notes,
        createdAt: widget.tripToEdit!.createdAt,
      );
      await DatabaseHelper.instance.updateFishingTrip(updatedTrip);
    } else {
      final newTrip = FishingTrip(
        name: name,
        startDate: _startDate!,
        endDate: _endDate,
        location: location.isEmpty ? null : location,
        notes: notes.isEmpty ? null : notes,
      );
      await DatabaseHelper.instance.insertFishingTrip(newTrip);
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tripToEdit != null ? 'Edit Trip' : 'Add Trip'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Trip Name',
                hintText: 'e.g., Dundee Beach June 2026',
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              title: const Text('Start Date'),
              subtitle: Text(
                _startDate != null
                    ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'
                    : 'Not set',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectStartDate,
            ),
            const SizedBox(height: 24),
            ListTile(
              title: const Text('End Date (optional)'),
              subtitle: Text(
                _endDate != null
                    ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                    : 'Not set',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectEndDate,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'e.g., Dundee Beach, NT',
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Any additional details...',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saveTrip,
              child: Text(widget.tripToEdit != null ? 'Update Trip' : 'Save Trip'),
            ),
          ],
        ),
      ),
    );
  }
}
