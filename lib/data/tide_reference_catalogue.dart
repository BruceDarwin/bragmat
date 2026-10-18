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

/// Proposed NT coverage awaiting WorldTides verification.
///
/// Coordinates are approximations from the BoM/AHO NT tide-location
/// lists — the verifier confirms the true request coordinates. These
/// entries are NEVER returned by TideReferenceService pickers; promote
/// by moving an entry to [kTideReferenceCatalogue] after verification.
const List<TideReference> kTideReferenceCandidates = [
  // Darwin & surrounds
  TideReference(
    id: 'nightcliff',
    displayName: 'Nightcliff',
    latitude: -12.383,
    longitude: 130.855,
    region: TideRegion.darwinSurrounds,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  TideReference(
    id: 'charles_point_patches',
    displayName: 'Charles Point Patches',
    latitude: -12.37,
    longitude: 130.63,
    region: TideRegion.darwinSurrounds,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  // Fog Bay & Daly coast
  TideReference(
    id: 'anson_bay',
    displayName: 'Anson Bay',
    latitude: -13.42,
    longitude: 130.07,
    region: TideRegion.fogBayAndDaly,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  TideReference(
    id: 'tapa_bay',
    displayName: 'Tapa Bay',
    latitude: -12.63,
    longitude: 130.44,
    region: TideRegion.fogBayAndDaly,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  // Tiwi Islands
  TideReference(
    id: 'snake_bay',
    displayName: 'Snake Bay',
    latitude: -11.42,
    longitude: 130.60,
    region: TideRegion.tiwiIslands,
    altNames: ['Snake Bay (Melville Island)'],
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  TideReference(
    id: 'cape_van_diemen',
    displayName: 'Cape Van Diemen',
    latitude: -11.90,
    longitude: 130.02,
    region: TideRegion.tiwiIslands,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  TideReference(
    id: 'point_fawcett',
    displayName: 'Point Fawcett',
    latitude: -11.78,
    longitude: 130.03,
    region: TideRegion.tiwiIslands,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  // Cobourg Peninsula & Van Diemen Gulf
  TideReference(
    id: 'port_essington',
    displayName: 'Port Essington',
    latitude: -11.37,
    longitude: 132.15,
    region: TideRegion.cobourgPeninsula,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  TideReference(
    id: 'cape_don',
    displayName: 'Cape Don',
    latitude: -11.32,
    longitude: 131.77,
    region: TideRegion.cobourgPeninsula,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  // Arnhem Land
  TideReference(
    id: 'melville_bay',
    displayName: 'Melville Bay',
    latitude: -12.250,
    longitude: 136.700,
    region: TideRegion.arnhemLand,
    altNames: ['Gove', 'Gove Harbour', 'Nhulunbuy'],
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  TideReference(
    id: 'cape_wessel',
    displayName: 'Cape Wessel',
    latitude: -11.00,
    longitude: 136.75,
    region: TideRegion.arnhemLand,
    altNames: ['Wessel Islands'],
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  TideReference(
    id: 'elcho_island',
    displayName: 'Elcho Island',
    latitude: -12.02,
    longitude: 135.57,
    region: TideRegion.arnhemLand,
    altNames: ['Galiwinku'],
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  TideReference(
    id: 'north_goulburn_island',
    displayName: 'North Goulburn Island',
    latitude: -11.55,
    longitude: 133.42,
    region: TideRegion.arnhemLand,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  // Groote Eylandt
  TideReference(
    id: 'milner_bay',
    displayName: 'Milner Bay',
    latitude: -13.860,
    longitude: 136.420,
    region: TideRegion.grooteEylandt,
    altNames: ['Groote Eylandt', 'Alyangula'],
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  // Gulf of Carpentaria
  TideReference(
    id: 'centre_island',
    displayName: 'Centre Island',
    latitude: -15.740,
    longitude: 136.810,
    region: TideRegion.gulfOfCarpentaria,
    altNames: ['Pellew Group', 'Borroloola'],
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  // Joseph Bonaparte Gulf
  TideReference(
    id: 'port_keats',
    displayName: 'Port Keats',
    latitude: -14.25,
    longitude: 129.52,
    region: TideRegion.josephBonaparteGulf,
    altNames: ['Wadeye'],
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  // Offshore waters — bluewater marks fishers actually use
  TideReference(
    id: 'evans_shoal',
    displayName: 'Evans Shoal',
    latitude: -9.85,
    longitude: 129.70,
    region: TideRegion.offshore,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
  ),
  TideReference(
    id: 'money_shoal',
    displayName: 'Money Shoal',
    latitude: -11.93,
    longitude: 131.00,
    region: TideRegion.offshore,
    verification: TideVerification.candidate(
        provenance: 'bom/aho location — coords approximate'),
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
