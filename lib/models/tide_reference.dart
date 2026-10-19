/// Tide Reference Model
///
/// Represents a fixed tide reference location that can be selected by the user
/// for tide data requests, regardless of the actual catch location.
library;

/// The kind of source a tide reference resolves to in WorldTides.
///
/// [station] — a real tide gauge/harmonic station carried by WorldTides
///             (the API response includes a `station` name).
/// [model]   — a named location with no gauge; predictions come from the
///             WorldTides background atlas (e.g. FES2022).
enum TideReferenceSource { station, model }

/// Coastal regions used to group catalogue entries for display.
///
/// Currently covers the Northern Territory coastline; the catalogue
/// carries a separate [TideReference.state] so other Australian states
/// can introduce their own region values without reusing these.
enum TideRegion {
  darwinSurrounds,
  fogBayAndDaly,
  tiwiIslands,
  cobourgPeninsula,
  arnhemLand,
  grooteEylandt,
  gulfOfCarpentaria,
  josephBonaparteGulf,
  offshore,
}

/// Whether a catalogue entry has been confirmed against the tide
/// provider. [verified] entries may be offered to users; [candidate]
/// entries are proposed locations awaiting verification and are never
/// shown in pickers.
enum TideVerificationStatus { verified, candidate }

/// Verification metadata for a catalogue entry: when and how the
/// entry was confirmed against the provider.
class TideVerification {
  final TideVerificationStatus status;

  /// ISO date ('YYYY-MM-DD' or 'YYYY-MM') the entry was verified.
  /// Null for unverified candidates.
  final String? verifiedOn;

  /// Short provenance note, e.g. 'worldtides stations+extremes run'
  /// or 'bom/aho location list — coords approximate'.
  final String? provenance;

  const TideVerification.verified({this.verifiedOn, this.provenance})
      : status = TideVerificationStatus.verified;

  const TideVerification.candidate({this.provenance})
      : status = TideVerificationStatus.candidate,
        verifiedOn = null;
}

class TideReference {
  final String id;
  final String displayName;
  final double latitude;
  final double longitude;
  final bool isUserCreated;

  /// Whether this reference is a real tide station or a model-only
  /// location. Null for the automatic (catch-location) sentinel, for
  /// unverified candidates whose true source is unknown, and for
  /// references reconstructed from historical records where the source
  /// kind is unknown.
  final TideReferenceSource? source;

  /// Australian state/territory code ('NT', 'QLD', …) this reference
  /// belongs to. Defaults to 'NT' — the catalogue is NT-focused.
  final String state;

  /// Geographical region used to group entries in pickers. Null for
  /// the automatic sentinel and reconstructed historical references.
  final TideRegion? region;

  /// Alternative names this reference may be recorded or searched
  /// under — e.g. 'Gove' for 'Melville Bay'. Used by the recorded-
  /// reference resolver and by catalogue search.
  final List<String> altNames;

  /// Provider-specific station identifier, e.g. the WorldTides
  /// station id 'Australia:NT_TP053'. Informational only — identity
  /// remains the catalogue [id].
  final String? providerStationId;

  /// Verification state. Verified entries are published to pickers;
  /// candidate entries stay in the catalogue file as proposals and are
  /// never offered to users until verified.
  final TideVerification verification;

  const TideReference({
    required this.id,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.isUserCreated = false,
    this.source,
    this.state = 'NT',
    this.region,
    this.altNames = const [],
    this.providerStationId,
    this.verification = const TideVerification.candidate(),
  });

  /// True when this reference is backed by a real tide station.
  bool get isStation => source == TideReferenceSource.station;

  /// True when this reference is a named location served by the
  /// WorldTides background model rather than a physical gauge.
  bool get isModelLocation => source == TideReferenceSource.model;

  /// True when this entry has been verified against the tide provider
  /// and may be offered in pickers. Candidate entries in the catalogue
  /// file are proposals only.
  bool get isPublished =>
      verification.status == TideVerificationStatus.verified;

  /// Copy with method for creating modified copies
  TideReference copyWith({
    String? id,
    String? displayName,
    double? latitude,
    double? longitude,
    bool? isUserCreated,
    TideReferenceSource? source,
    String? state,
    TideRegion? region,
    List<String>? altNames,
    String? providerStationId,
    TideVerification? verification,
  }) {
    return TideReference(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isUserCreated: isUserCreated ?? this.isUserCreated,
      source: source ?? this.source,
      state: state ?? this.state,
      region: region ?? this.region,
      altNames: altNames ?? this.altNames,
      providerStationId: providerStationId ?? this.providerStationId,
      verification: verification ?? this.verification,
    );
  }

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'latitude': latitude,
      'longitude': longitude,
      'isUserCreated': isUserCreated ? 1 : 0,
      'source': source?.name,
      'state': state,
      'region': region?.name,
      'altNames': altNames,
      'providerStationId': providerStationId,
      'verificationStatus': verification.status.name,
      'verifiedOn': verification.verifiedOn,
      'verificationProvenance': verification.provenance,
    };
  }

  /// Create from map
  factory TideReference.fromMap(Map<String, dynamic> map) {
    final status = map['verificationStatus'] == 'verified'
        ? TideVerificationStatus.verified
        : TideVerificationStatus.candidate;
    return TideReference(
      id: map['id'] as String,
      displayName: map['displayName'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      isUserCreated: (map['isUserCreated'] as int?) == 1,
      source: _parseSource(map['source'] as String?),
      state: map['state'] as String? ?? 'NT',
      region: _parseRegion(map['region'] as String?),
      altNames: (map['altNames'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      providerStationId: map['providerStationId'] as String?,
      verification: status == TideVerificationStatus.verified
          ? TideVerification.verified(
              verifiedOn: map['verifiedOn'] as String?,
              provenance: map['verificationProvenance'] as String?)
          : TideVerification.candidate(
              provenance: map['verificationProvenance'] as String?),
    );
  }

  static TideRegion? _parseRegion(String? value) {
    if (value == null) return null;
    for (final r in TideRegion.values) {
      if (r.name == value) return r;
    }
    return null;
  }

  static TideReferenceSource? _parseSource(String? value) {
    switch (value) {
      case 'station':
        return TideReferenceSource.station;
      case 'model':
        return TideReferenceSource.model;
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TideReference && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
