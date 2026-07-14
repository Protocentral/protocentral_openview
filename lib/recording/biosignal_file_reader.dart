// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'recording_models.dart';

/// `.hpd` (BIOSIG v1) reader. Symmetric with [BiosignalFileWriter]. Lifted
/// verbatim from healthypi_studio so files round-trip between the two apps.
class BiosignalFileReader {
  final File _file;
  late RandomAccessFile _raf;
  bool _isOpen = false;

  BiosignalFileReader(this._file);

  Future<void> open() async {
    if (_isOpen) return;
    _raf = await _file.open();
    _isOpen = true;
  }

  Future<void> close() async {
    if (_isOpen) {
      await _raf.close();
      _isOpen = false;
    }
  }

  Future<RecordingMetadata> readHeader() async {
    if (!_isOpen) {
      throw RecordingException('File not open. Call open() first.');
    }
    await _raf.setPosition(0);
    final sig = await _raf.read(6);
    if (String.fromCharCodes(sig) != 'BIOSIG') {
      throw RecordingException('Invalid file signature');
    }
    final version = _u16(await _raf.read(2));
    if (version != 1) {
      throw RecordingException('Unsupported format version: $version');
    }
    _u32(await _raf.read(4)); // header size placeholder
    _u64(await _raf.read(8)); // data offset placeholder

    final deviceId = _str(await _raf.read(64));
    final deviceName = _str(await _raf.read(64));
    final firmwareVersion = _str(await _raf.read(32));
    final createdAtMs = _i64(await _raf.read(8));
    final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
    final channelCount = _u16(await _raf.read(2));
    final recordingDurationMicros = _i64(await _raf.read(8));
    final totalSamples = _u64(await _raf.read(8));

    final channels = <ChannelInfo>[];
    for (int i = 0; i < channelCount; i++) {
      channels.add(ChannelInfo(
        id: _str(await _raf.read(32)),
        name: _str(await _raf.read(64)),
        unit: _str(await _raf.read(32)),
        samplingRate: _f64(await _raf.read(8)),
        gainFactor: _f64(await _raf.read(8)),
        offset: _f64(await _raf.read(8)),
        minValue: _f64(await _raf.read(8)),
        maxValue: _f64(await _raf.read(8)),
      ));
    }

    SubjectMetadata? subject;
    if ((await _raf.read(1))[0] == 1) {
      final ageVal = _i32(await _raf.read(4));
      subject = SubjectMetadata(
        subjectId: _str(await _raf.read(64)),
        age: ageVal == -1 ? null : ageVal,
        gender: _str(await _raf.read(2)),
        condition: _str(await _raf.read(128)),
        notes: _str(await _raf.read(256)),
      );
    }

    SessionMetadata? session;
    if ((await _raf.read(1))[0] == 1) {
      final protocolName = _str(await _raf.read(128));
      final location = _str(await _raf.read(128));
      final operator_ = _str(await _raf.read(64));
      final notes = _str(await _raf.read(256));
      final tagsLength = _u32(await _raf.read(4));
      final tagsJson = String.fromCharCodes(await _raf.read(tagsLength));
      final customTags =
          Map<String, String>.from(jsonDecode(tagsJson) as Map? ?? {});
      session = SessionMetadata(
        protocolName: protocolName,
        location: location,
        operator: operator_,
        notes: notes,
        customTags: customTags,
      );
    }

    return RecordingMetadata(
      fileFormatVersion: '1.0',
      deviceId: deviceId,
      deviceName: deviceName,
      firmwareVersion: firmwareVersion,
      createdAt: createdAt,
      channels: channels,
      subjectMetadata: subject,
      sessionMetadata: session,
      recordingDuration: Duration(microseconds: recordingDurationMicros),
      totalSamples: totalSamples,
    );
  }

  /// Stream every sample. Caller must have an open file.
  Stream<MultiChannelSample> readSamples() async* {
    if (!_isOpen) {
      throw RecordingException('File not open. Call open() first.');
    }
    final metadata = await readHeader();
    final length = await _raf.length();

    while (await _raf.position() < length) {
      try {
        final markerBytes = await _raf.read(4);
        if (markerBytes.length < 4) break;
        final marker = _u32(markerBytes);
        if (marker != 0x44415441) break; // DATA marker

        _u32(await _raf.read(4)); // blockSeq
        final sampleCount = _u32(await _raf.read(4));
        _i64(await _raf.read(8)); // first ts in block

        for (int i = 0; i < sampleCount; i++) {
          final seq = _u32(await _raf.read(4));
          final ts = _i64(await _raf.read(8));
          final values = <String, double>{};
          for (final c in metadata.channels) {
            values[c.id] = _f64(await _raf.read(8));
          }
          yield MultiChannelSample(
            sequenceNumber: seq,
            timestampMicros: ts,
            values: values,
          );
        }
        await _raf.read(4); // CRC32
      } catch (_) {
        break;
      }
    }
  }

  /// Count of DATA-block samples in the file (cheap pass; doesn't yield).
  Future<int> countSamples() async {
    if (!_isOpen) throw RecordingException('File not open');
    final metadata = await readHeader();
    final length = await _raf.length();
    int total = 0;
    while (await _raf.position() < length) {
      final markerBytes = await _raf.read(4);
      if (markerBytes.length < 4) break;
      final marker = _u32(markerBytes);
      if (marker != 0x44415441) break;
      _u32(await _raf.read(4));
      final sampleCount = _u32(await _raf.read(4));
      _i64(await _raf.read(8));
      // Skip the sample payload.
      final perSample = 4 + 8 + 8 * metadata.channels.length;
      final cur = await _raf.position();
      await _raf.setPosition(cur + perSample * sampleCount + 4 /*crc*/);
      total += sampleCount;
    }
    return total;
  }

  static int _u16(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getUint16(0, Endian.little);
  static int _u32(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getUint32(0, Endian.little);
  static int _u64(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getUint64(0, Endian.little);
  static int _i32(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getInt32(0, Endian.little);
  static int _i64(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getInt64(0, Endian.little);
  static double _f64(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getFloat64(0, Endian.little);

  static String _str(List<int> bytes) {
    final nul = bytes.indexOf(0);
    return String.fromCharCodes(
        bytes.sublist(0, nul >= 0 ? nul : bytes.length));
  }
}
