import '../models/photo_metadata_result.dart';
import '../widgets/photo_details_dialog.dart';

/// Field updates produced by applying a confirmed [PhotoDetailsDecision]
/// to a [PhotoMetadataResult]. Null fields mean "leave the current
/// catch value unchanged" — nothing is ever silently overwritten.
class PhotoDetailsUpdates {
  const PhotoDetailsUpdates({
    this.dateCaught,
    this.latitude,
    this.longitude,
    this.coordinateSource,
    this.clearFavouriteSpot = false,
  });

  /// New catch date/time, or null to keep the current value.
  final DateTime? dateCaught;

  /// New catch latitude/longitude, or null to keep current values.
  final double? latitude;
  final double? longitude;

  /// New coordinate_source value ('photo_gps'), or null to keep current.
  final String? coordinateSource;

  /// Whether a selected favourite spot should be cleared because the
  /// photo's coordinates were applied instead.
  final bool clearFavouriteSpot;

  bool get isEmpty =>
      dateCaught == null && latitude == null && coordinateSource == null;
}

/// Pure application/policy logic for photo metadata.
///
/// Extraction ([PhotoMetadataService]) and confirmation
/// ([PhotoDetailsFoundDialog]) are deliberately separated from application
/// so this logic is fully unit-testable without a UI or database.
class PhotoDetailsApplier {
  /// Whether a newly attached photo should automatically trigger the
  /// "Photo Details Found" prompt.
  ///
  /// Approved rules (Stage 4 plan §6): only the FIRST photo added to a NEW
  /// catch may auto-prompt. Subsequent photos and photos added while
  /// editing an existing catch never auto-prompt — metadata from those is
  /// applied only through the explicit "Use photo details" action.
  static bool shouldAutoPrompt({
    required PhotoMetadataResult metadata,
    required bool isFirstPhoto,
    required bool isEditMode,
  }) {
    return !isEditMode && isFirstPhoto && metadata.hasAnyMetadata;
  }

  /// Build the field updates implied by a confirmed decision.
  ///
  /// Only fields that are both selected AND valid are applied — the method
  /// re-checks [PhotoMetadataResult] validity itself, so an invalid value
  /// can never be applied even if the caller mis-asks for it.
  static PhotoDetailsUpdates buildUpdates({
    required PhotoMetadataResult metadata,
    required PhotoDetailsDecision decision,
    required DateTime? currentDateCaught,
  }) {
    if (!decision.hasAnySelection) return const PhotoDetailsUpdates();

    DateTime? newDateCaught;
    final photoDt = metadata.dateTime;
    final dateTimeUsable =
        metadata.dateTimeStatus == DateTimeStatus.valid && photoDt != null;
    if (dateTimeUsable && (decision.useDate || decision.useTime)) {
      final base = currentDateCaught ?? DateTime.now();
      newDateCaught = DateTime(
        decision.useDate ? photoDt.year : base.year,
        decision.useDate ? photoDt.month : base.month,
        decision.useDate ? photoDt.day : base.day,
        decision.useTime ? photoDt.hour : base.hour,
        decision.useTime ? photoDt.minute : base.minute,
      );
    }

    double? newLat;
    double? newLon;
    String? newSource;
    if (decision.useLocation && metadata.hasValidGps) {
      newLat = metadata.latitude;
      newLon = metadata.longitude;
      newSource = 'photo_gps';
    }

    return PhotoDetailsUpdates(
      dateCaught: newDateCaught,
      latitude: newLat,
      longitude: newLon,
      coordinateSource: newSource,
      clearFavouriteSpot: newSource != null,
    );
  }
}
