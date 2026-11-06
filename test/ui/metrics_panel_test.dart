// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:OpenView/boards/board_registry.dart';
import 'package:OpenView/boards/packet_spec.dart';
import 'package:OpenView/controllers/channel_controller.dart';
import 'package:OpenView/theme/signal_colors.dart';
import 'package:OpenView/ui/widgets/metrics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _chartKey = Key('chart');
const _refresh = Duration(milliseconds: 300);

Future<void> _pump(
  WidgetTester tester, {
  required String boardId,
  required ValueGetter<Map<String, num>> read,
  double width = 1200,
  ValueChanged<CommandSpec>? onCommand,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: const [SignalColors.light]),
    home: Scaffold(
      body: MetricsLayout(
        metrics: BoardRegistry.byId(boardId)!.metrics,
        read: read,
        onCommand: onCommand,
        child: const SizedBox.expand(key: _chartKey),
      ),
    ),
  ));
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  group('easyECG readouts', () {
    testWidgets('shows heart rate in bpm with the signal status',
        (tester) async {
      await _pump(tester,
          boardId: 'easyecg',
          read: () => {'heartRate': 72, 'signalStatus': 0});

      expect(find.text('Heart rate'), findsOneWidget);
      expect(find.text('72'), findsOneWidget);
      expect(find.text('bpm'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('shows a placeholder until a rate is established',
        (tester) async {
      await _pump(tester,
          boardId: 'easyecg', read: () => {'heartRate': 0, 'signalStatus': 0});

      expect(find.text('--'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('names each signal problem and dims the rate', (tester) async {
      final values = <String, num>{'heartRate': 72, 'signalStatus': 0};
      await _pump(tester, boardId: 'easyecg', read: () => values);
      final normal = _colorOf(tester, '72')!;

      values['signalStatus'] = 1;
      await tester.pump(_refresh);
      expect(find.text('Lead-off or mains pickup'), findsOneWidget);
      expect(_colorOf(tester, '72')!.a, lessThan(normal.a));

      values['signalStatus'] = 2;
      await tester.pump(_refresh);
      expect(find.text('Amplifier saturated'), findsOneWidget);
    });

    testWidgets('clears the reading when the stream goes stale',
        (tester) async {
      Map<String, num> values = {'heartRate': 72, 'signalStatus': 0};
      await _pump(tester, boardId: 'easyecg', read: () => values);
      expect(find.text('72'), findsOneWidget);

      values = const {};
      await tester.pump(_refresh);
      expect(find.text('72'), findsNothing);
      expect(find.text('--'), findsOneWidget);
      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('picks up new values on the refresh timer', (tester) async {
      final values = <String, num>{'heartRate': 72, 'signalStatus': 0};
      await _pump(tester, boardId: 'easyecg', read: () => values);

      values['heartRate'] = 80;
      await tester.pump(_refresh);
      expect(find.text('80'), findsOneWidget);
    });

    testWidgets('reports an undeclared status code', (tester) async {
      await _pump(tester,
          boardId: 'easyecg',
          read: () => {'heartRate': 72, 'signalStatus': 9});

      expect(find.text('Unknown (9)'), findsOneWidget);
    });
  });

  testWidgets('easyEMG shows a real 0% rather than a placeholder',
      (tester) async {
    await _pump(tester, boardId: 'easyemg', read: () => {'percentMvc': 0});

    expect(find.text('Effort (MVC)'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);
  });

  group('easyEMG MVC', () {
    testWidgets('flags effort above 100% in the warning colour',
        (tester) async {
      await _pump(tester,
          boardId: 'easyemg', read: () => {'percentMvc': 340, 'mvcStep': 4});

      expect(find.text('340'), findsOneWidget);
      expect(find.text('Above your MVC: record it again'), findsOneWidget);
      expect(_colorOf(tester, '340'), SignalColors.light.qualityWarn);
    });

    testWidgets('100% is not flagged', (tester) async {
      await _pump(tester,
          boardId: 'easyemg', read: () => {'percentMvc': 100, 'mvcStep': 4});

      expect(find.text('Above your MVC: record it again'), findsNothing);
      expect(_colorOf(tester, '100'), SignalColors.light.eeg);
    });

    testWidgets('shows the step and sends Record MVC', (tester) async {
      final sent = <CommandSpec>[];
      await _pump(tester,
          boardId: 'easyemg',
          read: () => {'percentMvc': 0, 'mvcStep': 2},
          onCommand: sent.add);

      expect(find.text('Contract hard now'), findsOneWidget);
      await tester.tap(find.text('Record MVC'));
      expect(sent.single.bytes, [0x6D]);
    });

    testWidgets('hides Record MVC when commands can\'t be sent',
        (tester) async {
      await _pump(tester,
          boardId: 'easyemg', read: () => {'percentMvc': 0, 'mvcStep': 0});

      expect(find.text('Not recorded'), findsOneWidget);
      expect(find.text('Record MVC'), findsNothing);
    });
  });

  group('layout', () {
    testWidgets('sits beside the chart on a wide window', (tester) async {
      await _pump(tester,
          boardId: 'easyecg',
          read: () => {'heartRate': 72, 'signalStatus': 0});

      expect(
        tester.getTopLeft(find.text('Heart rate')).dx,
        greaterThan(tester.getTopRight(find.byKey(_chartKey)).dx),
      );
    });

    for (final width in [700.0, 360.0]) {
      testWidgets('sits above the chart at ${width}px with no overflow',
          (tester) async {
        await _pump(tester,
            boardId: 'easyecg',
            width: width,
            read: () => {'heartRate': 188, 'signalStatus': 1});

        expect(tester.takeException(), isNull);
        expect(
          tester.getBottomLeft(find.text('Heart rate')).dy,
          lessThan(tester.getTopLeft(find.byKey(_chartKey)).dy),
        );
      });
    }

    testWidgets('a board with no metrics gets the chart alone',
        (tester) async {
      await _pump(tester, boardId: 'max30001', read: () => {'heartRate': 72});

      expect(find.text('72'), findsNothing);
      expect(tester.getSize(find.byKey(_chartKey)), const Size(1200, 700));
    });
  });

  group('shared vitals', () {
    testWidgets('ADS1292R labels heart rate and respiration rate',
        (tester) async {
      await _pump(tester,
          boardId: 'ads1292r', read: () => {'heartRate': 72, 'respRate': 16});

      expect(find.text('72'), findsOneWidget);
      expect(find.text('bpm'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);
      expect(find.text('br/min'), findsOneWidget);
    });

    testWidgets('AFE4490 shows placeholders while its readings are invalid',
        (tester) async {
      await _pump(tester,
          boardId: 'afe4490', read: () => {'heartRate': 0, 'spo2': 0});

      expect(find.text('--'), findsNWidgets(2));
    });

    testWidgets('HealthyPi formats temperature and fits a phone width',
        (tester) async {
      await _pump(tester,
          boardId: 'healthypi',
          width: 312,
          read: () => {
                'heartRate': 188,
                'spo2': 98,
                'respRate': 16,
                'temperature': 36.5,
              });

      expect(tester.takeException(), isNull);
      expect(find.text('36.5'), findsOneWidget);
      expect(find.text('°C'), findsOneWidget);
      // Two tiles per row, so "Temperature" is not squeezed.
      expect(
        tester.getTopLeft(find.text('Respiration')).dy,
        greaterThan(tester.getBottomLeft(find.text('Heart rate')).dy),
      );
    });
  });

  test('every readout comes from an event the decoder emits', () {
    for (final board in BoardRegistry.all.where((b) => b.metrics.isNotEmpty)) {
      expect(board.channels, isNotEmpty,
          reason: 'readouts are drawn beside the chart');

      final emitted = {
        for (final p in board.packets)
          if (p.expectedPayloadLength != null)
            ...p.decode(Uint8List(p.expectedPayloadLength!)).events.keys,
      };
      for (final m in board.metrics) {
        expect(emitted, contains(m.eventKey),
            reason: '${board.id} declares ${m.eventKey}');
      }
    }
  });

  test('boards whose firmware does not send vitals declare no readouts', () {
    // MAX30001: bytes 8-11 carry a BioZ skip flag and zeros. ADS1293 and Pulse
    // Express: the sketches send no HR. MAX30003: sketch not yet checked.
    for (final id in ['max30001', 'ads1293', 'pulse_express', 'max30003']) {
      expect(BoardRegistry.byId(id)!.metrics, isEmpty, reason: id);
    }
  });

  test('easyECG hides only the unfiltered trace until asked', () {
    final board = BoardRegistry.byId('easyecg')!;
    final chart = ChannelController(channels: board.channels, buffers: const {});
    addTearDown(chart.dispose);

    expect(chart.strip('ecg').visible, isTrue);
    expect(chart.strip('ecg_unfiltered').visible, isFalse);

    chart.setVisible('ecg_unfiltered', true);
    expect(chart.strip('ecg_unfiltered').visible, isTrue);
  });

  test('easyEMG keeps both traces on screen', () {
    final board = BoardRegistry.byId('easyemg')!;
    expect(board.channels.where((c) => c.optional), isEmpty);
  });
}
