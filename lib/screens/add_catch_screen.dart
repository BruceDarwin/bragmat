import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';

class AddCatchScreen extends StatefulWidget {
  final Catch? catchToEdit;
  final VoidCallback? onCatchSaved;
  const AddCatchScreen({super.key, this.catchToEdit, this.onCatchSaved});

  @override
  State<AddCatchScreen> createState() => _AddCatchScreenState();
}

class _AddCatchScreenState extends State<AddCatchScreen> {
  final _fishTypeController = TextEditingController();
  final _lengthController = TextEditingController();
  final _notesController = TextEditingController();
  final _locationController = TextEditingController();
  DateTime? _dateCaught;
  String? _imagePath;
  DateTime? _photoDateTime;
  double? _latitude;
  double? _longitude;
  String? _selectedFishType;
  List<String> _fishTypes = [];

  @override
  void initState() {
    super.initState();
    _loadFishTypes();
    if (widget.catchToEdit != null) {
      _fishTypeController.text = widget.catchToEdit!.fishType;
      _lengthController.text = widget.catchToEdit!.lengthCm.toString();
      _notesController.text = widget.catchToEdit!.notes ?? '';
      _locationController.text = widget.catchToEdit!.location ?? '';
      _dateCaught = widget.catchToEdit!.dateCaught;
      _imagePath = widget.catchToEdit!.imagePath;
      _photoDateTime = widget.catchToEdit!.photoDateTime;
      _latitude = widget.catchToEdit!.latitude;
      _longitude = widget.catchToEdit!.longitude;
    }
  }

  Future<void> _loadFishTypes() async {
    final types = await DatabaseHelper.instance.getFishTypes();
    setState(() {
      // Remove duplicates and trim whitespace
      final uniqueTypes = types.map((t) => t.trim()).toSet().toList();
      _fishTypes = uniqueTypes;

      // If editing and current fish type is not in list, add it once
      if (widget.catchToEdit != null) {
        final currentFishType = widget.catchToEdit!.fishType.trim();
        if (currentFishType.isNotEmpty &&
            !_fishTypes.contains(currentFishType)) {
          _fishTypes = [..._fishTypes, currentFishType];
        }
        // Set selected fish type to the trimmed value
        _selectedFishType = currentFishType.isEmpty ? null : currentFishType;
      }
    });
  }

  Future<void> _showAddFishTypeDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Fish Type'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Fish Type Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final trimmedResult = result.trim();
      // Check if already exists in current list
      if (!_fishTypes.contains(trimmedResult)) {
        final inserted = await DatabaseHelper.instance.insertFishType(trimmedResult);
        if (inserted != -1) {
          await _loadFishTypes();
          setState(() {
            _selectedFishType = trimmedResult;
          });
        }
      } else {
        // Already exists, just select it
        setState(() {
          _selectedFishType = trimmedResult;
        });
      }
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

          debugPrint('Extracted GPS - Latitude: $latitude, Longitude: $longitude');
        }
      } else {
        debugPrint('No GPS data found in photo EXIF');
      }
    } catch (e) {
      debugPrint('Error reading EXIF data: $e');
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
    final fishType = _selectedFishType ?? _fishTypeController.text;
    final length = int.tryParse(_lengthController.text) ?? 0;
    final notes = _notesController.text;
    final location = _locationController.text.trim();

    if (fishType.isEmpty) {
      return;
    }

    Catch? savedCatch;

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
        location: location.isEmpty ? null : location,
      );
      await DatabaseHelper.instance.updateCatch(updatedCatch);
      savedCatch = updatedCatch;
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
        location: location.isEmpty ? null : location,
      );
      await DatabaseHelper.instance.insertCatch(newCatch);
      savedCatch = newCatch;
    }

    if (!mounted) return;

    // Only pop if editing (catchToEdit != null)
    // When adding from bottom nav, use callback to switch to My Catches
    if (widget.catchToEdit != null) {
      Navigator.pop(context, savedCatch);
    } else {
      // Call callback to switch to My Catches tab
      widget.onCatchSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.catchToEdit != null ? 'Edit Catch' : 'Add Catch'),
        automaticallyImplyLeading: widget.catchToEdit != null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFishTypes,
            tooltip: 'Refresh Fish Types',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library),
              label: Text(_imagePath != null ? 'Change Photo' : 'Add Photo'),
            ),
            const SizedBox(height: 24),
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
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              value: _selectedFishType,
              decoration: const InputDecoration(labelText: 'Fish Type'),
              items: [
                ..._fishTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }),
                const DropdownMenuItem(
                  value: 'add_new',
                  child: Text('+ Add New Fish Type'),
                ),
              ],
              onChanged: (value) {
                if (value == 'add_new') {
                  _showAddFishTypeDialog();
                } else {
                  setState(() {
                    _selectedFishType = value;
                    _fishTypeController.text = value ?? '';
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _lengthController,
              decoration: const InputDecoration(labelText: 'Size (cm)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
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