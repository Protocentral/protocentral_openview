// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// tinyGSR Breakout (USB) — pktType 2 — ~10 Hz, 24-bit GSR samples.
///
/// tinyGSR is a Galvanic Skin Response (GSR) / Electrodermal Activity (EDA)
/// sensor that measures changes in skin electrical conductance, an indicator
/// of emotional arousal and stress.  The onboard analog front-end drives a
/// constant voltage across the skin and digitises the resulting current with
/// a 24-bit ADC.  Values are sign-extended to 32 bits for alignment.
///
/// A second slot is reserved for a raw resistance estimate in integer ohms;
/// it is zero if the firmware does not populate it.
///
/// Payload layout (8 bytes):
///   [0-3]   gsr      int32 LE  (raw 24-bit ADC count, sign-extended)
///   [4-5]   resOhms  int16 LE  (skin resistance in Ω, 0 if unused)
///   [6-7]   0x0000   reserved

DecodedPacket decodeTinyGsrPkt2(Uint8List p) {
  final gsr     = Codec.readInt32LE(p, 0).toDouble();
  final resOhms = Codec.readInt16LE(p, 4);

  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'gsr': [gsr],
    },
    events: {
      'resistance': resOhms,
    },
  );
}
