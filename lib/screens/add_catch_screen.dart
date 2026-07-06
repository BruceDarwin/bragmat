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
import '../models/environmental_condition.dart';
import '../models/lure.dart';
import '../models/bait.dart';
import '../services/current_trip_service.dart';
import '../services/preferences_service.dart';
import '../services/environmental_conditions_service.dart';
import '../helpers/tide_context_helper.dart';
import '../widgets/bragmat_section_card.dart';
import '../widgets/location_action_buttons.dart';
import 'location_picker_screen.dart';

class AddCatchScreen extends StatefulWidget {
  final Catch? catchToEdit;
  const AddCatchScreen({super.key, this.catchToEdit});

  @override
  State<AddCatchScreen> createState() => _AddCatchScreenState();
}

class _AddCatchScreenState extends State<AddCatchScreen> with WidgetsBindingObserver {
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
  int? _selectedLureId;
  List<Lure> _lures = [];
  int? _selectedBaitId;
  List<Bait> _baits = [];
  final _lureSizeController = TextEditingController();
  final _lureColourController = TextEditingController();
  String? _lurePhotoPath;
  
  // Environmental conditions
  String? _selectedTideStage;
  String? _selectedTideStrength;
  final _tideNotesController = TextEditingController();
  final _tideHeightController = TextEditingController();
  String? _selectedTideMovement;
  final _tideStationController = TextEditingController();
  String? _selectedWeatherCondition;
  final _temperatureController = TextEditingController();
  final _humidityController = TextEditingController();
  final _cloudCoverController = TextEditingController();
  final _windSpeedController = TextEditingController();
  String? _selectedWindDirection;
  final _barometricPressureController = TextEditingController();
  final _rainfallController = TextEditingController();
  String? _selectedRiverFlow;
  String? _selectedWaterClarity;
  EnvironmentalCondition? _existingEnvironmentalCondition;
  
  // Change tracking
  bool _hasUnsavedChanges = false;
  late Catch? _originalCatch;
  bool _isLoadingInitialData = false;

  @override
  void initState() {
    super.initState();
    
    // Add observer for app lifecycle changes (camera resume handling)
    WidgetsBinding.instance.addObserver(this);
    
    // Load all initial data before building the form
    _loadInitialData();
  }

  /// Load all required data before building the form
  /// This prevents dropdown assertion errors from selected values being set before item lists are loaded
  Future<void> _loadInitialData() async {
    if (widget.catchToEdit != null) {
      setState(() {
        _isLoadingInitialData = true;
      });
      
      // Load all lookup lists and environmental data in parallel where possible
      await Future.wait([
        _loadFishTypes(),
        _loadFishingBuddies(),
        _loadFishingTrips(),
        _loadFavouriteSpots(),
        _loadLures(),
        _loadBaits(),
      ]);
      
      // Load environmental condition after lists are loaded
      await _loadEnvironmentalCondition();
      
      // Now set the catch-specific values after lists are ready
      _originalCatch = widget.catchToEdit;
      await _loadMediaForCatch();
      
      // Safely set fish type - will add to list if not present
      final fishType = widget.catchToEdit!.fishType;
      _fishTypeController.text = fishType;
      _selectedFishType = _safeFishTypeValue(fishType);
      _lengthController.text = widget.catchToEdit!.lengthCm.toString();
      _notesController.text = widget.catchToEdit!.notes ?? '';
      _locationController.text = widget.catchToEdit!.location ?? '';
      _dateCaught = widget.catchToEdit!.dateCaught;
      
      // Trip and buddy IDs - validate after lists are loaded
      _selectedTripId = _safeIdValue(widget.catchToEdit!.tripId, _fishingTrips, 'tripId');
      _selectedFishingBuddyId = _safeIdValue(widget.catchToEdit!.fishingBuddyId, _fishingBuddies, 'fishingBuddyId');
      _selectedLureId = _safeIdValue(widget.catchToEdit!.lureId, _lures, 'lureId');
      _selectedBaitId = _safeIdValue(widget.catchToEdit!.baitId, _baits, 'baitId');
      _lureSizeController.text = widget.catchToEdit!.lureSize ?? '';
      _lureColourController.text = widget.catchToEdit!.lureColour ?? '';
      _lurePhotoPath = widget.catchToEdit!.lurePhotoPath;
      
      _latitudeController.text = widget.catchToEdit!.latitude?.toString() ?? '';
      _longitudeController.text = widget.catchToEdit!.longitude?.toString() ?? '';
      _coordinateSource = widget.catchToEdit!.coordinateSource;
      
      setState(() {
        _isLoadingInitialData = false;
      });
    } else {
      // For new catches, load lookup lists in parallel
      await Future.wait([
        _loadFishTypes(),
        _loadFishingBuddies(),
        _loadFishingTrips(),
        _loadFavouriteSpots(),
        _loadLures(),
        _loadBaits(),
      ]);
      
      // Check for lost data when adding a new catch
      // Lost data recovery is for when the app is killed during a new catch creation
      _retrieveLostData();
      
      // For new catches, pre-select the current trip if set
      _loadCurrentTrip();
      
      // Set date caught to current date and time
      _dateCaught = DateTime.now();
    }
    
    // Add text change listeners after data is loaded
    _addTextChangeListeners();
  }

