// Verifies candidate tide references against the WorldTides v3 API.
//
// READ-ONLY VERIFICATION TOOL — it makes API calls but never writes to
// the database, the catalogue, or any file. Results are printed so a
// human can decide which entries belong in the curated catalogue in
// lib/services/tide_reference_service.dart. Nothing here mutates the
// catalogue automatically.
//
// For each candidate the tool makes two minimal calls:
//
//   1. `stations` — returns the nearest real tide stations
//      (id, name, coordinates, distance). Establishes station identity.
//   2. `extremes` — the same request shape the app uses (datum=CD),
//      WITHOUT `stations` (combining them previously caused
//      `extremes: null`). Reports whether predictions come from a named
//      station (`station` field) or the background atlas/model
//      (`atlas` field, e.g. FES2022), plus the response coordinates.
//
// API key handling:
//   - Read from the WORLDTIDES_API_KEY environment variable.
//   - Never printed, logged, written to a file, or included in output.
//   - Request URLs containing the key are never printed either.
//
// Windows usage:
//   PowerShell:
//     $env:WORLDTIDES_API_KEY = 'your-key-here'
//     dart run tool/verify_tide_stations.dart          # plan + estimate
//     dart run tool/verify_tide_stations.dart --run    # make the calls
//   Command Prompt:
//     set WORLDTIDES_API_KEY=your-key-here
//     dart run tool\verify_tide_stations.dart --run
//
// Credit cost: 1 credit per `stations` call (searches <= 500 km) +
// 1 credit per `extremes` call = 2 credits per candidate.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _baseUrl = 'https://www.worldtides.info/api/v3';
const _apiKeyEnvVar = 'WORLDTIDES_API_KEY';

/// Radius searched by each `stations` lookup (km).
const _stationSearchKm = 300;

/// A candidate location to verify. [expectedStation] is the WorldTides
/// station name we expect nearby — leave null for locations that are
/// expected to resolve to the background model only.
class Candidate {
  final String label;
  final double lat;
  final double lon;
  final String? expectedStation;

  const Candidate(this.label, this.lat, this.lon, {this.expectedStation});
}

/// Candidates under evaluation for the Northern Territory catalogue.
/// Only 'darwin' is currently verified and shipped; the rest are
/// unverified candidates pending results from this tool.
const _candidates = <Candidate>[
  // Verified in production; re-check to confirm the tool's output.
  Candidate('Darwin', -12.4667, 130.8500, expectedStation: 'Darwin'),
  // Model-only candidate — no WorldTides gauge is expected; fishers at
  // Dundee Beach use Darwin predictions. Verify atlas behaviour.
  Candidate('Dundee Beach', -12.705, 130.355),
  // Unverified NT candidates.
  Candidate('Melville Bay / Gove', -12.250, 136.700,
      expectedStation: 'Melville Bay'),
  Candidate('Milner Bay / Groote Eylandt', -13.860, 136.420,
      expectedStation: 'Milner Bay'),
  Candidate('Centre Island / Pellew Group', -15.550, 136.750,
      expectedStation: 'Centre Island'),
  Candidate('Cape Wessel / Tiwi area', -11.000, 136.750),
];

/// What the `extremes` response resolved to for a request.
enum PredictionSource { station, atlas, none, error }

/// Result of one `stations` lookup.
class StationLookup {
  final String? id;
  final String? name;
  final double? lat;
  final double? lon;
  final double? distanceKm;
  final int totalFound;
  final String? error;

  const StationLookup({
    this.id,
    this.name,
    this.lat,
    this.lon,
    this.distanceKm,
    this.totalFound = 0,
    this.error,
  });
}

/// Result of one `extremes` request (same request shape as the app).
class PredictionResult {
  final PredictionSource source;
  final String? stationName;
  final String? atlas;
  final double? responseLat;
  final double? responseLon;
  final int eventCount;
  final String? error;

  const PredictionResult({
    required this.source,
    this.stationName,
    this.atlas,
    this.responseLat,
    this.responseLon,
    this.eventCount = 0,
    this.error,
  });
}

/// Parses the WorldTides `stations` response.
///
/// Shape: `{ "stations": [ { "id": ..., "name": ..., "lat": ...,
/// "lon": ..., "distance": ... }, ... ] }`
StationLookup parseStationsResponse(Map<String, dynamic> data) {
  final error = data['error'];
  if (error is String && error.isNotEmpty) {
    return StationLookup(error: error);
  }
  final stations = data['stations'];
  if (stations is! List || stations.isEmpty) {
    return const StationLookup(totalFound: 0);
  }
  final nearest = stations.first as Map<String, dynamic>;
  return StationLookup(
    id: nearest['id']?.toString(),
    name: nearest['name'] as String?,
    lat: (nearest['lat'] as num?)?.toDouble(),
    lon: (nearest['lon'] as num?)?.toDouble(),
    distanceKm: (nearest['distance'] as num?)?.toDouble(),
    totalFound: stations.length,
  );
}

/// Parses the WorldTides `extremes` response for source metadata.
///
/// `station` present → named gauge; `atlas` only → background model.
PredictionResult parseExtremesResponse(Map<String, dynamic> data) {
  final error = data['error'];
  if (error is String && error.isNotEmpty) {
    return PredictionResult(source: PredictionSource.error, error: error);
  }
  final station = data['station'] as String?;
  final atlas = data['atlas'] as String?;
  final extremes = data['extremes'];
  return PredictionResult(
    source: station != null
        ? PredictionSource.station
        : (atlas != null ? PredictionSource.atlas : PredictionSource.none),
    stationName: station,
    atlas: atlas,
    responseLat: (data['responseLat'] as num?)?.toDouble(),
    responseLon: (data['responseLon'] as num?)?.toDouble(),
    eventCount: extremes is List ? extremes.length : 0,
  );
}

