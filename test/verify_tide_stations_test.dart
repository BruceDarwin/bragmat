// Tests for the response parsing and suitability verdicts used by
// tool/verify_tide_stations.dart. These run without any API key or
// network access — they only exercise the pure parsing/decision code.

import 'package:flutter_test/flutter_test.dart';

import '../tool/verify_tide_stations.dart';

void main() {
  group('parseStationsResponse', () {
    test('parses the nearest station', () {
      final result = parseStationsResponse({
        'stations': [
          {
            'id': 'darwin',
            'name': 'Darwin',
            'lat': -12.4667,
            'lon': 130.85,
            'distance': 1.2,
          },
          {'id': 'nightcliff', 'name': 'Nightcliff', 'lat': -12.38, 'lon': 130.85},
        ],
      });
      expect(result.name, 'Darwin');
      expect(result.id, 'darwin');
      expect(result.lat, -12.4667);
      expect(result.distanceKm, 1.2);
      expect(result.totalFound, 2);
    });

    test('empty list means no nearby station', () {
      final result = parseStationsResponse({'stations': []});
      expect(result.name, isNull);
      expect(result.totalFound, 0);
    });

    test('surfaces API error strings', () {
      final result = parseStationsResponse({'error': 'call failed'});
      expect(result.error, 'call failed');
    });

    // Regression: WorldTides returns station coordinates/distance as
    // numeric strings — `as num?` crashed the original run.
    test('numeric-string fields are coerced', () {
      final result = parseStationsResponse({
        'stations': [
          {
            'id': 'darwin',
            'name': 'Darwin',
            'lat': '-12.4667',
            'lon': '130.85',
            'distance': '1.234',
          },
        ],
      });
      expect(result.lat, -12.4667);
      expect(result.lon, 130.85);
      expect(result.distanceKm, 1.234);
    });

    test('malformed or missing numeric fields become null, not a crash',
        () {
      final result = parseStationsResponse({
        'stations': [
          {'id': 'x', 'name': 'X', 'lat': 'not-a-number', 'distance': {}},
        ],
      });
      expect(result.lat, isNull);
      expect(result.lon, isNull);
      expect(result.distanceKm, isNull);
      expect(result.name, 'X');
    });

    test('a non-map station entry reports a parse error', () {
      final result = parseStationsResponse({
        'stations': ['unexpected string entry'],
      });
      expect(result.error, isNotNull);
    });

    test('non-string error values are surfaced safely', () {
      final result = parseStationsResponse({'error': 42});
      expect(result.error, '42');
    });
  });

  group('parseStationList (discovery)', () {
    test('parses every station in the response', () {
      final result = parseStationList({
        'stations': [
          {'id': 'a', 'name': 'A', 'lat': '-12.0', 'lon': '130.0'},
          {'id': 'b', 'name': 'B', 'lat': -12.5, 'lon': 130.5},
          {'id': 'c', 'name': 'C', 'lat': -13.0, 'lon': 131.0},
        ],
      });
      expect(result.error, isNull);
      expect(result.stations.map((s) => s.id), ['a', 'b', 'c']);
      expect(result.stations.first.lat, -12.0);
    });

    test('surfaces API errors and returns no stations', () {
      final result = parseStationList({'error': 'invalid key'});
      expect(result.error, 'invalid key');
      expect(result.stations, isEmpty);
    });

    test('skips malformed entries instead of throwing', () {
      final result = parseStationList({
        'stations': [
          'bad entry',
          {'id': 'ok', 'name': 'OK', 'lat': '-12.0', 'lon': '130.0'},
        ],
      });
      expect(result.stations.single.id, 'ok');
    });

    test('missing stations key returns empty list', () {
      expect(parseStationList({}).stations, isEmpty);
    });
  });

  group('dedupeStations', () {
    DiscoveredStation st(String id, double dist,
            {String? name, String anchor = 'a1'}) =>
        DiscoveredStation(
            id: id,
            name: name ?? id,
            lat: -12.0,
            lon: 130.0,
            distanceKm: dist,
            anchorKey: anchor);

    test('deduplicates by station id, keeping the closest sighting', () {
      final result = dedupeStations([
        st('s1', 40.0, anchor: 'far'),
        st('s1', 10.0, anchor: 'near'),
        st('s2', 5.0),
      ]);
      expect(result.length, 2);
      final s1 = result.firstWhere((s) => s.id == 's1');
      expect(s1.anchorKey, 'near');
    });

    test('stations with different ids are preserved', () {
      final result = dedupeStations([st('a', 1), st('b', 2), st('c', 3)]);
      expect(result.length, 3);
    });

    test('null-id stations dedupe by name+coords fallback', () {
      final result = dedupeStations([
        const DiscoveredStation(name: 'X', lat: -12.0, lon: 130.0),
        const DiscoveredStation(name: 'X', lat: -12.0, lon: 130.0),
        const DiscoveredStation(name: 'Y', lat: -12.0, lon: 130.0),
      ]);
      expect(result.length, 2);
    });
  });

  group('isOfficialLocation', () {
    test('matches BoM NT location names', () {
      expect(isOfficialLocation('Darwin'), isTrue);
      expect(isOfficialLocation('Snake Bay'), isTrue);
      expect(isOfficialLocation('Native Point'), isTrue);
    });

    test('is case-insensitive and substring-tolerant', () {
      expect(isOfficialLocation('darwin'), isTrue);
      expect(isOfficialLocation('Melville Bay (Gove)'), isTrue);
    });

    test('rejects unknown names and null', () {
      expect(isOfficialLocation('Not A Place'), isFalse);
      expect(isOfficialLocation(null), isFalse);
    });
  });

  group('kmBetween', () {
    test('computes a plausible distance', () {
      // Darwin to Native Point ≈ 65 km
      final d = kmBetween(-12.4667, 130.85, -12.65, 130.2667);
      expect(d, greaterThan(50));
      expect(d, lessThan(80));
    });

    test('zero for identical points', () {
      expect(kmBetween(-12.0, 130.0, -12.0, 130.0), 0);
    });
  });

  group('parseExtremesResponse', () {
    test('station response resolves to station source', () {
      final result = parseExtremesResponse({
        'station': 'Darwin',
        'atlas': 'Australia',
        'responseLat': -12.4667,
        'responseLon': 130.85,
        'extremes': [
          {'date': '2026-08-01T16:33+0000', 'height': 1.2, 'type': 'Low'},
        ],
      });
      expect(result.source, PredictionSource.station);
      expect(result.stationName, 'Darwin');
      expect(result.eventCount, 1);
      expect(result.responseLat, -12.4667);
    });

    test('atlas-only response resolves to model source', () {
      final result = parseExtremesResponse({
        'atlas': 'FES2022',
        'responseLat': -12.5,
        'responseLon': 130.5,
        'extremes': [
          {'date': '2026-08-01T16:13+0000', 'height': 1.29, 'type': 'Low'},
        ],
      });
      expect(result.source, PredictionSource.atlas);
      expect(result.stationName, isNull);
      expect(result.atlas, 'FES2022');
    });

    test('error response resolves to error source', () {
      final result = parseExtremesResponse({'error': 'invalid key'});
      expect(result.source, PredictionSource.error);
      expect(result.error, 'invalid key');
    });

    test('numeric-string response coordinates are coerced', () {
      final result = parseExtremesResponse({
        'station': 'Darwin',
        'responseLat': '-12.4667',
        'responseLon': '130.85',
        'extremes': [],
      });
      expect(result.source, PredictionSource.station);
      expect(result.responseLat, -12.4667);
      expect(result.responseLon, 130.85);
    });

    test('malformed fields do not throw', () {
      final result = parseExtremesResponse({
        'station': {'unexpected': 'map'},
        'responseLat': [1, 2],
        'extremes': 'not-a-list',
      });
      // station present (stringified) — still classified, not crashed
      expect(result.responseLat, isNull);
      expect(result.eventCount, 0);
    });
  });

  group('candidate selection', () {
    const candidates = [
      Candidate('darwin', 'Darwin', -12.4667, 130.85),
      Candidate('dundee_beach', 'Dundee Beach', -12.705, 130.355),
      Candidate('melville_bay', 'Melville Bay / Gove', -12.25, 136.7),
    ];

    test('no selectors returns all candidates', () {
      expect(selectCandidates(candidates, const []).length, 3);
    });

    test('keys select exactly the named candidates', () {
      final selected = selectCandidates(
          candidates, const ['darwin', 'dundee_beach']);
      expect(selected.map((c) => c.key), ['darwin', 'dundee_beach']);
    });

    test('label substrings and case-insensitive matching work', () {
      final selected = selectCandidates(candidates, const ['DUNDEE']);
      expect(selected.single.key, 'dundee_beach');
    });

    test('unmatched selectors are reported as unknown', () {
      final unknown = <String>[];
      final selected = selectCandidates(candidates, const ['darwin', 'bogus'],
          unknown: unknown);
      expect(selected.map((c) => c.key), ['darwin']);
      expect(unknown, ['bogus']);
    });

    test('parseOnlySelectors handles --only=x,y and --only x y forms', () {
      expect(parseOnlySelectors(['--run', '--only=darwin,dundee_beach']),
          ['darwin', 'dundee_beach']);
      expect(parseOnlySelectors(['--only', 'darwin']), ['darwin']);
      expect(parseOnlySelectors(['--run']), isEmpty);
    });

    test('parseReportPath handles path, bare flag, and absent forms', () {
      expect(parseReportPath(['--report=report.txt']), 'report.txt');
      expect(parseReportPath(['--report', 'out.txt']), 'out.txt');
      expect(parseReportPath(['--report']),
          'verify_tide_stations_report.txt');
      expect(parseReportPath(['--run']), isNull);
    });
  });

  group('assessSuitability', () {
    const dundee = Candidate('dundee_beach', 'Dundee Beach', -12.705, 130.355);
    const darwin = Candidate('darwin', 'Darwin', -12.4667, 130.85,
        expectedStation: 'Darwin');

    StationLookup noStation() => const StationLookup(totalFound: 0);
    StationLookup darwinStation() => const StationLookup(
          id: 'darwin',
          name: 'Darwin',
          lat: -12.4667,
          lon: 130.85,
          distanceKm: 0.1,
          totalFound: 1,
        );

    test('matching station response is suitable as a station reference',
        () {
      final verdict = assessSuitability(
        darwin,
        darwinStation(),
        const PredictionResult(
          source: PredictionSource.station,
          stationName: 'Darwin',
        ),
      );
      expect(verdict, contains('SUITABLE'));
    });

    test('unexpected station name is flagged for review', () {
      final verdict = assessSuitability(
        darwin,
        darwinStation(),
        const PredictionResult(
          source: PredictionSource.station,
          stationName: 'Nightcliff',
        ),
      );
      expect(verdict, contains('REVIEW'));
    });

    test('atlas-only response is model-only — not a station', () {
      final verdict = assessSuitability(
        dundee,
        noStation(),
        const PredictionResult(
          source: PredictionSource.atlas,
          atlas: 'FES2022',
        ),
      );
      expect(verdict, contains('MODEL-ONLY'));
      expect(verdict, isNot(contains('SUITABLE as tide station')));
    });

    test('API errors are inconclusive, never suitable', () {
      final verdict = assessSuitability(
        darwin,
        const StationLookup(error: 'HTTP 500'),
        const PredictionResult(source: PredictionSource.error),
      );
      expect(verdict, contains('INCONCLUSIVE'));
    });
  });

  group('assessExtremesOnly', () {
    const snakeBay = Candidate('snake_bay', 'Snake Bay', -11.4, 130.6667,
        expectedStation: 'Snake Bay');
    const croker = Candidate('cape_croker', 'Cape Croker', -11.0, 132.567);

    test('expected station served → SUITABLE', () {
      expect(
        assessExtremesOnly(
          snakeBay,
          const PredictionResult(
              source: PredictionSource.station, stationName: 'Snake Bay'),
        ),
        contains('SUITABLE'),
      );
    });

    test('parenthesised station names still match', () {
      // WorldTides returns 'Milner Bay (Groote Eylandt)' — substring
      // matching must accept it for expected 'Milner Bay'.
      const milner = Candidate('milner_bay', 'Milner Bay', -13.85, 136.4,
          expectedStation: 'Milner Bay');
      expect(
        assessExtremesOnly(
          milner,
          const PredictionResult(
              source: PredictionSource.station,
              stationName: 'Milner Bay (Groote Eylandt)'),
        ),
        contains('SUITABLE'),
      );
    });

    test('substituted station is flagged for review', () {
      expect(
        assessExtremesOnly(
          snakeBay,
          const PredictionResult(
              source: PredictionSource.station, stationName: 'Darwin'),
        ),
        contains('REVIEW'),
      );
    });

    test('atlas when a station was expected is flagged for review', () {
      expect(
        assessExtremesOnly(
          snakeBay,
          const PredictionResult(
              source: PredictionSource.atlas, atlas: 'FES2022'),
        ),
        contains('REVIEW'),
      );
    });

    test('atlas for a model candidate is confirmed MODEL-ONLY', () {
      expect(
        assessExtremesOnly(
          croker,
          const PredictionResult(
              source: PredictionSource.atlas, atlas: 'FES2022'),
        ),
        contains('MODEL-ONLY'),
      );
    });

    test('a station where a model was expected is flagged for review',
        () {
      expect(
        assessExtremesOnly(
          croker,
          const PredictionResult(
              source: PredictionSource.station,
              stationName: 'Port Essington'),
        ),
        contains('REVIEW'),
      );
    });

    test('errors are inconclusive', () {
      expect(
        assessExtremesOnly(
          snakeBay,
          const PredictionResult(
              source: PredictionSource.error, error: 'HTTP 500'),
        ),
        contains('INCONCLUSIVE'),
      );
    });
  });

  group('assessSuitability errors', () {
    const darwin = Candidate('darwin', 'Darwin', -12.4667, 130.85,
        expectedStation: 'Darwin');

    test('API errors are inconclusive, never suitable', () {
      final verdict = assessSuitability(
        darwin,
        const StationLookup(error: 'HTTP 500'),
        const PredictionResult(source: PredictionSource.error),
      );
      expect(verdict, contains('INCONCLUSIVE'));
    });
  });
}