  void _addTextChangeListeners() {
    _fishTypeController.addListener(_onFieldChanged);
    _lengthController.addListener(_onFieldChanged);
    _notesController.addListener(_onFieldChanged);
    _locationController.addListener(_onFieldChanged);
    _latitudeController.addListener(_onFieldChanged);
    _longitudeController.addListener(_onFieldChanged);
    _tideHeightController.addListener(_onFieldChanged);
    _tideStationController.addListener(_onFieldChanged);
    _temperatureController.addListener(_onFieldChanged);
    _humidityController.addListener(_onFieldChanged);
    _cloudCoverController.addListener(_onFieldChanged);
    _windSpeedController.addListener(_onFieldChanged);
    _barometricPressureController.addListener(_onFieldChanged);
    _rainfallController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    // Remove observer when widget is disposed
    WidgetsBinding.instance.removeObserver(this);
    
    _fishTypeController.removeListener(_onFieldChanged);
    _lengthController.removeListener(_onFieldChanged);
    _notesController.removeListener(_onFieldChanged);
    _locationController.removeListener(_onFieldChanged);
    _latitudeController.removeListener(_onFieldChanged);
    _longitudeController.removeListener(_onFieldChanged);
    _tideHeightController.removeListener(_onFieldChanged);
    _tideStationController.removeListener(_onFieldChanged);
    _temperatureController.removeListener(_onFieldChanged);
    _humidityController.removeListener(_onFieldChanged);
    _cloudCoverController.removeListener(_onFieldChanged);
    _windSpeedController.removeListener(_onFieldChanged);
    _barometricPressureController.removeListener(_onFieldChanged);
    _rainfallController.removeListener(_onFieldChanged);
    _fishTypeController.dispose();
    _lengthController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _tideHeightController.dispose();
    _tideStationController.dispose();
    _temperatureController.dispose();
    _humidityController.dispose();
    _cloudCoverController.dispose();
    _windSpeedController.dispose();
    _barometricPressureController.dispose();
    _rainfallController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app resumes from camera, check for lost data
    if (state == AppLifecycleState.resumed) {
      _retrieveLostData();
    }
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
    final mode = await PreferencesService.getFishTypeSelectionMode();
    
    if (mode == FishTypeSelectionMode.defaultFishType) {
      final defaultFishType = await PreferencesService.getDefaultFishType();
      if (defaultFishType != null && _fishTypes.contains(defaultFishType)) {
        setState(() {
          _selectedFishType = defaultFishType;
        });
      }
    } else if (mode == FishTypeSelectionMode.rememberLastUsed) {
      final lastUsedFishType = await PreferencesService.getLastUsedFishType();
      if (lastUsedFishType != null && _fishTypes.contains(lastUsedFishType)) {
        setState(() {
          _selectedFishType = lastUsedFishType;
        });
      }
    }
  }

  Future<void> _retrieveLostData() async {
    final picker = ImagePicker();
    final lostData = await picker.retrieveLostData();
    
    if (lostData == null || lostData.isEmpty) {
      return;
    }
    
    bool recovered = false;
    
    if (lostData.file != null) {
      final file = File(lostData.file!.path);
      await _processPickedFile(file, 'lost_data');
      recovered = true;
    } else if (lostData.files != null && lostData.files!.isNotEmpty) {
      for (final lostFile in lostData.files!) {
        final file = File(lostFile.path);
        await _processPickedFile(file, 'lost_data');
        recovered = true;
      }
    }
    
    if (recovered && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recovered photo from previous camera session'),
          duration: Duration(seconds: 3),
        ),
      );
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
        // Trip ID validation is now handled in _loadInitialData after lists are loaded
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

