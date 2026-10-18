/// Curated tide-reference catalogue for Bragmat.
///
/// Two tiers, both version-controlled:
///
///   * [kTideReferenceCatalogue] — entries VERIFIED against the
///     WorldTides API (station identity + coordinates via `stations`,
///     prediction source via `extremes`). Only these are offered to
///     users (TideReferenceService.getAllReferences).
///   * [kTideReferenceCandidates] — proposed locations awaiting
///     verification (coordinates approximate, from the BoM/AHO NT
///     tide-location lists). Never shown in pickers; the
///     tool/verify_tide_stations.dart workflow verifies them before
///     promotion.
///
/// Entries carry region/state grouping and provider metadata; request
/// coordinates recorded on historical catches remain authoritative for
/// those catches — editing a catalogue entry never rewrites history.
library;

import '../models/tide_reference.dart';

/// Display labels for region grouping in pickers and reports.
const Map<TideRegion, String> tideRegionLabels = {
  TideRegion.darwinSurrounds: 'Darwin & surrounds',
  TideRegion.fogBayAndDaly: 'Fog Bay & Daly coast',
  TideRegion.tiwiIslands: 'Tiwi Islands',
  TideRegion.cobourgPeninsula: 'Cobourg Peninsula',
  TideRegion.arnhemLand: 'Arnhem Land',
  TideRegion.grooteEylandt: 'Groote Eylandt',
  TideRegion.gulfOfCarpentaria: 'Gulf of Carpentaria',
  TideRegion.josephBonaparteGulf: 'Joseph Bonaparte Gulf',
  TideRegion.offshore: 'Offshore waters',
};

/// Coarse Australian state classification for discovery reporting.
/// NT borders: ~129°E with WA, ~138°E with QLD on the Gulf coast.
/// Stations returned by wide-radius discovery sweeps can lie outside
/// the NT — this labels them so reports distinguish interstate finds.
/// Returns 'NT', 'WA', 'QLD' or 'other' (e.g. Indonesian waters).
String tideStateForCoordinates(double lat, double lon) {
  if (lon < 129.0) return 'WA';
  if (lon > 138.0) return 'QLD';
  if (lat > -10.0) return 'other'; // north of NT — non-Australian waters
  return 'NT';
}

/// Approximate NT region classification for discovery reporting.
/// Bounding boxes only — catalogue entries set their region explicitly;
/// this exists so the verifier can bucket newly discovered stations
/// that are not yet catalogued.
TideRegion tideRegionForCoordinates(double lat, double lon) {
  if (_box(lat, lon, -12.60, -12.10, 130.35, 131.10)) {
    return TideRegion.darwinSurrounds;
  }
  if (_box(lat, lon, -11.90, -10.90, 129.95, 131.35)) {
    return TideRegion.tiwiIslands;
  }
  if (_box(lat, lon, -11.80, -10.85, 131.35, 133.00)) {
    return TideRegion.cobourgPeninsula;
  }
  if (_box(lat, lon, -14.75, -13.35, 135.80, 137.20)) {
    return TideRegion.grooteEylandt;
  }
  if (lat < -14.6 && lon > 133.0) return TideRegion.gulfOfCarpentaria;
  if (lat < -14.0 && lon <= 130.4) return TideRegion.josephBonaparteGulf;
  if (_box(lat, lon, -14.20, -12.50, 129.40, 130.50)) {
    return TideRegion.fogBayAndDaly;
  }
  if (_box(lat, lon, -13.40, -10.90, 133.00, 137.50)) {
    return TideRegion.arnhemLand;
  }
  return TideRegion.offshore;
}

bool _box(
        double lat, double lon, double latMin, double latMax, double lonMin, double lonMax) =>
    lat >= latMin && lat <= latMax && lon >= lonMin && lon <= lonMax;

