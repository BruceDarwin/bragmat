import 'package:flutter/material.dart';

/// Reusable location action buttons row for consistent location selection
/// across the app. Used in Add Catch and Add/Edit Favourite Spot screens.
class LocationActionButtons extends StatelessWidget {
  final VoidCallback? onUseCurrentLocation;
  final VoidCallback onPickOnMap;
  final bool isLoading;
  final bool showCurrentLocation;

  const LocationActionButtons({
    super.key,
    this.onUseCurrentLocation,
    required this.onPickOnMap,
    this.isLoading = false,
    this.showCurrentLocation = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showCurrentLocation) {
      return ElevatedButton.icon(
        onPressed: onPickOnMap,
        icon: const Icon(Icons.map),
        label: const Text('Pick on Map'),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onUseCurrentLocation,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: const Text('Use Current Location'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onPickOnMap,
            icon: const Icon(Icons.map),
            label: const Text('Pick on Map'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),
      ],
    );
  }
}
