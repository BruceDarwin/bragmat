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
// Discovery mode:
//   dart run tool/verify_tide_stations.dart --discover            # plan
//   dart run tool/verify_tide_stations.dart --discover --run      # execute
//   dart run tool/verify_tide_stations.dart --discover --only anchor_darwin
// `--discover` sweeps anchor points across the NT coast with `stations`
// requests (500 km radius), parses the FULL returned station list,
// deduplicates by WorldTides station id, groups results by region and
// reports which catalogue candidates have a real gauge nearby. One
// `stations` call per anchor; --only selects anchors by key/label.
//
// Robustness: response fields are coerced defensively (numbers and
// numeric strings accepted; malformed/missing values become null or a
// per-candidate error). A bad response for one candidate is reported
// and does not abort the run.
//
// Credit cost (WorldTides v3 pricing):
//   stations — 1 credit for stationDistance <= 500 km, 2 credits up to
//              5000 km, 3 credits above.
//   extremes — 1 credit per 7 days (the tool requests 3 days).
// So verification = 2 credits/candidate (300 km stations + extremes);
// discovery = 1 credit/anchor (500 km stations only).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bragmat/data/tide_reference_catalogue.dart';
import 'package:bragmat/models/tide_reference.dart';
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

/// Verification candidates — built from the catalogue file
/// (lib/data/tide_reference_catalogue.dart) so verified entries and
/// proposed candidates share one source of truth. Verified entries
/// expect their own name as the serving station; candidates expect
/// nothing — the run reports what is actually found.
final List<Candidate> _candidates = [
  for (final r in kTideReferenceCatalogue)
    Candidate(r.id, r.displayName, r.latitude, r.longitude,
        expectedStation:
            r.source == TideReferenceSource.station ? r.displayName : null),
  for (final r in kTideReferenceCandidates)
    Candidate(r.id, r.displayName, r.latitude, r.longitude),
];

/// Anchor points for `--discover` sweeps. Each `stations` call uses a
/// 500 km radius — 1 credit per anchor under WorldTides v3 pricing —
/// and returns every station in range, so overlapping coverage is
/// intentional (results are deduplicated by station id).
const _discoveryAnchors = <Candidate>[
  Candidate('anchor_darwin', 'Darwin / Fog Bay / Tiwi south', -12.60, 130.55),
  Candidate('anchor_cobourg', 'Tiwi north / Cobourg / Van Diemen Gulf',
      -11.45, 131.90),
  Candidate('anchor_arnhem', 'Arnhem Land coast', -12.45, 134.60),
  Candidate('anchor_ne_arnhem', 'NE Arnhem / Gove / Wessel Islands',
      -12.10, 136.40),
  Candidate('anchor_groote', 'Groote Eylandt / SW Gulf', -14.20, 136.55),
  Candidate(
      'anchor_gulf', 'Gulf of Carpentaria coast (NT)', -15.90, 136.20),
  Candidate('anchor_bonaparte', 'Joseph Bonaparte Gulf', -14.60, 129.20),
];

/// Radius used by `--discover` (km). 500 km is the largest radius that
/// still costs 1 credit per `stations` request.
const _discoveryRadiusKm = 500;

