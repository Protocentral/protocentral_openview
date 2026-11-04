// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// easyEMG Breakout — pktType 2 — 500 Hz, signed 12-bit ADC counts.
///
/// Streamed by the `06.OpenView` example in protocentral_easyemg_arduino. The
/// firmware samples at 1000 SPS and averages 2 samples into each packet, so
/// the sEMG trace is band-limited to 250 Hz. The envelope is computed from
/// every 1000 SPS sample and keeps the full bandwidth.
///
/// Payload layout (8 bytes):
///   [0-1]  sEMG          int16 LE (counts, +/-2048)
///   [2-3]  RMS envelope  int16 LE (counts, 0..2048)
///   [4-5]  %MVC          int16 LE (0 until an MVC has been recorded)
///   [6-7]  Reserved      always 0
DecodedPacket decodeEasyEmgPkt2(Uint8List p) {
  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'emg': [Codec.readInt16LE(p, 0).toDouble()],
      'emg_envelope': [Codec.readInt16LE(p, 2).toDouble()],
    },
    events: {
      'percentMvc': Codec.readInt16LE(p, 4),
    },
  );
}
