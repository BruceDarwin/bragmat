/// Resolves a stored `coordinate_source` value to a display label.
///
/// The canonical stored values are snake_case identifiers (`manual`,
/// `device_gps`, `photo_gps`, `favourite_spot`, `map_selected`). Older
/// records may hold the equivalent display strings (`'Device GPS'`,
/// `'Map Selected'`, `'Favourite Spot'`, `'Manual'`) — these are mapped
/// here at display time only; historical records are never rewritten.
///
/// When no source is recorded, a catch whose coordinates match attached
/// photo GPS metadata is inferred as 'Photo EXIF'; otherwise 'Manual'.
library;

import '../models/catch_media.dart';

const Map<String, String> _canonicalLabels = {
  'manual': 'Manual',
  'device_gps': 'Device GPS',
  'photo_gps': 'Photo GPS',
  'favourite_spot': 'Favourite Spot',
  'map_selected': 'Map Selected',
};

/// Legacy display strings written by earlier app versions, mapped to their
/// canonical identifiers.
const Map<String, String> _legacyAliases = {
  'Manual': 'manual',
  'Device GPS': 'device_gps',
  'Photo EXIF': 'photo_gps',
  'Favourite Spot': 'favourite_spot',
  'Map Selected': 'map_selected',
};

/// Returns the display label for a stored [coordinateSource] value.
///
/// Unknown non-empty values pass through unchanged so nothing is hidden.
/// When no source is recorded, [mediaItems] with GPS coordinates matching
/// [latitude]/[longitude] imply a photo-EXIF source; otherwise 'Manual'.
String coordinateSourceLabel({
  String? coordinateSource,
  double? latitude,
  double? longitude,
  List<CatchMedia> mediaItems = const [],
}) {
  if (coordinateSource != null && coordinateSource.isNotEmpty) {
    final canonical = _legacyAliases[coordinateSource] ?? coordinateSource;
    return _canonicalLabels[canonical] ?? coordinateSource;
  }

  if (latitude != null && longitude != null) {
    for (final media in mediaItems) {
      if (media.latitude != null && media.longitude != null) {
        final latDiff = (media.latitude! - latitude).abs();
        final lonDiff = (media.longitude! - longitude).abs();
        if (latDiff < 0.000001 && lonDiff < 0.000001) {
          return 'Photo EXIF';
        }
      }
    }
  }
  return 'Manual';
}
