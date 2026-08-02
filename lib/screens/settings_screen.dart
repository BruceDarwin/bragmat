import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';
import '../models/favourite_spot.dart';
import '../models/lure.dart';
import '../models/bait.dart';
import '../models/tide_reference.dart';
import '../services/backup_service.dart';
import '../services/preferences_service.dart';
import '../services/environmental_conditions_service.dart';
import '../services/worldtides_service.dart';
import '../services/secure_storage_service.dart';
import '../services/tide_reference_service.dart';
import '../widgets/bragmat_section_card.dart';
import 'favourite_spots_screen.dart';
import 'achievements_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _fishTypes = [];
  List<Catch> _catches = [];
  List<FishingBuddy> _fishingBuddies = [];
  List<Lure> _lures = [];
  List<Bait> _baits = [];
  FishTypeSelectionMode _fishTypeSelectionMode = FishTypeSelectionMode.noDefault;
  String? _defaultFishType;
  String? _worldTidesApiKey;
  String? _apiTestStatus;
  TideReference? _currentTideReference;

  @override
  void initState() {
    super.initState();
    _loadFishTypes();
    _loadStatistics();
    _loadFishingBuddies();
    _loadLures();
    _loadBaits();
    _loadFishTypePreferences();
    _loadWorldTidesApiKey();
    _loadTideReference();
    _migrateApiKey();
  }

  Future<void> _loadStatistics() async {
    final catches = await DatabaseHelper.instance.getCatches();
    final fishTypes = await DatabaseHelper.instance.getFishTypes();
    setState(() {
      _catches = catches;
      _fishTypes = fishTypes;
    });
    // Validate default fish type after fish types are loaded
    await _validateDefaultFishType();
  }

  Future<void> _loadFishTypes() async {
    final types = await DatabaseHelper.instance.getFishTypes();
    setState(() {
      _fishTypes = types;
    });
  }

  Future<void> _loadFishingBuddies() async {
    final buddies = await DatabaseHelper.instance.getFishingBuddies();
    setState(() {
      _fishingBuddies = buddies;
    });
  }

  Future<void> _loadLures() async {
    final lures = await DatabaseHelper.instance.getLures();
    setState(() {
      _lures = lures;
    });
  }

  Future<void> _loadBaits() async {
    final baits = await DatabaseHelper.instance.getBaits();
    setState(() {
      _baits = baits;
    });
  }

  Future<void> _loadFishTypePreferences() async {
    final mode = await PreferencesService.getFishTypeSelectionMode();
    final defaultFishType = await PreferencesService.getDefaultFishType();
    setState(() {
      _fishTypeSelectionMode = mode;
      _defaultFishType = defaultFishType;
    });
  }

  Future<void> _validateDefaultFishType() async {
    if (_defaultFishType != null) {
      final safeValue = _safeDropdownValue(_defaultFishType, _fishTypes);
      if (safeValue == null) {
        // Default fish type is invalid, clear it
        await PreferencesService.setDefaultFishType(null);
        setState(() {
          _defaultFishType = null;
        });
        // If default is cleared, revert to No Default mode
        if (_fishTypeSelectionMode == FishTypeSelectionMode.defaultFishType) {
          await PreferencesService.setFishTypeSelectionMode(FishTypeSelectionMode.noDefault);
          setState(() {
            _fishTypeSelectionMode = FishTypeSelectionMode.noDefault;
          });
        }
      }
    }
  }

  Future<void> _loadWorldTidesApiKey() async {
    final apiKey = await SecureStorageService.getWorldTidesApiKey();
    setState(() {
      _worldTidesApiKey = apiKey;
    });
  }

  Future<void> _migrateApiKey() async {
    await SecureStorageService.migrateApiKey();
  }

  Future<void> _setFishTypeSelectionMode(FishTypeSelectionMode mode) async {
    await PreferencesService.setFishTypeSelectionMode(mode);
    setState(() {
      _fishTypeSelectionMode = mode;
    });
  }

  Future<void> _setDefaultFishType(String? fishType) async {
    await PreferencesService.setDefaultFishType(fishType);
    setState(() {
      _defaultFishType = fishType;
    });
  }

  Future<void> _setWorldTidesApiKey(String? apiKey) async {
    await SecureStorageService.setWorldTidesApiKey(apiKey);
    setState(() {
      _worldTidesApiKey = apiKey;
    });
  }

  Future<void> _clearWorldTidesApiKey() async {
    await SecureStorageService.deleteWorldTidesApiKey();
    setState(() {
      _worldTidesApiKey = null;
    });
  }

  Future<void> _loadTideReference() async {
    final reference = await TideReferenceService.getCurrentReference();
    setState(() {
      _currentTideReference = reference;
    });
  }

  Future<void> _setTideReferenceMode(String mode) async {
    if (mode == 'automatic') {
      await TideReferenceService.setAutomaticMode();
    } else {
      await TideReferenceService.setFixedReference('darwin');
    }
    await _loadTideReference();
  }

  /// Safely validate dropdown value exists exactly once in the list
  /// Returns null if value is missing or duplicated
  String? _safeDropdownValue(String? value, List<String> items) {
    if (value == null) {
      return null;
    }
    // Count occurrences of the value
    final count = items.where((item) => item == value).length;
    if (count == 1) {
      return value;
    }
    // Value is missing or duplicated, return null
    return null;
  }

  Future<void> _testWorldTidesApi() async {
    final apiKey = await SecureStorageService.getWorldTidesApiKey();
    
    if (apiKey == null || apiKey.isEmpty) {
      _showWorldTidesTestResult(
        success: false,
        message: 'No API key configured. Please enter your WorldTides API key first.',
        details: null,
      );
      return;
    }

    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Testing WorldTides API variants...'),
          ],
        ),
      ),
    );

    try {
      // Test multiple request variants
      final results = await _testWorldTidesVariants(apiKey);
      
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      _showWorldTidesVariantResults(results);
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      _showWorldTidesTestResult(
        success: false,
        message: 'WorldTides API test failed.',
        details: 'Error: $e',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _testWorldTidesVariants(String apiKey) async {
    final results = <Map<String, dynamic>>[];
    
    // Test coordinates
    final testCoordinates = [
      {'name': 'Darwin/Nightcliff', 'lat': -12.376717, 'lon': 130.8508711},
      {'name': 'Darwin Harbour', 'lat': -12.4634, 'lon': 130.8446},
      {'name': 'Fort Hill Wharf', 'lat': -12.4650, 'lon': 130.8370},
    ];
    
    final testDate = DateTime.now();
    final dateStr = '${testDate.year}-${testDate.month.toString().padLeft(2, '0')}-${testDate.day.toString().padLeft(2, '0')}';
    
    // Test variants
    final variants = [
      {
        'name': 'extremes only',
        'params': {
          'extremes': '',
          'lat': '',
          'lon': '',
          'date': dateStr,
          'key': apiKey,
          'stations': '',
          'localtime': '',
          'timezone': 'auto',
          'days': '3',
        },
      },
      {
        'name': 'heights only',
        'params': {
          'heights': '',
          'lat': '',
          'lon': '',
          'date': dateStr,
          'key': apiKey,
          'stations': '',
          'localtime': '',
          'timezone': 'auto',
          'days': '3',
        },
      },
      {
        'name': 'extremes + heights',
        'params': {
          'extremes': '',
          'heights': '',
          'lat': '',
          'lon': '',
          'date': dateStr,
          'key': apiKey,
          'stations': '',
          'localtime': '',
          'timezone': 'auto',
          'days': '3',
        },
      },
      {
        'name': 'extremes (no stations/timezone/localtime)',
        'params': {
          'extremes': '',
          'lat': '',
          'lon': '',
          'date': dateStr,
          'key': apiKey,
          'days': '3',
        },
      },
      {
        'name': 'extremes + stationDistance',
        'params': {
          'extremes': '',
          'lat': '',
          'lon': '',
          'date': dateStr,
          'key': apiKey,
          'stations': '',
          'localtime': '',
          'timezone': 'auto',
          'days': '3',
          'stationDistance': '50',
        },
      },
    ];
    
    for (final coord in testCoordinates) {
      for (final variant in variants) {
        final params = Map<String, String>.from(variant['params'] as Map<String, String>);
        params['lat'] = coord['lat'].toString();
        params['lon'] = coord['lon'].toString();
        
        final url = Uri.parse('https://www.worldtides.info/api/v3').replace(queryParameters: params);
        final redactedUrl = url.toString().replaceAll(RegExp(r'key=[^&\s]+'), 'key=REDACTED');
        
        try {
          final response = await http.get(url).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timed out');
            },
          );
          
          final responseBody = response.body;
          final redactedBody = responseBody.replaceAll(RegExp(r'key=[^&\s]+'), 'key=REDACTED');
          
          final data = json.decode(responseBody);
          
          final stations = data['stations'] as List?;
          final extremes = data['extremes'];
          final heights = data['heights'];
          final error = data['error'] as String?;
          final message = data['message'] as String?;
          
          String? stationName;
          double? stationDistance;
          if (stations != null && stations.isNotEmpty) {
            final station = stations.first;
            stationName = station['name'] as String?;
            stationDistance = (station['distance'] as num?)?.toDouble();
          }
          
          results.add({
            'variant': variant['name'],
            'location': coord['name'],
            'url': redactedUrl,
            'status': response.statusCode,
            'stationName': stationName,
            'stationDistance': stationDistance,
            'extremes': extremes != null ? (extremes is List ? '${(extremes as List).length} events' : 'non-null') : 'null',
            'heights': heights != null ? (heights is List ? '${(heights as List).length} points' : 'non-null') : 'null',
            'error': error,
            'message': message,
            'success': extremes != null && extremes is List && (extremes as List).isNotEmpty,
          });
          
          debugPrint('WorldTides Test: ${coord['name']} - ${variant['name']} - Status: ${response.statusCode}');
          debugPrint('WorldTides Test: URL: $redactedUrl');
          debugPrint('WorldTides Test: Station: $stationName, Distance: $stationDistance');
          debugPrint('WorldTides Test: Extremes: ${results.last['extremes']}, Heights: ${results.last['heights']}');
          if (error != null) debugPrint('WorldTides Test: Error: $error');
          if (message != null) debugPrint('WorldTides Test: Message: $message');
          
        } catch (e) {
          results.add({
            'variant': variant['name'],
            'location': coord['name'],
            'url': redactedUrl,
            'status': 'ERROR',
            'stationName': null,
            'stationDistance': null,
            'extremes': 'error',
            'heights': 'error',
            'error': e.toString(),
            'message': null,
            'success': false,
          });
          debugPrint('WorldTides Test: ${coord['name']} - ${variant['name']} - Error: $e');
        }
      }
    }
    
    return results;
  }

  void _showWorldTidesVariantResults(List<Map<String, dynamic>> results) {
    final successfulResults = results.where((r) => r['success'] as bool).toList();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              successfulResults.isNotEmpty ? Icons.check_circle : Icons.error,
              color: successfulResults.isNotEmpty ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('WorldTides API Test Results'),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 500,
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final result = results[index];
              final success = result['success'] as bool;
              
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: success ? Colors.green[50] : Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            success ? Icons.check_circle : Icons.info,
                            size: 16,
                            color: success ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${result['location']} - ${result['variant']}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Status: ${result['status']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Station: ${result['stationName'] ?? 'None'}'),
                      Text('Distance: ${result['stationDistance']?.toStringAsFixed(1) ?? 'N/A'} km'),
                      Text('Extremes: ${result['extremes']}'),
                      Text('Heights: ${result['heights']}'),
                      if (result['error'] != null)
                        Text('Error: ${result['error']}', style: const TextStyle(color: Colors.red)),
                      if (result['message'] != null)
                        Text('Message: ${result['message']}', style: const TextStyle(color: Colors.blue)),
                      const SizedBox(height: 4),
                      Text(
                        result['url'] as String,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showWorldTidesTestResult({
    required bool success,
    required String message,
    String? details,
  }) {
    setState(() {
      _apiTestStatus = success ? 'success' : 'failed';
    });
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(success ? 'API Test Successful' : 'API Test Failed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (details != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Details:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                details,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showClearApiKeyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear API Key'),
        content: const Text('Are you sure you want to remove the WorldTides API key? This will disable official tide context data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearWorldTidesApiKey();
              setState(() {
                _apiTestStatus = null;
              });
            },
            child: const Text('Clear'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  Future<void> _showFishTypesDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fish Types'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAddFishTypeDialog();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Fish Type'),
              ),
              const SizedBox(height: 16),
              if (_fishTypes.isEmpty)
                const Text('No fish types yet')
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _fishTypes.length,
                    itemBuilder: (context, index) {
                      final fishType = _fishTypes[index];
                      return ListTile(
                        title: Text(fishType),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.pop(context);
                                _showEditFishTypeDialog(fishType);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                Navigator.pop(context);
                                _showDeleteFishTypeDialog(fishType);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFishingBuddiesDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fishing Buddies'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAddFishingBuddyDialog();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Fishing Buddy'),
              ),
              const SizedBox(height: 16),
              if (_fishingBuddies.isEmpty)
                const Text('No fishing buddies yet')
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _fishingBuddies.length,
                    itemBuilder: (context, index) {
                      final buddy = _fishingBuddies[index];
                      return ListTile(
                        title: Text(buddy.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.pop(context);
                                _showEditFishingBuddyDialog(buddy);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                Navigator.pop(context);
                                _showDeleteFishingBuddyDialog(buddy);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecalculateEnvironmentalDataDialog() async {
    // Count catches that would need WorldTides API calls
    final db = await DatabaseHelper.instance.database;
    final catches = await db.query('catches', 
      where: 'latitude IS NOT NULL AND longitude IS NOT NULL',
    );
    
    final envService = EnvironmentalConditionsService();
    int catchesNeedingWorldTides = 0;
    for (final catchMap in catches) {
      final catchId = catchMap['id'] as int;
      final existing = await envService.getEnvironmentalConditionForCatch(catchId);
      // Count if no existing WorldTides context
      if (existing == null || existing.tideContextDataSource != 'WorldTides' || existing.tideContextPhrase == null) {
        catchesNeedingWorldTides++;
      }
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recalculate Environmental Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will update missing automatic environmental data for catches with date/time and GPS coordinates. Manual observations will not be overwritten.',
            ),
            const SizedBox(height: 16),
            if (catchesNeedingWorldTides > 0) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'WorldTides API Usage',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Approximately $catchesNeedingWorldTides API calls will be made to fetch official tide data.',
                      style: TextStyle(color: Colors.orange.shade800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This will consume API credits from your WorldTides account.',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'This may take several minutes depending on the number of catches.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Recalculate'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _recalculateEnvironmentalData();
    }
  }

  Future<void> _showLegacyTideDataDialog() async {
    final envService = EnvironmentalConditionsService();
    
    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('Analyzing Legacy Tide Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning environmental conditions...'),
          ],
        ),
      ),
    );

    // Run diagnostic
    final diagnostic = await envService.diagnoseLegacyTideData();
    
    // Close loading dialog
    if (mounted) {
      Navigator.pop(context);
    }

    // Show results dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Legacy Tide Data Analysis'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Records that may have been incorrectly populated by old Open-Meteo backfill:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text('Total environmental condition records: ${diagnostic['total_records']}'),
                const SizedBox(height: 8),
                Text('Records marked as Manual/Observed: ${diagnostic['manual_data_source']}'),
                const SizedBox(height: 8),
                Text(
                  'Likely generated (no manual indicators): ${diagnostic['likely_generated']}',
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Likely manual (has manual indicators): ${diagnostic['likely_manual']}'),
                const SizedBox(height: 16),
                const Text(
                  'Manual indicators found:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Records with tide context phrase: ${diagnostic['has_tide_context']}'),
                const SizedBox(height: 4),
                Text('Records with tide notes: ${diagnostic['has_tide_notes']}'),
                const SizedBox(height: 4),
                Text('Records with tide height: ${diagnostic['has_tide_height']}'),
                const SizedBox(height: 4),
                Text('Records with tide station: ${diagnostic['has_tide_station']}'),
                const SizedBox(height: 4),
                Text('Records with tide strength: ${diagnostic['has_tide_strength']}'),
                const SizedBox(height: 16),
                const Text(
                  'Note: Manual tide fields should only contain user-entered observations.',
                  style: TextStyle(color: Colors.orange),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Records without manual indicators were likely generated by the old backfill system.',
                  style: TextStyle(color: Colors.orange),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (diagnostic['likely_generated'] > 0)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showCleanupLegacyTideDataDialog(diagnostic['likely_generated'] as int);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
                child: const Text('Clear Legacy Data'),
              ),
          ],
        ),
      );
    }
  }

  Future<void> _showCleanupLegacyTideDataDialog(int likelyGeneratedCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Legacy Estimated Tide Fields'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will clear tide fields from $likelyGeneratedCount records that appear to have been generated by the old Open-Meteo backfill system.'),
            const SizedBox(height: 16),
            const Text(
              'Records will only be cleared if they lack manual indicators:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Tide notes'),
            const Text('• Tide height'),
            const Text('• Tide station'),
            const Text('• Tide strength'),
            const Text('• Tide context phrase'),
            const SizedBox(height: 16),
            const Text(
              'Records with any of these indicators will be preserved as manual observations.',
              style: TextStyle(color: Colors.green),
            ),
            const SizedBox(height: 16),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Clear Legacy Data'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _cleanupLegacyTideData();
    }
  }

  Future<void> _cleanupLegacyTideData() async {
    // Show progress dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('Clearing Legacy Tide Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing records...'),
          ],
        ),
      ),
    );

    final envService = EnvironmentalConditionsService();
    final cleanedCount = await envService.cleanupLegacyTideData();

    // Show results
    if (mounted) {
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Legacy Tide Data Cleanup Complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Records cleaned: $cleanedCount'),
              const SizedBox(height: 16),
              const Text(
                'Cleared fields: tideStage, tideMovement, tideStrength, tideHeight, tideStation, tideNotes, tideDataSource, tideObservedOrEstimated',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _recalculateEnvironmentalData() async {
    // Show progress dialog
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Recalculating Environmental Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Processed: 0'),
            const SizedBox(height: 8),
            Text('Updated: 0'),
            const SizedBox(height: 8),
            Text('Skipped: 0'),
          ],
        ),
      ),
    );

    final envService = EnvironmentalConditionsService();
    int processed = 0;
    int updated = 0;
    int skipped = 0;

    try {
      final result = await envService.recalculateEnvironmentalDataForAllCatches(
        onProgress: (proc, upd, skip) {
          processed = proc;
          updated = upd;
          skipped = skip;
          // Update dialog if still mounted
          if (mounted) {
            Navigator.pop(context);
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Recalculating Environmental Data'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Processed: $processed'),
                    const SizedBox(height: 8),
                    Text('Updated: $updated'),
                    const SizedBox(height: 8),
                    Text('Skipped: $skipped'),
                  ],
                ),
              ),
            );
          }
        },
      );

      // Show results
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Environmental Recalculation Complete'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Processed: ${result['processed']}'),
                const SizedBox(height: 8),
                Text('Updated: ${result['updated']}'),
                const SizedBox(height: 8),
                Text('Skipped: ${result['skipped']}'),
                const SizedBox(height: 8),
                if (result['failed']! > 0)
                  Text('Failed: ${result['failed']}', style: const TextStyle(color: Colors.red)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showClearAllDataDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete all catches, fish types, fishing buddies, and favourite spots. This action cannot be undone.\n\nAre you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All Data'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.deleteAllCatches();
      await DatabaseHelper.instance.deleteAllFishTypes();
      await DatabaseHelper.instance.deleteAllFishingBuddies();
      // Delete all favourite spots
      final spots = await DatabaseHelper.instance.getFavouriteSpots();
      for (final spot in spots) {
        await DatabaseHelper.instance.deleteFavouriteSpot(spot.id!);
      }
      await DatabaseHelper.instance.deleteAllFishingTrips();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared')),
        );
        _loadStatistics();
        _loadFishTypes();
        _loadFishingBuddies();
      }
    }
  }

  Future<void> _showAboutDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Bragmat'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bragmat helps anglers record, manage and review their fishing catches.',
            ),
            SizedBox(height: 16),
            Text(
              'Version: 1.0.0',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Database Version: 1',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Website: Coming Soon',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDataSourcesDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Data Sources'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weather Data',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Open-Meteo Weather API'),
              Text('Free, non-commercial use'),
              SizedBox(height: 16),
              Text(
                'Tide Data',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Open-Meteo Marine API'),
              Text('Model-based sea level height including ocean tides'),
              SizedBox(height: 8),
              Text(
                'Important:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
              ),
              Text(
                'Tide data is model-based and indicative only.',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                'Not suitable for navigation.',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                'May be inaccurate in coastal areas, rivers, and estuaries.',
                style: TextStyle(color: Colors.orange),
              ),
              SizedBox(height: 8),
              Text(
                'Datum Difference:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
              ),
              Text(
                'Open-Meteo tide data is relative to mean sea level (MSL).',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                'Official tide tables use tide chart datum (LAT/MLLW).',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                'Open-Meteo is used only to estimate tide movement/stage.',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                'It is NOT equivalent to official tide table heights.',
                style: TextStyle(color: Colors.orange),
              ),
              SizedBox(height: 16),
              Text(
                'Moon & Sun Data',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Calculated using astronomical algorithms'),
              SizedBox(height: 16),
              Text(
                'Data Accuracy',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Manual observations always take precedence'),
              Text('API data is for reference only'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFishTypeDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Fish Type'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Fish Type Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      // Check for duplicates (case-insensitive, ignoring extra spaces)
      final normalized = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final exists = _fishTypes.any((type) =>
        type.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == normalized);

      if (!exists) {
        final result = await DatabaseHelper.instance.insertFishType(name);
        if (result != -1) {
          _loadFishTypes();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fish type added')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fish type already exists')),
          );
        }
      }
    }
  }

  // LURES
  Future<void> _showLuresDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lures'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAddLureDialog();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Lure'),
              ),
              const SizedBox(height: 16),
              if (_lures.isEmpty)
                const Text('No lures yet')
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _lures.length,
                    itemBuilder: (context, index) {
                      final lure = _lures[index];
                      return ListTile(
                        title: Text(lure.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.pop(context);
                                _showEditLureDialog(lure);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                Navigator.pop(context);
                                _showDeleteLureDialog(lure);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddLureDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Lure'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Lure Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      final normalized = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final exists = _lures.any((lure) =>
        lure.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == normalized);

      if (!exists) {
        final result = await DatabaseHelper.instance.insertLure(name);
        if (result != -1) {
          _loadLures();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Lure added')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lure already exists')),
          );
        }
      }
    }
  }

  Future<void> _showEditLureDialog(Lure lure) async {
    final controller = TextEditingController(text: lure.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Lure'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Lure Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      if (name != lure.name) {
        // Delete old and insert new (simple approach for unique constraint)
        await DatabaseHelper.instance.deleteLure(lure.id!);
        final result = await DatabaseHelper.instance.insertLure(name);
        if (result != -1) {
          _loadLures();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Lure updated')),
            );
          }
        }
      }
    }
  }

  Future<void> _showDeleteLureDialog(Lure lure) async {
    final isUsed = await DatabaseHelper.instance.isLureUsed(lure.id!);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Lure'),
        content: Text(
          isUsed
              ? 'This lure is used by catches. Deleting it will remove the lure reference from those catches. Are you sure you want to delete "${lure.name}"?'
              : 'Are you sure you want to delete "${lure.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.deleteLure(lure.id!);
      _loadLures();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lure deleted')),
        );
      }
    }
  }

  // BAITS
  Future<void> _showBaitsDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Baits'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAddBaitDialog();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Bait'),
              ),
              const SizedBox(height: 16),
              if (_baits.isEmpty)
                const Text('No baits yet')
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _baits.length,
                    itemBuilder: (context, index) {
                      final bait = _baits[index];
                      return ListTile(
                        title: Text(bait.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.pop(context);
                                _showEditBaitDialog(bait);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                Navigator.pop(context);
                                _showDeleteBaitDialog(bait);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddBaitDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Bait'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Bait Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      final normalized = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final exists = _baits.any((bait) =>
        bait.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == normalized);

      if (!exists) {
        final result = await DatabaseHelper.instance.insertBait(name);
        if (result != -1) {
          _loadBaits();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bait added')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bait already exists')),
          );
        }
      }
    }
  }

  Future<void> _showEditBaitDialog(Bait bait) async {
    final controller = TextEditingController(text: bait.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Bait'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Bait Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      if (name != bait.name) {
        // Delete old and insert new (simple approach for unique constraint)
        await DatabaseHelper.instance.deleteBait(bait.id!);
        final result = await DatabaseHelper.instance.insertBait(name);
        if (result != -1) {
          _loadBaits();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bait updated')),
            );
          }
        }
      }
    }
  }

  Future<void> _showDeleteBaitDialog(Bait bait) async {
    final isUsed = await DatabaseHelper.instance.isBaitUsed(bait.id!);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bait'),
        content: Text(
          isUsed
              ? 'This bait is used by catches. Deleting it will remove the bait reference from those catches. Are you sure you want to delete "${bait.name}"?'
              : 'Are you sure you want to delete "${bait.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.deleteBait(bait.id!);
      _loadBaits();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bait deleted')),
        );
      }
    }
  }

  Future<void> _showEditFishTypeDialog(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Fish Type'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Fish Type Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();
      if (newName != oldName) {
        // Check for duplicates (case-insensitive, ignoring extra spaces)
        final normalized = newName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final exists = _fishTypes.any((type) =>
          type.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == normalized && type != oldName);

        if (!exists) {
          await DatabaseHelper.instance.updateFishType(oldName, newName);
          _loadFishTypes();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fish type updated')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fish type already exists')),
            );
          }
        }
      }
    }
  }

  Future<void> _showDeleteFishTypeDialog(String name) async {
    final isUsed = await DatabaseHelper.instance.isFishTypeUsed(name);
    if (isUsed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: fish type is in use')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Fish Type'),
        content: Text('Are you sure you want to delete "$name"?'),
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
      await DatabaseHelper.instance.deleteFishType(name);
      await _loadFishTypes();
      
      // Clean up preferences if the deleted fish type was in use
      await PreferencesService.clearDefaultFishTypeIfDeleted(_fishTypes);
      await PreferencesService.clearLastUsedFishTypeIfDeleted(_fishTypes);
      await _loadFishTypePreferences();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fish type deleted')),
        );
      }
    }
  }

  // Fishing Buddies CRUD
  Future<void> _showAddFishingBuddyDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Fishing Buddy'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Fishing Buddy Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      // Check for duplicates (case-insensitive, ignoring extra spaces)
      final normalized = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final exists = _fishingBuddies.any((buddy) =>
        buddy.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == normalized);

      if (!exists) {
        final result = await DatabaseHelper.instance.insertFishingBuddy(name);
        if (result != -1) {
          _loadFishingBuddies();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fishing buddy added')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fishing buddy already exists')),
          );
        }
      }
    }
  }

  Future<void> _showEditFishingBuddyDialog(FishingBuddy buddy) async {
    final controller = TextEditingController(text: buddy.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Fishing Buddy'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Fishing Buddy Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();
      if (newName != buddy.name) {
        // Check for duplicates (case-insensitive, ignoring extra spaces)
        final normalized = newName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final exists = _fishingBuddies.any((b) =>
          b.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == normalized && b.id != buddy.id);

        if (!exists) {
          await DatabaseHelper.instance.updateFishingBuddy(buddy.id!, newName);
          _loadFishingBuddies();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fishing buddy updated')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fishing buddy already exists')),
            );
          }
        }
      }
    }
  }

  Future<void> _showDeleteFishingBuddyDialog(FishingBuddy buddy) async {
    // Prevent deleting "Me"
    if (buddy.name == 'Me') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete "Me" fishing buddy')),
        );
      }
      return;
    }

    final isUsed = await DatabaseHelper.instance.isFishingBuddyUsed(buddy.id!);
    if (isUsed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: fishing buddy is in use')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Fishing Buddy'),
        content: Text('Are you sure you want to delete "${buddy.name}"?'),
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
      await DatabaseHelper.instance.deleteFishingBuddy(buddy.id!);
      _loadFishingBuddies();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fishing buddy deleted')),
        );
      }
    }
  }

  Future<void> _exportCatchesToCSV() async {
    try {
      final catches = await DatabaseHelper.instance.getCatches();
      
      if (catches.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No catches to export')),
          );
        }
        return;
      }

      // Get downloads directory
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access downloads directory')),
          );
        }
        return;
      }

      // Create CSV content
      final csvContent = StringBuffer();
      // Header row
      csvContent.writeln('Fish Type,Size (cm),Date Caught,Location,Notes,Photo Path,Photo Date/Time,Latitude,Longitude,Fishing Buddy,Fishing Trip');
      
      // Load fishing buddies for name lookup
      final fishingBuddies = await DatabaseHelper.instance.getFishingBuddies();
      final buddyMap = {for (var buddy in fishingBuddies) buddy.id!: buddy.name};
      
      // Load fishing trips for name lookup
      final fishingTrips = await DatabaseHelper.instance.getFishingTrips();
      final tripMap = {for (var trip in fishingTrips) trip.id!: trip.name};
      
      // Data rows
      for (final catch_ in catches) {
        final fishType = _escapeCSV(catch_.fishType);
        final size = catch_.lengthCm.toString();
        final dateCaught = catch_.dateCaught?.toString().split(' ')[0] ?? catch_.createdAt.toString().split(' ')[0];
        final location = _escapeCSV(catch_.location ?? '');
        final notes = _escapeCSV(catch_.notes ?? '');
        final photoPath = _escapeCSV(catch_.imagePath ?? '');
        final photoDateTime = catch_.photoDateTime?.toString() ?? '';
        final latitude = catch_.latitude?.toString() ?? '';
        final longitude = catch_.longitude?.toString() ?? '';
        final fishingBuddy = catch_.fishingBuddyId != null
            ? _escapeCSV(buddyMap[catch_.fishingBuddyId] ?? 'Unknown')
            : '';
        final fishingTrip = catch_.tripId != null
            ? _escapeCSV(tripMap[catch_.tripId] ?? 'Unknown')
            : '';
        
        csvContent.writeln('$fishType,$size,$dateCaught,$location,$notes,$photoPath,$photoDateTime,$latitude,$longitude,$fishingBuddy,$fishingTrip');
      }

      // Generate filename with timestamp
      final timestamp = DateTime.now().toString().replaceAll(':', '-').replaceAll(' ', '_').split('.')[0];
      final filename = 'bragmat_catches_$timestamp.csv';
      final filePath = '${directory.path}/$filename';
      
      // Write file
      final file = File(filePath);
      await file.writeAsString(csvContent.toString());

      // Verify file exists
      if (await file.exists()) {
        final fileSize = await file.length();
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export Successful'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CSV file exported successfully.'),
                const SizedBox(height: 8),
                const Text('File path:'),
                const SizedBox(height: 4),
                SelectableText(
                  filePath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await Share.shareXFiles(
                    [XFile(filePath)],
                    subject: 'Bragmat Catches Export',
                    text: 'Exported $filename',
                  );
                },
                child: const Text('Share CSV'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  String _escapeCSV(String value) {
    // Escape values that contain commas, quotes, or newlines
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  // Temporarily disabled due to file_picker build issue
  // Future<void> _importCatchesFromCSV() async {
  //   debugPrint('=== Import Catches from CSV started ===');
  //   
  //   try {
  //     // Pick CSV file
  //     final result = await FilePicker.platform.pickFiles(
  //       type: FileType.custom,
  //       allowedExtensions: ['csv'],
  //     );

  //     if (result == null || result.files.isEmpty) {
  //       debugPrint('No file selected');
  //       return;
  //     }

  //     final file = result.files.first;
  //     debugPrint('Selected file: ${file.name}');
  //     
  //     if (file.path == null) {
  //       debugPrint('ERROR: File path is null');
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text('Could not read file')),
  //         );
  //       }
  //       return;
  //     }

  //     // Read file
  //     final csvFile = File(file.path!);
  //     final csvContent = await csvFile.readAsString();
  //     debugPrint('File read successfully');

  //     // Parse CSV
  //     final lines = csvContent.split('\n');
  //     if (lines.isEmpty) {
  //       debugPrint('ERROR: File is empty');
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text('File is empty')),
  //         );
  //       }
  //       return;
  //     }

  //     // Get existing catches for duplicate detection
  //     final existingCatches = await DatabaseHelper.instance.getCatches();
  //     debugPrint('Existing catches: ${existingCatches.length}');

  //     // Statistics
  //     int rowsRead = 0;
  //     int catchesImported = 0;
  //     int rowsSkipped = 0;
  //     List<String> errors = [];

  //     // Skip header row
  //     final dataLines = lines.skip(1).toList();
  //     rowsRead = dataLines.length;

  //     for (int i = 0; i < dataLines.length; i++) {
  //       final line = dataLines[i].trim();
  //       if (line.isEmpty) {
  //         rowsSkipped++;
  //         continue;
  //       }

  //       // Parse CSV line (handle quoted values)
  //       final values = _parseCSVLine(line);
        
  //       if (values.length < 2) {
  //         errors.add('Row ${i + 2}: Invalid format (expected at least 2 columns)');
  //         rowsSkipped++;
  //         continue;
  //       }

  //       // Extract fields
  //       final fishType = values[0].trim();
  //       final size = int.tryParse(values[1].trim()) ?? 0;
  //       final dateCaughtStr = values.length > 2 ? values[2].trim() : '';
  //       final location = values.length > 3 ? values[3].trim() : '';
  //       final notes = values.length > 4 ? values[4].trim() : '';
  //       final photoPath = values.length > 5 ? values[5].trim() : '';
  //       final photoDateTimeStr = values.length > 6 ? values[6].trim() : '';
  //       final latitudeStr = values.length > 7 ? values[7].trim() : '';
  //       final longitudeStr = values.length > 8 ? values[8].trim() : '';
  //       final fishingBuddyStr = values.length > 9 ? values[9].trim() : '';

  //       // Validate required fields
  //       if (fishType.isEmpty) {
  //         errors.add('Row ${i + 2}: Fish type is required');
  //         rowsSkipped++;
  //         continue;
  //       }

  //       // Parse date
  //       DateTime? dateCaught;
  //       if (dateCaughtStr.isNotEmpty) {
  //         try {
  //           dateCaught = DateTime.parse(dateCaughtStr);
  //         } catch (e) {
  //           debugPrint('Row ${i + 2}: Could not parse date: $dateCaughtStr');
  //         }
  //       }

  //       // Parse photo date/time
  //       DateTime? photoDateTime;
  //       if (photoDateTimeStr.isNotEmpty) {
  //         try {
  //           photoDateTime = DateTime.parse(photoDateTimeStr);
  //         } catch (e) {
  //           debugPrint('Row ${i + 2}: Could not parse photo date/time: $photoDateTimeStr');
  //         }
  //       }

  //       // Parse coordinates
  //       double? latitude;
  //       if (latitudeStr.isNotEmpty) {
  //         latitude = double.tryParse(latitudeStr);
  //       }
  //       double? longitude;
  //       if (longitudeStr.isNotEmpty) {
  //         longitude = double.tryParse(longitudeStr);
  //       }

  //       // Handle fishing buddy
  //       int? fishingBuddyId;
  //       if (fishingBuddyStr.isNotEmpty) {
  //         // Look up fishing buddy by name
  //         final buddy = await DatabaseHelper.instance.getFishingBuddyByName(fishingBuddyStr);
  //         if (buddy != null) {
  //           fishingBuddyId = buddy.id;
  //         } else {
  //           // Create new fishing buddy if it doesn't exist
  //           final insertedId = await DatabaseHelper.instance.insertFishingBuddy(fishingBuddyStr);
  //           if (insertedId != -1) {
  //             fishingBuddyId = insertedId;
  //           }
  //         }
  //       } else {
  //         // Default to "Me" if no fishing buddy specified
  //         final meBuddy = await DatabaseHelper.instance.getMeFishingBuddy();
  //         fishingBuddyId = meBuddy?.id;
  //       }

  //       // Check for duplicates (fish type + size + date combination)
  //       final isDuplicate = existingCatches.any((existing) {
  //         final existingDate = existing.dateCaught ?? existing.createdAt;
  //         final importDate = dateCaught ?? DateTime.now();
  //         return existing.fishType == fishType &&
  //                existing.lengthCm == size &&
  //                existingDate.year == importDate.year &&
  //                existingDate.month == importDate.month &&
  //                existingDate.day == importDate.day;
  //       });

  //       if (isDuplicate) {
  //         errors.add('Row ${i + 2}: Duplicate catch (fish type: $fishType, size: $size)');
  //         rowsSkipped++;
  //         continue;
  //       }

  //       // Create catch object
  //       final newCatch = Catch(
  //         fishType: fishType,
  //         lengthCm: size,
  //         notes: notes.isEmpty ? null : notes,
  //         createdAt: DateTime.now(),
  //         dateCaught: dateCaught,
  //         imagePath: photoPath.isEmpty ? null : photoPath,
  //         photoDateTime: photoDateTime,
  //         latitude: latitude,
  //         longitude: longitude,
  //         location: location.isEmpty ? null : location,
  //         fishingBuddyId: fishingBuddyId,
  //       );

  //       // Insert into database
  //       await DatabaseHelper.instance.insertCatch(newCatch);
  //       catchesImported++;
  //       debugPrint('Imported catch: $fishType');
  //     }

  //     debugPrint('Import complete: $catchesImported imported, $rowsSkipped skipped, ${errors.length} errors');

  //     if (mounted) {
  //       showDialog(
  //         context: context,
  //         builder: (context) => AlertDialog(
  //           title: const Text('Import Complete'),
  //           content: Column(
  //             mainAxisSize: MainAxisSize.min,
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               Text('Rows read: $rowsRead'),
  //               Text('Catches imported: $catchesImported'),
  //               Text('Rows skipped: $rowsSkipped'),
  //               if (errors.isNotEmpty) ...[
  //                 const SizedBox(height: 8),
  //                 const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
  //                 const SizedBox(height: 4),
  //                 SizedBox(
  //                   height: 150,
  //                   child: ListView.builder(
  //                     shrinkWrap: true,
  //                     itemCount: errors.length > 10 ? 10 : errors.length,
  //                     itemBuilder: (context, index) => Text(
  //                       errors[index],
  //                       style: const TextStyle(fontSize: 12, color: Colors.red),
  //                     ),
  //                   ),
  //                 ),
  //                 if (errors.length > 10)
  //                   Text('... and ${errors.length - 10} more errors', style: const TextStyle(fontSize: 12)),
  //               ],
  //             ],
  //           ),
  //           actions: [
  //             TextButton(
  //               onPressed: () {
  //                 Navigator.pop(context);
  //                 _loadStatistics(); // Refresh statistics
  //               },
  //               child: const Text('OK'),
  //             ),
  //           ],
  //         ),
  //       );
  //     }
  //   } catch (e) {
  //     debugPrint('ERROR: Import failed: $e');
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('Import failed: $e')),
  //       );
  //     }
  //   }
  //   debugPrint('=== Import Catches from CSV completed ===');
  // }

  List<String> _parseCSVLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Escaped quote
          buffer.write('"');
          i++;
        } else {
          // Toggle quote mode
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // End of value
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    
    // Add last value
    values.add(buffer.toString());
    
    return values;
  }

  Future<void> _backupData() async {
    try {
      debugPrint('=== Backup Data Started ===');
      final filePath = await BackupService.exportBackup();
      debugPrint('Backup file created at: $filePath');
      
      final file = File(filePath);
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;
      final fileName = filePath.split('/').last;
      
      debugPrint('File exists: $fileExists');
      debugPrint('File size: $fileSize bytes');
      debugPrint('File name: $fileName');
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Backup Created'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Backup file created successfully.'),
                const SizedBox(height: 16),
                const Text('File name:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(
                  fileName,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('File path:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(
                  filePath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Text('File size: ${(fileSize / 1024).toStringAsFixed(2)} KB'),
                const SizedBox(height: 16),
                const Text(
                  'Note: If you cannot find this file in Downloads, use the Share button below to save it to another location.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await Share.shareXFiles(
                    [XFile(filePath)],
                    subject: 'Bragmat Backup',
                    text: 'Bragmat data backup',
                  );
                },
                child: const Text('Share Backup'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      
      debugPrint('=== Backup Data Completed ===');
    } catch (e) {
      debugPrint('Backup failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
  }

  Future<void> _testPhotoGPS() async {
    debugPrint('=== Test Photo GPS Started ===');
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile == null) {
      debugPrint('No photo selected');
      return;
    }
    
    debugPrint('Photo selected: ${pickedFile.path}');
    
    final file = File(pickedFile.path);
    final fileExists = await file.exists();
    final fileSize = fileExists ? await file.length() : 0;
    
    debugPrint('File exists: $fileExists');
    debugPrint('File size: $fileSize bytes');
    
    if (!fileExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found')),
        );
      }
      return;
    }
    
    // Read EXIF data
    Map<String, dynamic>? exifData;
    try {
      final bytes = await file.readAsBytes();
      exifData = await readExifFromBytes(bytes);
      debugPrint('EXIF data keys: ${exifData.keys.toList()}');
    } catch (e) {
      debugPrint('Error reading EXIF: $e');
      exifData = null;
    }
    
    // Extract GPS data
    double? latitude;
    double? longitude;
    String? dateTaken;
    List<String> gpsTags = [];
    
    if (exifData != null) {
      // Get date taken
      if (exifData.containsKey('DateTimeOriginal')) {
        dateTaken = exifData['DateTimeOriginal'].toString();
        debugPrint('DateTimeOriginal: $dateTaken');
      }
      
      // Get GPS tags
      final allGpsTags = exifData.entries.where((e) => e.key.startsWith('GPS')).toList();
      for (final tag in allGpsTags) {
        gpsTags.add('${tag.key}: ${tag.value}');
        debugPrint('GPS tag: ${tag.key} = ${tag.value}');
      }
      
      // Try to extract coordinates
      if (exifData.containsKey('GPSLatitude') && exifData.containsKey('GPSLongitude')) {
        final lat = exifData['GPSLatitude'];
        final latRef = exifData['GPSLatitudeRef'];
        final lon = exifData['GPSLongitude'];
        final lonRef = exifData['GPSLongitudeRef'];
        
        debugPrint('GPSLatitude: $lat');
        debugPrint('GPSLatitudeRef: $latRef');
        debugPrint('GPSLongitude: $lon');
        debugPrint('GPSLongitudeRef: $lonRef');
        
        if (lat != null && latRef != null && lon != null && lonRef != null) {
          latitude = _convertToDecimalDegrees(lat, latRef);
          longitude = _convertToDecimalDegrees(lon, lonRef);
          debugPrint('Extracted coordinates: $latitude, $longitude');
        }
      }
    }
    
    debugPrint('=== Test Photo GPS Completed ===');
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Photo GPS Test Results'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('File path:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(
                  pickedFile.path,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 12),
                Text('File size: ${(fileSize / 1024).toStringAsFixed(2)} KB'),
                const SizedBox(height: 12),
                const Text('EXIF metadata:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(exifData != null ? 'Yes (${exifData.length} tags)' : 'No'),
                const SizedBox(height: 12),
                if (dateTaken != null) ...[
                  const Text('Date taken:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(dateTaken),
                  const SizedBox(height: 12),
                ],
                const Text('GPS coordinates:', style: TextStyle(fontWeight: FontWeight.bold)),
                if (latitude != null && longitude != null) ...[
                  Text('Latitude: ${latitude.toStringAsFixed(6)}'),
                  Text('Longitude: ${longitude.toStringAsFixed(6)}'),
                ] else ...[
                  const Text('No GPS coordinates found'),
                  const SizedBox(height: 12),
                  const Text('GPS tags found:', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (gpsTags.isEmpty)
                    const Text('None')
                  else
                    ...gpsTags.map((tag) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(tag, style: const TextStyle(fontSize: 11)),
                    )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  double _convertToDecimalDegrees(dynamic value, dynamic ref) {
    if (value is! List) return 0.0;
    
    final degrees = _convertRational(value[0]);
    final minutes = _convertRational(value[1]);
    final seconds = _convertRational(value[2]);
    
    var decimal = degrees + (minutes / 60) + (seconds / 3600);
    
    if (ref == 'S' || ref == 'W') {
      decimal = -decimal;
    }
    
    return decimal;
  }

  double _convertRational(dynamic value) {
    if (value is List && value.length >= 2) {
      final numerator = value[0] is int ? value[0] as int : int.tryParse(value[0].toString()) ?? 0;
      final denominator = value[1] is int ? value[1] as int : int.tryParse(value[1].toString()) ?? 1;
      if (denominator != 0) {
        return numerator / denominator;
      }
    }
    return 0.0;
  }

  Future<void> _restoreData() async {
    // Show instructions dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To restore a backup:'),
            SizedBox(height: 8),
            Text('1. Copy your backup JSON file to the Downloads folder'),
            SizedBox(height: 4),
            Text('2. The file must be named: bragmat_backup_*.json'),
            SizedBox(height: 4),
            Text('3. The most recent backup will be used'),
            SizedBox(height: 16),
            Text('Warning: This will replace your current data if it exists.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      // Find backup file in downloads
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access downloads directory')),
          );
        }
        return;
      }

      // Find most recent backup file
      final files = directory.listSync().whereType<File>().toList();
      final backupFiles = files
          .where((f) => f.path.contains('bragmat_backup_') && f.path.endsWith('.json'))
          .toList();

      if (backupFiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No backup file found in Downloads folder')),
          );
        }
        return;
      }

      // Sort by last modified, most recent first
      backupFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final backupFile = backupFiles.first;

      // Check if database has data
      final existingCatches = await DatabaseHelper.instance.getCatches();
      final hasExistingData = existingCatches.isNotEmpty;

      // Show confirmation with file name
      final restoreConfirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Restore from this file?'),
              const SizedBox(height: 8),
              Text('File: ${backupFile.path.split('/').last}'),
              const SizedBox(height: 8),
              if (hasExistingData) ...[
                const Text(
                  'Warning: Your current data will be replaced.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );

      if (restoreConfirmed != true) {
        return;
      }

      await BackupService.restoreBackup(backupFile.path, overwrite: hasExistingData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully')),
        );
        // Reload data
        _loadStatistics();
        _loadFishTypes();
        _loadFishingBuddies();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preferences Section
          BragmatSectionCard(
            icon: Icons.tune,
            title: 'Preferences',
            children: [
              DropdownButtonFormField<FishTypeSelectionMode>(
                initialValue: _fishTypeSelectionMode,
                decoration: const InputDecoration(
                  labelText: 'Fish Type Selection Mode',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: FishTypeSelectionMode.noDefault,
                    child: Text('No Default'),
                  ),
                  DropdownMenuItem(
                    value: FishTypeSelectionMode.defaultFishType,
                    child: Text('Default Fish Type'),
                  ),
                  DropdownMenuItem(
                    value: FishTypeSelectionMode.rememberLastUsed,
                    child: Text('Remember Last Used Fish Type'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _setFishTypeSelectionMode(value);
                  }
                },
              ),
              if (_fishTypeSelectionMode == FishTypeSelectionMode.defaultFishType) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _safeDropdownValue(_defaultFishType, _fishTypes),
                  decoration: const InputDecoration(
                    labelText: 'Default Fish Type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('None'),
                    ),
                    ..._fishTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    _setDefaultFishType(value);
                  },
                ),
              ],
            ],
          ),

          // Tide Reference Location Section
          BragmatSectionCard(
            icon: Icons.waves,
            title: 'Tide Reference Location',
            children: [
              const Text(
                'Choose the default tide reference for new catches',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              RadioListTile<String>(
                title: const Text('Automatic (catch location)'),
                subtitle: const Text('Use the catch location coordinates'),
                value: 'automatic',
                groupValue: _currentTideReference?.id,
                onChanged: (value) {
                  if (value != null) {
                    _setTideReferenceMode(value);
                  }
                },
              ),
              RadioListTile<String>(
                title: const Text('Darwin'),
                subtitle: const Text('Always use Darwin tide station'),
                value: 'darwin',
                groupValue: _currentTideReference?.id,
                onChanged: (value) {
                  if (value != null) {
                    _setTideReferenceMode(value);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // API Keys Section
          BragmatSectionCard(
            icon: Icons.key,
            title: 'API Keys',
            children: [
              // API Key Status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _worldTidesApiKey != null && _worldTidesApiKey!.isNotEmpty
                      ? Colors.green.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _worldTidesApiKey != null && _worldTidesApiKey!.isNotEmpty
                        ? Colors.green.shade200
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _worldTidesApiKey != null && _worldTidesApiKey!.isNotEmpty
                          ? Icons.check_circle
                          : Icons.info_outline,
                      size: 20,
                      color: _worldTidesApiKey != null && _worldTidesApiKey!.isNotEmpty
                          ? Colors.green.shade700
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _worldTidesApiKey != null && _worldTidesApiKey!.isNotEmpty
                            ? 'API key saved'
                            : 'API key missing',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _worldTidesApiKey != null && _worldTidesApiKey!.isNotEmpty
                              ? Colors.green.shade900
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // API Key Input
              TextField(
                decoration: InputDecoration(
                  labelText: 'WorldTides API Key',
                  hintText: 'Enter your WorldTides API key',
                  border: const OutlineInputBorder(),
                  helperText: 'Required for official tide context data',
                  suffixIcon: _worldTidesApiKey != null && _worldTidesApiKey!.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.visibility_off),
                          onPressed: () {
                            // Clear the text field to show masked version
                            setState(() {});
                          },
                          tooltip: 'Hide API key',
                        )
                      : null,
                ),
                controller: TextEditingController(
                  text: _worldTidesApiKey != null && _worldTidesApiKey!.isNotEmpty
                      ? SecureStorageService.maskApiKey(_worldTidesApiKey)
                      : '',
                ),
                onChanged: (value) {
                  _setWorldTidesApiKey(value.trim().isEmpty ? null : value.trim());
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Get your API key from https://www.worldtides.info/',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 12),
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _testWorldTidesApi,
                      icon: const Icon(Icons.science),
                      label: const Text('Test API'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_worldTidesApiKey != null && _worldTidesApiKey!.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showClearApiKeyDialog(),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear Key'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                        ),
                      ),
                    ),
                ],
              ),
              // Test Status
              if (_apiTestStatus != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _apiTestStatus == 'success'
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _apiTestStatus == 'success'
                          ? Colors.green.shade200
                          : Colors.red.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _apiTestStatus == 'success'
                            ? Icons.check_circle
                            : Icons.error,
                        size: 16,
                        color: _apiTestStatus == 'success'
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _apiTestStatus == 'success'
                              ? 'API test successful'
                              : 'API test failed',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _apiTestStatus == 'success'
                                ? Colors.green.shade900
                                : Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Manage Lists Section
          BragmatSectionCard(
            icon: Icons.list,
            title: 'Manage Lists',
            children: [
              ListTile(
                leading: const Icon(Icons.set_meal),
                title: const Text('Fish Types'),
                subtitle: Text('${_fishTypes.length} types'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showFishTypesDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Fishing Buddies'),
                subtitle: Text('${_fishingBuddies.length} buddies'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showFishingBuddiesDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.phishing),
                title: const Text('Lures'),
                subtitle: Text('${_lures.length} lures'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showLuresDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('Baits'),
                subtitle: Text('${_baits.length} baits'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showBaitsDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.place),
                title: const Text('Favourite Fishing Spots'),
                subtitle: const Text('Manage your spots'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FavouriteSpotsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Data Management Section
          BragmatSectionCard(
            icon: Icons.storage,
            title: 'Data Management',
            children: [
              ListTile(
                leading: const Icon(Icons.backup),
                title: const Text('Backup Data'),
                subtitle: const Text('Create a backup of all your data'),
                onTap: _backupData,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore Data'),
                subtitle: const Text('Restore from a backup file'),
                onTap: _restoreData,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('Export CSV'),
                subtitle: const Text('Export catches to CSV file'),
                onTap: _exportCatchesToCSV,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Recalculate Environmental Data'),
                subtitle: const Text('Update missing automatic environmental data for catches with GPS'),
                onTap: _showRecalculateEnvironmentalDataDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.waves),
                title: const Text('Review Legacy Estimated Tide Data'),
                subtitle: const Text('Identify tide data that may have been incorrectly backfilled'),
                onTap: _showLegacyTideDataDialog,
              ),
              const Divider(height: 1),
              _buildComingSoonMenuItem(Icons.file_download, 'Import CSV (Coming Soon)'),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Clear All Data', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Permanently delete all catches and data', style: TextStyle(color: Colors.red)),
                onTap: _showClearAllDataDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // App Section
          BragmatSectionCard(
            icon: Icons.info,
            title: 'App',
            children: [
              ListTile(
                leading: const Icon(Icons.emoji_events),
                title: const Text('Achievements'),
                subtitle: const Text('View your fishing milestones'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AchievementsScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              _buildInfoRow('App Version', '1.0.0'),
              const Divider(height: 1),
              _buildInfoRow('Database Version', '1'),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('About Bragmat'),
                subtitle: const Text('Learn more about the app'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showAboutDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('Data Sources'),
                subtitle: const Text('Weather, tide, and environmental data'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showDataSourcesDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Developer Section (collapsed by default)
          BragmatSectionCard(
            icon: Icons.code,
            title: 'Developer',
            children: [
              ExpansionTile(
                title: const Text('Database Info'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow('Catches', '${_catches.length}'),
                        _buildInfoRow('Fish Types', '${_fishTypes.length}'),
                        _buildInfoRow('Fishing Buddies', '${_fishingBuddies.length}'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComingSoonMenuItem(IconData icon, String label) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Text(
        'Coming Soon',
        style: TextStyle(
          color: Colors.grey,
          fontSize: 12,
        ),
      ),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coming Soon')),
        );
      },
    );
  }
}
