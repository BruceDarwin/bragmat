import 'package:bragmat/services/debug_tools.dart';
import 'package:bragmat/services/zip_backup_service.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_test/flutter_test.dart';

/// Verifies the release-build restriction on development-only tooling.
///
/// [DebugTools.isEnabled] is compile-time false in release builds; the
/// [DebugTools.debugEnabledOverride] seam simulates that here. The
/// fault-injection stage hook must not be able to execute when the gate
/// is closed, even if a hook was assigned directly (UI bypass).
void main() {
  tearDown(() {
    DebugTools.debugEnabledOverride = null;
    ZipBackupService.debugStageHook = null;
  });

  group('DebugTools gate', () {
    test('isEnabled tracks the build mode when no override is set', () {
      expect(DebugTools.isEnabled, kDebugMode);
    });

    test('override=false simulates a release build', () {
      DebugTools.debugEnabledOverride = false;
      expect(DebugTools.isEnabled, isFalse);
    });

    test('override=true enables tools for development testing', () {
      DebugTools.debugEnabledOverride = true;
      expect(DebugTools.isEnabled, isTrue);
    });
  });

  group('restore fault-injection hook release guard', () {
    test('stage hook cannot fire when debug tools are unavailable',
        () async {
      DebugTools.debugEnabledOverride = false;
      var fired = false;
      ZipBackupService.debugStageHook = (_) async {
        fired = true;
      };

      await ZipBackupService.fireDebugStageHook('swapped');

      expect(fired, isFalse);
    });

    test('stage hook fires when debug tools are enabled', () async {
      DebugTools.debugEnabledOverride = true;
      String? firedAt;
      ZipBackupService.debugStageHook = (stage) async {
        firedAt = stage;
      };

      await ZipBackupService.fireDebugStageHook('swapped');

      expect(firedAt, 'swapped');
    });
  });
}
