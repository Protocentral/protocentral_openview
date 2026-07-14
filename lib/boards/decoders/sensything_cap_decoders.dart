// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// Sensything CAP — 4-channel capacitive front-end.
///
/// Wire format (matches SensythingBLE.cpp:142 — BLE and USB are byte-identical):
///   pktType 2
///   payload: channelCount (4) × int16 little-endian = 8 bytes
///
///   [0-1]  ch1 int16 LE
///   [2-3]  ch2 int16 LE
///   [4-5]  ch3 int16 LE
///   [6-7]  ch4 int16 LE
DecodedPacket decodeSensythingCapPkt2(Uint8List p) {
  if (p.length < 8) return const DecodedPacket(pktType: 2);
  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ch1': [Codec.readInt16LE(p, 0).toDouble()],
      'ch2': [Codec.readInt16LE(p, 2).toDouble()],
      'ch3': [Codec.readInt16LE(p, 4).toDouble()],
      'ch4': [Codec.readInt16LE(p, 6).toDouble()],
    },
  );
}
