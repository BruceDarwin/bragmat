import 'package:flutter/material.dart';

import '../models/photo_metadata_result.dart';

/// The fields the user chose to take from a photo's metadata.
///
/// Returned by [PhotoDetailsFoundDialog]; `null` means the user kept their
/// current catch details (cancelled / dismissed / pressed keep).
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

/// "Photo Details Found" confirmation dialog.
///
/// Presents extracted photo metadata (from [PhotoMetadataResult]) with
/// independent opt-in checkboxes for date, time and location. Only fields
/// that are actually usable are offered — invalid or suspicious values are
/// explained but never offered for application.
///
/// Dismiss via `Navigator.pop(context, decision)` with a
/// [PhotoDetailsDecision], or `pop(null)` to keep current catch details.
class PhotoDetailsFoundDialog extends StatefulWidget {
  const PhotoDetailsFoundDialog({
    super.key,
    required this.metadata,
    this.currentDateCaught,
    this.currentDateTimeAuthoritative = false,
    this.currentLatitude,
    this.currentLongitude,
    this.currentLocationName,
  });

  /// Extracted metadata to present.
  final PhotoMetadataResult metadata;

  /// The catch's current date/time, for conflict display.
  final DateTime? currentDateCaught;

  /// Whether the current date/time is authoritative (existing catch record
  /// or explicitly edited by the user) rather than an untouched default.
  /// Controls whether a "Current:" conflict line is shown.
  final bool currentDateTimeAuthoritative;

  /// The catch's current coordinates, for conflict display.
  final double? currentLatitude;
  final double? currentLongitude;

  /// The catch's current location name, if any.
  final String? currentLocationName;

  @override
  State<PhotoDetailsFoundDialog> createState() =>
      _PhotoDetailsFoundDialogState();
}

class _PhotoDetailsFoundDialogState extends State<PhotoDetailsFoundDialog> {
  bool _useDate = false;
  bool _useTime = false;
  bool _useLocation = false;

  PhotoMetadataResult get _m => widget.metadata;

  bool get _dateTimeOfferable =>
      _m.dateTimeStatus == DateTimeStatus.valid && _m.dateTime != null;

  bool get _locationOfferable => _m.hasValidGps;

  bool get _anythingOfferable => _dateTimeOfferable || _locationOfferable;

  bool get _nothingToShow =>
      !_anythingOfferable &&
      _m.dateTimeStatus == DateTimeStatus.absent &&
      _m.gpsStatus == GpsStatus.absent;

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _fmtDateTime(DateTime d) => '${_fmtDate(d)} ${_fmtTime(d)}';

