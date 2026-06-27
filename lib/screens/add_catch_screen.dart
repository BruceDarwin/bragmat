import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import 'package:geolocator/geolocator.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';
import '../models/catch_media.dart';
import '../models/fishing_trip.dart';
import '../models/favourite_spot.dart';
import '../services/current_trip_service.dart';
import '../services/preferences_service.dart';
import 'location_picker_screen.dart';

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
  String? _coordinateSource;
  int? _selectedFavouriteSpotId;
  List<FavouriteSpot> _favouriteSpots = [];
  
  // Change tracking
  bool _hasUnsavedChanges = false;
  late Catch? _originalCatch;

  @override
  void initState() {
    super.initState();
    _loadFishTypes();
    _loadFishingBuddies();
    _loadFishingTrips();
    _loadFavouriteSpots();
    // Only check for lost data when adding a new catch, not when editing
    // Lost data recovery is for when the app is killed during a new catch creation
    if (widget.catchToEdit == null) {
      _retrieveLostData();
    }
    if (widget.catchToEdit != null) {
      _originalCatch = widget.catchToEdit;
      _loadMediaForCatch();
      _fishTypeController.text = widget.catchToEdit!.fishType;
      _lengthController.text = widget.catchToEdit!.lengthCm.toString();
      _notesController.text = widget.catchToEdit!.notes ?? '';
      _locationController.text = widget.catchToEdit!.location ?? '';
      _dateCaught = widget.catchToEdit!.dateCaught;
      _selectedTripId = widget.catchToEdit!.tripId;
      _latitudeController.text = widget.catchToEdit!.latitude?.toString() ?? '';
      _longitudeController.text = widget.catchToEdit!.longitude?.toString() ?? '';
      _coordinateSource = widget.catchToEdit!.coordinateSource;
      _selectedFishingBuddyId = widget.catchToEdit!.fishingBuddyId;
    } else {
      // For new catches, pre-select the current trip if set
      _loadCurrentTrip();
      // Set date caught to current date and time
      _dateCaught = DateTime.now();
    }
    
    // Add text change listeners
    _fishTypeController.addListener(_onFieldChanged);
    _lengthController.addListener(_onFieldChanged);
    _notesController.addListener(_onFieldChanged);
    _locationController.addListener(_onFieldChanged);
    _latitudeController.addListener(_onFieldChanged);
    _longitudeController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _fishTypeController.removeListener(_onFieldChanged);
    _lengthController.removeListener(_onFieldChanged);
    _notesController.removeListener(_onFieldChanged);
    _locationController.removeListener(_onFieldChanged);
    _latitudeController.removeListener(_onFieldChanged);
    _longitudeController.removeListener(_onFieldChanged);
    _fishTypeController.dispose();
    _lengthController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  bool _hasChanges() {
    // For new catches, any data entry counts as changes
    if (widget.catchToEdit == null) {
      return _hasUnsavedChanges;
    }
    
    // For editing, compare with original
    if (_originalCatch == null) return false;
    
    final original = _originalCatch!;
    final currentFishType = _selectedFishType ?? _fishTypeController.text;
    final currentLength = int.tryParse(_lengthController.text) ?? 0;
    final currentNotes = _notesController.text;
    final currentLocation = _locationController.text.trim();
    final currentLatitude = double.tryParse(_latitudeController.text);
    final currentLongitude = double.tryParse(_longitudeController.text);
    
    return currentFishType != original.fishType ||
           currentLength != original.lengthCm ||
           currentNotes != (original.notes ?? '') ||
           currentLocation != (original.location ?? '') ||
           currentLatitude != original.latitude ||
           currentLongitude != original.longitude ||
           _dateCaught != original.dateCaught ||
           _selectedTripId != original.tripId ||
           _selectedFishingBuddyId != original.fishingBuddyId ||
           _coordinateSource != original.coordinateSource ||
           _mediaItems.length != _getOriginalMediaCount();
  }

  int _getOriginalMediaCount() {
    // This is a simplified check - in practice we'd need to load original media count
    // For now, we'll use the _hasUnsavedChanges flag for media changes
    return _mediaItems.length;
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges()) {
      return true;
    }
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Do you want to discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  Future<void> _applyFishTypePreference() async {
    debugPrint('=== Applying Fish Type Preference ===');
    debugPrint('Editing existing catch: ${widget.catchToEdit != null}');
    debugPrint('Current fish types loaded: $_fishTypes');
    
    final mode = await PreferencesService.getFishTypeSelectionMode();
    debugPrint('Fish type selection mode: $mode');
    
    if (mode == FishTypeSelectionMode.defaultFishType) {
      final defaultFishType = await PreferencesService.getDefaultFishType();
      debugPrint('Default fish type from preferences: $defaultFishType');
      debugPrint('Default fish type exists in list: ${_fishTypes.contains(defaultFishType ?? "")}');
      
      if (defaultFishType != null && _fishTypes.contains(defaultFishType)) {
        debugPrint('Setting selected fish type to: $defaultFishType');
        setState(() {
          _selectedFishType = defaultFishType;
        });
        debugPrint('Selected fish type after setState: $_selectedFishType');
      } else {
        debugPrint('NOT setting default fish type - either null or not in list');
      }
    } else if (mode == FishTypeSelectionMode.rememberLastUsed) {
      final lastUsedFishType = await PreferencesService.getLastUsedFishType();
      debugPrint('Last used fish type from preferences: $lastUsedFishType');
      debugPrint('Last used fish type exists in list: ${_fishTypes.contains(lastUsedFishType ?? "")}');
      
      if (lastUsedFishType != null && _fishTypes.contains(lastUsedFishType)) {
        debugPrint('Setting selected fish type to: $lastUsedFishType');
        setState(() {
          _selectedFishType = lastUsedFishType;
        });
        debugPrint('Selected fish type after setState: $_selectedFishType');
      } else {
        debugPrint('NOT setting last used fish type - either null or not in list');
      }
    } else {
      debugPrint('No Default mode - leaving fish type unselected');
    }
    debugPrint('=== End Applying Fish Type Preference ===');
  }

  Future<void> _retrieveLostData() async {
    debugPrint('=== Checking for lost image picker data ===');
    final picker = ImagePicker();
    final lostData = await picker.retrieveLostData();
    if (lostData != null) {
      debugPrint('Lost data found:');
      debugPrint('  isEmpty: ${lostData.isEmpty}');
      debugPrint('  file: ${lostData.file}');
      debugPrint('  files: ${lostData.files}');
      
      if (!lostData.isEmpty && lostData.file != null) {
        debugPrint('Processing lost image: ${lostData.file!.path}');
        final file = File(lostData.file!.path);
        await _processPickedFile(file, 'lost_data');
      } else if (!lostData.isEmpty && lostData.files != null && lostData.files!.isNotEmpty) {
        debugPrint('Processing ${lostData.files!.length} lost images');
        for (final lostFile in lostData.files!) {
          final file = File(lostFile.path);
          await _processPickedFile(file, 'lost_data');
        }
      } else {
        debugPrint('No lost data to recover');
      }
    } else {
      debugPrint('No lost data available');
    }
    debugPrint('=== End checking for lost data ===');
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

  Future<void> _loadFavouriteSpots() async {
    final spots = await DatabaseHelper.instance.getFavouriteSpots();
    if (mounted) {
      setState(() {
        _favouriteSpots = spots;
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
    
    // Apply fish type preference after fish types are loaded (only for new catches)
    // Use a callback to ensure setState has completed
    if (widget.catchToEdit == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _applyFishTypePreference();
      });
    }
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
        // Preserve the time from the existing dateCaught, or use current time
        final existingTime = _dateCaught;
        _dateCaught = DateTime(
          picked.year,
          picked.month,
          picked.day,
          existingTime?.hour ?? DateTime.now().hour,
          existingTime?.minute ?? DateTime.now().minute,
        );
        _onFieldChanged();
      });
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateCaught ?? DateTime.now()),
    );
    if (picked != null) {
      setState(() {
        // Preserve the date from the existing dateCaught, or use current date
        final existingDate = _dateCaught;
        _dateCaught = DateTime(
          existingDate?.year ?? DateTime.now().year,
          existingDate?.month ?? DateTime.now().month,
          existingDate?.day ?? DateTime.now().day,
          picked.hour,
          picked.minute,
        );
        _onFieldChanged();
      });
    }
  }

  Future<void> _pickImage() async {
    debugPrint('=== Add Photo Button Tapped ===');
    debugPrint('Current media items count: ${_mediaItems.length}');
    debugPrint('Mounted: $mounted');
    
    try {
      debugPrint('Creating ImagePicker instance');
      final picker = ImagePicker();
      debugPrint('Opening gallery picker');
      
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85, // Compress to reduce memory pressure
        maxWidth: 1920, // Limit resolution to reduce memory
        maxHeight: 1080,
      );
      
      debugPrint('Gallery picker returned');
      debugPrint('Picked file is null: ${pickedFile == null}');
      
      if (pickedFile != null) {
        debugPrint('Picked file path: ${pickedFile.path}');
        debugPrint('Processing picked file');
        final file = File(pickedFile.path);
        await _processPickedFile(file, 'gallery');
        debugPrint('File processing complete');
      } else {
        debugPrint('User cancelled gallery selection');
      }
      
      debugPrint('After gallery pick - media items count: ${_mediaItems.length}');
      debugPrint('After gallery pick - mounted: $mounted');
    } catch (e, stackTrace) {
      debugPrint('ERROR in _pickImage: $e');
      debugPrint('Stack trace: $stackTrace');
    }
    
    debugPrint('=== End _pickImage ===');
  }

  Future<void> _takePhoto() async {
    debugPrint('=== Photo Source: Camera ===');
    debugPrint('Current media items count: ${_mediaItems.length}');
    debugPrint('Mounted: $mounted');
    debugPrint('Editing existing catch: ${widget.catchToEdit != null}');
    if (widget.catchToEdit != null) {
      debugPrint('Existing catch id: ${widget.catchToEdit!.id}');
    }
    
    final picker = ImagePicker();
    debugPrint('About to call picker.pickImage');
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85, // Compress to reduce memory pressure
      maxWidth: 1920, // Limit resolution to reduce memory
      maxHeight: 1080,
    );
    debugPrint('Camera pick returned: ${pickedFile != null}');
    
    if (pickedFile != null) {
      debugPrint('ORIGINAL Image path from image_picker: ${pickedFile.path}');
      debugPrint('Mounted after camera pick: $mounted');
      final file = File(pickedFile.path);
      await _processPickedFile(file, 'camera');
    } else {
      debugPrint('Camera pick returned null (user cancelled or error)');
    }
    
    debugPrint('After camera pick - media items count: ${_mediaItems.length}');
    debugPrint('After camera pick - mounted: $mounted');
  }

  Future<void> _processPickedFile(File file, String source) async {
    debugPrint('=== Processing Picked File ===');
    debugPrint('Source: $source');
    debugPrint('Editing existing catch: ${widget.catchToEdit != null}');
    if (widget.catchToEdit != null) {
      debugPrint('Existing catch id: ${widget.catchToEdit!.id}');
    }
    
    final originalPath = file.path;
    debugPrint('ORIGINAL path: $originalPath');
    
    final fileExists = await file.exists();
    final fileSize = fileExists ? await file.length() : 0;
    
    debugPrint('File exists: $fileExists');
    debugPrint('File size: $fileSize bytes');
    
    // Extract GPS data from ORIGINAL file immediately
    debugPrint('=== Extracting GPS from ORIGINAL file ===');
    final gpsData = await _extractGpsData(originalPath);
    final latitude = gpsData['latitude'];
    final longitude = gpsData['longitude'];
    debugPrint('GPS from ORIGINAL: lat=$latitude, lon=$longitude');
    
    final photoDateTime = DateTime.now();
    
    debugPrint('Before setState - media items count: ${_mediaItems.length}');
    debugPrint('Before setState - mounted: $mounted');
    
    if (mounted) {
      setState(() {
        // If this is the first photo, mark it as primary
        final role = _mediaItems.isEmpty ? 'primary' : 'other';
        _mediaItems.add(CatchMedia(
          catchId: 0, // Will be set when saving
          filePath: originalPath,
          mediaType: 'photo',
          role: role,
          dateTaken: photoDateTime,
          latitude: latitude,
          longitude: longitude,
        ));
        
        debugPrint('After adding media - media items count: ${_mediaItems.length}');
        debugPrint('Stored path in CatchMedia: $originalPath');
        debugPrint('Editing existing catch: ${widget.catchToEdit != null}');
        
        // Auto-populate latitude/longitude fields if GPS data found
        if (latitude != null && longitude != null) {
          _latitudeController.text = latitude.toString();
          _longitudeController.text = longitude.toString();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS coordinates found in photo'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No GPS coordinates found in photo'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
      
      debugPrint('After setState - media items count: ${_mediaItems.length}');
    } else {
      debugPrint('ERROR: Widget not mounted, cannot setState');
    }
    
    debugPrint('=== End Processing Picked File ===');
  }

  Future<Map<String, double?>> _extractGpsData(String imagePath) async {
    double? latitude;
    double? longitude;
    
    debugPrint('=== EXIF GPS Extraction ===');
    debugPrint('Image path: $imagePath');
    
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final data = await readExifFromBytes(bytes);

      debugPrint('EXIF data keys: ${data.keys.toList()}');
      
      // Log all GPS-related tags
      final gpsTags = data.entries.where((e) => e.key.startsWith('GPS')).toList();
      debugPrint('GPS tags found: ${gpsTags.length}');
      for (final tag in gpsTags) {
        debugPrint('  ${tag.key}: ${tag.value}');
      }

      if (data.containsKey('GPSLatitude') && data.containsKey('GPSLongitude')) {
        final lat = data['GPSLatitude'];
        final latRef = data['GPSLatitudeRef'];
        final lon = data['GPSLongitude'];
        final lonRef = data['GPSLongitudeRef'];

        debugPrint('GPSLatitude: $lat');
        debugPrint('GPSLatitudeRef: $latRef');
        debugPrint('GPSLongitude: $lon');
        debugPrint('GPSLongitudeRef: $lonRef');

        if (lat != null && latRef != null && lon != null && lonRef != null) {
          latitude = _convertToDecimalDegrees(lat, latRef);
          longitude = _convertToDecimalDegrees(lon, lonRef);
          debugPrint('Extracted coordinates: $latitude, $longitude');
        } else {
          debugPrint('GPS data incomplete');
        }
      } else {
        debugPrint('No GPSLatitude or GPSLongitude found in EXIF');
      }
    } catch (e) {
      debugPrint('Error reading EXIF data: $e');
    }
    
    debugPrint('Final GPS data: latitude=$latitude, longitude=$longitude');
    debugPrint('=== End EXIF GPS Extraction ===');
    
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

  Future<void> _getCurrentLocation() async {
    debugPrint('=== Getting Current Location ===');
    
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions are permanently denied');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission permanently denied')),
        );
      }
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      debugPrint('Location captured: ${position.latitude}, ${position.longitude}');
      
      if (mounted) {
        setState(() {
          _latitudeController.text = position.latitude.toString();
          _longitudeController.text = position.longitude.toString();
          _coordinateSource = 'Device GPS';
          _selectedFavouriteSpotId = null; // Clear favourite spot selection when using current location
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location captured')),
        );
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to get current location')),
        );
      }
    }
    
    debugPrint('=== End Getting Current Location ===');
  }

  Future<void> _pickLocationOnMap() async {
    final currentLat = double.tryParse(_latitudeController.text);
    final currentLng = double.tryParse(_longitudeController.text);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLatitude: currentLat,
          initialLongitude: currentLng,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _latitudeController.text = result['latitude'].toString();
        _longitudeController.text = result['longitude'].toString();
        _coordinateSource = 'Map Selected';
        _selectedFavouriteSpotId = null; // Clear favourite spot selection when manually picking location
      });
    }
  }

  void _onFavouriteSpotSelected(FavouriteSpot? spot) {
    if (spot != null) {
      setState(() {
        _selectedFavouriteSpotId = spot.id;
        _locationController.text = spot.name;
        _latitudeController.text = spot.latitude.toString();
        _longitudeController.text = spot.longitude.toString();
        _coordinateSource = 'Favourite Spot';
      });
    } else {
      setState(() {
        _selectedFavouriteSpotId = null;
      });
    }
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
        debugPrint('Media items to save: ${_mediaItems.length}');
        for (int i = 0; i < _mediaItems.length; i++) {
          debugPrint('  Media item $i: path=${_mediaItems[i].filePath}, role=${_mediaItems[i].role}');
        }
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
          coordinateSource: _coordinateSource,
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
          final insertedId = await DatabaseHelper.instance.insertCatchMedia(mediaToInsert);
          debugPrint('Media inserted with id: $insertedId');
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
          coordinateSource: _coordinateSource,
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
      
      // Remember last used fish type
      await PreferencesService.setLastUsedFishType(fishType);
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
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
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
          padding: const EdgeInsets.all(16).copyWith(bottom: 100),
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
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_mediaItems.isEmpty ? 'Take Photo' : 'Take Photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library),
                    label: Text(_mediaItems.isEmpty ? 'Add Photo' : 'Add Photo'),
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
            ListTile(
              title: const Text('Time Caught'),
              subtitle: Text(
                _dateCaught != null
                    ? '${_dateCaught!.hour.toString().padLeft(2, '0')}:${_dateCaught!.minute.toString().padLeft(2, '0')}'
                    : 'Not set',
              ),
              trailing: const Icon(Icons.access_time),
              onTap: _selectTime,
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
                  _onFieldChanged();
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
                  _onFieldChanged();
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
                    _onFieldChanged();
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
            const SizedBox(height: 8),
            if (_favouriteSpots.isNotEmpty)
              DropdownButtonFormField<int>(
                value: _selectedFavouriteSpotId,
                decoration: const InputDecoration(
                  labelText: 'Favourite Spot (optional)',
                  prefixIcon: Icon(Icons.place),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ..._favouriteSpots.map((spot) {
                    return DropdownMenuItem(
                      value: spot.id,
                      child: Text(spot.name),
                    );
                  }),
                ],
                onChanged: (value) {
                  final spot = value != null
                      ? _favouriteSpots.firstWhere((s) => s.id == value)
                      : null;
                  _onFavouriteSpotSelected(spot);
                },
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _getCurrentLocation,
                    icon: const Icon(Icons.location_on),
                    label: const Text('Use Current Location'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickLocationOnMap,
                    icon: const Icon(Icons.map),
                    label: const Text('Pick on Map'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
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
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saveCatch,
              child: Text(
                widget.catchToEdit != null ? 'Save Changes' : 'Save Catch',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}