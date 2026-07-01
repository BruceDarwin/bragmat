import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';
import '../models/catch_media.dart';
import '../models/environmental_condition.dart';
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_mediaItems.isNotEmpty)
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
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _catchItem.fishType,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_fishingBuddyName != null && _fishingBuddyName != 'Me')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Caught by $_fishingBuddyName',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  _buildSection('Basic Info', [
                    if (_catchItem.dateCaught != null)
                      _buildDetailRow('Date Caught',
                          '${_catchItem.dateCaught!.day}/${_catchItem.dateCaught!.month}/${_catchItem.dateCaught!.year} ${_catchItem.dateCaught!.hour.toString().padLeft(2, '0')}:${_catchItem.dateCaught!.minute.toString().padLeft(2, '0')}'),
                    _buildDetailRow('Length', '${_catchItem.lengthCm} cm'),
                    if (_catchItem.photoDateTime != null)
                      _buildDetailRow('Photo Taken',
                          '${_catchItem.photoDateTime!.day}/${_catchItem.photoDateTime!.month}/${_catchItem.photoDateTime!.year} ${_catchItem.photoDateTime!.hour.toString().padLeft(2, '0')}:${_catchItem.photoDateTime!.minute.toString().padLeft(2, '0')}'),
                  ]),
                  if (_catchItem.location != null && _catchItem.location!.isNotEmpty ||
                      (_catchItem.latitude != null && _catchItem.longitude != null))
                    _buildSection('Location', [
                      if (_catchItem.location != null && _catchItem.location!.isNotEmpty)
                        _buildDetailRow('Location', _catchItem.location!),
                      if (_catchItem.latitude != null && _catchItem.longitude != null)
                        _buildDetailRow('GPS Location',
                            '${_catchItem.latitude!.toStringAsFixed(6)}, ${_catchItem.longitude!.toStringAsFixed(6)}'),
                      if (_catchItem.latitude != null && _catchItem.longitude != null)
                        _buildDetailRow('Coordinate Source', _getCoordinateSource()),
                      if (!_isOnline && _catchItem.latitude != null && _catchItem.longitude != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.cloud_off,
                                  size: 16,
                                  color: Colors.orange.shade700,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Map imagery unavailable while offline',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ]),
                  if (_catchItem.notes != null && _catchItem.notes!.isNotEmpty)
                    _buildSection('Notes', [
                      _buildDetailRow('Notes', _catchItem.notes!),
                    ]),
                  if (_environmentalCondition != null)
                    _buildEnvironmentalSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          if (label.isNotEmpty) const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRowWithIcon(String icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                icon,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvironmentalSection() {
    final envService = EnvironmentalConditionsService();
    final summary = envService.getEnvironmentalSummary(_environmentalCondition);
    
    final condition = _environmentalCondition!;
    final details = <Widget>[];
    
    // Moon phase with icon
    if (condition.moonPhase != null) {
      final moonText = condition.moonIllumination != null 
          ? '${condition.moonPhase!} (${condition.moonIllumination!.toStringAsFixed(0)}%)'
          : condition.moonPhase!;
      details.add(_buildDetailRowWithIcon('🌙', 'Moon', moonText));
    }
    
    // Sunrise with icon
    if (condition.sunriseTime != null) {
      final sunService = SunTimesService();
      final sunrise = sunService.formatTime(condition.sunriseTime!);
      details.add(_buildDetailRowWithIcon('🌅', 'Sunrise', sunrise));
    } else if (condition.latitude != null && condition.longitude != null) {
      details.add(_buildDetailRowWithIcon('🌅', 'Sunrise', 'Not available'));
    }
    
    // Sunset with icon
    if (condition.sunsetTime != null) {
      final sunService = SunTimesService();
      final sunset = sunService.formatTime(condition.sunsetTime!);
      details.add(_buildDetailRowWithIcon('🌇', 'Sunset', sunset));
    } else if (condition.latitude != null && condition.longitude != null) {
      details.add(_buildDetailRowWithIcon('🌇', 'Sunset', 'Not available'));
    }
    
    // Tide section with icon
    final hasTideData = (condition.tideStage != null && condition.tideStage != 'Unknown') ||
                       condition.tideStrength != null ||
                       (condition.tideNotes != null && condition.tideNotes!.isNotEmpty) ||
                       condition.tideHeight != null ||
                       condition.tideMovement != null ||
                       (condition.tideStation != null && condition.tideStation!.isNotEmpty);
    
    if (hasTideData) {
      final tideDetails = <String>[];
      
      if (condition.tideStage != null && condition.tideStage != 'Unknown') {
        tideDetails.add(condition.tideStage!);
      }
      if (condition.tideStrength != null) {
        tideDetails.add(condition.tideStrength!);
      }
      
      if (tideDetails.isNotEmpty) {
        details.add(_buildDetailRowWithIcon('🌊', 'Tide', tideDetails.join(' • ')));
      }
      
      if (condition.tideNotes != null && condition.tideNotes!.isNotEmpty) {
        details.add(_buildDetailRow('', condition.tideNotes!));
      }
      
      if (condition.tideHeight != null) {
        details.add(_buildDetailRow('', 'Height: ${condition.tideHeight!.toStringAsFixed(2)} m'));
      }
      
      if (condition.tideMovement != null) {
        details.add(_buildDetailRow('', 'Movement: ${condition.tideMovement!}'));
      }
      
      if (condition.tideStation != null && condition.tideStation!.isNotEmpty) {
        details.add(_buildDetailRow('', 'Station: ${condition.tideStation!}'));
      }
    }
    
    // Weather with icon
    if (condition.weatherCondition != null && condition.weatherCondition != 'Unknown') {
      details.add(_buildDetailRowWithIcon('☀️', 'Weather', condition.weatherCondition!));
    }
    
    // Temperature
    if (condition.temperature != null) {
      details.add(_buildDetailRow('', '${condition.temperature!.toStringAsFixed(1)}°C'));
    }
    
    // Wind
    if (condition.windDirection != null && condition.windDirection != 'Unknown') {
      final windText = condition.windSpeed != null 
          ? '${condition.windDirection!} • ${condition.windSpeed!.toStringAsFixed(0)} km/h'
          : condition.windDirection!;
      details.add(_buildDetailRowWithIcon('💨', 'Wind', windText));
    } else if (condition.windSpeed != null) {
      details.add(_buildDetailRowWithIcon('💨', 'Wind', '${condition.windSpeed!.toStringAsFixed(0)} km/h'));
    }
    
    // Other conditions
    if (condition.barometricPressure != null) {
      details.add(_buildDetailRow('Barometric Pressure', '${condition.barometricPressure!.toStringAsFixed(1)} hPa'));
    }
    if (condition.rainfall != null) {
      details.add(_buildDetailRow('Rainfall', '${condition.rainfall!.toStringAsFixed(1)} mm'));
    }
    if (condition.riverFlow != null) {
      details.add(_buildDetailRow('River Flow', condition.riverFlow!));
    }
    if (condition.waterClarity != null && condition.waterClarity != 'Unknown') {
      details.add(_buildDetailRow('Water Clarity', condition.waterClarity!));
    }
    
    return _buildSection('Fishing Conditions', details);
  }

  String _getCoordinateSource() {
    // Use the coordinateSource field from the catch
    if (_catchItem.coordinateSource != null && _catchItem.coordinateSource!.isNotEmpty) {
      return _catchItem.coordinateSource!;
    }
    
    // Fallback: Check if any media item has GPS coordinates that match the catch coordinates
    if (_mediaItems.isNotEmpty) {
      for (final media in _mediaItems) {
        if (media.latitude != null && media.longitude != null) {
          // Check if media coordinates match catch coordinates (within small tolerance)
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