/// BoM/ANTT Northern Territory prediction locations — used to flag
/// which discovered WorldTides stations correspond to official
/// Australian tide locations.
const _officialNtLocations = <String>[
  'Anson Bay', 'Arafura Sea', 'Aurari Bay', 'Auster Point', 'Beagle A',
  'Burge Point', 'Cache Point', 'Cadell Strait', 'Calder Shoal',
  'Camp Point', 'Cape Arnhem', 'Cape Beatrice', 'Cape Cockburn',
  'Cape Crocker', 'Cape Don', 'Cape Ford', 'Cape Grey', 'Cape Hotham',
  'Cape Scott', 'Cape Van Dieman', 'Cape Wessel', 'Catfish Island',
  'Centre Island', 'Chambers Bay', 'Charles Point', 'Christine Reef',
  'Copeland', 'Cuthbert Point', 'Darwin', "D'Urville Point",
  'East Field Island', 'Elcho Island', 'Entrance', 'Evans Shoal',
  'Fenton Patches', 'Fish Reef', 'Glyde Point', 'Goodrich Bank',
  'Grant', 'Guluwuru Island', 'Hancox Shoal', 'Hawk', 'Hopeful Bay',
  'Hogmany Shoal', 'Hutchison River', 'Jones Point', 'Loxton Shoal',
  'Lynedoch Bank', 'Mallison', 'Medina Inlet', 'Melville Bay',
  'Milner Bay', 'Money Shoal', 'Munkunuwa', 'Native Point',
  'New Year', 'Newby Shoal', 'Nightcliff', 'North Goulburn',
  'Jones Shoal', 'Peron', 'Crocodile Island', 'Peacock',
  'One Tree Point', 'Parsons Bank', 'Paxie Shoal', 'Point David',
  'Point Fawcett', 'Point Jahleel', 'Point Jenny', 'Point Stuart',
  'Port Essington', 'Port Keats', 'Quoin Island', 'Smith Point',
  'Snake Bay', 'Barlow Point', 'St. Asaph Bay', 'Stevens', 'Tapa Bay',
  'Boxers', 'Truant Island', 'Two Hills Bay', 'Two Island Bay',
  'Alligator Head', 'West Island', 'Yabooma Island',
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

/// One station returned by a `stations` discovery request.
class DiscoveredStation {
  final String? id;
  final String? name;
  final double? lat;
  final double? lon;
  final double? distanceKm;
  final String anchorKey;

  const DiscoveredStation({
    this.id,
    this.name,
    this.lat,
    this.lon,
    this.distanceKm,
    this.anchorKey = '',
  });

  DiscoveredStation fromAnchor(String anchor) => DiscoveredStation(
        id: id,
        name: name,
        lat: lat,
        lon: lon,
        distanceKm: distanceKm,
        anchorKey: anchor,
      );
}

/// Result of parsing a full `stations` response for discovery.
class StationListResult {
  final List<DiscoveredStation> stations;
  final String? error;

  const StationListResult(this.stations, {this.error});
}

/// Parses the complete `stations` response (used by --discover).
/// Malformed entries are skipped rather than aborting the list.
StationListResult parseStationList(Map<String, dynamic> data) {
  final error = _asString(data['error']);
  if (error != null && error.isNotEmpty) {
    return StationListResult(const [], error: error);
  }
  final stations = data['stations'];
  if (stations is! List) {
    return const StationListResult([]);
  }
  final parsed = <DiscoveredStation>[];
  for (final entry in stations) {
    if (entry is! Map) continue; // skip malformed entries
    parsed.add(DiscoveredStation(
      id: _asString(entry['id']),
      name: _asString(entry['name']),
      lat: _asDouble(entry['lat']),
      lon: _asDouble(entry['lon']),
      distanceKm: _asDouble(entry['distance']),
    ));
  }
  return StationListResult(parsed);
}

/// Deduplicates discovered stations across anchors by WorldTides
/// station id (falling back to name when id is absent), keeping the
/// sighting closest to its anchor.
List<DiscoveredStation> dedupeStations(List<DiscoveredStation> all) {
  final byKey = <String, DiscoveredStation>{};
  for (final s in all) {
    final key = (s.id != null && s.id!.isNotEmpty)
        ? s.id!
        : 'name:${s.name ?? '?'}@${s.lat},${s.lon}';
    final existing = byKey[key];
    if (existing == null ||
        (s.distanceKm ?? double.infinity) <
            (existing.distanceKm ?? double.infinity)) {
      byKey[key] = s;
    }
  }
  return byKey.values.toList();
}

/// True when a discovered station name corresponds to an official
/// BoM/ANTT NT tide location (substring-tolerant, case-insensitive).
bool isOfficialLocation(String? stationName) {
  if (stationName == null) return false;
  final n = stationName.toLowerCase();
  return _officialNtLocations.any((o) {
    final ol = o.toLowerCase();
    return n.contains(ol) || ol.contains(n);
  });
}

/// Great-circle distance in km (haversine) — used to report which
/// catalogue candidates have a real gauge nearby.
double kmBetween(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

double _rad(double deg) => deg * math.pi / 180.0;

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
  final discover = args.contains('--discover');
  final reportPath = parseReportPath(args);
  final pool = discover ? _discoveryAnchors : _candidates;
  final unknown = <String>[];
  final selected =
      selectCandidates(pool, parseOnlySelectors(args), unknown: unknown);

  if (unknown.isNotEmpty) {
    stderr.writeln('ERROR: --only matched nothing for: ${unknown.join(", ")}');
    stderr.writeln('Valid keys: ${pool.map((c) => c.key).join(", ")}');
    exitCode = 2;
    return;
  }
  if (selected.isEmpty) {
    stderr.writeln('ERROR: --only selected no candidates.');
    exitCode = 2;
    return;
  }

  if (discover) {
    _out('WorldTides NT station discovery (read-only)');
    _out('Anchors selected: ${selected.length} of ${_discoveryAnchors.length}');
    for (final c in selected) {
      _out('  - ${c.key}: ${c.label} (${c.lat}, ${c.lon})');
    }
    _out('');
    _out('Calls:  1 x stations per anchor '
        '($_discoveryRadiusKm km radius = 1 credit each)');
    _out('Estimated credit cost: ${selected.length} credits');
  } else {
    _out('WorldTides tide-station verification (read-only)');
    _out('Candidates selected: ${selected.length} of ${_candidates.length}');
    for (final c in selected) {
      _out('  - ${c.key}: ${c.label} (${c.lat}, ${c.lon})'
          '${c.expectedStation != null ? " [expects ${c.expectedStation}]" : ""}');
    }
    _out('');
    _out('Calls:  2 per candidate (1 x stations + 1 x extremes)');
    _out('Estimated credit cost: ${selected.length * 2} credits');
  }
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

  if (discover) {
    await _runDiscovery(selected, apiKey);
  } else {
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
        'lib/data/tide_reference_catalogue.dart — this tool never modifies it.');
  }
  _writeReport(reportPath);
}

