/// Coordinate validation helpers for map display.
///
/// A coordinate is displayable when both values are non-null, finite and
/// within the valid geographic ranges. (0, 0) is a legitimate coordinate —
/// it is not a missing-value sentinel and must not be rejected.
library;

/// Whether [latitude] is non-null, finite and within -90..90 inclusive.
bool isValidMapLatitude(double? latitude) {
  return latitude != null && latitude.isFinite && !latitude.isNaN
      && latitude >= -90.0 && latitude <= 90.0;
}

/// Whether [longitude] is non-null, finite and within -180..180 inclusive.
bool isValidMapLongitude(double? longitude) {
  return longitude != null && longitude.isFinite && !longitude.isNaN
      && longitude >= -180.0 && longitude <= 180.0;
}

/// Whether a coordinate pair is safe to display on a map.
bool hasValidMapCoordinates(double? latitude, double? longitude) {
  return isValidMapLatitude(latitude) && isValidMapLongitude(longitude);
}
