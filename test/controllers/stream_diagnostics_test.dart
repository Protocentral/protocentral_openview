// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:OpenView/controllers/stream_diagnostics.dart';
import 'package:OpenView/ui/widgets/stream_diagnostics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _budget = Duration(microseconds: 16666);
const _ms1 = Duration(milliseconds: 1);

void main() {
  late DateTime now;
  late StreamDiagnostics d;

  void advance(Duration by) => now = now.add(by);

  /// One second of steady 60 fps frames and 100 Hz chunks, with the given costs.
  void healthySecond({
    Duration build = _ms1,
    Duration raster = _ms1,
    Duration uiDelay = Duration.zero,
    bool withChunks = true,
    int frames = 60,
  }) {
    final frameStep = Duration(microseconds: 1000000 ~/ frames);
    for (var i = 0; i < frames; i++) {
      advance(frameStep);
      d.recordFrame(build: build, raster: raster);
      d.recordUiDelay(uiDelay);
      if (withChunks) d.recordChunk(15);
    }
  }

  setUp(() {
    now = DateTime(2026);
    d = StreamDiagnostics(now: () => now);
  });

  StreamFinding finding() => d.snapshot(frameBudget: _budget).finding;

  group('findings', () {
    test('needs some frames before saying anything', () {
      d.recordFrame(build: _ms1, raster: _ms1);

      expect(finding(), StreamFinding.collecting);
    });

    test('healthy timings find nothing', () {
      healthySecond();

      expect(finding(), StreamFinding.noneFound);
    });

    test('slow raster blames drawing', () {
      healthySecond(raster: const Duration(milliseconds: 30));

      expect(finding(), StreamFinding.slowRaster);
    });

    test('slow builds blame the UI thread', () {
      healthySecond(build: const Duration(milliseconds: 30));

      expect(finding(), StreamFinding.uiOverloaded);
    });

    test('a late UI thread is overloaded even when frames look fast', () {
      healthySecond(uiDelay: const Duration(milliseconds: 40));

      expect(finding(), StreamFinding.uiOverloaded);
    });

    test('fast but few frames point past the app', () {
      healthySecond(frames: 20);

      expect(finding(), StreamFinding.lowFrameRate);
    });

    test('a 30 Hz cap is not mistaken for a low frame rate', () {
      healthySecond(frames: 30);

      expect(
        d.snapshot(frameBudget: const Duration(microseconds: 33333)).finding,
        StreamFinding.noneFound,
      );
    });

    test('long gaps on a healthy app point at the data', () {
      for (var s = 0; s < 3; s++) {
        healthySecond(withChunks: false);
        d.recordChunk(150);
      }

      expect(finding(), StreamFinding.dataGaps);
    });

    test('data gaps on an overloaded UI blame the UI, not the data', () {
      for (var s = 0; s < 3; s++) {
        healthySecond(
          withChunks: false,
          uiDelay: const Duration(milliseconds: 40),
        );
        d.recordChunk(150);
      }

      expect(finding(), StreamFinding.uiOverloaded);
    });
  });

  group('window', () {
    test('old readings age out, so a recovery shows', () {
      healthySecond(raster: const Duration(milliseconds: 30));
      expect(finding(), StreamFinding.slowRaster);

      for (var s = 0; s < 7; s++) {
        healthySecond();
      }

      expect(finding(), StreamFinding.noneFound);
    });

    test('rates use the time measured so far, then the full window', () {
      healthySecond();
      final early = d.snapshot(frameBudget: _budget);
      expect(early.framesPerSecond, closeTo(60, 1));
      expect(early.bytesPerSecond, closeTo(900, 20));

      for (var s = 0; s < 9; s++) {
        healthySecond();
      }
      final later = d.snapshot(frameBudget: _budget);
      expect(later.framesPerSecond, closeTo(60, 1));
      expect(later.bytesPerSecond, closeTo(900, 20));
    });

    test('percentiles come from the actual samples', () {
      final s = TimingSummary.of([for (var i = 1; i <= 100; i++) i * 1000]);

      expect(s.count, 100);
      expect(s.p50.inMilliseconds, inInclusiveRange(50, 51));
      expect(s.p95.inMilliseconds, 95);
      expect(s.max.inMilliseconds, 100);
    });

    test('no samples gives zeros rather than an error', () {
      expect(TimingSummary.of(const []).max, Duration.zero);
    });
  });

  test('the report carries the setup and every measurement', () {
    healthySecond();

    final report = d.snapshot(frameBudget: _budget).report('OpenView 1.2.3');

    expect(report, startsWith('OpenView 1.2.3'));
    for (final part in ['Frames:', 'Build:', 'Raster:', 'UI delay:', 'Data gap:',
        'Data rate:', 'Finding:']) {
      expect(report, contains(part));
    }
  });

  group('StreamDiagnosticsPanel', () {
    void Function(int)? attached;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StreamDiagnosticsPanel(
            frameBudget: _budget,
            attachChunks: (onChunk) => attached = onChunk,
            describeSetup: () => 'test setup',
          ),
        ),
      ));
    }

    testWidgets('attaches to chunks while open and detaches when closed',
        (tester) async {
      await pump(tester);
      expect(attached, isNotNull);

      await tester.pumpWidget(const SizedBox());
      expect(attached, isNull);
    });

    testWidgets('fits a narrow window', (tester) async {
      await pump(tester);
      tester.view.physicalSize = const Size(360, 400);
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('copies the report with the setup', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await pump(tester);

      await tester.tap(find.text('Copy report'));
      await tester.pump();

      expect(copied, startsWith('test setup'));
      expect(copied, contains('Finding:'));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
