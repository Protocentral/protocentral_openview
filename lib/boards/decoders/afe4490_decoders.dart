// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// AFE4490 Breakout/Shield (USB) — pktType 2 — ~100 Hz, 22-bit PPG samples.
///
/// The AFE4490 is a dual-LED pulse-oximetry front-end that simultaneously
/// samples Red and IR LED photodiode channels using a 22-bit ADC.
/// On-device SpO2 and heart rate are computed and transmitted alongside
/// the raw waveform samples.
///
/// Payload layout (12 bytes):
///   [0-3]    ppgRed  int32 LE  (Red LED photodiode count, 22-bit ADC)
///   [4-7]    ppgIr   int32 LE  (IR  LED photodiode count, 22-bit ADC)
///   [8]    HR      int8 LE  (bpm)
///   [9]  SpO2    int8 LE  (% × 1, e.g. 98 → 98 %)
///
DecodedPacket decodeAfe4490Pkt2(Uint8List p) {
  final ppgRed = Codec.readInt32LE(p, 0).toDouble();
  final ppgIr  = Codec.readInt32LE(p, 4).toDouble();
  final hr     = p[8];
  final spo2   = p[9];

  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ppgRed': [ppgRed],
      'ppgIr':  [ppgIr],
    },
    events: {
      'heartRate': hr,
      'spo2':      spo2,
    },
  );
}