  Future<void> _loadLures() async {
    final lures = await DatabaseHelper.instance.getLures();
    if (mounted) {
      setState(() {
        _lures = lures;
      });
    }
  }

  Future<void> _loadBaits() async {
    final baits = await DatabaseHelper.instance.getBaits();
    if (mounted) {
      setState(() {
        _baits = baits;
      });
    }
  }

  /// Safely validate a dropdown value against allowed values
  /// Handles null, empty, and "Unknown" values defensively
  String? _safeDropdownValue(String? value, List<String> allowedValues, String fieldName, {int? catchId}) {
    if (value == null || value.isEmpty || value == 'Unknown') {
      return null;
    }
    if (allowedValues.contains(value)) {
      return value;
    }
    return null;
  }

  /// Safely validate a dropdown value against allowed values including null
  /// For dropdowns that explicitly allow null as a valid option
  String? _safeDropdownValueWithNull(String? value, List<String?> allowedValues, String fieldName, {int? catchId}) {
    if (value == null) {
      return null;
    }
    if (value.isEmpty || value == 'Unknown') {
      return null;
    }
    if (allowedValues.contains(value)) {
      return value;
    }
    return null;
  }

  /// Safely validate a fish type value against current fish types list
  String? _safeFishTypeValue(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    if (_fishTypes.contains(value)) {
      return value;
    }
    // Add the missing fish type to the list so it can be selected
    setState(() {
      _fishTypes = [..._fishTypes, value];
    });
    return value;
  }

  /// Safely validate an integer ID dropdown value against available items
  int? _safeIdValue(int? value, List<dynamic> items, String fieldName) {
    if (value == null) {
      return null;
    }
    // Check if the ID exists in the items list
    // Handle both Map objects (with 'id' key) and model objects (with .id property)
    final idExists = items.any((item) {
      if (item is Map) {
        return item['id'] == value;
      } else {
        // Try to access .id property via dynamic
        try {
          return item.id == value;
        } catch (e) {
          return false;
        }
      }
    });
    if (idExists) {
      return value;
    }
    return null;
  }

