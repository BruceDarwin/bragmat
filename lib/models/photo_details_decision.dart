/// The fields the user chose to take from a photo's metadata.
///
/// Returned by PhotoDetailsFoundDialog; `null` (no decision) means the
/// user kept their current catch details (cancelled / dismissed / pressed
/// keep). Independent flags let date, time and location be accepted or
/// rejected separately — nothing is applied without explicit selection.
class PhotoDetailsDecision {
  const PhotoDetailsDecision({
    this.useDate = false,
    this.useTime = false,
    this.useLocation = false,
  });

  final bool useDate;
  final bool useTime;
  final bool useLocation;

  bool get hasAnySelection => useDate || useTime || useLocation;

  PhotoDetailsDecision copyWith({
    bool? useDate,
    bool? useTime,
    bool? useLocation,
  }) {
    return PhotoDetailsDecision(
      useDate: useDate ?? this.useDate,
      useTime: useTime ?? this.useTime,
      useLocation: useLocation ?? this.useLocation,
    );
  }
}
