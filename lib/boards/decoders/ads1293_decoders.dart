import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// ADS1293 Breakout/Shield (USB) — pktType 2 — 128 Hz, 24-bit samples.
///
/// Three independent ECG channels (Lead I, Lead II, V1) each from a
/// 24-bit sigma-delta ADC, sign-extended to int32.  Heart rate is
/// derived on-device and appended as a separate 16-bit field.
///
/// Payload layout (14 bytes):
///   [0-3]    ch1  int32 LE  (Lead I  — LA−RA, sign-extended 24-bit)
///   [4-7]    ch2  int32 LE  (Lead II — LL−RA, sign-extended 24-bit)
///   [8-11]   ch3  int32 LE  (V1/Lead III, sign-extended 24-bit)
///   [12-13]  HR   int16 LE  (bpm) - need to enable in the fw
///
/// Lead III can be derived as ch2 − ch1 when only 2 limb leads are used.
DecodedPacket decodeAds1293Pkt2(Uint8List p) {
  final ch1 = Codec.readInt32LE(p, 0).toDouble();
  final ch2 = Codec.readInt32LE(p, 4).toDouble();
  final ch3 = Codec.readInt32LE(p, 8).toDouble();
  //final hr = Codec.readInt16LE(p, 12);

  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ch1': [ch1],
      'ch2': [ch2],
      'ch3': [ch3],
    },
    /*events: {
      'heartRate': hr,
    },*/
  );
}
