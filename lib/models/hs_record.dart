import 'dart:typed_data';

/// Header of an episodic raw-signal **record** session (`RECORDS list`).
///
/// The exact CBOR key names are not fully pinned in the public contract, so
/// [fromMap] accepts several candidates per field and never throws.
class HsRecordHeader {
  const HsRecordHeader({
    required this.id,
    required this.startTs,
    required this.signal,
    required this.sampleFormat,
    required this.channels,
    required this.sampleRate,
    required this.nSamples,
    required this.byteLen,
    required this.crc32,
    required this.flags,
  });

  final int id;
  final int startTs;
  final int signal; // signal type (ECG/BioZ/PPG/HRV/IMU)
  final int sampleFormat;
  final int channels;
  final int sampleRate;
  final int nSamples;
  final int byteLen;
  final int crc32;
  final int flags; // e.g. PARTIAL

  /// PARTIAL flag (interrupted session — usable, not truncated). Bit 0 by
  /// convention; adjust if the firmware differs.
  bool get isPartial => (flags & 0x01) != 0;

  static int _i(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toInt();
    }
    return 0;
  }

  factory HsRecordHeader.fromMap(Map<Object?, Object?> m) => HsRecordHeader(
        id: _i(m, ['id']),
        startTs: _i(m, ['start_ts', 'ts', 'start', 'start_utc']),
        signal: _i(m, ['signal', 'sig', 'type']),
        sampleFormat: _i(m, ['fmt', 'sample_format', 'format']),
        channels: _i(m, ['ch', 'channels', 'nch']),
        sampleRate: _i(m, ['sr', 'sample_rate', 'rate', 'fs']),
        nSamples: _i(m, ['n', 'n_samples', 'nsamp', 'samples']),
        byteLen: _i(m, ['len', 'byte_len', 'bytes', 'size']),
        crc32: _i(m, ['crc', 'crc32']),
        flags: _i(m, ['flags', 'flag']),
      );

  DateTime get startTime =>
      DateTime.fromMillisecondsSinceEpoch(startTs * 1000, isUtc: true);

  String get signalName => hsSignalName(signal);

  int get effectiveChannels => channels <= 0 ? 1 : channels;
}

/// Best-effort signal-type names (firmware codes not pinned in the contract).
String hsSignalName(int code) {
  const names = {
    0: 'ECG',
    1: 'BioZ/GSR',
    2: 'PPG (wrist)',
    3: 'PPG (finger)',
    4: 'HRV (R-R)',
    5: 'IMU',
  };
  return names[code] ?? 'signal $code';
}

/// Decoded raw-record samples, split per channel.
///
/// The wire sample encoding isn't fully specified, so we **infer bytes-per-
/// sample from the header** (`byteLen / (nSamples × channels)`) rather than
/// trust the format code, and decode signed little-endian integers. [assumed]
/// is true when we had to fall back to a default, so the UI can flag it.
class HsRecordSamples {
  const HsRecordSamples({
    required this.channels,
    required this.data,
    required this.bytesPerSample,
    required this.assumed,
  });

  final int channels;
  final List<List<double>> data; // [channel][sample]
  final int bytesPerSample;
  final bool assumed;

  int get sampleCount => data.isEmpty ? 0 : data.first.length;

  factory HsRecordSamples.decode(HsRecordHeader h, Uint8List payload) {
    final ch = h.effectiveChannels;
    int bps;
    bool assumed = false;
    if (h.nSamples > 0 && ch > 0 && payload.isNotEmpty) {
      final inferred = payload.length ~/ (h.nSamples * ch);
      bps = (inferred == 1 || inferred == 2 || inferred == 4) ? inferred : 2;
      if (inferred != bps) assumed = true;
    } else {
      bps = 2;
      assumed = true;
    }

    final bd = ByteData.sublistView(payload);
    final totalSamples = payload.length ~/ (bps * ch);
    final data = List.generate(ch, (_) => <double>[]);
    for (int i = 0; i < totalSamples; i++) {
      for (int c = 0; c < ch; c++) {
        final off = (i * ch + c) * bps;
        if (off + bps > payload.length) break;
        double v;
        switch (bps) {
          case 1:
            v = bd.getInt8(off).toDouble();
            break;
          case 4:
            v = bd.getInt32(off, Endian.little).toDouble();
            break;
          default:
            v = bd.getInt16(off, Endian.little).toDouble();
        }
        data[c].add(v);
      }
    }
    return HsRecordSamples(
      channels: ch,
      data: data,
      bytesPerSample: bps,
      assumed: assumed,
    );
  }
}
