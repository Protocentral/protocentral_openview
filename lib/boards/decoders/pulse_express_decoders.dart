// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// Pulse Express (USB) — pktType 2 — ~100 Hz, 16-bit PPG samples.
///
/// The Pulse Express uses a MAX32664 bio-sensor hub paired with a
/// MAX30102 optical sensor.  The MAX32664 runs the SpO2/HR algorithm
/// internally and streams pre-computed vitals alongside the raw PPG
/// waveform over I²C/UART to the host.
///
/// Payload layout (9 bytes):
///   [0-1]   ppgIr   int16 LE  (IR  LED raw count, normalised to 16-bit)
///   [2-3]   ppgRed  int16 LE  (Red LED raw count, normalised to 16-bit)
///   [4-5]   HR      int16 LE  (bpm, from on-chip algorithm) - need to enable in the fw
///   [6-7]   SpO2    int16 LE  (%, from on-chip algorithm) - need to enable in the fw
///   [8]     status  uint8     (0x00 = OK; bit flags for lead-off / low-confidence) - need to enable in the fw

DecodedPacket decodePulseExpressPkt2(Uint8List p) {
  final ppgIr  = Codec.readInt16LE(p, 0).toDouble();
  final ppgRed = Codec.readInt16LE(p, 2).toDouble();
  //final hr     = Codec.readInt16LE(p, 4);
  //final spo2   = Codec.readInt16LE(p, 6);

  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ppgIr':  [ppgIr],
      'ppgRed': [ppgRed],
    },
    /*events: {
      'heartRate': hr,
      'spo2':      spo2,
    },*/
  );
}
