// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'hs_type.dart';

/// Quality / context bitmask flags carried in a sample's `quality` byte
/// (HPI_HS_API §5).
class HsQuality {
  static const int valid = 1 << 0; // timestamp valid (RTC synced), in range
  static const int onSkin = 1 << 1; // sensor reports skin contact
  static const int lowMotion = 1 << 2; // IMU below motion threshold
  static const int highConf = 1 << 3; // algorithm confidence high
  static const int duringSleep = 1 << 4; // captured in a sleep window
  static const int manual = 1 << 5; // user-initiated spot check

  static String describe(int q) {
    final flags = <String>[
      if (q & valid != 0) 'valid',
      if (q & onSkin != 0) 'on-skin',
      if (q & lowMotion != 0) 'low-motion',
      if (q & highConf != 0) 'high-conf',
      if (q & duringSleep != 0) 'sleep',
      if (q & manual != 0) 'manual',
    ];
    return flags.isEmpty ? '—' : flags.join(',');
  }
}

/// One HPI_HS **sample** — the packed 18-byte wire record returned by `SYNC`.
///
/// Wire layout (little-endian), Python `struct.unpack('<IqBBi', rec)`:
/// ```
///   seq     uint32   4   monotonic per-device sequence (the sync cursor)
///   ts_utc  int64    8   seconds since Unix epoch (UTC)
///   type    uint8    1   metric type id → look up in the TYPES registry
///   quality uint8    1   HsQuality bitmask
///   value   int32    4   fixed-point; real = value / type.scale
/// ```
class HsSample {
  const HsSample({
    required this.seq,
    required this.tsUtc,
    required this.type,
    required this.quality,
    required this.value,
  });

  final int seq;
  final int tsUtc;
  final int type;
  final int quality;
  final int value;

  /// Size of one packed record on the wire.
  static const int wireSize = 18;

  bool get isValid => (quality & HsQuality.valid) != 0;
  bool get isOnSkin => (quality & HsQuality.onSkin) != 0;

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(tsUtc * 1000, isUtc: true);

  /// Real-unit value given the registry entry for this sample's [type].
  double real(HsType type) => type.toReal(value);

  /// Decode a single 18-byte record from [data] starting at [offset].
  /// `seq@0 (u32) · ts_utc@4 (i64) · type@12 (u8) · quality@13 (u8) · value@14 (i32)`.
  factory HsSample.fromBytes(Uint8List data, [int offset = 0]) {
    final ByteData bd = ByteData.sublistView(data, offset, offset + wireSize);
    return HsSample(
      seq: bd.getUint32(0, Endian.little),
      tsUtc: bd.getInt64(4, Endian.little),
      type: bd.getUint8(12),
      quality: bd.getUint8(13),
      value: bd.getInt32(14, Endian.little),
    );
  }

  /// Decode a back-to-back packed byte string (the `recs` field of a `SYNC`
  /// response) into a list of samples.
  static List<HsSample> listFromBytes(Uint8List recs) {
    final List<HsSample> out = <HsSample>[];
    final int n = recs.length ~/ wireSize;
    final ByteData bd = ByteData.sublistView(recs);
    for (int i = 0; i < n; i++) {
      final int base = i * wireSize;
      out.add(HsSample(
        seq: bd.getUint32(base + 0, Endian.little),
        tsUtc: bd.getInt64(base + 4, Endian.little),
        type: bd.getUint8(base + 12),
        quality: bd.getUint8(base + 13),
        value: bd.getInt32(base + 14, Endian.little),
      ));
    }
    return out;
  }

  @override
  String toString() =>
      'HsSample(seq:$seq t:$tsUtc type:0x${type.toRadixString(16)} '
      'q:0x${quality.toRadixString(16)} v:$value)';
}
