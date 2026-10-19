import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/tide_reference_catalogue.dart';
import '../models/tide_reference.dart';
import '../services/tide_reference_service.dart';

/// Outcome of [showTideReferencePicker]. [reference] is null only when the
/// caller passed `allowNone: true` and the user chose "Not recorded".
/// A dismissed sheet returns `null` — callers must leave state unchanged.
class TideReferencePickerResult {
  final TideReference? reference;
  const TideReferencePickerResult(this.reference);
}

/// Shows the shared searchable tide-reference picker as a modal sheet.
///
/// Returns the chosen reference only when the user taps an entry;
/// dismissing the sheet (barrier tap, back, drag-down) returns null.
Future<TideReferencePickerResult?> showTideReferencePicker(
  BuildContext context, {
  TideReference? selected,
  bool allowNone = false,
}) {
  return showModalBottomSheet<TideReferencePickerResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => TideReferencePickerSheet(
      selected: selected,
      allowNone: allowNone,
    ),
  );
}

/// Searchable, region-grouped tide-reference picker.
///
/// Sources its entries from the published catalogue
/// ([kTideReferenceCatalogue]) via [tideReferencesByRegion] — the pickers
/// never see unverified candidates. "Automatic (catch location)" is
/// pinned above the list at all times; a selected reference that is no
/// longer in the catalogue is shown under "Recorded reference" so
/// historical choices remain visible rather than silently replaced.
class TideReferencePickerSheet extends StatefulWidget {
  final TideReference? selected;

  /// When true, offers a "Not recorded" option that resolves to
  /// [TideReferencePickerResult.reference] == null — used for historical
  /// catches that predate tide-reference recording.
  final bool allowNone;

  const TideReferencePickerSheet({
    super.key,
    this.selected,
    this.allowNone = false,
  });

  @override
  State<TideReferencePickerSheet> createState() =>
      _TideReferencePickerSheetState();
}

class _TideReferencePickerSheetState extends State<TideReferencePickerSheet> {
  String _query = '';

  bool _matches(TideReference ref) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return ref.displayName.toLowerCase().contains(q) ||
        ref.altNames.any((a) => a.toLowerCase().contains(q));
  }

  /// Published entries matching the query, grouped by region in
  /// catalogue order (insertion order of [tideReferencesByRegion]).
  Map<TideRegion, List<TideReference>> _grouped() {
    final grouped = <TideRegion, List<TideReference>>{};
    for (final ref in kTideReferenceCatalogue) {
      if (!_matches(ref)) continue;
      grouped
          .putIfAbsent(ref.region ?? TideRegion.offshore, () => [])
          .add(ref);
    }
    return grouped;
  }

  bool _isSelected(TideReference ref) =>
      widget.selected != null && widget.selected!.id == ref.id;

  /// A selected reference not in the published catalogue (historical /
  /// discontinued) — surfaced under its own header so it stays visible.
  TideReference? get _recordedOnly {
    final sel = widget.selected;
    if (sel == null || TideReferenceService.isAutomatic(sel)) return null;
    if (kTideReferenceCatalogue.any((r) => r.id == sel.id)) return null;
    return sel;
  }

  void _pick(TideReference? ref) =>
      Navigator.of(context).pop(TideReferencePickerResult(ref));

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Fit under the keyboard and inside the status-bar area on small
    // phones: shrink the sheet to whatever space remains.
    final maxHeight =
        media.size.height - media.viewInsets.bottom - media.padding.top;
    final height = math.min(media.size.height * 0.85, maxHeight);
    final theme = Theme.of(context);
    final recordedOnly = _recordedOnly;
    final grouped = _grouped();

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tide reference',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('tide_ref_close'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('tide_ref_search'),
                decoration: const InputDecoration(
                  hintText: 'Search name or alternative name',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            // Automatic is pinned above the list — always visible,
            // unaffected by the search filter.
            _automaticTile(theme),
            if (widget.allowNone) _notRecordedTile(theme),
            if (recordedOnly != null) ...[
              _regionHeader('Recorded reference', theme),
              _referenceTile(recordedOnly, theme),
            ],
            Expanded(
              child: grouped.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No matching tide references',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final entry in grouped.entries) ...[
                          _regionHeader(
                              tideRegionLabels[entry.key] ?? 'Other',
                              theme),
                          for (final ref in entry.value)
                            _referenceTile(ref, theme),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _automaticTile(ThemeData theme) {
    const ref = TideReference(
      id: 'automatic',
      displayName: 'Automatic (catch location)',
      latitude: 0,
      longitude: 0,
    );
    return ListTile(
      key: const Key('tide_ref_automatic'),
      dense: true,
      title: const Text('Automatic (catch location)'),
      subtitle: const Text('catch location'),
      trailing: _isSelected(ref)
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      onTap: () => _pick(ref),
    );
  }

  Widget _notRecordedTile(ThemeData theme) {
    return ListTile(
      key: const Key('tide_ref_not_recorded'),
      dense: true,
      title: const Text('Not recorded'),
      trailing: widget.selected == null
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      onTap: () => _pick(null),
    );
  }

  Widget _regionHeader(String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _referenceTile(TideReference ref, ThemeData theme) {
    final regionLabel = tideRegionLabels[ref.region];
    final source = TideReferenceService.describeSource(ref);
    return ListTile(
      key: Key('tide_ref_${ref.id}'),
      dense: true,
      title: Text(ref.displayName),
      subtitle:
          Text(regionLabel != null ? '$regionLabel · $source' : source),
      trailing: _isSelected(ref)
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      onTap: () => _pick(ref),
    );
  }
}
