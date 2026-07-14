// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../protocol/decoded_packet.dart';

/// Pure decoder function signature.
typedef PacketDecoder = DecodedPacket Function(Uint8List payload);

/// One packet type a board can emit.
class PacketSpec {
  final int pktType;
  final String label;
  final int? expectedPayloadLength;
  final PacketDecoder decode;

  const PacketSpec({
    required this.pktType,
    required this.label,
    required this.decode,
    this.expectedPayloadLength,
  });
}

class CommandSpec {
  final String id;
  final String label;
  final List<int> bytes;
  const CommandSpec({required this.id, required this.label, required this.bytes});
}