/// Runs the --discover sweep: one `stations` call per anchor, then a
/// deduplicated inventory grouped by NT region, plus per-candidate
/// nearest-gauge coverage so model-only gaps are visible.
Future<void> _runDiscovery(List<Candidate> anchors, String apiKey) async {
  final all = <DiscoveredStation>[];
  for (final anchor in anchors) {
    try {
      final data = await _get(_uri({
        'stations': '',
        'lat': '${anchor.lat}',
        'lon': '${anchor.lon}',
        'stationDistance': '$_discoveryRadiusKm',
      }, apiKey));
      final result = data == null
          ? const StationListResult([], error: 'request failed')
          : parseStationList(data);
      if (result.error != null) {
        _out('=== ${anchor.label} — stations lookup ERROR '
            '${result.error} ===');
      } else {
        _out('=== ${anchor.label}: ${result.stations.length} station(s) '
            'within $_discoveryRadiusKm km ===');
        all.addAll(
            result.stations.map((s) => s.fromAnchor(anchor.key)));
      }
    } catch (e) {
      _out('=== ${anchor.label} — UNEXPECTED ERROR: ${_scrub('$e')} ===');
    }
    _out('');
  }

  final unique = dedupeStations(all);
  unique.sort((a, b) =>
      (a.name ?? '').compareTo(b.name ?? ''));

  // Group by approximate NT region for readability.
  final byRegion = <TideRegion, List<DiscoveredStation>>{};
  for (final s in unique) {
    byRegion
        .putIfAbsent(
            tideRegionForCoordinates(s.lat ?? 0, s.lon ?? 0), () => [])
        .add(s);
  }

  _out('--- Deduplicated inventory: ${unique.length} unique station(s) '
      'from ${all.length} sightings ---');
  for (final region in TideRegion.values) {
    final list = byRegion[region];
    if (list == null || list.isEmpty) continue;
    _out('');
    _out('  ${tideRegionLabels[region]} (${list.length}):');
    for (final s in list) {
      final official = isOfficialLocation(s.name) ? ' [official]' : '';
      _out('    ${s.name ?? "?"}'
          '${s.id != null ? " (id: ${s.id})" : ""}'
          '  ${s.lat}, ${s.lon}'
          '  — via ${s.anchorKey}$official');
    }
  }
  _out('');

  // Coverage: which catalogue candidates have a real gauge nearby?
  _out('--- Candidate coverage (nearest discovered gauge) ---');
  for (final c in kTideReferenceCandidates) {
    DiscoveredStation? nearest;
    var nearestKm = double.infinity;
    for (final s in unique) {
      if (s.lat == null || s.lon == null) continue;
      final d = kmBetween(c.latitude, c.longitude, s.lat!, s.lon!);
      if (d < nearestKm) {
        nearestKm = d;
        nearest = s;
      }
    }
    if (nearest == null) {
      _out('  ${c.displayName}: no stations discovered — model-only');
    } else {
      _out('  ${c.displayName}: ${nearest.name} '
          '(${nearestKm.toStringAsFixed(1)} km)'
          '${nearestKm > 30 ? "  → likely model-only" : ""}');
    }
  }
  _out('');
  _out('Done. This report is sanitized — no API key or request URLs.');
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