  Future<void> _loadEnvironmentalCondition() async {
    if (widget.catchToEdit == null) return;
    
    final envService = EnvironmentalConditionsService();
    final catchId = widget.catchToEdit!.id!;
    
    final condition = await envService.getEnvironmentalConditionForCatch(catchId);
    
    if (condition != null) {
      setState(() {
        _existingEnvironmentalCondition = condition;
        _selectedTideStage = _safeDropdownValue(condition.tideStage, EnvironmentalCondition.tideStages, 'tideStage', catchId: catchId);
        _selectedTideStrength = _safeDropdownValue(condition.tideStrength, EnvironmentalCondition.tideStrengths, 'tideStrength', catchId: catchId);
        _tideNotesController.text = condition.tideNotes ?? '';
        _tideHeightController.text = condition.tideHeight?.toString() ?? '';
        // Tide movement: validate against custom dropdown items
        _selectedTideMovement = _safeDropdownValueWithNull(condition.tideMovement, [null, 'Run-in', 'Run-out', 'Slack'], 'tideMovement', catchId: catchId);
        _tideStationController.text = condition.tideStation ?? '';
        _selectedWeatherCondition = _safeDropdownValue(condition.weatherCondition, EnvironmentalCondition.weatherConditions, 'weatherCondition', catchId: catchId);
        _temperatureController.text = condition.temperature?.toString() ?? '';
        _humidityController.text = condition.humidity?.toString() ?? '';
        _cloudCoverController.text = condition.cloudCover?.toString() ?? '';
        _windSpeedController.text = condition.windSpeed?.toString() ?? '';
        _selectedWindDirection = _safeDropdownValue(condition.windDirection, EnvironmentalCondition.windDirections, 'windDirection', catchId: catchId);
        _barometricPressureController.text = condition.barometricPressure?.toString() ?? '';
        _rainfallController.text = condition.rainfall?.toString() ?? '';
        // River flow: validate against custom dropdown items
        _selectedRiverFlow = _safeDropdownValueWithNull(condition.riverFlow, [null, 'Low', 'Normal', 'High', 'Flood'], 'riverFlow', catchId: catchId);
        _selectedWaterClarity = _safeDropdownValue(condition.waterClarity, EnvironmentalCondition.waterClarities, 'waterClarity', catchId: catchId);
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
      // Default to "Me" only if "Me" is in the list and we're not editing
      // When editing, the buddy ID is set in _loadInitialData after lists are loaded
      if (_selectedFishingBuddyId == null && meBuddy != null && widget.catchToEdit == null) {
        final meInList = buddies.any((b) => b.id == meBuddy.id);
        if (meInList) {
          _selectedFishingBuddyId = meBuddy.id;
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
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85, // Compress to reduce memory pressure
        maxWidth: 1920, // Limit resolution to reduce memory
        maxHeight: 1080,
      );
      
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        await _processPickedFile(file, 'gallery');
      }
    } catch (e, stackTrace) {
      debugPrint('ERROR in _pickImage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        await _processPickedFile(file, 'camera');
      }
    } catch (e) {
      debugPrint('Camera: Error taking photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error taking photo: $e')),
        );
      }
    }
  }

  Future<void> _pickLurePhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      
      if (pickedFile != null) {
        if (mounted) {
          setState(() {
            _lurePhotoPath = pickedFile.path;
          });
        }
      }
    } catch (e) {
      debugPrint('ERROR in _pickLurePhoto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking lure photo: $e')),
        );
      }
    }
  }

  Future<void> _processPickedFile(File file, String source) async {
    final originalPath = file.path;
    
    // Extract GPS data from file
    final gpsData = await _extractGpsData(originalPath);
    final latitude = gpsData['latitude'];
    final longitude = gpsData['longitude'];
    
    final photoDateTime = DateTime.now();
    
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
        }
      });
    }
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
      debugPrint('EXIF: Error reading GPS data: $e');
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

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
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

  Future<void> _saveManualEnvironmentalConditions(int catchId) async {
    final envService = EnvironmentalConditionsService();
    
    // Check if manual fields have values
    final hasManualData = _selectedTideStage != null ||
        _selectedTideStrength != null ||
        _tideNotesController.text.isNotEmpty ||
        _tideHeightController.text.isNotEmpty ||
        _selectedTideMovement != null ||
        _tideStationController.text.isNotEmpty ||
        _selectedWeatherCondition != null ||
        _temperatureController.text.isNotEmpty ||
        _humidityController.text.isNotEmpty ||
        _cloudCoverController.text.isNotEmpty ||
        _windSpeedController.text.isNotEmpty ||
        _selectedWindDirection != null ||
        _barometricPressureController.text.isNotEmpty ||
        _rainfallController.text.isNotEmpty ||
        _selectedRiverFlow != null ||
        _selectedWaterClarity != null;
    
    if (!hasManualData) {
      return;
    }
    
    // Get existing condition to preserve calculated values
    final existing = await envService.getEnvironmentalConditionForCatch(catchId);
    final observationDateTime = _dateCaught ?? DateTime.now();
    
    // Use existing coordinates if available, otherwise try to parse from controllers
    final latitude = existing?.latitude ?? double.tryParse(_latitudeController.text);
    final longitude = existing?.longitude ?? double.tryParse(_longitudeController.text);
    
    
    await envService.saveEnvironmentalConditionForCatch(
      catchId,
      observationDateTime,
      latitude,
      longitude,
      tideStage: _selectedTideStage,
      tideStrength: _selectedTideStrength,
      tideNotes: _tideNotesController.text.trim().isEmpty ? null : _tideNotesController.text.trim(),
      tideHeight: double.tryParse(_tideHeightController.text),
      tideMovement: _selectedTideMovement,
      tideStation: _tideStationController.text.trim().isEmpty ? null : _tideStationController.text.trim(),
      weatherCondition: (_selectedWeatherCondition == null || _selectedWeatherCondition == 'Unknown') ? null : _selectedWeatherCondition,
      temperature: double.tryParse(_temperatureController.text),
      humidity: double.tryParse(_humidityController.text),
      cloudCover: double.tryParse(_cloudCoverController.text),
      windSpeed: double.tryParse(_windSpeedController.text),
      windDirection: (_selectedWindDirection == null || _selectedWindDirection == 'Unknown') ? null : _selectedWindDirection,
      barometricPressure: double.tryParse(_barometricPressureController.text),
      rainfall: double.tryParse(_rainfallController.text),
      riverFlow: _selectedRiverFlow,
      waterClarity: _selectedWaterClarity,
    );
  }

  void _saveCatch() async {
    final fishType = _selectedFishType ?? _fishTypeController.text;
    final length = int.tryParse(_lengthController.text) ?? 0;
    final notes = _notesController.text;
    final location = _locationController.text.trim();
    final latitude = double.tryParse(_latitudeController.text);
    final longitude = double.tryParse(_longitudeController.text);

    if (fishType.isEmpty) {
      return;
    }

    Catch? savedCatch;

    try {
      if (widget.catchToEdit != null) {
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
          lureId: _selectedLureId,
          baitId: _selectedBaitId,
          lureSize: _lureSizeController.text.trim().isEmpty ? null : _lureSizeController.text.trim(),
          lureColour: _lureColourController.text.trim().isEmpty ? null : _lureColourController.text.trim(),
          lurePhotoPath: _lurePhotoPath,
        );
        debugPrint('SaveCatch: Updating existing catch with ID: ${widget.catchToEdit!.id}');
        await DatabaseHelper.instance.updateCatch(updatedCatch);
        debugPrint('SaveCatch: Catch updated successfully');
        savedCatch = updatedCatch;
        
        // Delete existing media and re-add
        debugPrint('SaveCatch: Deleting existing media for catch ${widget.catchToEdit!.id}');
        await DatabaseHelper.instance.deleteAllMediaForCatch(widget.catchToEdit!.id!);
        for (final media in _mediaItems) {
          final mediaToInsert = media.copyWith(catchId: widget.catchToEdit!.id);
          await DatabaseHelper.instance.insertCatchMedia(mediaToInsert);
        }
        debugPrint('SaveCatch: Media items re-saved');
        
        // Save manual environmental conditions from form
        debugPrint('SaveCatch: Saving manual environmental conditions');
        await _saveManualEnvironmentalConditions(savedCatch!.id!);
        debugPrint('SaveCatch: Manual environmental conditions saved');
        
        // Upsert calculated conditions (moon/sun) from catch coordinates
        // Do NOT await WorldTides - make it non-blocking
        debugPrint('SaveCatch: Starting upsert of calculated conditions (non-blocking)');
        final envService = EnvironmentalConditionsService();
        envService.upsertCalculatedConditionsForCatch(savedCatch!).then((_) {
          debugPrint('SaveCatch: Calculated conditions upsert complete (async)');
        }).catchError((e) {
          debugPrint('SaveCatch: Calculated conditions upsert failed (async): $e');
        });
        debugPrint('SaveCatch: Calculated conditions upsert started (non-blocking)');
      } else {
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
          lureId: _selectedLureId,
          baitId: _selectedBaitId,
          lureSize: _lureSizeController.text.trim().isEmpty ? null : _lureSizeController.text.trim(),
          lureColour: _lureColourController.text.trim().isEmpty ? null : _lureColourController.text.trim(),
          lurePhotoPath: _lurePhotoPath,
        );
        debugPrint('SaveCatch: Inserting new catch');
        final catchId = await DatabaseHelper.instance.insertCatch(newCatch);
        debugPrint('SaveCatch: Catch inserted with ID: $catchId');
        savedCatch = newCatch.copyWith(id: catchId);
        
        // Save media items with the new catch ID
        debugPrint('SaveCatch: Saving ${_mediaItems.length} media items');
        for (final media in _mediaItems) {
          final mediaToInsert = media.copyWith(catchId: catchId);
          await DatabaseHelper.instance.insertCatchMedia(mediaToInsert);
        }
        debugPrint('SaveCatch: Media items saved');
        
        // Save manual environmental conditions from form
        debugPrint('SaveCatch: Saving manual environmental conditions');
        await _saveManualEnvironmentalConditions(catchId);
        debugPrint('SaveCatch: Manual environmental conditions saved');
        
        // Upsert calculated conditions (moon/sun) from catch coordinates
        // Do NOT await WorldTides - make it non-blocking
        debugPrint('SaveCatch: Starting upsert of calculated conditions (non-blocking)');
        final envService = EnvironmentalConditionsService();
        envService.upsertCalculatedConditionsForCatch(savedCatch!).then((_) {
          debugPrint('SaveCatch: Calculated conditions upsert complete (async)');
        }).catchError((e) {
          debugPrint('SaveCatch: Calculated conditions upsert failed (async): $e');
        });
        debugPrint('SaveCatch: Calculated conditions upsert started (non-blocking)');
      }
      
      // Remember last used fish type
      await PreferencesService.setLastUsedFishType(fishType);
    } catch (e, stackTrace) {
      debugPrint('ERROR saving catch: $e');
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

    // Pop with the saved catch to refresh the calling screen
    debugPrint('SaveCatch: Calling Navigator.pop with catch ID: ${savedCatch?.id}');
    Navigator.pop(context, savedCatch);
    debugPrint('SaveCatch: Navigator.pop completed');
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while initial data is being loaded
    if (_isLoadingInitialData) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.catchToEdit != null ? 'Edit Catch' : 'Add Catch'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.catchToEdit != null ? 'Edit Catch' : 'Add Catch'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _onWillPop()) {
                if (mounted) {
                  Navigator.pop(context);
                }
              }
            },
          ),
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
              // Photo Section
              BragmatSectionCard(
                icon: Icons.photo_camera,
                title: 'Catch Photo',
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _takePhoto,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Take Photo'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Add Photo'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Catch Details Section
              BragmatSectionCard(
                icon: Icons.catching_pokemon,
                title: 'Catch Details',
                children: [
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lengthController,
                    decoration: const InputDecoration(labelText: 'Size (cm)'),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Date & Time Section
              BragmatSectionCard(
                icon: Icons.calendar_today,
                title: 'Date & Time',
                children: [
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
                ],
              ),
              const SizedBox(height: 16),

              // Location Section
              BragmatSectionCard(
                icon: Icons.location_on,
                title: 'Location',
                children: [
                  TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(labelText: 'Location Name'),
                  ),
                  const SizedBox(height: 12),
                  if (_favouriteSpots.isNotEmpty)
                    (() {
                      final items = <DropdownMenuItem<int?>>[
                        const DropdownMenuItem(value: null, child: Text('None')),
                        ..._favouriteSpots.map((spot) {
                          return DropdownMenuItem<int?>(
                            value: spot.id,
                            child: Text(spot.name),
                          );
                        }),
                      ];
                      return DropdownButtonFormField<int?>(
                        value: _selectedFavouriteSpotId,
                        decoration: const InputDecoration(
                          labelText: 'Favourite Spot (optional)',
                          prefixIcon: Icon(Icons.place),
                        ),
                        items: items,
                        onChanged: (value) {
                          final spot = value != null
                              ? _favouriteSpots.firstWhere((s) => s.id == value)
                              : null;
                          _onFavouriteSpotSelected(spot);
                        },
                      );
                    })(),
                  const SizedBox(height: 12),
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
                      const SizedBox(width: 12),
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
                  const SizedBox(height: 12),
                  LocationActionButtons(
                    onUseCurrentLocation: _getCurrentLocation,
                    onPickOnMap: _pickLocationOnMap,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Trip Section
              BragmatSectionCard(
                icon: Icons.directions_boat,
                title: 'Trip',
                children: [
                  (() {
                    final items = _fishingTrips.isEmpty
                        ? <DropdownMenuItem<int?>>[]
                        : _fishingTrips.map((trip) {
                            return DropdownMenuItem<int?>(
                              value: trip.id,
                              child: Text(trip.name),
                            );
                          }).toList();
                    return DropdownButtonFormField<int?>(
                      initialValue: _selectedTripId,
                      decoration: const InputDecoration(labelText: 'Fishing Trip'),
                      items: items,
                      onChanged: (value) {
                        setState(() {
                          _selectedTripId = value;
                          _onFieldChanged();
                        });
                      },
                    );
                  })(),
                  const SizedBox(height: 12),
                  (() {
                    final items = _fishingBuddies.isEmpty
                        ? <DropdownMenuItem<int?>>[]
                        : _fishingBuddies.map((buddy) {
                            return DropdownMenuItem<int?>(
                              value: buddy.id,
                              child: Text(buddy.name),
                            );
                          }).toList();
                    return DropdownButtonFormField<int?>(
                      initialValue: _selectedFishingBuddyId,
                      decoration: const InputDecoration(labelText: 'Fishing Buddy'),
                      items: items,
                      onChanged: (value) {
                        setState(() {
                          _selectedFishingBuddyId = value;
                          _onFieldChanged();
                        });
                      },
                    );
                  })(),
                ],
              ),
              const SizedBox(height: 16),

              // Lure and Bait Section
              BragmatSectionCard(
                icon: Icons.phishing,
                title: 'Lure and Bait',
                initiallyExpanded: false,
                children: [
                  DropdownButtonFormField<int?>(
                    value: _selectedLureId,
                    decoration: const InputDecoration(labelText: 'Lure'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('None'),
                      ),
                      ..._lures.map((lure) {
                        return DropdownMenuItem<int?>(
                          value: lure.id,
                          child: Text(lure.name),
                        );
                      }).toList(),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedLureId = value;
                        _onFieldChanged();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    value: _selectedBaitId,
                    decoration: const InputDecoration(labelText: 'Bait'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('None'),
                      ),
                      ..._baits.map((bait) {
                        return DropdownMenuItem<int?>(
                          value: bait.id,
                          child: Text(bait.name),
                        );
                      }).toList(),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedBaitId = value;
                        _onFieldChanged();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _lureSizeController,
                    decoration: const InputDecoration(labelText: 'Lure Size (optional)'),
                    onChanged: (value) {
                      _onFieldChanged();
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lureColourController,
                    decoration: const InputDecoration(labelText: 'Lure Colour (optional)'),
                    onChanged: (value) {
                      _onFieldChanged();
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Lure Photo (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_lurePhotoPath != null)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_lurePhotoPath!),
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _lurePhotoPath = null;
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
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _pickLurePhoto(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Camera'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _pickLurePhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Environmental Conditions Section
              BragmatSectionCard(
                icon: Icons.wb_sunny,
                title: 'Environmental Conditions',
                initiallyExpanded: false,
                children: [
                  // Weather
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Weather',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  (() {
                    final items = EnvironmentalCondition.weatherConditions.map((condition) {
                      return DropdownMenuItem(
                        value: condition,
                        child: Text(condition),
                      );
                    }).toList();
                    return DropdownButtonFormField<String>(
                      value: _selectedWeatherCondition,
                      decoration: const InputDecoration(labelText: 'Weather Condition'),
                      items: items,
                      onChanged: (value) {
                        setState(() {
                          _selectedWeatherCondition = value;
                          _onFieldChanged();
                        });
                      },
                    );
                  })(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _temperatureController,
                          decoration: const InputDecoration(
                            labelText: 'Temperature (°C)',
                            hintText: 'e.g., 25',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _humidityController,
                          decoration: const InputDecoration(
                            labelText: 'Humidity (%)',
                            hintText: 'e.g., 65',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cloudCoverController,
                    decoration: const InputDecoration(
                      labelText: 'Cloud Cover (%)',
                      hintText: 'e.g., 40',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: (() {
                          final items = EnvironmentalCondition.windDirections.map((direction) {
                            return DropdownMenuItem(
                              value: direction,
                              child: Text(direction),
                            );
                          }).toList();
                          return DropdownButtonFormField<String>(
                            value: _selectedWindDirection,
                            decoration: const InputDecoration(labelText: 'Wind Direction'),
                            items: items,
                            onChanged: (value) {
                              setState(() {
                                _selectedWindDirection = value;
                                _onFieldChanged();
                              });
                            },
                          );
                        })(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _windSpeedController,
                    decoration: const InputDecoration(
                      labelText: 'Wind Speed (km/h)',
                      hintText: 'e.g., 15',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),

                  // Tide
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Tide',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  (() {
                    final items = EnvironmentalCondition.tideStages.map((stage) {
                      return DropdownMenuItem(
                        value: stage,
                        child: Text(stage),
                      );
                    }).toList();
                    return DropdownButtonFormField<String>(
                      value: _selectedTideStage,
                      decoration: const InputDecoration(labelText: 'Tide Stage'),
                      items: items,
                      onChanged: (value) {
                        setState(() {
                          _selectedTideStage = value;
                          _onFieldChanged();
                        });
                      },
                    );
                  })(),
                  const SizedBox(height: 12),
                  (() {
                    final items = EnvironmentalCondition.tideStrengths.map((strength) {
                      return DropdownMenuItem(
                        value: strength,
                        child: Text(strength),
                      );
                    }).toList();
                    return DropdownButtonFormField<String>(
                      value: _selectedTideStrength,
                      decoration: const InputDecoration(labelText: 'Tide Strength (Optional)'),
                      items: items,
                      onChanged: (value) {
                        setState(() {
                          _selectedTideStrength = value;
                          _onFieldChanged();
                        });
                      },
                    );
                  })(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: (() {
                          const items = [
                            DropdownMenuItem<String?>(value: null, child: Text('Unknown')),
                            DropdownMenuItem<String?>(value: 'Run-in', child: Text('Run-in')),
                            DropdownMenuItem<String?>(value: 'Run-out', child: Text('Run-out')),
                            DropdownMenuItem<String?>(value: 'Slack', child: Text('Slack')),
                          ];
                          return DropdownButtonFormField<String?>(
                            value: _selectedTideMovement,
                            decoration: const InputDecoration(labelText: 'Tide Movement'),
                            items: items,
                            onChanged: (value) {
                              setState(() {
                                _selectedTideMovement = value;
                                _onFieldChanged();
                              });
                            },
                          );
                        })(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _tideHeightController,
                          decoration: const InputDecoration(
                            labelText: 'Tide Height (m)',
                            hintText: 'e.g., 1.5',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tideNotesController,
                    decoration: const InputDecoration(
                      labelText: 'Tide Notes (Optional)',
                      hintText: 'e.g., Big spring tide, Dirty run-out',
                    ),
                    maxLines: 2,
                    onChanged: (_) => _onFieldChanged(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tideStationController,
                    decoration: const InputDecoration(
                      labelText: 'Tide Station (optional)',
                      hintText: 'e.g., Sydney Harbour',
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Official Tide Context Placeholder
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.grey.shade600,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Official Tide Context',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tide context not available',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Official tide context will be calculated after saving if GPS and catch time are available.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Water Conditions
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Water Conditions',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  (() {
                    final items = EnvironmentalCondition.waterClarities.map((clarity) {
                      return DropdownMenuItem(
                        value: clarity,
                        child: Text(clarity),
                      );
                    }).toList();
                    return DropdownButtonFormField<String>(
                      value: _selectedWaterClarity,
                      decoration: const InputDecoration(labelText: 'Water Clarity'),
                      items: items,
                      onChanged: (value) {
                        setState(() {
                          _selectedWaterClarity = value;
                          _onFieldChanged();
                        });
                      },
                    );
                  })(),
                  const SizedBox(height: 12),
                  (() {
                    const items = [
                      DropdownMenuItem<String?>(value: null, child: Text('Unknown')),
                      DropdownMenuItem<String?>(value: 'Low', child: Text('Low')),
                      DropdownMenuItem<String?>(value: 'Normal', child: Text('Normal')),
                      DropdownMenuItem<String?>(value: 'High', child: Text('High')),
                      DropdownMenuItem<String?>(value: 'Flood', child: Text('Flood')),
                    ];
                    return DropdownButtonFormField<String?>(
                      value: _selectedRiverFlow,
                      decoration: const InputDecoration(labelText: 'River Flow (optional)'),
                      items: items,
                      onChanged: (value) {
                        setState(() {
                          _selectedRiverFlow = value;
                          _onFieldChanged();
                        });
                      },
                    );
                  })(),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _barometricPressureController,
                    decoration: const InputDecoration(
                      labelText: 'Barometric Pressure (hPa)',
                      hintText: 'e.g., 1013',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _rainfallController,
                    decoration: const InputDecoration(
                      labelText: 'Rainfall (mm)',
                      hintText: 'e.g., 5',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Notes Section
              BragmatSectionCard(
                icon: Icons.note,
                title: 'Notes',
                children: [
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(labelText: 'Catch Notes'),
                    maxLines: 3,
                  ),
                ],
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