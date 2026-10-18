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
//     dart run tool/verify_tide_stations.dart                    # plan + estimate
//     dart run tool/verify_tide_stations.dart --run              # all candidates
//     dart run tool/verify_tide_stations.dart --run --only darwin,dundee_beach
//   Command Prompt:
//     set WORLDTIDES_API_KEY=your-key-here
//     dart run tool\verify_tide_stations.dart --run --only darwin,dundee_beach
//
// --only accepts candidate keys (see the list printed by a dry run) or
// label substrings, comma-separated, case-insensitive. Unknown keys are
// reported and cause a non-zero exit.
//
// --report [path] writes the printed output to a sanitized report file
// (default verify_tide_stations_report.txt). It contains only station
// names, coordinates and verdicts — never the API key or request URLs —
// so it is safe to share.
//
// Robustness: response fields are coerced defensively (numbers and
// numeric strings accepted; malformed/missing values become null or a
// per-candidate error). A bad response for one candidate is reported
// and does not abort the run.
//
// Credit cost: 1 credit per `stations` call (searches <= 500 km) +
// 1 credit per `extremes` call = 2 credits per selected candidate.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _baseUrl = 'https://www.worldtides.info/api/v3';
const _apiKeyEnvVar = 'WORLDTIDES_API_KEY';

/// Radius searched by each `stations` lookup (km).
const _stationSearchKm = 300;

/// A candidate location to verify. [expectedStation] is the WorldTides
/// station name we expect nearby — leave null for locations that are
/// expected to resolve to the background model only. [key] is the slug
/// used with --only.
class Candidate {
  final String key;
  final String label;
  final double lat;
  final double lon;
  final String? expectedStation;

  const Candidate(this.key, this.label, this.lat, this.lon,
      {this.expectedStation});
}

/// Candidates under evaluation for the Northern Territory catalogue.
/// Only 'darwin' is currently verified and shipped; the rest are
/// unverified candidates pending results from this tool.
const _candidates = <Candidate>[
  // Verified in production; re-check to confirm the tool's output.
  Candidate('darwin', 'Darwin', -12.4667, 130.8500,
      expectedStation: 'Darwin'),
  // Model-only candidate — no WorldTides gauge is expected; fishers at
  // Dundee Beach use Darwin predictions. Verify atlas behaviour.
  Candidate('dundee_beach', 'Dundee Beach', -12.705, 130.355),
  // Nearest real gauge to Dundee Beach (found by the stations lookup
  // during verification, id Australia:NT_TP053). Verify before deciding
  // between a station-backed Dundee option and the model-based one.
  Candidate('native_point', 'Native Point', -12.650, 130.2667,
      expectedStation: 'Native Point'),
  // Unverified NT candidates.
  Candidate('melville_bay', 'Melville Bay / Gove', -12.250, 136.700,
      expectedStation: 'Melville Bay'),
  Candidate('milner_bay', 'Milner Bay / Groote Eylandt', -13.860, 136.420,
      expectedStation: 'Milner Bay'),
  Candidate('centre_island', 'Centre Island / Pellew Group', -15.550,
      136.750,
      expectedStation: 'Centre Island'),
  Candidate('cape_wessel', 'Cape Wessel / Tiwi area', -11.000, 136.750),
];

/// Selects the candidates matching any of [selectors] (candidate key or
/// label substring, case-insensitive). Returns the selected candidates;
/// [unknown] collects selectors that matched nothing.
List<Candidate> selectCandidates(
  List<Candidate> candidates,
  List<String> selectors, {
  List<String>? unknown,
}) {
  if (selectors.isEmpty) return List.of(candidates);
  final selected = <Candidate>[];
  for (final raw in selectors) {
    final sel = raw.trim().toLowerCase();
    if (sel.isEmpty) continue;
    final matches = candidates
        .where((c) =>
            c.key.toLowerCase() == sel || c.label.toLowerCase().contains(sel))
        .toList();
    if (matches.isEmpty) {
      unknown?.add(raw);
    } else {
      for (final m in matches) {
        if (!selected.contains(m)) selected.add(m);
      }
    }
  }
  return selected;
}

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

/// Coerces a JSON value to [double], accepting numbers and numeric
/// strings — WorldTides returns station coordinates and distances as
/// strings in the `stations` response. Missing or malformed values
/// become null rather than throwing.
double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

/// Coerces a JSON scalar to [String]. Missing values become null.
String? _asString(dynamic value) => value?.toString();

/// Parses the WorldTides `stations` response.
///
/// Shape: `{ "stations": [ { "id": ..., "name": ..., "lat": ...,
/// "lon": ..., "distance": ... }, ... ] }` — where coordinates and
/// distance may be encoded as strings.
StationLookup parseStationsResponse(Map<String, dynamic> data) {
  final error = _asString(data['error']);
  if (error != null && error.isNotEmpty) {
    return StationLookup(error: error);
  }
  final stations = data['stations'];
  if (stations is! List || stations.isEmpty) {
    return const StationLookup(totalFound: 0);
  }
  final nearest = stations.first;
  if (nearest is! Map) {
    return const StationLookup(error: 'malformed station entry');
  }
  return StationLookup(
    id: _asString(nearest['id']),
    name: _asString(nearest['name']),
    lat: _asDouble(nearest['lat']),
    lon: _asDouble(nearest['lon']),
    distanceKm: _asDouble(nearest['distance']),
    totalFound: stations.length,
  );
}

