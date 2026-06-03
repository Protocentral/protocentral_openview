import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

/// HealthyPi 5 (USB) — pktType 3 — ECG & BioZ batch, ~125 Hz, 32-bit samples.
///
/// Firmware sends 8 ECG samples and 4 BioZ/Resp samples per packet,
/// followed by computed heart rate and respiration rate.
///
/// Payload layout (51 bytes):
///   [0-31]   ECG     8 × int32 LE (sign-extended 24-bit ADC)
///   [32-47]  BioZ    4 × int32 LE (bio-impedance / respiration waveform)
///   [48]     HR      uint8 (bpm)
///   [49]     RespRate uint8 (breaths/min)
///   [50]     0x00    reserved.
DecodedPacket decodeHealthypiPkt3(Uint8List p) {
  final ecgSamples = <double>[];
  for (int i = 0; i < 8; i++) {
    ecgSamples.add(Codec.readInt32LE(p, i * 4).toDouble());
  }

  final biozSamples = <double>[];
  for (int i = 0; i < 4; i++) {
    biozSamples.add(Codec.readInt32LE(p, 32 + i * 4).toDouble());
  }

  final hr = p[48];
  final respRate = p[49];

  return DecodedPacket(
    pktType: 3,
    channelSamples: {
      'ecg': ecgSamples,
      'bioz': biozSamples,
    },
    events: {
      'heartRate': hr,
      'respRate': respRate,
    },
  );
}

/// HealthyPi 5 (USB) — pktType 4 — PPG batch, 16-bit samples.
///
/// Firmware sends 8 PPG-Red samples per packet along with temperature
/// and a computed SpO2 value.
///
/// Payload layout (20 bytes):
///   [0-15]   PPG Red  8 × uint16 LE (raw photodiode counts)
///   [16-17]  Temp     int16 LE  (°C × 100, e.g. 3650 → 36.50 °C)
///   [18]     SpO2     uint8 (%)
///   [19]     0x00     reserved.
DecodedPacket decodeHealthypiPkt4(Uint8List p) {
  final ppgSamples = <double>[];
  for (int i = 0; i < 8; i++) {
    ppgSamples.add(Codec.readUint16LE(p, i * 2).toDouble());
  }

  final temp = Codec.readInt16LE(p, 16).toDouble() / 100.0;
  final spo2 = p[18];

  return DecodedPacket(
    pktType: 4,
    channelSamples: {
      'ppgRed': ppgSamples,
    },
    events: {
      'temperature': temp,
      'spo2': spo2,
    },
  );
}
