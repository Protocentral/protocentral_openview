// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

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
  final ecgSample = Codec.readInt32LE(p, 0).toDouble();
  final biozSample = Codec.readInt32LE(p, 4).toDouble();
  final bioZSkip = p[8] != 0; // true → firmware says skip this BioZ sample
  final rawRed = Codec.readInt32LE(p, 9).toDouble();
  final rawIr = Codec.readInt32LE(p, 13).toDouble();
  final temp = Codec.readInt16LE(p, 17).toDouble() / 100.0;
  final spo2 = p[19];
  final hr = p[20];
  final rr = p[21];

  return DecodedPacket(
    pktType: 2,
    channelSamples: {
      'ecg': [ecgSample],
      'bioz': [biozSample], // check events['bioZSkip'] before using
      'ppgRed': [rawRed],
      'ppgIr': [rawIr],
    },
    events: {
      'heartRate': hr,
      'respRate': rr,
      'spo2': spo2,
      'temperature': temp,
      'bioZSkip': bioZSkip ? 1 : 0,
    },
  );
}

// ── HealthyPi 5 firmware v1.0.0+ (USB) — separate ECG/BioZ and PPG packets ──
//
// From firmware 1.0.0, HealthyPi 5's USB stream batches samples into two
// framed packet types instead of the combined single-sample packet above (see
// README wire-format tables). All multi-byte fields are little-endian, matching
// pktType 2 and the BLE stream (verified against ProtoCentral OpenView 2).

/// HealthyPi 5 — pktType 3 — ECG + Respiration (BioZ) batch (USB).
///
/// Payload layout (50 bytes):
///   [0-31]   8 × ECG   int32 LE — one batch tick, 125 Hz stream
///   [32-47]  4 × Resp  int32 LE — bio-impedance / respiration, ~62 Hz stream
///   [48]     heartRate uint8    — bpm
///   [49]     respRate  uint8    — breaths/min
DecodedPacket decodeHealthypiPkt3(Uint8List p) {
  const ecgCount = 8;
  const respCount = 4;
  const respBase = ecgCount * 4; // 32
  const hrOffset = respBase + respCount * 4; // 48

  final ecg = <double>[];
  for (var i = 0; i < ecgCount; i++) {
    ecg.add(Codec.readInt32LE(p, i * 4).toDouble());
  }
  final resp = <double>[];
  for (var i = 0; i < respCount; i++) {
    resp.add(Codec.readInt32LE(p, respBase + i * 4).toDouble());
  }

  final events = <String, num>{};
  if (p.length > hrOffset) events['heartRate'] = p[hrOffset];
  if (p.length > hrOffset + 1) events['respRate'] = p[hrOffset + 1];

  return DecodedPacket(
    pktType: 3,
    channelSamples: {
      'ecg': ecg,
      'bioz': resp,
    },
    events: events,
  );
}

/// HealthyPi 5 — pktType 4 — PPG (Red) + Temperature + SpO₂ batch (USB).
///
/// Payload layout (19 bytes):
///   [0-15]   8 × PPG-Red int16 LE — 100 Hz stream
///   [16-17]  temperature int16 LE — °C × 100 (e.g. 3650 → 36.50 °C)
///   [18]     spo2        uint8    — SpO₂ in %
DecodedPacket decodeHealthypiPkt4(Uint8List p) {
  const ppgCount = 8;
  const tempOffset = ppgCount * 2; // 16
  const spo2Offset = tempOffset + 2; // 18

  final ppgRed = <double>[];
  for (var i = 0; i < ppgCount; i++) {
    ppgRed.add(Codec.readInt16LE(p, i * 2).toDouble());
  }

  final events = <String, num>{};
  if (p.length >= tempOffset + 2) {
    events['temperature'] = Codec.readInt16LE(p, tempOffset) / 100.0;
  }
  if (p.length > spo2Offset) events['spo2'] = p[spo2Offset];

  return DecodedPacket(
    pktType: 4,
    channelSamples: {
      'ppgRed': ppgRed,
    },
    events: events,
  );
}

