// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import '../boards/board_descriptor.dart';
import 'decoded_packet.dart';
import 'packet_framer_v3.dart';

/// Dispatches framed packets through the connected board's decoders, fanning
/// out the result to channel / matrix / event sinks.
class PacketRouter {
  final BoardDescriptor descriptor;

  /// Called for every decoded channel-sample burst.
  final void Function(String channelId, List<double> samples)? onChannel;

  /// Called for every decoded matrix frame.
  final void Function(String matrixId, MatrixFramePayload frame)? onMatrix;

  /// Called for scalar events (HR, SpO2, lead-off, markers).
  final void Function(String key, num value)? onEvent;

  /// Called when the framer surfaces an unknown packet type.
  final void Function(int pktType, int payloadLen)? onUnknown;

  /// Called for every successfully decoded packet, before the per-channel /
  /// per-event fan-out. Useful for recording and replay where the original
  /// packet grouping matters for sample-set assembly.
  final void Function(DecodedPacket packet)? onDecodedPacket;

  PacketRouter({
    required this.descriptor,
    this.onChannel,
    this.onMatrix,
    this.onEvent,
    this.onUnknown,
    this.onDecodedPacket,
  });

  void route(FramedPacket pkt) {
    if (!pkt.known) {
      onUnknown?.call(pkt.pktType, pkt.payload.length);
      return;
    }
    final spec = descriptor.packet(pkt.pktType);
    if (spec == null) {
      onUnknown?.call(pkt.pktType, pkt.payload.length);
      return;
    }
    final decoded = spec.decode(pkt.payload);
    if (decoded.isEmpty) return;

    onDecodedPacket?.call(decoded);

    decoded.channelSamples.forEach((id, samples) {
      onChannel?.call(id, samples);
    });
    decoded.matrixFrames.forEach((id, frame) {
      onMatrix?.call(id, frame);
    });
    decoded.events.forEach((key, value) {
      onEvent?.call(key, value);
    });
  }
}
