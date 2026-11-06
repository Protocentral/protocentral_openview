// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:OpenView/boards/board_registry.dart';
import 'package:OpenView/controllers/channel_controller.dart';
import 'package:OpenView/ui/widgets/ecg_paper.dart';
import 'package:OpenView/ui/widgets/paper_scale_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChannelController _chartFor(String boardId) {
  final c = ChannelController(
    channels: BoardRegistry.byId(boardId)!.channels,
    buffers: const {},
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('EcgPaper scale', () {
    // 1040 px over 5 s, as in a 1280 px window.
    const paper = EcgPaper(pxPerSec: 208, countsPerMv: 535);

    test('boxes are square: 0.2 s across equals 0.5 mV up', () {
      expect(paper.largeBoxPx, closeTo(41.6, 1e-9));
      expect(paper.pxPerMv * 0.5, closeTo(paper.largeBoxPx, 1e-9));
      expect(paper.smallBoxPx * 5, closeTo(paper.largeBoxPx, 1e-9));
    });

    test('gain scales the trace but not the grid', () {
      const doubled = EcgPaper(pxPerSec: 208, countsPerMv: 535, gain: 2);

      expect(doubled.largeBoxPx, paper.largeBoxPx);
      expect(doubled.pxPerMv, closeTo(paper.pxPerMv * 2, 1e-9));
      expect(doubled.largeBoxMv, 0.25);
    });

    test('the visible range is centred on the baseline', () {
      final top = paper.maxValue(100, 660);
      final bottom = paper.minValue(100, 660);

      expect((top + bottom) / 2, closeTo(100, 1e-9));
      // 660 px at 83.2 px/mV is about 7.9 mV.
      expect((top - bottom) / 535, closeTo(660 / 83.2, 1e-9));
    });
  });

  group('baselineOf', () {
    test('sits at the flat level, not pulled up by QRS peaks', () {
      final samples = Float64List(100)..fillRange(0, 100, 50);
      for (var i = 0; i < 100; i += 20) {
        samples[i] = 900;
      }

      expect(EcgPaper.baselineOf(samples), 50);
    });

    test('ignores the NaN slots of a part-filled buffer', () {
      final samples = Float64List.fromList([double.nan, double.nan, 7, 7, 7]);

      expect(EcgPaper.baselineOf(samples), 7);
    });

    test('is 0 with no samples at all', () {
      expect(EcgPaper.baselineOf(Float64List.fromList([double.nan])), 0);
    });
  });

  group('ChannelController', () {
    test('easyECG starts on paper at gain ×1', () {
      final chart = _chartFor('easyecg');

      expect(chart.hasPaperScale, isTrue);
      expect(chart.paperMode, isTrue);
      expect(chart.paperGain, 1);
      expect(chart.strip('ecg').yMode, YMode.paper);
      expect(chart.strip('ecg_unfiltered').yMode, YMode.paper);
    });

    test('switching moves both easyECG traces together', () {
      final chart = _chartFor('easyecg')..paperMode = false;

      expect(chart.strip('ecg').yMode, YMode.auto);
      expect(chart.strip('ecg_unfiltered').yMode, YMode.auto);
      expect(chart.paperMode, isFalse);
    });

    test('boards with no verified mV scale stay on auto', () {
      for (final id in ['ads1292r', 'max30001', 'healthypi']) {
        final chart = _chartFor(id);

        expect(chart.hasPaperScale, isFalse, reason: id);
        expect(chart.paperMode, isFalse, reason: id);
        expect(chart.strip(chart.channels.first.id).yMode, YMode.auto);
      }
    });

    test('fixed-range channels start on their display range, not paper', () {
      final chart = _chartFor('easyemg');

      expect(chart.hasPaperScale, isFalse);
      expect(chart.paperMode, isFalse);
      for (final c in chart.channels) {
        final s = chart.strip(c.id);
        expect(s.yMode, YMode.manual, reason: c.id);
        expect(s.yMin, c.displayMin, reason: c.id);
        expect(s.yMax, c.displayMax, reason: c.id);
      }
    });
  });

  group('PaperScaleControls', () {
    Future<ChannelController> pump(WidgetTester tester) async {
      final chart = _chartFor('easyecg');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: chart,
            builder: (_, __) => PaperScaleControls(chart: chart),
          ),
        ),
      ));
      return chart;
    }

    testWidgets('switches to Auto and hides the gain menu', (tester) async {
      final chart = await pump(tester);
      expect(find.text('Gain ×1'), findsOneWidget);

      await tester.tap(find.text('Auto'));
      await tester.pump();

      expect(chart.paperMode, isFalse);
      expect(find.textContaining('Gain'), findsNothing);
    });

    testWidgets('sets the gain from the menu', (tester) async {
      final chart = await pump(tester);

      await tester.tap(find.text('Gain ×1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('×0.5'));
      await tester.pumpAndSettle();

      expect(chart.paperGain, 0.5);
      expect(find.text('Gain ×0.5'), findsOneWidget);
    });
  });
}