// ── HealthyPi 5 BLE — one characteristic (hence one packet type) per signal ──
//
// Over BLE the board does NOT batch signals: each GATT characteristic streams a
// single signal, so OpenView routes each characteristic to its own synthetic
// packet type (chosen in healthypi.dart's BleProfile). All values are
// little-endian, matching ProtoCentral OpenView 2's parser (plots.dart:
// asInt32List / asInt16List, and single-byte HR/SpO2/RespRate reads).
//
// Synthetic BLE packet types (raw, unframed — no wire byte carries these):
const int hpiBlePktEcg = 0x11; // ECG_CHAR      — N × int32 LE
const int hpiBlePktResp = 0x12; // RESP_CHAR     — N × int32 LE
const int hpiBlePktPpg = 0x13; // HIST_CHAR      — N × int16 LE
const int hpiBlePktHr = 0x14; // HR_CHAR (2a37)  — HR in byte[1]
const int hpiBlePktSpo2 = 0x15; // SPO2_CHAR (2a5e) — SpO2 in byte[1]
const int hpiBlePktTemp = 0x16; // TEMP_CHAR (2a6e) — int16 LE ×0.01
const int hpiBlePktRespRate = 0x17; // HRV_CHAR   — resp rate in byte[0]

/// ECG characteristic — a run of int32 LE samples → 'ecg'.
DecodedPacket decodeHealthypiBleEcg(Uint8List p) {
  final n = p.length ~/ 4;
  if (n == 0) return DecodedPacket(pktType: hpiBlePktEcg);
  final ecg = <double>[
    for (var i = 0; i < n; i++) Codec.readInt32LE(p, i * 4).toDouble(),
  ];
  return DecodedPacket(pktType: hpiBlePktEcg, channelSamples: {'ecg': ecg});
}

/// Respiration characteristic — a run of int32 LE samples → 'bioz'.
DecodedPacket decodeHealthypiBleResp(Uint8List p) {
  final n = p.length ~/ 4;
  if (n == 0) return DecodedPacket(pktType: hpiBlePktResp);
  final resp = <double>[
    for (var i = 0; i < n; i++) Codec.readInt32LE(p, i * 4).toDouble(),
  ];
  return DecodedPacket(pktType: hpiBlePktResp, channelSamples: {'bioz': resp});
}

/// PPG (HIST) characteristic — a run of int16 LE samples → 'ppgRed'.
DecodedPacket decodeHealthypiBlePpg(Uint8List p) {
  final n = p.length ~/ 2;
  if (n == 0) return DecodedPacket(pktType: hpiBlePktPpg);
  final ppg = <double>[
    for (var i = 0; i < n; i++) Codec.readInt16LE(p, i * 2).toDouble(),
  ];
  return DecodedPacket(pktType: hpiBlePktPpg, channelSamples: {'ppgRed': ppg});
}

/// Heart Rate characteristic (BLE HR Measurement 0x2A37): flags in [0], the
/// (uint8) heart rate in [1].
DecodedPacket decodeHealthypiBleHr(Uint8List p) {
  if (p.length < 2) return DecodedPacket(pktType: hpiBlePktHr);
  return DecodedPacket(pktType: hpiBlePktHr, events: {'heartRate': p[1]});
}

/// SpO₂ characteristic (0x2A5E): SpO₂ (%) in [1]. Firmware uses 25 as an
/// "invalid" sentinel — suppressed here.
DecodedPacket decodeHealthypiBleSpo2(Uint8List p) {
  if (p.length < 2 || p[1] == 25) return DecodedPacket(pktType: hpiBlePktSpo2);
  return DecodedPacket(pktType: hpiBlePktSpo2, events: {'spo2': p[1]});
}

/// Temperature characteristic (0x2A6E): int16 LE in units of 0.01 °C.
DecodedPacket decodeHealthypiBleTemp(Uint8List p) {
  if (p.length < 2) return DecodedPacket(pktType: hpiBlePktTemp);
  return DecodedPacket(
    pktType: hpiBlePktTemp,
    events: {'temperature': Codec.readInt16LE(p, 0) * 0.01},
  );
}

/// Respiration-rate characteristic (HRV char): resp rate (breaths/min) in [0].
DecodedPacket decodeHealthypiBleRespRate(Uint8List p) {
  if (p.isEmpty) return DecodedPacket(pktType: hpiBlePktRespRate);
  return DecodedPacket(
    pktType: hpiBlePktRespRate,
    events: {'respRate': p[0]},
  );
}