/// Parses the WorldTides `extremes` response for source metadata.
///
/// `station` present → named gauge; `atlas` only → background model.
PredictionResult parseExtremesResponse(Map<String, dynamic> data) {
  final error = _asString(data['error']);
  if (error != null && error.isNotEmpty) {
    return PredictionResult(source: PredictionSource.error, error: error);
  }
  final station = _asString(data['station']);
  final atlas = _asString(data['atlas']);
  final extremes = data['extremes'];
  return PredictionResult(
    source: station != null
        ? PredictionSource.station
        : (atlas != null ? PredictionSource.atlas : PredictionSource.none),
    stationName: station,
    atlas: atlas,
    responseLat: _asDouble(data['responseLat']),
    responseLon: _asDouble(data['responseLon']),
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

/// Accumulates printed output so it can optionally be written to a
/// sanitized report file (--report). The report contains only what is
/// printed — candidate labels, station names, coordinates and verdicts.
/// The API key and request URLs are never emitted, so the report is
/// safe to share.
final _reportLines = StringBuffer();

void _out(String line) {
  stdout.writeln(line);
  _reportLines.writeln(line);
}

/// Removes any `key=` query parameter from a message before display —
/// belt-and-braces over never building log output from request URLs.
String _scrub(String message) =>
    message.replaceAll(RegExp(r'key=[^&\s]+'), 'key=***');

Future<void> _verify(Candidate c, String apiKey) async {
  _out('=== ${c.label} (requested ${c.lat}, ${c.lon}) ===');

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
    _out('  stations lookup: ERROR ${lookup.error}');
  } else if (lookup.name == null) {
    _out('  stations lookup: no station within $_stationSearchKm km');
  } else {
    _out('  nearest station:  ${lookup.name} (id: ${lookup.id})');
    _out('  station coords:   ${lookup.lat}, ${lookup.lon}');
    if (lookup.distanceKm != null) {
      _out('  distance:         ${lookup.distanceKm} km');
    }
    _out('  stations found:   ${lookup.totalFound}');
  }

  if (prediction.error != null) {
    _out('  prediction:       ERROR ${prediction.error}');
  } else {
    _out('  prediction via:   '
        '${prediction.source == PredictionSource.station ? "STATION" : prediction.source == PredictionSource.atlas ? "ATLAS/MODEL" : "NONE"}'
        '${prediction.stationName != null ? " — ${prediction.stationName}" : ""}'
        '${prediction.atlas != null ? " (${prediction.atlas})" : ""}');
    _out('  response coords:  ${prediction.responseLat}, ${prediction.responseLon}');
    _out('  events returned:  ${prediction.eventCount}');
  }

  _out('  verdict:          ${assessSuitability(c, lookup, prediction)}');
  _out('');
}

/// Parses `--only a,b,c` from the argument list. Returns the selectors.
List<String> parseOnlySelectors(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--only=')) {
      return arg.substring('--only='.length).split(',');
    }
  }
  final idx = args.indexOf('--only');
  if (idx >= 0 && idx + 1 < args.length) {
    return args[idx + 1].split(',');
  }
  return const [];
}

/// Parses `--report <path>` or `--report=<path>`. Returns the output
/// file path, or null when the flag is absent. A bare `--report` writes
/// to `verify_tide_stations_report.txt` in the current directory.
String? parseReportPath(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--report=')) {
      final v = arg.substring('--report='.length).trim();
      return v.isEmpty ? 'verify_tide_stations_report.txt' : v;
    }
  }
  final idx = args.indexOf('--report');
  if (idx < 0) return null;
  if (idx + 1 < args.length && !args[idx + 1].startsWith('--')) {
    return args[idx + 1];
  }
  return 'verify_tide_stations_report.txt';
}

Future<void> main(List<String> args) async {
  final run = args.contains('--run');
  final reportPath = parseReportPath(args);
  final unknown = <String>[];
  final selected =
      selectCandidates(_candidates, parseOnlySelectors(args), unknown: unknown);

  if (unknown.isNotEmpty) {
    stderr.writeln('ERROR: --only matched nothing for: ${unknown.join(", ")}');
    stderr.writeln('Valid keys: ${_candidates.map((c) => c.key).join(", ")}');
    exitCode = 2;
    return;
  }
  if (selected.isEmpty) {
    stderr.writeln('ERROR: --only selected no candidates.');
    exitCode = 2;
    return;
  }

  _out('WorldTides tide-station verification (read-only)');
  _out('Candidates selected: ${selected.length} of ${_candidates.length}');
  for (final c in selected) {
    _out('  - ${c.key}: ${c.label} (${c.lat}, ${c.lon})'
        '${c.expectedStation != null ? " [expects ${c.expectedStation}]" : ""}');
  }
  _out('');
  _out('Calls:  2 per candidate (1 x stations + 1 x extremes)');
  _out('Estimated credit cost: ${selected.length * 2} credits');
  _out('');

  if (!run) {
    _out('Dry run — no API calls made. Re-run with --run to execute.');
    _writeReport(reportPath);
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

  for (final c in selected) {
    try {
      await _verify(c, apiKey);
    } catch (e) {
      // One malformed response must not abort the whole run.
      _out('=== ${c.label} — UNEXPECTED ERROR: ${_scrub('$e')} ===');
      _out('');
    }
  }

  _out('Done. Review verdicts before editing the catalogue in '
      'lib/services/tide_reference_service.dart — this tool never modifies it.');
  _writeReport(reportPath);
}

/// Writes the captured output to [path] when --report was given.
void _writeReport(String? path) {
  if (path == null) return;
  try {
    File(path).writeAsStringSync(_reportLines.toString());
    stdout.writeln('Report written to $path '
        '(sanitized: no API key, no request URLs).');
  } catch (e) {
    stderr.writeln('WARNING: could not write report to $path: $e');
  }
}
