// Release-build gating for development/maintenance controls in Settings.
//
// DebugTools.debugEnabledOverride simulates a release build: with the gate
// closed the dev-only controls must not render; with it open they must.
// No network access — secure storage is mocked and Supabase is
// unconfigured in the test environment (Account section hidden).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/screens/settings_screen.dart';
import 'package:bragmat/services/debug_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final secureChannel =
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String?> secureStore = {};

  late Directory testDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('bragmat_gate_test_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<dynamic, dynamic>() ?? {};
      switch (call.method) {
        case 'read':
          return secureStore[args['key']];
        case 'write':
          secureStore[args['key'] as String] = args['value'] as String?;
          return null;
        case 'delete':
          secureStore.remove(args['key']);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    DebugTools.debugEnabledOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    // Windows can hold the ffi handle briefly after close — don't fail the
    // test on a temp-dir lock.
    try {
      if (await testDir.exists()) await testDir.delete(recursive: true);
    } on FileSystemException {
      // leave for OS cleanup
    }
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );
    await tester.pumpAndSettle();
  }

  const devOnlyLabels = [
    'Test API',
    'WorldTides API Key',
    'Recalculate Environmental Data',
    'Review Legacy Estimated Tide Data',
    'Clear All Data',
    'Import CSV (Coming Soon)',
  ];

  group('release build (DebugTools disabled)', () {
    testWidgets('development controls are absent', (tester) async {
      DebugTools.debugEnabledOverride = false;
      await pumpSettings(tester);
      for (final label in devOnlyLabels) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('user features and attribution remain', (tester) async {
      DebugTools.debugEnabledOverride = false;
      await pumpSettings(tester);
      expect(find.text('Backup Data'), findsWidgets);
      expect(find.text('Export CSV'), findsWidgets);
      expect(find.text('Achievements'), findsWidgets);
      expect(find.textContaining('Tidal data retrieved'), findsWidgets);
    });
  });

  group('debug build (DebugTools enabled)', () {
    testWidgets('development controls are present', (tester) async {
      DebugTools.debugEnabledOverride = true;
      await pumpSettings(tester);
      for (final label in devOnlyLabels.take(5)) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      // Restore Testing section is debug-only too
      expect(find.text('Restore Testing (Debug)'), findsOneWidget);
    });
  });
}
