import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';

class AddCatchScreen extends StatefulWidget {
  final Catch? catchToEdit;
  const AddCatchScreen({super.key, this.catchToEdit});

  @override
  State<AddCatchScreen> createState() => _AddCatchScreenState();
}

class _AddCatchScreenState extends State<AddCatchScreen> {
  final _fishTypeController = TextEditingController();
  final _lengthController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.catchToEdit != null) {
      _fishTypeController.text = widget.catchToEdit!.fishType;
      _lengthController.text = widget.catchToEdit!.lengthCm.toString();
      _notesController.text = widget.catchToEdit!.notes ?? '';
    }
  }

void _saveCatch() async {
  final fishType = _fishTypeController.text;
  final length = int.tryParse(_lengthController.text) ?? 0;
  final notes = _notesController.text;

  if (widget.catchToEdit != null) {
    final updatedCatch = Catch(
      id: widget.catchToEdit!.id,
      fishType: fishType,
      lengthCm: length,
      notes: notes,
      createdAt: widget.catchToEdit!.createdAt,
    );
    await DatabaseHelper.instance.updateCatch(updatedCatch);
  } else {
    final newCatch = Catch(
      fishType: fishType,
      lengthCm: length,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await DatabaseHelper.instance.insertCatch(newCatch);
  }

  if (!mounted) return;

  Navigator.pop(context);
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.catchToEdit != null ? 'Edit Catch' : 'Add Catch'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _fishTypeController,
              decoration: const InputDecoration(labelText: 'Fish Type'),
            ),
            TextField(
              controller: _lengthController,
              decoration: const InputDecoration(labelText: 'Length (cm)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveCatch,
              child: const Text('Save Catch'),
            ),
          ],
        ),
      ),
    );
  }
}