/// Published catalogue — WorldTides-verified references only.
///
///   * 'darwin': WorldTides station Australia:NT_TP001; `extremes`
///     returns 'Darwin' (Australia) predictions at these coords.
///   * 'dundee_beach': no gauge nearby; `extremes` served by the
///     FES2022 atlas with response coords exactly as requested.
///   * 'native_point': WorldTides station Australia:NT_TP053; `extremes`
///     returns 'Native Point' (Australia) predictions.
const List<TideReference> kTideReferenceCatalogue = [
  TideReference(
    id: 'darwin',
    displayName: 'Darwin',
    latitude: -12.4667,
    longitude: 130.8500,
    source: TideReferenceSource.station,
    region: TideRegion.darwinSurrounds,
    providerStationId: 'Australia:NT_TP001',
    verification: TideVerification.verified(
      verifiedOn: '2026-10',
      provenance: 'worldtides stations+extremes run '
          '(tool/verify_tide_stations.dart)',
    ),
  ),
  TideReference(
    id: 'dundee_beach',
    displayName: 'Dundee Beach',
    latitude: -12.705,
    longitude: 130.355,
    source: TideReferenceSource.model,
    region: TideRegion.fogBayAndDaly,
    verification: TideVerification.verified(
      verifiedOn: '2026-10',
      provenance: 'worldtides stations+extremes run — FES2022 '
          'atlas, no gauge (tool/verify_tide_stations.dart)',
    ),
  ),
  TideReference(
    id: 'native_point',
    displayName: 'Native Point',
    latitude: -12.650,
    longitude: 130.2667,
    source: TideReferenceSource.station,
    region: TideRegion.fogBayAndDaly,
    altNames: ['Native Pt'],
    providerStationId: 'Australia:NT_TP053',
    verification: TideVerification.verified(
      verifiedOn: '2026-10',
      provenance: 'worldtides stations+extremes run '
          '(tool/verify_tide_stations.dart)',
    ),
  ),
];

