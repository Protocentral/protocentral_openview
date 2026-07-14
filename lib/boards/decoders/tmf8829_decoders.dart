// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';

/// TMF8829 dToF — pktType 6.
///
/// Wire format (little-endian throughout):
///   [0]      rows  uint8         (8..48)
///   [1]      cols  uint8         (8..32)
///   [2..]    pixels uint16 × rows*cols  (distance in mm; 0 = no return)
///
/// At max resolution (48×32): 2 + 3072 = 3074 B payload. Comfortably under
/// the 8192-byte framer cap.
DecodedPacket decodeTmf8829Pkt6(Uint8List p) {
  if (p.length < 4) return const DecodedPacket(pktType: 6);
  final rows = p[0];
  final cols = p[1];
  final expected = 2 + rows * cols * 2;
  if (rows < 1 || cols < 1 || rows > 64 || cols > 64 || p.length < expected) {
    // Malformed — drop the frame quietly. Console screen will report it as
    // an unknown/short packet at the framer level if it gets really weird.
    return const DecodedPacket(pktType: 6);
  }

  // Copy the pixel slice into a fresh Uint16List view, isolated from the
  // framer's reusable scratch buffer.
  final pixelBytes = Uint8List.fromList(p.sublist(2, expected));
  final tsUs = DateTime.now().microsecondsSinceEpoch;

  return DecodedPacket(
    pktType: 6,
    matrixFrames: {
      'depth_map': MatrixFramePayload(
        rows: rows,
        cols: cols,
        data: pixelBytes.buffer,
        timestampUs: tsUs,
      ),
    },
  );
}
