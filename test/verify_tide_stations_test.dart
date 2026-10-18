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
}
