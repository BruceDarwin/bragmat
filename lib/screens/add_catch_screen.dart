import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
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
  DateTime? _dateCaught;
  String? _imagePath;
  DateTime? _photoDateTime;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    if (widget.catchToEdit != null) {
      _fishTypeController.text = widget.catchToEdit!.fishType;
      _lengthController.text = widget.catchToEdit!.lengthCm.toString();
      _notesController.text = widget.catchToEdit!.notes ?? '';
      _dateCaught = widget.catchToEdit!.dateCaught;
      _imagePath = widget.catchToEdit!.imagePath;
      _photoDateTime = widget.catchToEdit!.photoDateTime;
      _latitude = widget.catchToEdit!.latitude;
      _longitude = widget.catchToEdit!.longitude;
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateCaught ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _dateCaught = picked;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imagePath = pickedFile.path;
        _photoDateTime = DateTime.now();
        _latitude = null;
        _longitude = null;
      });
      await _extractGpsData(pickedFile.path);
    }
  }

  Future<void> _extractGpsData(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final data = await readExifFromBytes(bytes);

      if (data.containsKey('GPSLatitude') && data.containsKey('GPSLongitude')) {
        final lat = data['GPSLatitude'];
        final latRef = data['GPSLatitudeRef'];
        final lon = data['GPSLongitude'];
        final lonRef = data['GPSLongitudeRef'];

        if (lat != null && latRef != null && lon != null && lonRef != null) {
          final latitude = _convertToDecimalDegrees(lat, latRef);
          final longitude = _convertToDecimalDegrees(lon, lonRef);

          setState(() {
            _latitude = latitude;
            _longitude = longitude;
          });
        }
      }
    } catch (e) {
      // If EXIF reading fails, continue without GPS data
    }
  }

  double _convertToDecimalDegrees(dynamic value, dynamic ref) {
    if (value is! List || value.length != 3) return 0.0;

    final degrees = value[0] is num ? value[0].toDouble() : 0.0;
    final minutes = value[1] is num ? value[1].toDouble() : 0.0;
    final seconds = value[2] is num ? value[2].toDouble() : 0.0;

    final decimal = degrees + (minutes / 60) + (seconds / 3600);

    if (ref == 'S' || ref == 'W') {
      return -decimal;
    }
    return decimal;
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
      dateCaught: _dateCaught,
      imagePath: _imagePath,
      photoDateTime: _photoDateTime,
      latitude: _latitude,
      longitude: _longitude,
    );
    await DatabaseHelper.instance.updateCatch(updatedCatch);
  } else {
    final newCatch = Catch(
      fishType: fishType,
      lengthCm: length,
      notes: notes,
      createdAt: DateTime.now(),
      dateCaught: _dateCaught,
      imagePath: _imagePath,
      photoDateTime: _photoDateTime,
      latitude: _latitude,
      longitude: _longitude,
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
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Date Caught'),
              subtitle: Text(
                _dateCaught != null
                    ? '${_dateCaught!.day}/${_dateCaught!.month}/${_dateCaught!.year}'
                    : 'Not set',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
            ),
            const SizedBox(height: 16),
            if (_imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_imagePath!),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library),
              label: const Text('Add Photo'),
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