/// Proposed NT coverage awaiting WorldTides `extremes` verification.
///
/// Station identity and coordinates were established by the 2026-10
/// `stations` discovery sweep — coordinates here are the WorldTides
/// station positions (not BoM approximations). What remains unverified
/// is prediction serving: whether an `extremes` request at each point
/// resolves to the named gauge or falls back to the FES2022 atlas.
///
/// These entries are NEVER returned by TideReferenceService pickers;
/// promote by moving an entry to [kTideReferenceCatalogue] after a
/// SUITABLE verification verdict.
const List<TideReference> kTideReferenceCandidates = [
  // Darwin & surrounds
  TideReference(
    id: 'nightcliff',
    displayName: 'Nightcliff',
    latitude: -12.3667,
    longitude: 130.8167,
    region: TideRegion.darwinSurrounds,
    providerStationId: 'Australia:NT_TP063',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'charles_point_patches',
    displayName: 'Charles Point Patches',
    latitude: -12.3167,
    longitude: 130.6833,
    region: TideRegion.darwinSurrounds,
    providerStationId: 'Australia:NT_TP036',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'tapa_bay',
    displayName: 'Tapa Bay',
    latitude: -12.4333,
    longitude: 130.5833,
    region: TideRegion.darwinSurrounds,
    providerStationId: 'Australia:NT_TP055',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  // Fog Bay & Daly coast
  TideReference(
    id: 'anson_bay',
    displayName: 'Anson Bay',
    latitude: -13.3333,
    longitude: 130.0833,
    region: TideRegion.fogBayAndDaly,
    providerStationId: 'Australia:NT_TP049',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  // Tiwi Islands
  TideReference(
    id: 'snake_bay',
    displayName: 'Snake Bay',
    latitude: -11.4000,
    longitude: 130.6667,
    region: TideRegion.tiwiIslands,
    altNames: ['Snake Bay (Melville Island)'],
    providerStationId: 'Australia:NT_TP070',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'cape_van_diemen',
    displayName: 'Cape Van Dieman',
    latitude: -11.1500,
    longitude: 130.3667,
    region: TideRegion.tiwiIslands,
    altNames: ['Cape Van Diemen'],
    providerStationId: 'Australia:NT_TP069',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'point_fawcett',
    displayName: 'Point Fawcett',
    latitude: -11.6833,
    longitude: 130.0167,
    region: TideRegion.tiwiIslands,
    altNames: ['Point Fawcett (Offshore)'],
    providerStationId: 'Australia:NT_TP056',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  // Cobourg Peninsula & Van Diemen Gulf
  TideReference(
    id: 'port_essington',
    displayName: 'Port Essington',
    latitude: -11.0500,
    longitude: 132.0167,
    region: TideRegion.cobourgPeninsula,
    providerStationId: 'Australia:NT_TP074',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'cape_don',
    displayName: 'Cape Don',
    latitude: -11.3000,
    longitude: 131.7667,
    region: TideRegion.cobourgPeninsula,
    providerStationId: 'Australia:NT_TP040',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'cape_croker',
    displayName: 'Cape Croker',
    latitude: -11.0000,
    longitude: 132.5670,
    region: TideRegion.cobourgPeninsula,
    // Model-based: discovery shows only a FES2022 grid point here —
    // popular Cobourg fishing area with no gauge.
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — FES2022 point '
            'only; verify atlas behaviour'),
  ),
  // Arnhem Land
  TideReference(
    id: 'melville_bay',
    displayName: 'Melville Bay',
    latitude: -12.2000,
    longitude: 136.6667,
    region: TideRegion.arnhemLand,
    altNames: ['Gove', 'Gove Harbour', 'Nhulunbuy',
      'Melville Bay (Gove Harbour)'],
    providerStationId: 'Australia:NT_TP002',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'cape_wessel',
    displayName: 'Cape Wessel',
    latitude: -11.0000,
    longitude: 136.7500,
    region: TideRegion.arnhemLand,
    altNames: ['Wessel Islands'],
    providerStationId: 'Australia:NT_TP012',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'elcho_island',
    displayName: 'Elcho Island',
    latitude: -11.9167,
    longitude: 135.6667,
    region: TideRegion.arnhemLand,
    altNames: ['Galiwinku'],
    providerStationId: 'Australia:NT_TP018',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'north_goulburn_island',
    displayName: 'North Goulburn Island',
    latitude: -11.5000,
    longitude: 133.3667,
    region: TideRegion.arnhemLand,
    providerStationId: 'Australia:NT_TP088',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  // Groote Eylandt
  TideReference(
    id: 'milner_bay',
    displayName: 'Milner Bay',
    latitude: -13.8500,
    longitude: 136.4000,
    region: TideRegion.grooteEylandt,
    altNames: ['Groote Eylandt', 'Alyangula',
      'Milner Bay (Groote Eylandt)'],
    providerStationId: 'Australia:NT_TP003',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'port_langdon',
    displayName: 'Port Langdon',
    latitude: -13.8667,
    longitude: 136.8330,
    region: TideRegion.grooteEylandt,
    altNames: ['Umbakumba'],
    // Model-based: discovery shows only a FES2022 grid point on
    // Groote's west coast.
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — FES2022 point '
            'only; verify atlas behaviour'),
  ),
  // Gulf of Carpentaria
  TideReference(
    id: 'centre_island',
    displayName: 'Centre Island',
    latitude: -15.7333,
    longitude: 136.8000,
    region: TideRegion.gulfOfCarpentaria,
    altNames: ['Pellew Group', 'Sir Edward Pellew Group'],
    providerStationId: 'Australia:NT_TP014',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'borroloola',
    displayName: 'Borroloola Coast',
    latitude: -15.9700,
    longitude: 136.3500,
    region: TideRegion.gulfOfCarpentaria,
    altNames: ['Borroloola', 'Bing Bong', 'McArthur River'],
    // Model-based: no gauge on the mainland Gulf coast south of the
    // Pellew Group — a named model point for fishers working the
    // McArthur River coast.
    verification: TideVerification.candidate(
        provenance: 'no gauge in 2026-10 discovery — model point, '
            'coords approximate; verify atlas behaviour'),
  ),
  // Joseph Bonaparte Gulf
  TideReference(
    id: 'port_keats',
    displayName: 'Port Keats',
    latitude: -14.1500,
    longitude: 129.5667,
    region: TideRegion.josephBonaparteGulf,
    altNames: ['Wadeye'],
    providerStationId: 'Australia:NT_TP042',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  // Offshore waters — real WorldTides gauge positions from discovery
  TideReference(
    id: 'evans_shoal',
    displayName: 'Evans Shoal',
    latitude: -10.0667,
    longitude: 129.5167,
    region: TideRegion.offshore,
    providerStationId: 'Australia:NT_TP047',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
  TideReference(
    id: 'money_shoal',
    displayName: 'Money Shoal',
    latitude: -10.3167,
    longitude: 132.7167,
    region: TideRegion.offshore,
    providerStationId: 'Australia:NT_TP024',
    verification: TideVerification.candidate(
        provenance: 'worldtides discovery 2026-10 — station coords; '
            'extremes unverified'),
  ),
];

/// Catalogue lookup by stable id across BOTH published entries and
/// unpublished candidates. Picker-facing lookups must use
/// [kTideReferenceCatalogue] instead so candidates stay hidden.
final Map<String, TideReference> tideReferenceCatalogueById = {
  for (final r in kTideReferenceCatalogue) r.id: r,
  for (final r in kTideReferenceCandidates) r.id: r,
};

/// Published references grouped by region (insertion-ordered).
Map<TideRegion, List<TideReference>> tideReferencesByRegion() {
  final grouped = <TideRegion, List<TideReference>>{};
  for (final ref in kTideReferenceCatalogue) {
    grouped.putIfAbsent(
        ref.region ?? TideRegion.offshore, () => []).add(ref);
  }
  return grouped;
}
