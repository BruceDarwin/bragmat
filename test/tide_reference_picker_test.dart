import 'package:bragmat/data/tide_reference_catalogue.dart';
import 'package:bragmat/models/tide_reference.dart';
import 'package:bragmat/services/tide_reference_service.dart';
import 'package:bragmat/widgets/tide_reference_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal host that opens the picker from a button and records the
/// result so tests can inspect what (if anything) was returned.
class _Harness extends StatefulWidget {
  final TideReference? selected;
  final bool allowNone;
  const _Harness({this.selected, this.allowNone = false});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  TideReferencePickerResult? result;
  bool completed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final r = await showTideReferencePicker(
              context,
              selected: widget.selected,
              allowNone: widget.allowNone,
            );
            setState(() {
              result = r;
              completed = true;
            });
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

extension on WidgetTester {
  Future<_HarnessState> openPicker({
    TideReference? selected,
    bool allowNone = false,
  }) async {
    await pumpWidget(MaterialApp(
      home: _Harness(selected: selected, allowNone: allowNone),
    ));
    await tap(find.text('open'));
    await pumpAndSettle();
    return state<_HarnessState>(find.byType(_Harness));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TideReferencePickerSheet', () {
    testWidgets('pins Automatic and lists every published reference '
        'grouped under region headers', (tester) async {
      await tester.openPicker();

      expect(find.byKey(const Key('tide_ref_automatic')), findsOneWidget);
      expect(find.text('Automatic (catch location)'), findsOneWidget);

      // Sweep the list collecting built tiles and headers —
      // scrollUntilVisible would overshoot past each target and never
      // scroll back, and lazy building means not everything exists at once.
      final scrollable = find.byType(Scrollable).last;
      final seen = <String>{};
      final seenRegions = <String>{};
      for (var i = 0; i < 40 && seen.length < kTideReferenceCatalogue.length; i++) {
        for (final ref in kTideReferenceCatalogue) {
          if (find.byKey(Key('tide_ref_${ref.id}')).evaluate().isNotEmpty) {
            seen.add(ref.id);
          }
        }
        for (final label in tideRegionLabels.values) {
          if (find.text(label).evaluate().isNotEmpty) {
            seenRegions.add(label);
          }
        }
        await tester.drag(scrollable, const Offset(0, -120));
        await tester.pump();
      }
      expect(seen, kTideReferenceCatalogue.map((r) => r.id).toSet());

      // Region headers are emitted by grouping.
      expect(seenRegions, contains('Darwin & surrounds'));
      expect(seenRegions, contains('Arnhem Land'));
      expect(seenRegions, contains('Joseph Bonaparte Gulf'));

      // Non-catalogue names never appear (all 2026-10 candidates
      // have been verified and published).
      expect(find.text('Wyndham'), findsNothing);
      expect(find.text('Karumba'), findsNothing);
    });

    testWidgets('tapping a reference returns it and closes', (tester) async {
      final h = await tester.openPicker();

      await tester.scrollUntilVisible(
        find.byKey(const Key('tide_ref_darwin')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('tide_ref_darwin')));
      await tester.pumpAndSettle();

      expect(h.completed, isTrue);
      expect(h.result?.reference?.id, 'darwin');
    });

    testWidgets('tapping Automatic returns the automatic sentinel',
        (tester) async {
      final h = await tester.openPicker(
        selected: TideReferenceService.getReferenceById('darwin'),
      );
      await tester.tap(find.byKey(const Key('tide_ref_automatic')));
      await tester.pumpAndSettle();

      expect(h.result?.reference, isNotNull);
      expect(TideReferenceService.isAutomatic(h.result!.reference!), isTrue);
    });

    testWidgets('dismissing the sheet changes nothing', (tester) async {
      final h = await tester.openPicker();

      // Tap the barrier above the sheet.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(h.completed, isTrue);
      expect(h.result, isNull);
    });

    testWidgets('close button dismisses without a selection', (tester) async {
      final h = await tester.openPicker();
      await tester.tap(find.byKey(const Key('tide_ref_close')));
      await tester.pumpAndSettle();

      expect(h.completed, isTrue);
      expect(h.result, isNull);
    });

    testWidgets('search filters by display name and alt names',
        (tester) async {
      await tester.openPicker();
      final search = find.byKey(const Key('tide_ref_search'));

      await tester.enterText(search, 'gove');
      await tester.pump();
      expect(find.text('Melville Bay'), findsOneWidget);
      expect(find.text('Darwin'), findsNothing);

      await tester.enterText(search, 'wadeye');
      await tester.pump();
      expect(find.text('Port Keats'), findsOneWidget);
      expect(find.text('Melville Bay'), findsNothing);

      await tester.enterText(search, 'groote');
      await tester.pump();
      expect(find.text('Milner Bay'), findsOneWidget);
      expect(find.text('Port Keats'), findsNothing);

      await tester.enterText(search, 'galiwinku');
      await tester.pump();
      expect(find.text('Elcho Island'), findsOneWidget);

      // Automatic stays pinned regardless of the query.
      expect(find.byKey(const Key('tide_ref_automatic')), findsOneWidget);
    });

    testWidgets('shows a checkmark on the currently selected reference',
        (tester) async {
      await tester.openPicker(
        selected: TideReferenceService.getReferenceById('darwin'),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('tide_ref_darwin')),
        200,
        scrollable: find.byType(Scrollable).last,
      );

      final tile = tester.widget<ListTile>(
        find.byKey(const Key('tide_ref_darwin')),
      );
      expect(tile.trailing, isA<Icon>());
      expect((tile.trailing as Icon).icon, Icons.check);

      // Unselected entries have no checkmark.
      await tester.scrollUntilVisible(
        find.byKey(const Key('tide_ref_snake_bay')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      final other = tester.widget<ListTile>(
        find.byKey(const Key('tide_ref_snake_bay')),
      );
      expect(other.trailing, isNull);
    });

    testWidgets('a recorded reference missing from the catalogue stays '
        'visible and selectable', (tester) async {
      const historical = TideReference(
        id: 'recorded_old_jetty',
        displayName: 'Old Jetty',
        latitude: -12.1,
        longitude: 131.0,
      );
      await tester.openPicker(selected: historical);

      expect(find.text('Recorded reference'), findsOneWidget);
      expect(find.byKey(const Key('tide_ref_recorded_old_jetty')),
          findsOneWidget);

      final tile = tester.widget<ListTile>(
        find.byKey(const Key('tide_ref_recorded_old_jetty')),
      );
      expect((tile.trailing as Icon).icon, Icons.check);

      // Tapping it returns the historical reference unchanged.
      await tester.tap(find.byKey(const Key('tide_ref_recorded_old_jetty')));
      await tester.pumpAndSettle();
      final h = tester.state<_HarnessState>(find.byType(_Harness));
      expect(h.result?.reference?.id, 'recorded_old_jetty');
    });

    testWidgets('allowNone offers "Not recorded" returning a null '
        'reference', (tester) async {
      final h = await tester.openPicker(
        selected: TideReferenceService.getReferenceById('darwin'),
        allowNone: true,
      );
      await tester.tap(find.byKey(const Key('tide_ref_not_recorded')));
      await tester.pumpAndSettle();

      expect(h.completed, isTrue);
      expect(h.result, isNotNull);
      expect(h.result!.reference, isNull);
    });

    testWidgets('"Not recorded" is hidden when allowNone is false',
        (tester) async {
      await tester.openPicker();
      expect(
          find.byKey(const Key('tide_ref_not_recorded')), findsNothing);
    });

    testWidgets('renders on a small screen with the keyboard open',
        (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.openPicker();

      // Simulate the keyboard covering the lower half.
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('tide_ref_automatic')), findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 0);
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
    });
  });

  group('picker → Settings persistence', () {
    testWidgets('a picked reference persists as the new default',
        (tester) async {
      final h = await tester.openPicker();

      await tester.scrollUntilVisible(
        find.byKey(const Key('tide_ref_milner_bay')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('tide_ref_milner_bay')));
      await tester.pumpAndSettle();

      final picked = h.result!.reference!;
      await TideReferenceService.setFixedReference(picked.id);

      final current = await TideReferenceService.getCurrentReference();
      expect(current.id, 'milner_bay');
      expect(await TideReferenceService.getMode(), 'fixed');
    });

    testWidgets('picking Automatic persists automatic mode', (tester) async {
      SharedPreferences.setMockInitialValues({
        'tide_reference_mode': 'fixed',
        'tide_reference_id': 'darwin',
      });
      final h = await tester.openPicker(
        selected: TideReferenceService.getReferenceById('darwin'),
      );

      await tester.tap(find.byKey(const Key('tide_ref_automatic')));
      await tester.pumpAndSettle();

      await TideReferenceService.setAutomaticMode();
      expect(await TideReferenceService.getMode(), 'automatic');
      expect(h.result, isNotNull);
    });
  });
}