  String _fmtOffset(double offset) {
    final sign = offset < 0 ? '-' : '+';
    final abs = offset.abs();
    final h = abs.floor();
    final m = ((abs - h) * 60).round();
    return 'UTC$sign${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  bool _dateTimeDiffers(DateTime current, DateTime photo) =>
      current.year != photo.year ||
      current.month != photo.month ||
      current.day != photo.day ||
      current.hour != photo.hour ||
      current.minute != photo.minute;

  bool _locationDiffers(double lat, double lon) =>
      (_m.latitude! - lat).abs() > 1e-6 || (_m.longitude! - lon).abs() > 1e-6;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Photo Details Found'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildContent(),
        ),
      ),
      actions: _buildActions(),
    );
  }

  List<Widget> _buildContent() {
    if (_nothingToShow) {
      return const [
        Text('No date, time or location details were found in this photo.'),
      ];
    }

    final children = <Widget>[
      const Text(
        'This photo contains details that may apply to this catch. '
        'Choose which to use:',
      ),
      const SizedBox(height: 16),
    ];

    _buildDateTimeSection(children);
    _buildLocationSection(children);

    return children;
  }

  void _buildDateTimeSection(List<Widget> children) {
    if (_dateTimeOfferable) {
      final dt = _m.dateTime!;
      children.add(Text(
        'Photo date/time: ${_fmtDateTime(dt)}',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ));

      if (_m.dateTimeSource == DateTimeSource.fileModification) {
        children.add(const SizedBox(height: 4));
        children.add(Text(
          'File date: ${_fmtDateTime(dt)} — this may not be when the '
          'photo was taken',
          style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
        ));
      } else if (_m.hasTimezone) {
        children.add(const SizedBox(height: 4));
        children.add(Text(
          'Timezone: ${_fmtOffset(_m.timezoneOffset!)}',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ));
      } else {
        children.add(const SizedBox(height: 4));
        children.add(Text(
          'The photo does not include timezone information. '
          'Check that the time is correct.',
          style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
        ));
      }

      if (widget.currentDateTimeAuthoritative &&
          widget.currentDateCaught != null &&
          _dateTimeDiffers(widget.currentDateCaught!, dt)) {
        children.add(const SizedBox(height: 4));
        children.add(Text(
          'Current: ${_fmtDateTime(widget.currentDateCaught!)}  →  '
          'Photo: ${_fmtDateTime(dt)}',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ));
      }

      children.add(CheckboxListTile(
        title: Text('Use photo date (${_fmtDate(dt)})'),
        value: _useDate,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        onChanged: (v) => setState(() => _useDate = v ?? false),
      ));
      children.add(CheckboxListTile(
        title: Text('Use photo time (${_fmtTime(dt)})'),
        value: _useTime,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        onChanged: (v) => setState(() => _useTime = v ?? false),
      ));
    } else if (_m.dateTimeStatus != DateTimeStatus.absent) {
      children.add(Text(
        "The photo's date and time could not be read${_dateTimeReason()}.",
        style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
      ));
      children.add(const SizedBox(height: 8));
    }
  }

  void _buildLocationSection(List<Widget> children) {
    if (_locationOfferable) {
      children.add(const SizedBox(height: 4));
      children.add(Text(
        'Photo location: ${_m.latitude!.toStringAsFixed(6)}, '
        '${_m.longitude!.toStringAsFixed(6)}',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ));

      final lat = widget.currentLatitude;
      final lon = widget.currentLongitude;
      if (lat != null && lon != null && _locationDiffers(lat, lon)) {
        children.add(const SizedBox(height: 4));
        final name = widget.currentLocationName;
        children.add(Text(
          'Current: ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}'
          '${name != null && name.isNotEmpty ? ' ($name)' : ''}  →  '
          'Photo: ${_m.latitude!.toStringAsFixed(6)}, '
          '${_m.longitude!.toStringAsFixed(6)}',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ));
      }

      children.add(CheckboxListTile(
        title: const Text('Use photo location'),
        value: _useLocation,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        onChanged: (v) => setState(() => _useLocation = v ?? false),
      ));
    } else if (_m.gpsStatus != GpsStatus.absent) {
      children.add(const SizedBox(height: 4));
      children.add(Text(
        "The photo's location could not be used${_gpsReason()}.",
        style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
      ));
    }
  }

  String _dateTimeReason() {
    switch (_m.dateTimeStatus) {
      case DateTimeStatus.malformed:
        return ' (unreadable values)';
      case DateTimeStatus.rejected:
        return ' (implausible value)';
      default:
        return '';
    }
  }

  String _gpsReason() {
    switch (_m.gpsStatus) {
      case GpsStatus.malformed:
        return ' (unreadable values)';
      case GpsStatus.incomplete:
        return ' (incomplete data)';
      case GpsStatus.rejected:
        return ' (invalid coordinates)';
      default:
        return '';
    }
  }

  List<Widget> _buildActions() {
    if (!_anythingOfferable) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ];
    }

    return [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep current catch details'),
      ),
      ElevatedButton(
        onPressed: (_useDate || _useTime || _useLocation)
            ? () => Navigator.pop(
                  context,
                  PhotoDetailsDecision(
                    useDate: _useDate,
                    useTime: _useTime,
                    useLocation: _useLocation,
                  ),
                )
            : null,
        child: const Text('Apply selected details'),
      ),
    ];
  }
}
