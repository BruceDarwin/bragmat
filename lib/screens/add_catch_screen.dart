import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';
import '../models/catch_media.dart';
import '../models/fishing_trip.dart';
import '../services/current_trip_service.dart';

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
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  DateTime? _dateCaught;
  List<CatchMedia> _mediaItems = [];
  String? _selectedFishType;
  List<String> _fishTypes = [];
  int? _selectedFishingBuddyId;
  List<FishingBuddy> _fishingBuddies = [];
  int? _selectedTripId;
  List<FishingTrip> _fishingTrips = [];

  @override
  void initState() {
    super.initState();
    _loadFishTypes();
    _loadFishingBuddies();
    _loadFishingTrips();
    if (widget.catchToEdit != null) {
      _loadMediaForCatch();
      _fishTypeController.text = widget.catchToEdit!.fishType;
      _lengthController.text = widget.catchToEdit!.lengthCm.toString();
      _notesController.text = widget.catchToEdit!.notes ?? '';
      _locationController.text = widget.catchToEdit!.location ?? '';
      _dateCaught = widget.catchToEdit!.dateCaught;
      _selectedTripId = widget.catchToEdit!.tripId;
      _latitudeController.text = widget.catchToEdit!.latitude?.toString() ?? '';
      _longitudeController.text = widget.catchToEdit!.longitude?.toString() ?? '';
    } else {
      // For new catches, pre-select the current trip if set
      _loadCurrentTrip();
    }
  }

  Future<void> _loadCurrentTrip() async {
    final currentTripId = await CurrentTripService.getCurrentTripId();
    if (mounted) {
      setState(() {
        _selectedTripId = currentTripId;
      });
    }
  }

  Future<void> _loadMediaForCatch() async {
    if (widget.catchToEdit?.id != null) {
      final media = await DatabaseHelper.instance.getMediaForCatch(widget.catchToEdit!.id!);
      if (mounted) {
        setState(() {
          _mediaItems = media;
        });
      }
    }
  }

  Future<void> _loadFishingTrips() async {
    final trips = await DatabaseHelper.instance.getFishingTrips();
    if (mounted) {
      setState(() {
        _fishingTrips = trips;
      });
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

  Future<void> _loadFishingBuddies() async {
    final buddies = await DatabaseHelper.instance.getFishingBuddies();
    final meBuddy = await DatabaseHelper.instance.getMeFishingBuddy();
    setState(() {
      _fishingBuddies = buddies;
      // Default to "Me" only if "Me" is in the list
      if (_selectedFishingBuddyId == null && meBuddy != null) {
        final meInList = buddies.any((b) => b.id == meBuddy.id);
        if (meInList) {
          _selectedFishingBuddyId = meBuddy.id;
        }
      }
      // If editing, set the selected fishing buddy only if it's in the list
      if (widget.catchToEdit != null && widget.catchToEdit!.fishingBuddyId != null) {
        final buddy = buddies.firstWhere(
          (b) => b.id == widget.catchToEdit!.fishingBuddyId,
          orElse: () => meBuddy!,
        );
        // Only set if the buddy is actually in the list
        if (buddies.any((b) => b.id == buddy.id)) {
          _selectedFishingBuddyId = buddy.id;
        } else {
          _selectedFishingBuddyId = null;
        }
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
      await _processPickedImage(pickedFile);
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      await _processPickedImage(pickedFile);
    }
  }

  Future<void> _processPickedImage(XFile pickedFile) async {
    final photoDateTime = DateTime.now();
    double? latitude;
    double? longitude;
    
    // Extract GPS data
    final gpsData = await _extractGpsData(pickedFile.path);
    latitude = gpsData['latitude'];
    longitude = gpsData['longitude'];
    
    setState(() {
      // If this is the first photo, mark it as primary
      final role = _mediaItems.isEmpty ? 'primary' : 'other';
      _mediaItems.add(CatchMedia(
        catchId: 0, // Will be set when saving
        filePath: pickedFile.path,
        mediaType: 'photo',
        role: role,
        dateTaken: photoDateTime,
        latitude: latitude,
        longitude: longitude,
      ));
    });
  }

  Future<Map<String, double?>> _extractGpsData(String imagePath) async {
    double? latitude;
    double? longitude;
    
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
          latitude = _convertToDecimalDegrees(lat, latRef);
          longitude = _convertToDecimalDegrees(lon, lonRef);
        }
      }
    } catch (e) {
      // If EXIF reading fails, continue without GPS data
    }
    
    return {'latitude': latitude, 'longitude': longitude};
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
    debugPrint('=== Save Catch Button Tapped ===');
    
    final fishType = _selectedFishType ?? _fishTypeController.text;
    final length = int.tryParse(_lengthController.text) ?? 0;
    final notes = _notesController.text;
    final location = _locationController.text.trim();
    final latitude = double.tryParse(_latitudeController.text);
    final longitude = double.tryParse(_longitudeController.text);

    debugPrint('Form values:');
    debugPrint('  fishType: $fishType');
    debugPrint('  length: $length');
    debugPrint('  notes: $notes');
    debugPrint('  location: $location');
    debugPrint('  latitude: $latitude');
    debugPrint('  longitude: $longitude');
    debugPrint('  selectedTripId: $_selectedTripId');
    debugPrint('  selectedFishingBuddyId: $_selectedFishingBuddyId');
    debugPrint('  dateCaught: $_dateCaught');
    debugPrint('  mediaItems count: ${_mediaItems.length}');
    if (_mediaItems.isNotEmpty) {
      debugPrint('  first media path: ${_mediaItems.first.filePath}');
    }

    if (fishType.isEmpty) {
      debugPrint('ERROR: fishType is empty, returning');
      return;
    }

    Catch? savedCatch;

    try {
      if (widget.catchToEdit != null) {
        debugPrint('Editing existing catch: ${widget.catchToEdit!.id}');
        final updatedCatch = Catch(
          id: widget.catchToEdit!.id,
          fishType: fishType,
          lengthCm: length,
          notes: notes,
          createdAt: widget.catchToEdit!.createdAt,
          dateCaught: _dateCaught,
          location: location.isEmpty ? null : location,
          fishingBuddyId: _selectedFishingBuddyId,
          tripId: _selectedTripId,
          latitude: latitude,
          longitude: longitude,
        );
        debugPrint('Catch object before update: ${updatedCatch.toMap()}');
        await DatabaseHelper.instance.updateCatch(updatedCatch);
        debugPrint('Update successful');
        savedCatch = updatedCatch;
        
        // Delete existing media and re-add
        debugPrint('Deleting existing media for catch ${widget.catchToEdit!.id}');
        await DatabaseHelper.instance.deleteAllMediaForCatch(widget.catchToEdit!.id!);
        debugPrint('Media deleted, adding ${_mediaItems.length} media items');
        for (final media in _mediaItems) {
          final mediaToInsert = media.copyWith(catchId: widget.catchToEdit!.id);
          debugPrint('Inserting media: ${mediaToInsert.toMap()}');
          await DatabaseHelper.instance.insertCatchMedia(mediaToInsert);
        }
        debugPrint('All media inserted');
      } else {
        debugPrint('Creating new catch');
        final newCatch = Catch(
          fishType: fishType,
          lengthCm: length,
          notes: notes,
          createdAt: DateTime.now(),
          dateCaught: _dateCaught,
          location: location.isEmpty ? null : location,
          fishingBuddyId: _selectedFishingBuddyId,
          tripId: _selectedTripId,
          latitude: latitude,
          longitude: longitude,
        );
        debugPrint('Catch object before insert: ${newCatch.toMap()}');
        final catchId = await DatabaseHelper.instance.insertCatch(newCatch);
        debugPrint('Insert successful, catchId: $catchId');
        savedCatch = newCatch.copyWith(id: catchId);
        
        // Save media items with the new catch ID
        debugPrint('Adding ${_mediaItems.length} media items to catch $catchId');
        for (final media in _mediaItems) {
          final mediaToInsert = media.copyWith(catchId: catchId);
          debugPrint('Inserting media: ${mediaToInsert.toMap()}');
          await DatabaseHelper.instance.insertCatchMedia(mediaToInsert);
        }
        debugPrint('All media inserted');
      }
    } catch (e, stackTrace) {
      debugPrint('ERROR saving catch: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving catch: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    debugPrint('Save successful, navigating away');

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
            if (_mediaItems.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _mediaItems.length,
                itemBuilder: (context, index) {
                  final media = _mediaItems[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(media.filePath),
                          height: 100,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (media.role == 'primary')
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
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _mediaItems.removeAt(index);
                              // If we removed the primary, set the first remaining as primary
                              if (media.role == 'primary' && _mediaItems.isNotEmpty) {
                                _mediaItems[0] = _mediaItems[0].copyWith(role: 'primary');
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library),
                    label: Text(_mediaItems.isEmpty ? 'Add Photo' : 'Add Photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_mediaItems.isEmpty ? 'Take Photo' : 'Take Photo'),
                  ),
                ),
              ],
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
            DropdownButtonFormField<int>(
              initialValue: _selectedTripId,
              decoration: const InputDecoration(labelText: 'Fishing Trip'),
              items: _fishingTrips.isEmpty
                  ? []
                  : _fishingTrips.map((trip) {
                      return DropdownMenuItem(
                        value: trip.id,
                        child: Text(trip.name),
                      );
                    }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedTripId = value;
                });
              },
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<int>(
              initialValue: _selectedFishingBuddyId,
              decoration: const InputDecoration(labelText: 'Fishing Buddy'),
              items: _fishingBuddies.isEmpty
                  ? []
                  : _fishingBuddies.map((buddy) {
                      return DropdownMenuItem(
                        value: buddy.id,
                        child: Text(buddy.name),
                      );
                    }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedFishingBuddyId = value;
                });
              },
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _selectedFishType,
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latitudeController,
                    decoration: const InputDecoration(
                      labelText: 'Latitude (optional)',
                      hintText: 'e.g., -33.8688',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _longitudeController,
                    decoration: const InputDecoration(
                      labelText: 'Longitude (optional)',
                      hintText: 'e.g., 151.2093',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  ),
                ),
              ],
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