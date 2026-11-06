// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:OpenView/boards/board_descriptor.dart';
import 'package:OpenView/boards/board_registry.dart';
import 'package:OpenView/boards/channel_spec.dart';
import 'package:OpenView/boards/decoders/easyecg_decoders.dart';
import 'package:OpenView/boards/decoders/easyemg_decoders.dart';
import 'package:OpenView/protocol/decoded_packet.dart';
import 'package:OpenView/protocol/packet_framer_v3.dart';
import 'package:OpenView/protocol/packet_router.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _payload(int a, int b, int c, int d) {
  final p = Uint8List(8);
  ByteData.sublistView(p)
    ..setInt16(0, a, Endian.little)
    ..setInt16(2, b, Endian.little)
    ..setInt16(4, c, Endian.little)
    ..setInt16(6, d, Endian.little);
  return p;
}

// The frame both Arduino sketches write:
// 0x0A 0xFA <len> 0x00 <type> <payload...> 0x00 0x0B
Uint8List _sketchFrame(Uint8List payload) => Uint8List.fromList([
      0x0A, 0xFA, payload.length, 0x00, 0x02,
      ...payload,
      0x00, 0x0B,
    ]);

/// Pushes [bytes] through the real framer and router for [board].
List<DecodedPacket> _decodeStream(BoardDescriptor board, Uint8List bytes) {
  final decoded = <DecodedPacket>[];
  final router = PacketRouter(descriptor: board, onDecodedPacket: decoded.add);
  PacketFramer(
    knownTypes: board.packets.map((p) => p.pktType).toSet(),
    onPacket: router.route,
  ).processChunk(bytes);
  return decoded;
}

void main() {
  group('easyECG', () {
    test('decodes filtered and unfiltered traces, HR and status', () {
      final d = decodeEasyEcgPkt2(_payload(-1500, 1499, 72, 2));

      expect(d.pktType, 2);
      expect(d.channelSamples['ecg'], [-1500.0]);
      expect(d.channelSamples['ecg_unfiltered'], [1499.0]);
      expect(d.events, {'heartRate': 72, 'signalStatus': 2});
    });

    test('a frame from the sketch reaches both channels', () {
      final board = BoardRegistry.byId('easyecg')!;
      final decoded = _decodeStream(
        board,
        _sketchFrame(_payload(-300, 250, 60, 0)),
      );

      expect(decoded, hasLength(1));
      expect(decoded.single.channelSamples['ecg'], [-300.0]);
      expect(decoded.single.events['signalStatus'], 0);
    });
  });

  group('easyEMG', () {
    test('one count is 2.418 µV at the electrodes', () {
      // +/-0.256 V over 2048 counts, through the x51.7 front end.
      expect(easyEmgMicrovoltsPerCount, closeTo(2.4178, 1e-4));
    });

    test('decodes sEMG and envelope to µV, passes %MVC, ignores the reserved slot',
        () {
      final d = decodeEasyEmgPkt2(_payload(-2048, 2048, 85, 0));

      expect(d.pktType, 2);
      expect(d.channelSamples['emg']!.single,
          closeTo(-2048 * easyEmgMicrovoltsPerCount, 1e-9));
      expect(d.channelSamples['emg_envelope']!.single,
          closeTo(2048 * easyEmgMicrovoltsPerCount, 1e-9));
      expect(d.events, {'percentMvc': 85, 'mvcStep': 0});
    });

    test('reads the MVC step from byte 6', () {
      final p = _payload(0, 0, 0, 0);
      p[6] = 2; // contract now
      expect(decodeEasyEmgPkt2(p).events['mvcStep'], 2);
    });

    test('Record MVC sends the sketch its m command', () {
      final board = BoardRegistry.byId('easyemg')!;
      final mvc = board.metrics.firstWhere((m) => m.eventKey == 'mvcStep');

      expect(mvc.action?.bytes, [0x6D]);
      expect(mvc.states.keys, containsAll([0, 1, 2, 3, 4]));
    });

    test('a frame from the sketch reaches both channels', () {
      final board = BoardRegistry.byId('easyemg')!;
      final decoded = _decodeStream(
        board,
        _sketchFrame(_payload(-120, 40, 0, 0)),
      );

      expect(decoded, hasLength(1));
      expect(decoded.single.channelSamples['emg']!.single,
          closeTo(-120 * easyEmgMicrovoltsPerCount, 1e-9));
      expect(decoded.single.channelSamples['emg_envelope']!.single,
          closeTo(40 * easyEmgMicrovoltsPerCount, 1e-9));
    });

    test('channels are in µV on a fixed range that holds a contraction', () {
      final board = BoardRegistry.byId('easyemg')!;
      final emg = board.channels.firstWhere((c) => c.id == 'emg');
      final env = board.channels.firstWhere((c) => c.id == 'emg_envelope');

      for (final c in board.channels) {
        expect(c.unit, SignalUnit.uv, reason: c.id);
        expect(c.fixedRange, isTrue, reason: c.id);
      }
      // A bench recording of forearm flexes peaked at 892 counts (2.16 mV)
      // and its envelope at 257 counts (621 µV).
      expect(emg.displayMax, greaterThan(892 * easyEmgMicrovoltsPerCount));
      expect(emg.displayMin, lessThan(-892 * easyEmgMicrovoltsPerCount));
      expect(env.displayMin, 0);
      expect(env.displayMax, greaterThan(257 * easyEmgMicrovoltsPerCount));
    });
  });

  group('descriptors match the Arduino sketches', () {
    for (final (id, baud, hz) in [
      ('easyecg', 57600, 125),
      ('easyemg', 115200, 500),
    ]) {
      test('$id: USB only, $baud baud, $hz Hz, 8-byte pktType 2', () {
        final board = BoardRegistry.byId(id)!;

        expect(board.transports.usb, isTrue);
        expect(board.transports.ble, isFalse);
        expect(board.transports.wifi, isFalse);
        expect(board.usbProfile!.baudRate, baud);
        expect(board.packet(2)!.expectedPayloadLength, 8);
        expect(board.channels, hasLength(2));
        for (final c in board.channels) {
          expect(c.sampleRateHz, hz);
        }
      });

      test('$id: every decoded channel is declared', () {
        final board = BoardRegistry.byId(id)!;
        final decoded = board.packet(2)!.decode(_payload(1, 2, 3, 0));

        expect(
          decoded.channelSamples.keys.toSet(),
          board.channels.map((c) => c.id).toSet(),
        );
      });
    }

    test('EMG channels use the EMG kind', () {
      final board = BoardRegistry.byId('easyemg')!;
      expect(board.channels.map((c) => c.kind),
          everyElement(ChannelKind.emg));
    });
  });
}
