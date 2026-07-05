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
  
  // Environmental conditions
  String? _selectedTideStage;
  String? _selectedTideStrength;
  final _tideNotesController = TextEditingController();
  final _tideHeightController = TextEditingController();
  String? _selectedTideMovement;
  final _tideStationController = TextEditingController();
  // Tide context fields
  bool _showTideContext = false;
  final _tideStationNameController = TextEditingController();
  String? _selectedReferenceTideEventType; // High / Low
  DateTime? _referenceTideEventTime;
  final _referenceTideEventHeightController = TextEditingController();
  String? _selectedReferenceTideEventRelation; // Before / After
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
  final _environmentalNotesController = TextEditingController();
  EnvironmentalCondition? _existingEnvironmentalCondition;
  
  // Change tracking
  bool _hasUnsavedChanges = false;
  late Catch? _originalCatch;
  bool _isLoadingInitialData = false;

  @override
  void initState() {
    super.initState();
    
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
      
      // Debug: Log catch details to check trip/buddy references
      final envService = EnvironmentalConditionsService();
      await envService.debugCatchDetails(widget.catchToEdit!.id!, 'Loading in Edit Catch');
      
      // Load all lookup lists and environmental data in parallel where possible
      await Future.wait([
        _loadFishTypes(),
        _loadFishingBuddies(),
        _loadFishingTrips(),
        _loadFavouriteSpots(),
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
    _environmentalNotesController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
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
    _environmentalNotesController.removeListener(_onFieldChanged);
    _fishTypeController.dispose();
    _lengthController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _tideHeightController.dispose();
    _tideStationController.dispose();
    _tideStationNameController.dispose();
    _referenceTideEventHeightController.dispose();
    _temperatureController.dispose();
    _humidityController.dispose();
    _cloudCoverController.dispose();
    _windSpeedController.dispose();
    _barometricPressureController.dispose();
    _rainfallController.dispose();
    _environmentalNotesController.dispose();
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

  String _generateTideContextPhrase() {
    if (_tideStationNameController.text.isEmpty ||
        _selectedReferenceTideEventType == null ||
        _referenceTideEventTime == null ||
        _referenceTideEventHeightController.text.isEmpty ||
        _selectedReferenceTideEventRelation == null) {
      return '';
    }

    final stationName = _tideStationNameController.text.trim();
    final eventType = _selectedReferenceTideEventType!;
    final eventTime = _referenceTideEventTime!;
    final eventHeight = double.tryParse(_referenceTideEventHeightController.text) ?? 0.0;
    final relation = _selectedReferenceTideEventRelation!;
    final catchTime = _dateCaught ?? DateTime.now();

    final minutesFromEvent = TideContextHelper.calculateMinutesBetween(catchTime, eventTime);

    return TideContextHelper.generatePhrase(
      stationName: stationName,
      eventType: eventType,
      eventTime: eventTime,
      eventHeight: eventHeight,
      relation: relation,
      minutesFromEvent: minutesFromEvent,
    );
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
        // Trip ID validation is now handled in _loadInitialData after lists are loaded
      });
    }
  }

  Future<void> _loadFavouriteSpots() async {
    final spots = await DatabaseHelper.instance.getFavouriteSpots();
    if (mounted) {
      setState(() {
        _favouriteSpots = spots;
        // Validate selected favourite spot ID after list is loaded
        if (widget.catchToEdit != null) {
          // Note: favouriteSpotId is not in Catch model, so we check from environmental condition
          // This will be validated when environmental condition is loaded
          debugPrint('Favourite spots loaded: ${spots.length} spots (catch ID: ${widget.catchToEdit!.id})');
        }
      });
    }
  }

  /// Safely validate a dropdown value against allowed values
  /// Handles null, empty, and "Unknown" values defensively
  String? _safeDropdownValue(String? value, List<String> allowedValues, String fieldName, {int? catchId}) {
    if (value == null || value.isEmpty || value == 'Unknown') {
      debugPrint('Dropdown $fieldName: value is null/empty/Unknown, using null${catchId != null ? " (catch ID: $catchId)" : ""}');
      return null;
    }
    if (allowedValues.contains(value)) {
      debugPrint('Dropdown $fieldName: value "$value" is valid${catchId != null ? " (catch ID: $catchId)" : ""}');
      return value;
    }
    debugPrint('Dropdown $fieldName: value "$value" is NOT in allowed list $allowedValues, using null${catchId != null ? " (catch ID: $catchId)" : ""}');
    return null;
  }

  /// Safely validate a dropdown value against allowed values including null
  /// For dropdowns that explicitly allow null as a valid option
  String? _safeDropdownValueWithNull(String? value, List<String?> allowedValues, String fieldName, {int? catchId}) {
    if (value == null) {
      debugPrint('Dropdown $fieldName: value is null, using null${catchId != null ? " (catch ID: $catchId)" : ""}');
      return null;
    }
    if (value.isEmpty || value == 'Unknown') {
      debugPrint('Dropdown $fieldName: value is empty/Unknown, using null${catchId != null ? " (catch ID: $catchId)" : ""}');
      return null;
    }
    if (allowedValues.contains(value)) {
      debugPrint('Dropdown $fieldName: value "$value" is valid${catchId != null ? " (catch ID: $catchId)" : ""}');
      return value;
    }
    debugPrint('Dropdown $fieldName: value "$value" is NOT in allowed list $allowedValues, using null${catchId != null ? " (catch ID: $catchId)" : ""}');
    return null;
  }

  /// Safely validate a fish type value against current fish types list
  String? _safeFishTypeValue(String? value) {
    if (value == null || value.isEmpty) {
      debugPrint('Fish type: value is null or empty, using null');
      return null;
    }
    if (_fishTypes.contains(value)) {
      debugPrint('Fish type: value "$value" is valid');
      return value;
    }
    debugPrint('Fish type: value "$value" is NOT in current fish types list, adding it to list');
    // Add the missing fish type to the list so it can be selected
    setState(() {
      _fishTypes = [..._fishTypes, value];
    });
    return value;
  }

  /// Safely validate an integer ID dropdown value against available items
  int? _safeIdValue(int? value, List<dynamic> items, String fieldName) {
    if (value == null) {
      debugPrint('Dropdown $fieldName: value is null, using null');
      return null;
    }
    // Check if the ID exists in the items list
    final idExists = items.any((item) => item is Map && item['id'] == value);
    if (idExists) {
      debugPrint('Dropdown $fieldName: value $value is valid');
      return value;
    }
    debugPrint('Dropdown $fieldName: value $value is NOT in available items, using null');
    return null;
  }

  /// Debug helper to log dropdown state before building
  void _debugDropdown(String fieldName, dynamic value, List<dynamic> items) {
    debugPrint('=== BUILDING $fieldName DROPDOWN ===');
    debugPrint('Current value: $value');
    debugPrint('Items count: ${items.length}');
    
    // Only check for assertion issues if value is non-null
    if (value != null) {
      final matchingItems = items.where((item) {
        if (item is DropdownMenuItem) {
          return item.value == value;
        }
        return false;
      }).length;
      debugPrint('Matching items count: $matchingItems');
      if (matchingItems == 0) {
        debugPrint('WARNING: Zero matching items - this will cause assertion!');
      } else if (matchingItems > 1) {
        debugPrint('WARNING: Multiple matching items - this will cause assertion!');
      }
    } else {
      debugPrint('Value is null - valid for optional dropdowns');
    }
  }

  Future<void> _loadEnvironmentalCondition() async {
    if (widget.catchToEdit == null) return;
    
    final envService = EnvironmentalConditionsService();
    final catchId = widget.catchToEdit!.id!;
    
    // Debug: Log database state before loading
    await envService.debugEnvironmentalConditionForCatch(catchId, 'After loading in Edit Catch');
    
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
        // Tide context fields
        _tideStationNameController.text = condition.tideStationName ?? '';
        _selectedReferenceTideEventType = _safeDropdownValue(condition.referenceTideEventType, ['High', 'Low'], 'referenceTideEventType', catchId: catchId);
        _referenceTideEventTime = condition.referenceTideEventTime;
        _referenceTideEventHeightController.text = condition.referenceTideEventHeight?.toString() ?? '';
        _selectedReferenceTideEventRelation = _safeDropdownValue(condition.referenceTideEventRelation, ['Before', 'After'], 'referenceTideEventRelation', catchId: catchId);
        // Show tide context if data exists
        _showTideContext = condition.tideContextPhrase != null && condition.tideContextPhrase!.isNotEmpty;
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
        _environmentalNotesController.text = condition.riverFlow ?? '';
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

  Future<void> _saveManualEnvironmentalConditions(int catchId) async {
    final envService = EnvironmentalConditionsService();
    
    // Check if manual fields have values
    final hasManualData = _selectedTideStage != null ||
        _selectedTideStrength != null ||
        _tideNotesController.text.isNotEmpty ||
        _tideHeightController.text.isNotEmpty ||
        _selectedTideMovement != null ||
        _tideStationController.text.isNotEmpty ||
        _tideStationNameController.text.isNotEmpty ||
        _selectedReferenceTideEventType != null ||
        _referenceTideEventTime != null ||
        _referenceTideEventHeightController.text.isNotEmpty ||
        _selectedReferenceTideEventRelation != null ||
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
    
    // Generate tide context phrase if all fields are present
    String? tideContextPhrase;
    int? minutesFromReferenceTideEvent;
    if (_tideStationNameController.text.isNotEmpty &&
        _selectedReferenceTideEventType != null &&
        _referenceTideEventTime != null &&
        _referenceTideEventHeightController.text.isNotEmpty &&
        _selectedReferenceTideEventRelation != null) {
      tideContextPhrase = _generateTideContextPhrase();
      minutesFromReferenceTideEvent = TideContextHelper.calculateMinutesBetween(
        observationDateTime,
        _referenceTideEventTime!,
      );
    }
    
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
      // Tide context fields
      tideStationName: _tideStationNameController.text.trim().isEmpty ? null : _tideStationNameController.text.trim(),
      referenceTideEventType: _selectedReferenceTideEventType,
      referenceTideEventTime: _referenceTideEventTime,
      referenceTideEventHeight: double.tryParse(_referenceTideEventHeightController.text),
      referenceTideEventRelation: _selectedReferenceTideEventRelation,
      minutesFromReferenceTideEvent: minutesFromReferenceTideEvent,
      tideContextPhrase: tideContextPhrase,
      tideContextDataSource: 'Manual',
      tideContextConfidence: 'High',
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
        );
        await DatabaseHelper.instance.updateCatch(updatedCatch);
        savedCatch = updatedCatch;
        
        // Delete existing media and re-add
        await DatabaseHelper.instance.deleteAllMediaForCatch(widget.catchToEdit!.id!);
        for (final media in _mediaItems) {
          final mediaToInsert = media.copyWith(catchId: widget.catchToEdit!.id);
          await DatabaseHelper.instance.insertCatchMedia(mediaToInsert);
        }
        
        // Save manual environmental conditions from form
        await _saveManualEnvironmentalConditions(savedCatch!.id!);
        
        // Upsert calculated conditions (moon/sun) from catch coordinates
        final envService = EnvironmentalConditionsService();
        await envService.upsertCalculatedConditionsForCatch(savedCatch!);
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
        );
        final catchId = await DatabaseHelper.instance.insertCatch(newCatch);
        savedCatch = newCatch.copyWith(id: catchId);
        
        // Save media items with the new catch ID
        for (final media in _mediaItems) {
          final mediaToInsert = media.copyWith(catchId: catchId);
          await DatabaseHelper.instance.insertCatchMedia(mediaToInsert);
        }
        
        // Save manual environmental conditions from form
        await _saveManualEnvironmentalConditions(catchId);
        
        // Upsert calculated conditions (moon/sun) from catch coordinates
        final envService = EnvironmentalConditionsService();
        await envService.upsertCalculatedConditionsForCatch(savedCatch!);
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

    // Always pop with result to refresh the calling screen
    Navigator.pop(context, true);
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
              // Debug diagnostics
              if (widget.catchToEdit != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.yellow.shade100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DROPDOWN DIAGNOSTICS', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Fish Type: $_selectedFishType'),
                      Text('Favourite Spot ID: $_selectedFavouriteSpotId'),
                      Text('Trip ID: $_selectedTripId'),
                      Text('Fishing Buddy ID: $_selectedFishingBuddyId'),
                      Text('Weather: $_selectedWeatherCondition'),
                      Text('Wind: $_selectedWindDirection'),
                      Text('Tide Stage: $_selectedTideStage'),
                      Text('Tide Strength: $_selectedTideStrength'),
                      Text('Tide Movement: $_selectedTideMovement'),
                      Text('Ref Event Type: $_selectedReferenceTideEventType'),
                      Text('Ref Event Relation: $_selectedReferenceTideEventRelation'),
                      Text('Water Clarity: $_selectedWaterClarity'),
                      Text('River Flow: $_selectedRiverFlow'),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
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
                  (() {
                    debugPrint('=== BUILDING FISH TYPE DROPDOWN ===');
                    debugPrint('Current value: $_selectedFishType');
                    debugPrint('Fish types list: $_fishTypes');
                    final matchingItems = _fishTypes.where((t) => t == _selectedFishType).length;
                    debugPrint('Matching items count: $matchingItems');
                    return DropdownButtonFormField<String>(
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
                            _onFieldChanged();
                          });
                        }
                      },
                    );
                  })(),
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
                      _debugDropdown('FAVOURITE SPOT', _selectedFavouriteSpotId, items);
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
                    _debugDropdown('FISHING TRIP', _selectedTripId, items);
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
                    _debugDropdown('FISHING BUDDY', _selectedFishingBuddyId, items);
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
                    _debugDropdown('WEATHER CONDITION', _selectedWeatherCondition, items);
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
                          _debugDropdown('WIND DIRECTION', _selectedWindDirection, items);
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
                    _debugDropdown('TIDE STAGE', _selectedTideStage, items);
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
                    _debugDropdown('TIDE STRENGTH', _selectedTideStrength, items);
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
                          _debugDropdown('TIDE MOVEMENT', _selectedTideMovement, items);
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
                  
                  // Tide Context - discoverable button
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue.shade200),
                      borderRadius: BorderRadius.circular(8),
                      color: _showTideContext ? Colors.blue.shade50 : Colors.transparent,
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showTideContext = !_showTideContext;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.waves,
                                  color: Colors.blue.shade700,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Record tide timing',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Optional: record how this catch relates to a high or low tide',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  _showTideContext ? Icons.expand_less : Icons.expand_more,
                                  color: Colors.blue.shade700,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showTideContext) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _tideStationNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Tide Station Name',
                                    hintText: 'e.g., Darwin',
                                  ),
                                  onChanged: (_) => _onFieldChanged(),
                                ),
                                const SizedBox(height: 12),
                                (() {
                                  const items = [
                                    DropdownMenuItem(value: 'High', child: Text('High Tide')),
                                    DropdownMenuItem(value: 'Low', child: Text('Low Tide')),
                                  ];
                                  _debugDropdown('REFERENCE TIDE EVENT TYPE', _selectedReferenceTideEventType, items);
                                  return DropdownButtonFormField<String>(
                                    value: _selectedReferenceTideEventType,
                                    decoration: const InputDecoration(labelText: 'Reference Event'),
                                    items: items,
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedReferenceTideEventType = value;
                                        _onFieldChanged();
                                      });
                                    },
                                  );
                                })(),
                                const SizedBox(height: 12),
                                InkWell(
                                  onTap: () async {
                                    final pickedDate = await showDatePicker(
                                      context: context,
                                      initialDate: _referenceTideEventTime ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (pickedDate != null && mounted) {
                                      final pickedTime = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.fromDateTime(
                                          _referenceTideEventTime ?? DateTime.now(),
                                        ),
                                      );
                                      if (pickedTime != null) {
                                        setState(() {
                                          _referenceTideEventTime = DateTime(
                                            pickedDate.year,
                                            pickedDate.month,
                                            pickedDate.day,
                                            pickedTime.hour,
                                            pickedTime.minute,
                                          );
                                          _onFieldChanged();
                                        });
                                      }
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Reference Event Time',
                                    ),
                                    child: Text(
                                      _referenceTideEventTime != null
                                          ? '${_referenceTideEventTime!.day}/${_referenceTideEventTime!.month}/${_referenceTideEventTime!.year} ${_referenceTideEventTime!.hour}:${_referenceTideEventTime!.minute.toString().padLeft(2, '0')}'
                                          : 'Select date and time',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _referenceTideEventHeightController,
                                  decoration: const InputDecoration(
                                    labelText: 'Reference Event Height (m)',
                                    hintText: 'e.g., 6.37',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) => _onFieldChanged(),
                                ),
                                const SizedBox(height: 12),
                                (() {
                                  const items = [
                                    DropdownMenuItem(value: 'Before', child: Text('Before')),
                                    DropdownMenuItem(value: 'After', child: Text('After')),
                                  ];
                                  _debugDropdown('REFERENCE TIDE EVENT RELATION', _selectedReferenceTideEventRelation, items);
                                  return DropdownButtonFormField<String>(
                                    value: _selectedReferenceTideEventRelation,
                                    decoration: const InputDecoration(labelText: 'Relation'),
                                    items: items,
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedReferenceTideEventRelation = value;
                                        _onFieldChanged();
                                      });
                                    },
                                  );
                                })(),
                                const SizedBox(height: 16),
                                // Phrase preview
                                if (_tideStationNameController.text.isNotEmpty &&
                                    _selectedReferenceTideEventType != null &&
                                    _referenceTideEventTime != null &&
                                    _referenceTideEventHeightController.text.isNotEmpty &&
                                    _selectedReferenceTideEventRelation != null)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.blue.shade300),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Preview:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _generateTideContextPhrase(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
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
                    _debugDropdown('WATER CLARITY', _selectedWaterClarity, items);
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
                    _debugDropdown('RIVER FLOW', _selectedRiverFlow, items);
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