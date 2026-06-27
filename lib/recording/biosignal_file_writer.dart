import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'recording_models.dart';

/// `.hpd` (BIOSIG v1) writer — block-based, append-only.
///
/// Lifted verbatim from healthypi_studio so files round-trip between the
/// two apps. Only the import path was changed.
class BiosignalFileWriter {
  static const int blockSize = 65536;
  static const int dataBlockMarker = 0x44415441; // 'DATA'
  static const int eventMarkerCode = 0x45564E54; // 'EVNT'
  static const int indexMarker = 0x494E4458; // 'INDX'

  final IOSink _sink;
  // ignore: unused_field
  final int _bufferSize;

  int _blockSequence = 0;
  int _bytesWritten = 0;
  bool _headerWritten = false;
  final List<_IndexEntry> _indexEntries = [];

  BiosignalFileWriter(File file, {int bufferSize = blockSize})
      : _bufferSize = bufferSize,
        _sink = file.openWrite();

  int get bytesWritten => _bytesWritten;

  Future<void> writeHeader(RecordingMetadata metadata) async {
    if (_headerWritten) {
      throw RecordingException('Header already written');
    }

    final buffer = BytesBuilder();

    // Magic 'BIOSIG'
    buffer.add(utf8.encode('BIOSIG'));

    // Format version
    buffer.add(_uint16ToBytes(1));

    // Header size placeholder (kept for compatibility)
    buffer.add(_uint32ToBytes(0));

    // Data offset placeholder
    buffer.add(_uint64ToBytes(0));

    // Device info
    buffer.add(_stringToBytes(metadata.deviceId, 64));
    buffer.add(_stringToBytes(metadata.deviceName, 64));
    buffer.add(_stringToBytes(metadata.firmwareVersion, 32));

    // Created-at timestamp
    buffer.add(_int64ToBytes(metadata.createdAt.millisecondsSinceEpoch));

    // Channel count
    buffer.add(_uint16ToBytes(metadata.channels.length));

    // Recording params (final values are unknown at header-write time —
    // populated by finalize() rewriting the relevant fields if needed).
    buffer.add(_int64ToBytes(metadata.recordingDuration.inMicroseconds));
    buffer.add(_uint64ToBytes(metadata.totalSamples));

    // Channel configurations
    for (final c in metadata.channels) {
      buffer.add(_stringToBytes(c.id, 32));
      buffer.add(_stringToBytes(c.name, 64));
      buffer.add(_stringToBytes(c.unit, 32));
      buffer.add(_float64ToBytes(c.samplingRate));
      buffer.add(_float64ToBytes(c.gainFactor));
      buffer.add(_float64ToBytes(c.offset));
      buffer.add(_float64ToBytes(c.minValue));
      buffer.add(_float64ToBytes(c.maxValue));
    }

    // Subject metadata (present flag + payload, or 0)
    if (metadata.subjectMetadata != null) {
      buffer.addByte(1);
      final sm = metadata.subjectMetadata!;
      buffer.add(_stringToBytes(sm.subjectId ?? '', 64));
      buffer.add(_int32ToBytes(sm.age ?? -1));
      buffer.add(_stringToBytes(sm.gender ?? '', 2));
      buffer.add(_stringToBytes(sm.condition ?? '', 128));
      buffer.add(_stringToBytes(sm.notes ?? '', 256));
    } else {
      buffer.addByte(0);
    }

    // Session metadata (present flag + payload, or 0)
    if (metadata.sessionMetadata != null) {
      buffer.addByte(1);
      final sm = metadata.sessionMetadata!;
      buffer.add(_stringToBytes(sm.protocolName, 128));
      buffer.add(_stringToBytes(sm.location ?? '', 128));
      buffer.add(_stringToBytes(sm.operator ?? '', 64));
      buffer.add(_stringToBytes(sm.notes ?? '', 256));
      final tagsJson = jsonEncode(sm.customTags);
      buffer.add(_uint32ToBytes(tagsJson.length));
      buffer.add(utf8.encode(tagsJson));
    } else {
      buffer.addByte(0);
    }

    final headerBytes = buffer.toBytes();
    _sink.add(headerBytes);
    _bytesWritten += headerBytes.length;
    _headerWritten = true;
  }

