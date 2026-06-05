import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';

class AddCatchScreen extends StatefulWidget {
  const AddCatchScreen({super.key});

  @override
  State<AddCatchScreen> createState() => _AddCatchScreenState();
}

class _AddCatchScreenState extends State<AddCatchScreen> {
  final _fishTypeController = TextEditingController();
  final _lengthController = TextEditingController();
  final _notesController = TextEditingController();

void _saveCatch() async {
  final fishType = _fishTypeController.text;
  final length = int.tryParse(_lengthController.text) ?? 0;
  final notes = _notesController.text;

  final newCatch = Catch(
    fishType: fishType,
    lengthCm: length,
    notes: notes,
    createdAt: DateTime.now(),
  );

  await DatabaseHelper.instance.insertCatch(newCatch);

  if (!mounted) return; // 👈 important

  Navigator.pop(context);
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Catch')),
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