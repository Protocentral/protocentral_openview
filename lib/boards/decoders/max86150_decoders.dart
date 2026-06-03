import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// MAX86150 Breakout (USB) — pktType 2 — up to 200 Hz, 18-bit samples.
///
/// The MAX86150 integrates a single-lead ECG front-end (18-bit) with a
/// dual-LED PPG front-end (18-bit Red + IR) in one package.
/// On-device SpO2 and heart rate are computed and appended.
///
/// Payload layout (16 bytes):
///   [0-3]    ecg     int32 LE  (sign-extended 18-bit ECG ADC value)
///   [4-7]    ppgRed  int32 LE  (Red  LED count, 18-bit ADC)
///   [8-11]   ppgIr   int32 LE  (IR   LED count, 18-bit ADC)
///   [12-13]  HR      int16 LE  (bpm)
///   [14-15]  SpO2    int16 LE  (%)

DecodedPacket decodeMax86150Pkt2(Uint8List p) {
  final ecg    = Codec.readInt32LE(p, 0).toDouble();
  final ppgRed = Codec.readInt32LE(p, 4).toDouble();
  final ppgIr  = Codec.readInt32LE(p, 8).toDouble();
  final hr     = Codec.readInt16LE(p, 12);
  final spo2   = Codec.readInt16LE(p, 14);

  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ecg':    [ecg],
      'ppgRed': [ppgRed],
      'ppgIr':  [ppgIr],
    },
    events: {
      'heartRate': hr,
      'spo2':      spo2,
    },
  );
}
