import 'dart:typed_data';

/// One decoded packet, ready for routing to channel/matrix/event sinks.
///
/// Decoders produce these from raw payload bytes. The router fans them out
/// to per-channel ring buffers, the matrix buffer, or the event log.
class DecodedPacket {
  /// Per-channel samples, keyed by `ChannelSpec.id`. Lists are short bursts
  /// (e.g., 8 samples per packet) — the router pushes each list into the
  /// channel's ring buffer.
  final Map<String, List<double>> channelSamples;

  /// 2-D matrix frames, keyed by `MatrixSpec.id`. One entry per matrix that
  /// appeared in this packet.
  final Map<String, MatrixFramePayload> matrixFrames;

  /// Scalar / event values (HR, SpO2, leadOff flags, markers, etc.).
  final Map<String, num> events;

  /// Original packet type byte. Useful for the console screen.
  final int pktType;

  const DecodedPacket({
    required this.pktType,
    this.channelSamples = const {},
    this.matrixFrames = const {},
    this.events = const {},
  });

  bool get isEmpty =>
      channelSamples.isEmpty && matrixFrames.isEmpty && events.isEmpty;
}

class MatrixFramePayload {
  final int rows;
  final int cols;
  final ByteBuffer data;
  final int timestampUs;
  const MatrixFramePayload({
    required this.rows,
    required this.cols,
    required this.data,
    required this.timestampUs,
  });
}
