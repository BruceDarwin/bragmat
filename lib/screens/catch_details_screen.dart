import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';
import '../models/catch_media.dart';
import '../models/environmental_condition.dart';
import '../models/fishing_trip.dart';
import '../widgets/bragmat_section_card.dart';
import 'add_catch_screen.dart';
import 'photo_viewer_screen.dart';
import 'catch_map_screen.dart';
import '../services/connectivity_service.dart';
import '../services/environmental_conditions_service.dart';
import '../services/sun_times_service.dart';

class CatchDetailsScreen extends StatefulWidget {
  final Catch catchItem;

  const CatchDetailsScreen({super.key, required this.catchItem});

  @override
  State<CatchDetailsScreen> createState() => _CatchDetailsScreenState();
}

class _CatchDetailsScreenState extends State<CatchDetailsScreen> {
  late Catch _catchItem;
  String? _fishingBuddyName;
  List<CatchMedia> _mediaItems = [];
  bool _isOnline = true;
  final ConnectivityService _connectivityService = ConnectivityService();
  EnvironmentalCondition? _environmentalCondition;

  @override
  void initState() {
    super.initState();
    _catchItem = widget.catchItem;
    _loadFishingBuddyName();
    _loadMedia();
    _loadEnvironmentalCondition();
    _checkConnectivity();
    _connectivityService.connectivityStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  Future<void> _checkConnectivity() async {
    final isOnline = await _connectivityService.checkConnection();
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
      });
    }
  }

  Future<void> _loadFishingBuddyName() async {
    if (_catchItem.fishingBuddyId != null) {
      final buddies = await DatabaseHelper.instance.getFishingBuddies();
      final buddy = buddies.firstWhere(
        (b) => b.id == _catchItem.fishingBuddyId,
        orElse: () => FishingBuddy(name: 'Unknown'),
      );
      if (mounted) {
        setState(() {
          _fishingBuddyName = buddy.name;
        });
      }
    }
  }

  Future<void> _loadMedia() async {
    if (_catchItem.id != null) {
      final media = await DatabaseHelper.instance.getMediaForCatch(_catchItem.id!);
      if (mounted) {
        setState(() {
          _mediaItems = media;
        });
      }
    }
  }

  Future<void> _loadEnvironmentalCondition() async {
    debugPrint('=== _loadEnvironmentalCondition ===');
    debugPrint('Catch ID: ${_catchItem.id}');
    debugPrint('Catch date: ${_catchItem.dateCaught?.toIso8601String()}');
    debugPrint('Catch latitude: ${_catchItem.latitude}');
    debugPrint('Catch longitude: ${_catchItem.longitude}');
    
    if (_catchItem.id != null) {
      final envService = EnvironmentalConditionsService();
      final condition = await envService.getEnvironmentalConditionForCatch(_catchItem.id!);
      debugPrint('Environmental condition found: ${condition != null}');
      if (condition != null) {
        debugPrint('  Moon Phase: ${condition.moonPhase}');
        debugPrint('  Moon Illumination: ${condition.moonIllumination?.toStringAsFixed(1)}%');
        debugPrint('  Sunrise: ${condition.sunriseTime?.toIso8601String()}');
        debugPrint('  Sunset: ${condition.sunsetTime?.toIso8601String()}');
      }
      if (mounted) {
        setState(() {
          _environmentalCondition = condition;
        });
      }
    }
    debugPrint('=== End _loadEnvironmentalCondition ===');
  }

  Future<void> _deleteMedia(int mediaId) async {
    await DatabaseHelper.instance.deleteCatchMedia(mediaId);
    await _loadMedia();
  }

  Future<void> _setAsPrimary(int mediaId) async {
    await DatabaseHelper.instance.setPrimaryMedia(mediaId);
    await _loadMedia();
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Catch'),
        content: Text('Are you sure you want to delete ${_catchItem.fishType}?'),
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

    if (confirmed == true && _catchItem.id != null) {
      await DatabaseHelper.instance.deleteCatch(_catchItem.id!);
      if (context.mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catch Details'),
        actions: [
          if (_catchItem.latitude != null && _catchItem.longitude != null)
            IconButton(
              icon: const Icon(Icons.map),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CatchMapScreen(centerOnCatch: _catchItem),
                  ),
                );
              },
              tooltip: 'View on Map',
            ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final edited = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddCatchScreen(catchToEdit: _catchItem),
                ),
              );
              if (edited is Catch && mounted) {
                setState(() {
                  _catchItem = edited;
                });
                // Reload fishing buddy name in case it changed
                _loadFishingBuddyName();
                // Return true to parent to trigger refresh
                Navigator.pop(context, true);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _showDeleteDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Photo Section
            if (_mediaItems.isNotEmpty)
              BragmatSectionCard(
                icon: Icons.photo_camera,
                title: 'Catch Photo',
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _mediaItems.length,
                    itemBuilder: (context, index) {
                      final media = _mediaItems[index];
                      return Stack(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PhotoViewerScreen(imagePath: media.filePath),
                                ),
                              );
                            },
                            child: Hero(
                              tag: 'catch_photo_${media.id}',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(media.filePath),
                                  width: double.infinity,
                                  height: 200,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          if (media.role == 'primary')
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Primary',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: PopupMenuButton<String>(
                              icon: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.more_vert,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              onSelected: (value) async {
                                if (value == 'delete') {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Delete Photo'),
                                      content: const Text('Are you sure you want to delete this photo?'),
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
                                  if (confirmed == true) {
                                    await _deleteMedia(media.id!);
                                  }
                                } else if (value == 'primary') {
                                  await _setAsPrimary(media.id!);
                                }
                              },
                              itemBuilder: (context) => [
                                if (media.role != 'primary')
                                  const PopupMenuItem(
                                    value: 'primary',
                                    child: Text('Set as Primary'),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            if (_mediaItems.isNotEmpty) const SizedBox(height: 16),

            // Catch Details Section
            BragmatSectionCard(
              icon: Icons.catching_pokemon,
              title: 'Catch Details',
              children: [
                Text(
                  _catchItem.fishType,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (_fishingBuddyName != null && _fishingBuddyName != 'Me')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Caught by $_fishingBuddyName',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                const SizedBox(height: 12),
                BragmatDataRow(
                  icon: Icons.straighten,
                  label: 'Length',
                  value: '${_catchItem.lengthCm} cm',
                ),
                if (_catchItem.photoDateTime != null)
                  BragmatDataRow(
                    icon: Icons.camera_alt,
                    label: 'Photo Taken',
                    value: '${_catchItem.photoDateTime!.day}/${_catchItem.photoDateTime!.month}/${_catchItem.photoDateTime!.year} ${_catchItem.photoDateTime!.hour.toString().padLeft(2, '0')}:${_catchItem.photoDateTime!.minute.toString().padLeft(2, '0')}',
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Date & Time Section
            if (_catchItem.dateCaught != null)
              BragmatSectionCard(
                icon: Icons.calendar_today,
                title: 'Date & Time',
                children: [
                  BragmatDataRow(
                    icon: Icons.event,
                    label: 'Date Caught',
                    value: '${_catchItem.dateCaught!.day}/${_catchItem.dateCaught!.month}/${_catchItem.dateCaught!.year}',
                  ),
                  BragmatDataRow(
                    icon: Icons.access_time,
                    label: 'Time Caught',
                    value: '${_catchItem.dateCaught!.hour.toString().padLeft(2, '0')}:${_catchItem.dateCaught!.minute.toString().padLeft(2, '0')}',
                  ),
                ],
              ),
            if (_catchItem.dateCaught != null) const SizedBox(height: 16),

            // Location Section
            if (_catchItem.location != null && _catchItem.location!.isNotEmpty ||
                (_catchItem.latitude != null && _catchItem.longitude != null))
              BragmatSectionCard(
                icon: Icons.location_on,
                title: 'Location',
                children: [
                  if (_catchItem.location != null && _catchItem.location!.isNotEmpty)
                    BragmatDataRow(
                      icon: Icons.place,
                      label: 'Location Name',
                      value: _catchItem.location!,
                    ),
                  if (_catchItem.latitude != null && _catchItem.longitude != null)
                    BragmatDataRow(
                      icon: Icons.gps_fixed,
                      label: 'GPS Coordinates',
                      value: '${_catchItem.latitude!.toStringAsFixed(6)}, ${_catchItem.longitude!.toStringAsFixed(6)}',
                    ),
                  if (_catchItem.latitude != null && _catchItem.longitude != null)
                    BragmatDataRow(
                      icon: Icons.info_outline,
                      label: 'Coordinate Source',
                      value: _getCoordinateSource(),
                    ),
                  if (!_isOnline && _catchItem.latitude != null && _catchItem.longitude != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: 20,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Map imagery unavailable while offline',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            if (_catchItem.location != null && _catchItem.location!.isNotEmpty ||
                (_catchItem.latitude != null && _catchItem.longitude != null))
              const SizedBox(height: 16),

            // Trip Section
            if (_catchItem.tripId != null || _fishingBuddyName != null)
              BragmatSectionCard(
                icon: Icons.directions_boat,
                title: 'Trip',
                children: [
                  if (_catchItem.tripId != null)
                    FutureBuilder(
                      future: DatabaseHelper.instance.getFishingTrip(_catchItem.tripId!),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return BragmatDataRow(
                            icon: Icons.directions_boat,
                            label: 'Fishing Trip',
                            value: snapshot.data!.name,
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  if (_fishingBuddyName != null && _fishingBuddyName != 'Me')
                    BragmatDataRow(
                      icon: Icons.person,
                      label: 'Fishing Buddy',
                      value: _fishingBuddyName!,
                    ),
                ],
              ),
            if (_catchItem.tripId != null || _fishingBuddyName != null)
              const SizedBox(height: 16),

            // Environmental Conditions Section
            if (_environmentalCondition != null)
              BragmatSectionCard(
                icon: Icons.wb_sunny,
                title: 'Environmental Conditions',
                initiallyExpanded: false,
                children: _buildEnvironmentalDetails(),
              ),
            if (_environmentalCondition != null) const SizedBox(height: 16),

            // Notes Section
            if (_catchItem.notes != null && _catchItem.notes!.isNotEmpty)
              BragmatSectionCard(
                icon: Icons.note,
                title: 'Notes',
                children: [
                  Text(
                    _catchItem.notes!,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEnvironmentalDetails() {
    final condition = _environmentalCondition!;
    final details = <Widget>[];

    // Moon
    if (condition.moonPhase != null) {
      final moonText = condition.moonIllumination != null
          ? '${condition.moonPhase!} (${condition.moonIllumination!.toStringAsFixed(0)}%)'
          : condition.moonPhase!;
      details.add(BragmatDataRow(
        icon: Icons.nightlight,
        label: 'Moon Phase',
        value: moonText,
      ));
    }

    // Sun times
    if (condition.sunriseTime != null || condition.sunsetTime != null) {
      final sunService = SunTimesService();
      if (condition.sunriseTime != null) {
        details.add(BragmatDataRow(
          icon: Icons.wb_sunny,
          label: 'Sunrise',
          value: sunService.formatTime(condition.sunriseTime!),
        ));
      }
      if (condition.sunsetTime != null) {
        details.add(BragmatDataRow(
          icon: Icons.bedtime,
          label: 'Sunset',
          value: sunService.formatTime(condition.sunsetTime!),
        ));
      }
    }

    // Weather
    if (condition.weatherCondition != null || condition.temperature != null) {
      if (condition.weatherCondition != null && condition.weatherCondition != 'Unknown') {
        details.add(BragmatDataRow(
          icon: Icons.cloud,
          label: 'Weather',
          value: condition.weatherCondition!,
        ));
      }
      if (condition.temperature != null) {
        details.add(BragmatDataRow(
          icon: Icons.thermostat,
          label: 'Temperature',
          value: '${condition.temperature!.toStringAsFixed(1)}°C',
        ));
      }
      if (condition.humidity != null) {
        details.add(BragmatDataRow(
          icon: Icons.water_drop,
          label: 'Humidity',
          value: '${condition.humidity!.toStringAsFixed(0)}%',
        ));
      }
      if (condition.cloudCover != null) {
        details.add(BragmatDataRow(
          icon: Icons.cloud_queue,
          label: 'Cloud Cover',
          value: '${condition.cloudCover!.toStringAsFixed(0)}%',
        ));
      }
    }

    // Wind
    if (condition.windDirection != null || condition.windSpeed != null) {
      final windText = condition.windDirection != null && condition.windDirection != 'Unknown'
          ? (condition.windSpeed != null
              ? '${condition.windDirection!} • ${condition.windSpeed!.toStringAsFixed(0)} km/h'
              : condition.windDirection!)
          : (condition.windSpeed != null
              ? '${condition.windSpeed!.toStringAsFixed(0)} km/h'
              : null);
      if (windText != null) {
        details.add(BragmatDataRow(
          icon: Icons.air,
          label: 'Wind',
          value: windText,
        ));
      }
    }

    // Tide
    if (condition.tideStage != null || condition.tideStrength != null) {
      // Main tide stage display
      if (condition.tideStage != null && condition.tideStage != 'Unknown') {
        details.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.waves, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    condition.tideStage!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        // Show strength if available
        if (condition.tideStrength != null) {
          details.add(
            Padding(
              padding: const EdgeInsets.only(left: 36, bottom: 8),
              child: Text(
                condition.tideStrength!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[700],
                ),
              ),
            ),
          );
        }
      }

      // Tide details
      final tideDetails = <Widget>[];
      
      // Movement
      if (condition.tideMovement != null && condition.tideMovement != 'Unknown') {
        tideDetails.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const SizedBox(width: 36),
                Text(
                  'Movement: ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  condition.tideMovement!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      }

      // Height (manual only)
      if (condition.tideHeight != null && condition.tideObservedOrEstimated == 'Observed') {
        tideDetails.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const SizedBox(width: 36),
                Text(
                  'Height: ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${condition.tideHeight!.toStringAsFixed(2)} m',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      }

      // Confidence (estimated only)
      if (condition.tideConfidence != null && condition.tideObservedOrEstimated == 'Estimated') {
        tideDetails.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const SizedBox(width: 36),
                Text(
                  'Confidence: ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  condition.tideConfidence!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      }

      // Source attribution
      if (condition.tideObservedOrEstimated != null) {
        tideDetails.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const SizedBox(width: 36),
                Text(
                  'Source: ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Expanded(
                  child: Text(
                    condition.tideObservedOrEstimated == 'Estimated'
                        ? 'Estimated from ${condition.tideDataSource ?? 'Open-Meteo Marine'}'
                        : 'Manual observation',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // Notes
      if (condition.tideNotes != null && condition.tideNotes!.isNotEmpty) {
        tideDetails.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 36),
            child: Text(
              condition.tideNotes!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );
      }

      details.addAll(tideDetails);
    }

    // Water conditions
    if (condition.waterClarity != null || condition.riverFlow != null) {
      if (condition.waterClarity != null && condition.waterClarity != 'Unknown') {
        details.add(BragmatDataRow(
          icon: Icons.visibility,
          label: 'Water Clarity',
          value: condition.waterClarity!,
        ));
      }
      if (condition.riverFlow != null) {
        details.add(BragmatDataRow(
          icon: Icons.waves,
          label: 'River Flow',
          value: condition.riverFlow!,
        ));
      }
    }

    // Other
    if (condition.barometricPressure != null) {
      details.add(BragmatDataRow(
        icon: Icons.speed,
        label: 'Barometric Pressure',
        value: '${condition.barometricPressure!.toStringAsFixed(1)} hPa',
      ));
    }
    if (condition.rainfall != null) {
      details.add(BragmatDataRow(
        icon: Icons.grain,
        label: 'Rainfall',
        value: '${condition.rainfall!.toStringAsFixed(1)} mm',
      ));
    }

    return details;
  }

  String _getCoordinateSource() {
    if (_catchItem.coordinateSource != null && _catchItem.coordinateSource!.isNotEmpty) {
      return _catchItem.coordinateSource!;
    }
    
    if (_mediaItems.isNotEmpty) {
      for (final media in _mediaItems) {
        if (media.latitude != null && media.longitude != null) {
          final latDiff = (media.latitude! - (_catchItem.latitude ?? 0)).abs();
          final lonDiff = (media.longitude! - (_catchItem.longitude ?? 0)).abs();
          if (latDiff < 0.000001 && lonDiff < 0.000001) {
            return 'Photo EXIF';
          }
        }
      }
    }
    return 'Manual';
  }
}
