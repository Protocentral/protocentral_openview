// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// easyECG Breakout — pktType 2 — 125 Hz, signed 12-bit ADC counts.
///
/// Streamed by the `04.OpenView` example in protocentral_easyecg_arduino. The
/// firmware samples at 1000 SPS, applies a mains notch and a 40 Hz low-pass,
/// and decimates to 125 Hz.
///
/// Payload layout (8 bytes):
///   [0-1]  ECG, filtered    int16 LE (counts)
///   [2-3]  ECG, unfiltered  int16 LE (counts; 0 if the sketch disables it)
///   [4-5]  Heart rate       int16 LE (bpm; 0 until established)
///   [6-7]  Signal status    int16 LE (0 = OK, 1 = lead-off or mains pickup,
///                                     2 = amplifier saturated)
DecodedPacket decodeEasyEcgPkt2(Uint8List p) {
  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ecg': [Codec.readInt16LE(p, 0).toDouble()],
      'ecg_unfiltered': [Codec.readInt16LE(p, 2).toDouble()],
    },
    events: {
      'heartRate': Codec.readInt16LE(p, 4),
      'signalStatus': Codec.readInt16LE(p, 6),
    },
  );
}
