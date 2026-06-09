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

  final respSamples = <double>[];
  for (int i = 0; i < 4; i++) {
    respSamples.add(Codec.readInt32LE(p, 32 + i * 4).toDouble());
  }

  final hr = p[48];
  final respRate = p[49];

  return DecodedPacket(
    pktType: 3,
    channelSamples: {
      'ecg': ecgSamples,
      'resp': respSamples,
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
  final spo2 = p[16];
  final temp = Codec.readInt16LE(p, 17).toDouble() / 100.0;


  return DecodedPacket(
    pktType: 4,
    channelSamples: {
      'ppgRed': ppgSamples,
    },
    events: {
      'spo2': spo2,
      'temperature': temp,
    },
  );
}

/// HealthyPi 5 (USB) — pktType 2 — Combined ECG, BioZ & PPG single-sample packet.
///
/// Payload layout (22 bytes):
///   [0-3]    ecg_sample       int32  LE — sign-extended 24-bit ADC value
///   [4-7]    bioz_sample      int32  LE — bio-impedance / respiration waveform
///   [8]      bioZSkipSample   uint8  — 0 = valid BioZ; 1 = skip (do not plot/process)
///   [9-12]   raw_red          int32  LE — PPG red-channel raw photodiode counts
///   [13-16]  raw_ir           int32  LE — PPG IR-channel raw photodiode counts
///   [17-18]  temp             int16  LE — °C × 100 (only low 16 bits of int32 used;
///                                         e.g. 3650 → 36.50 °C)
///   [19]     spo2             uint8  — SpO₂ in %
///   [20]     hr               uint8  — heart rate in bpm
///   [21]     rr               uint8  — respiration rate in breaths/min
///
/// Note: bioz_sample is always emitted in channelSamples. Consumers must check
/// the 'bioZSkip' event flag (1 = invalid) before plotting or processing the
/// 'bioz' channel for this sample.
DecodedPacket decodeHealthypiPkt2(Uint8List p) {
  final ecgSample  = Codec.readInt32LE(p, 0).toDouble();
  final biozSample = Codec.readInt32LE(p, 4).toDouble();
  final bioZSkip   = p[8] != 0;               // true → firmware says skip this BioZ sample
  final rawRed     = Codec.readInt32LE(p, 9).toDouble();
  final rawIr      = Codec.readInt32LE(p, 13).toDouble();
  final temp       = Codec.readInt16LE(p, 17).toDouble() / 100.0;
  final spo2       = p[19];
  final hr         = p[20];
  final rr         = p[21];

  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ecg':    [ecgSample],
      'bioz':   [biozSample],   // check events['bioZSkip'] before using
      'ppgRed': [rawRed],
      'ppgIr':  [rawIr],
    },
    events: {
      'heartRate':   hr,
      'respRate':    rr,
      'spo2':        spo2,
      'temperature': temp,
      'bioZSkip':    bioZSkip ? 1 : 0,
    },
  );
}
