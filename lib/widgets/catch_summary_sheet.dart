/// Shared catch-summary bottom sheet, extracted from CatchMapScreen so the
/// Trip Details map (UX-1B) presents identical catch information and the
/// same navigation into CatchDetailsScreen.
library;

import 'package:flutter/material.dart';

import '../models/catch.dart';
import '../screens/catch_details_screen.dart';
import 'resolved_image.dart';

/// Opens the standard catch-summary bottom sheet for [catchItem].
///
/// [sequenceLabel] (e.g. 'Catch 3 of 7') is shown beside the title when a
/// chronological position is meaningful — used by the trip map's numbered
/// markers; the all-catches map leaves it null.
void showCatchSummarySheet(
  BuildContext context,
  Catch catchItem, {
  String? buddyName,
  String? tripName,
  String? primaryMediaPath,
  String? sequenceLabel,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            catchItem.fishType?.isEmpty ?? true
                                ? 'Unidentified'
                                : catchItem.fishType!,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (sequenceLabel != null)
                            Text(
                              sequenceLabel,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_full),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CatchDetailsScreen(catchItem: catchItem),
                          ),
                        );
                      },
                      tooltip: 'View Full Details',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (primaryMediaPath != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ResolvedImage(
                      imagePath: primaryMediaPath,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailRow(context, Icons.straighten,
                        '${catchItem.lengthCm} cm', 'Length'),
                    const SizedBox(height: 12),
                    _detailRow(
                      context,
                      Icons.calendar_today,
                      _formatDate(catchItem.dateCaught ?? catchItem.createdAt),
                      'Date',
                    ),
                    if (buddyName != null) ...[
                      const SizedBox(height: 12),
                      _detailRow(context, Icons.person, buddyName, 'Caught by'),
                    ],
                    if (tripName != null) ...[
                      const SizedBox(height: 12),
                      _detailRow(
                          context, Icons.directions_boat, tripName, 'Trip'),
                    ],
                    if (catchItem.location != null &&
                        catchItem.location!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _detailRow(
                          context, Icons.place, catchItem.location!, 'Location'),
                    ],
                    if (catchItem.latitude != null &&
                        catchItem.longitude != null) ...[
                      const SizedBox(height: 12),
                      _detailRow(
                        context,
                        Icons.my_location,
                        '${catchItem.latitude!.toStringAsFixed(6)}, ${catchItem.longitude!.toStringAsFixed(6)}',
                        'Coordinates',
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CatchDetailsScreen(catchItem: catchItem),
                            ),
                          );
                        },
                        icon: const Icon(Icons.open_in_full),
                        label: const Text('View Full Details'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _detailRow(
    BuildContext context, IconData icon, String value, String label) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.bodyLarge),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600])),
          ],
        ),
      ),
    ],
  );
}

String _formatDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}
