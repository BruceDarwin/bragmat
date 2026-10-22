import 'package:flutter/foundation.dart';

/// Central switch for development-only tooling: restore fault injection,
/// disposable test-data seeding and diagnostic screens.
///
/// Enabled only in debug builds — in release/profile builds [isEnabled] is
/// false, so gated UI is omitted and service-level debug hooks cannot fire,
/// even if a caller attempts to invoke them directly.
class DebugTools {
  DebugTools._();

  /// Test seam — lets unit tests exercise the release behaviour. Never set
  /// from application code.
  static bool? debugEnabledOverride;

  /// Whether development tools exist in this build at all.
  static bool get isEnabled => debugEnabledOverride ?? kDebugMode;
}
