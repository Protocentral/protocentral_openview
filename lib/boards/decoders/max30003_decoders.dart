import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// MAX30003 ECG Breakout — pktType 2 — 128 Hz.
///
/// Payload layout (12 bytes):
///   [0-3]  ECG  int32
///   [4-7]  RR   int32 (computed respiration rate)
///   [8-11] HR   int32 (computed heart rate)
DecodedPacket decodeMax30003Pkt2(Uint8List p) {
  final ecg = Codec.readInt32LE(p, 0).toDouble();
  final rr = Codec.readInt32LE(p, 4);
  final hr = Codec.readInt32LE(p, 8);
  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ecg': [ecg],
    },
    events: {
      'heartRate': hr,
      'respRate': rr,
    },
  );
}
