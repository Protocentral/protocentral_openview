import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// Sensything Ox — pktType 2 — 128 Hz.
///
/// Payload layout (10 bytes, little-endian, AFE4490 family):
///   [0-3]  ECG  int32 (raw ADC; unsigned interpretation per legacy decoder)
///   [4-7]  PPG  int32 (raw ADC; unsigned interpretation per legacy decoder)
///   [8]    SpO2 uint8 (% O2 saturation)
///   [9]    HR   uint8 (bpm)
///
/// Channel mapping (board descriptor):
///   ecg, ppg
/// Events:
///   spo2, heartRate
DecodedPacket decodeSensythingOxPkt2(Uint8List p) {
  final ecg = Codec.readUint32LE(p, 0).toDouble();
  final ppg = Codec.readUint32LE(p, 4).toDouble();
  final spo2 = p[8];
  final hr = p[9];
  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ecg': [ecg],
      'ppg': [ppg],
    },
    events: {
      'spo2': spo2,
      'heartRate': hr,
    },
  );
}
