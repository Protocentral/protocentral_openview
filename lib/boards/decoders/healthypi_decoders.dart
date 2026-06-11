import 'dart:typed_data';

import '../../protocol/decoded_packet.dart';
import 'shared_codecs.dart';

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
