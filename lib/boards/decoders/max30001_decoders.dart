// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// MAX30001 ECG & BioZ Breakout (USB) — pktType 2 — 128 Hz, 18/19-bit samples.
///
/// The MAX30001 is a single-chip biopotential (ECG) and bio-impedance (BioZ)
/// measurement AFE.  The BioZ channel is typically used for respiration
/// monitoring via thoracic impedance.  Both channels output sign-extended
/// values packed into int32 fields.  R-R interval (inter-beat interval) is
/// computed on-device from the ECG RTOR engine and provided in milliseconds.
///
/// Payload layout (12 bytes):
///   [0-3]    ecg   int32 LE  (sign-extended 18-bit ECG ADC value)
///   [4-7]    bioz  int32 LE  (sign-extended 19-bit BioZ ADC value,
///                              used as respiration waveform)
///   [8-9]    HR    int16 LE  (bpm, from on-chip RTOR engine)
///   [10-11]  RR    int16 LE  (ms, R-R interval from RTOR engine)

DecodedPacket decodeMax30001Pkt2(Uint8List p) {
  final ecg  = Codec.readInt32LE(p, 0).toDouble();
  final bioz = Codec.readInt32LE(p, 4).toDouble();
  final hr   = Codec.readInt16LE(p, 8);
  final rr   = Codec.readInt16LE(p, 10);

  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ecg':  [ecg],
      'bioz': [bioz],
    },
    events: {
      'heartRate': hr,
      'rr':        rr,
    },
  );
}
