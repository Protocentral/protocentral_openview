// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// Sensything Ox — pktType 2 — AFE4400 pulse oximeter.
///
/// One sample is 8 bytes (4 × int16 LE — see SensythingBLE.cpp:59-67):
///   [0-1]  ir_raw     int16 LE  — AFE4400 IR photodiode
///   [2-3]  red_raw    int16 LE  — AFE4400 Red photodiode
///   [4-5]  spo2       int16 LE  — % O2 saturation
///   [6-7]  heart_rate int16 LE  — bpm
///
/// A BLE notification may carry one sample (8 B) or a batch of N samples
/// (N × 8 B); decode every sample so none are dropped at high stream rates.
///
/// Channel mapping (board descriptor): ppgIr, ppgRed
/// Events: spo2, heartRate (from the most recent sample in the payload)
const int _sampleLen = 8;

DecodedPacket decodeSensythingOxPkt2(Uint8List p) {
  final count = p.length ~/ _sampleLen;
  if (count == 0) return const DecodedPacket(pktType: 2);
  final ir = <double>[];
  final red = <double>[];
  int spo2 = 0;
  int hr = 0;
  for (var i = 0; i < count; i++) {
    final o = i * _sampleLen;
    ir.add(Codec.readInt16LE(p, o).toDouble());
    red.add(Codec.readInt16LE(p, o + 2).toDouble());
    spo2 = Codec.readInt16LE(p, o + 4);
    hr = Codec.readInt16LE(p, o + 6);
  }
  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ppgIr': ir,
      'ppgRed': red,
    },
    events: {
      'spo2': spo2,
      'heartRate': hr,
    },
  );
}