  Future<void> writeSamples(List<MultiChannelSample> samples) async {
    if (!_headerWritten) {
      throw RecordingException('Header must be written before samples');
    }
    if (samples.isEmpty) return;

    final buffer = BytesBuilder();
    buffer.add(_uint32ToBytes(dataBlockMarker));
    buffer.add(_uint32ToBytes(_blockSequence++));
    buffer.add(_uint32ToBytes(samples.length));
    buffer.add(_int64ToBytes(samples.first.timestampMicros));
    _indexEntries.add(_IndexEntry(
      timestamp: samples.first.timestampMicros,
      fileOffset: _bytesWritten,
      sampleCount: samples.length,
    ));

    for (final s in samples) {
      buffer.add(_uint32ToBytes(s.sequenceNumber));
      buffer.add(_int64ToBytes(s.timestampMicros));
      for (final v in s.values.values) {
        buffer.add(_float64ToBytes(v));
      }
    }

    final blockBytes = buffer.toBytes();
    final crc = _crc32(blockBytes);
    final framed = BytesBuilder()
      ..add(blockBytes)
      ..add(_uint32ToBytes(crc));
    final out = framed.toBytes();
    _sink.add(out);
    _bytesWritten += out.length;
  }

  Future<void> writeEvent(EventMarker event) async {
    if (!_headerWritten) {
      throw RecordingException('Header must be written before events');
    }
    final buffer = BytesBuilder();
    buffer.add(_uint32ToBytes(eventMarkerCode));
    buffer.add(_uint32ToBytes(event.sequenceNumber));
    buffer.add(_int64ToBytes(event.timestampMicros));
    final typeBytes = utf8.encode(event.type);
    buffer.add(_uint16ToBytes(typeBytes.length));
    buffer.add(typeBytes);
    final descBytes = utf8.encode(event.description);
    buffer.add(_uint16ToBytes(descBytes.length));
    buffer.add(descBytes);
    final out = buffer.toBytes();
    _sink.add(out);
    _bytesWritten += out.length;
  }

  Future<void> finalize() async {
    if (!_headerWritten) {
      throw RecordingException('Cannot finalize without header');
    }
    // Optional INDX block
    if (_indexEntries.isNotEmpty) {
      final buffer = BytesBuilder();
      buffer.add(_uint32ToBytes(indexMarker));
      buffer.add(_uint32ToBytes(_indexEntries.length));
      for (final e in _indexEntries) {
        buffer.add(_int64ToBytes(e.timestamp));
        buffer.add(_uint64ToBytes(e.fileOffset));
        buffer.add(_uint64ToBytes(e.sampleCount));
      }
      final out = buffer.toBytes();
      _sink.add(out);
      _bytesWritten += out.length;
    }
    // ENDOF footer + version
    final footer = BytesBuilder()
      ..add(utf8.encode('ENDOF'))
      ..addByte(0)
      ..add(_uint16ToBytes(1));
    final fb = footer.toBytes();
    _sink.add(fb);
    _bytesWritten += fb.length;
    await _sink.flush();
    await _sink.close();
  }

  // --- Encoding helpers ----------------------------------------------------

  static Uint8List _uint16ToBytes(int value) {
    final b = ByteData(2)..setUint16(0, value & 0xFFFF, Endian.little);
    return b.buffer.asUint8List();
  }

  static Uint8List _uint32ToBytes(int value) {
    final b = ByteData(4)..setUint32(0, value & 0xFFFFFFFF, Endian.little);
    return b.buffer.asUint8List();
  }

  static Uint8List _uint64ToBytes(int value) {
    final b = ByteData(8)..setUint64(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  static Uint8List _int32ToBytes(int value) {
    final b = ByteData(4)..setInt32(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  static Uint8List _int64ToBytes(int value) {
    final b = ByteData(8)..setInt64(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  static Uint8List _float64ToBytes(double value) {
    final b = ByteData(8)..setFloat64(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  static Uint8List _stringToBytes(String str, int maxLength) {
    final encoded = utf8.encode(str);
    final out = Uint8List(maxLength);
    final n = encoded.length < maxLength ? encoded.length : maxLength;
    out.setRange(0, n, encoded);
    return out;
  }

  static int _crc32(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    for (var i = 0; i < bytes.length; i++) {
      crc = crc ^ bytes[i];
      for (var j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc = crc >> 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}

class _IndexEntry {
  final int timestamp;
  final int fileOffset;
  final int sampleCount;
  const _IndexEntry({
    required this.timestamp,
    required this.fileOffset,
    required this.sampleCount,
  });
}