/// Judges whether a candidate is suitable for the user-facing catalogue.
///
/// [stationMatch] means the nearest station name matches the candidate's
/// expected station (case-insensitive, substring-tolerant).
String assessSuitability(
  Candidate candidate,
  StationLookup lookup,
  PredictionResult prediction,
) {
  if (lookup.error != null || prediction.error != null) {
    return 'INCONCLUSIVE — API error, rerun later';
  }
  if (prediction.source == PredictionSource.station) {
    final nameOk = candidate.expectedStation == null ||
        _nameMatches(candidate.expectedStation!, prediction.stationName);
    return nameOk
        ? 'SUITABLE as tide station reference'
        : 'REVIEW — predictions came from '
            '"${prediction.stationName}", expected "${candidate.expectedStation}"';
  }
  if (prediction.source == PredictionSource.atlas) {
    return 'MODEL-ONLY — suitable only as a model-based reference '
        '(no gauge; ${prediction.atlas ?? "atlas"})';
  }
  return 'UNSUITABLE — no usable predictions returned';
}

bool _nameMatches(String expected, String? actual) {
  if (actual == null) return false;
  final e = expected.toLowerCase();
  final a = actual.toLowerCase();
  return a.contains(e) || e.contains(a);
}

Future<Map<String, dynamic>?> _get(Uri uri) async {
  try {
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      return {'error': 'HTTP ${response.statusCode}'};
    }
    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return {'error': 'unexpected response shape'};
    }
    return decoded;
  } catch (e) {
    // Never include the URI in errors — it carries the API key.
    return {'error': e.toString().replaceAll(RegExp(r'key=[^&\s]+'), 'key=***')};
  }
}

Uri _uri(Map<String, String> params, String apiKey) =>
    Uri.parse(_baseUrl).replace(queryParameters: {...params, 'key': apiKey});

Future<void> _verify(Candidate c, String apiKey) async {
  stdout.writeln('=== ${c.label} (requested ${c.lat}, ${c.lon}) ===');

  final stationsData = await _get(_uri({
    'stations': '',
    'lat': '${c.lat}',
    'lon': '${c.lon}',
    'stationDistance': '$_stationSearchKm',
  }, apiKey));
  final lookup =
      stationsData == null ? const StationLookup(error: 'request failed') : parseStationsResponse(stationsData);

  final extremesData = await _get(_uri({
    'extremes': '',
    'lat': '${c.lat}',
    'lon': '${c.lon}',
    'days': '3',
    'datum': 'CD',
  }, apiKey));
  final prediction =
      extremesData == null ? const PredictionResult(source: PredictionSource.error, error: 'request failed') : parseExtremesResponse(extremesData);

  if (lookup.error != null) {
    stdout.writeln('  stations lookup: ERROR ${lookup.error}');
  } else if (lookup.name == null) {
    stdout.writeln('  stations lookup: no station within $_stationSearchKm km');
  } else {
    stdout.writeln('  nearest station:  ${lookup.name} (id: ${lookup.id})');
    stdout.writeln('  station coords:   ${lookup.lat}, ${lookup.lon}');
    if (lookup.distanceKm != null) {
      stdout.writeln('  distance:         ${lookup.distanceKm} km');
    }
    stdout.writeln('  stations found:   ${lookup.totalFound}');
  }

  if (prediction.error != null) {
    stdout.writeln('  prediction:       ERROR ${prediction.error}');
  } else {
    stdout.writeln('  prediction via:   '
        '${prediction.source == PredictionSource.station ? "STATION" : prediction.source == PredictionSource.atlas ? "ATLAS/MODEL" : "NONE"}'
        '${prediction.stationName != null ? " — ${prediction.stationName}" : ""}'
        '${prediction.atlas != null ? " (${prediction.atlas})" : ""}');
    stdout.writeln('  response coords:  ${prediction.responseLat}, ${prediction.responseLon}');
    stdout.writeln('  events returned:  ${prediction.eventCount}');
  }

  stdout.writeln('  verdict:          ${assessSuitability(c, lookup, prediction)}');
  stdout.writeln('');
}

Future<void> main(List<String> args) async {
  final run = args.contains('--run');

  stdout.writeln('WorldTides tide-station verification (read-only)');
  stdout.writeln('Candidates: ${_candidates.length}');
  for (final c in _candidates) {
    stdout.writeln('  - ${c.label} (${c.lat}, ${c.lon})'
        '${c.expectedStation != null ? " [expects ${c.expectedStation}]" : ""}');
  }
  stdout.writeln('');
  stdout.writeln('Calls:  2 per candidate (1 x stations + 1 x extremes)');
  stdout.writeln('Estimated credit cost: ${_candidates.length * 2} credits');
  stdout.writeln('');

  if (!run) {
    stdout.writeln('Dry run — no API calls made. Re-run with --run to execute.');
    return;
  }

  final apiKey = Platform.environment[_apiKeyEnvVar];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('ERROR: set $_apiKeyEnvVar to your WorldTides API key.');
    stderr.writeln('The key is read from the environment only — it is never');
    stderr.writeln('printed, stored, or committed.');
    exitCode = 2;
    return;
  }

  for (final c in _candidates) {
    await _verify(c, apiKey);
  }

  stdout.writeln('Done. Review verdicts before editing the catalogue in '
      'lib/services/tide_reference_service.dart — this tool never modifies it.');
}
