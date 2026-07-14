// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// MAX86150 Breakout (USB) — pktType 2 — up to 200 Hz, 18-bit samples.
///
/// The MAX86150 integrates a single-lead ECG front-end (18-bit) with a
/// dual-LED PPG front-end (18-bit Red + IR) in one package.
/// On-device SpO2 and heart rate are computed and appended.
///
/// Payload layout (16 bytes):
///   [0-1]    ecg     int16 LE  (sign-extended 18-bit ECG ADC value)
///   [2-3]    ppgRed  int16 LE  (Red  LED count, 18-bit ADC)
///   [4-5]   ppgIr   int16 LE  (IR   LED count, 18-bit ADC)

DecodedPacket decodeMax86150Pkt2(Uint8List p) {
  final ecg    = Codec.readInt16LE(p, 0).toDouble();
  final ppgRed = Codec.readInt16LE(p, 2).toDouble();
  final ppgIr  = Codec.readInt16LE(p, 4).toDouble();

  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ecg':    [ecg],
      'ppgRed': [ppgRed],
      'ppgIr':  [ppgIr],
    },
  );
}
