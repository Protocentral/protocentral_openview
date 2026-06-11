import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// ADS1292R Breakout — pktType 2 — 128 Hz, 16-bit samples.
///
/// Payload layout (8 bytes):
///   [0-1]  ECG   int16 (sign-extended)
///   [2-3]  RESP  int16 (sign-extended)
///   [4-5]  HR    int16
///   [6-7]  RR    int16
DecodedPacket decodeAds1292rPkt2(Uint8List p) {
  final ecg = Codec.readInt16LE(p, 0).toDouble();
  final resp = Codec.readInt16LE(p, 2).toDouble();
  final hr = Codec.readInt16LE(p, 4);
  final rr = Codec.readInt16LE(p, 6);
  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ecg': [ecg],
      'resp': [resp],
    },
    events: {
      'heartRate': hr,
      'respRate': rr,
    },
  );
}
