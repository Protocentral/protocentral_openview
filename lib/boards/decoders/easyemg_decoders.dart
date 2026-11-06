// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// Microvolts at the electrodes per ADC count: the TLA2024's +/-0.256 V range
/// over 2048 counts, divided by the front end's x51.7 gain. Matches
/// `countsToMicrovolts()` in the Arduino library.
const double easyEmgMicrovoltsPerCount = 0.256 / 2048 * 1e6 / 51.7;

/// easyEMG Breakout — pktType 2 — 500 Hz, decoded to µV at the electrodes.
///
/// Streamed by the `06.OpenView` example in protocentral_easyemg_arduino. The
/// firmware samples at 1000 SPS and averages 2 samples into each packet, so
/// the sEMG trace is band-limited to 250 Hz. The envelope is computed from
/// every 1000 SPS sample and keeps the full bandwidth. Both arrive already
/// filtered: a 20 Hz high-pass and, by default, a notch on every mains
/// harmonic up to 450 Hz.
///
/// Payload layout (8 bytes):
///   [0-1]  sEMG          int16 LE (counts, +/-2048)
///   [2-3]  RMS envelope  int16 LE (counts, 0..2048)
///   [4-5]  %MVC          int16 LE (0 until an MVC has been recorded)
///   [6-7]  Reserved      always 0
///
/// sEMG and the envelope are scaled by [easyEmgMicrovoltsPerCount], about
/// 2.42 µV per count; %MVC is passed through.
DecodedPacket decodeEasyEmgPkt2(Uint8List p) {
  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'emg': [Codec.readInt16LE(p, 0) * easyEmgMicrovoltsPerCount],
      'emg_envelope': [Codec.readInt16LE(p, 2) * easyEmgMicrovoltsPerCount],
    },
    events: {
      'percentMvc': Codec.readInt16LE(p, 4),
    },
  );
}
