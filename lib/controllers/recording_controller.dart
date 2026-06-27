import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../boards/board_descriptor.dart';
import '../protocol/decoded_packet.dart';
import '../recording/biosignal_file_writer.dart';
import '../recording/recording_models.dart';
import 'connection_controller.dart';

/// Orchestrates a `.hpd` capture session: subscribes to the connection's
/// packet stream, assembles per-packet `MultiChannelSample`s with host
/// timestamps, and drives [BiosignalFileWriter].
class RecordingController extends ChangeNotifier {
  final ConnectionController connection;
  RecordingController({required this.connection});

  RecordingState _state = RecordingState.idle;
  RecordingState get state => _state;

  String? _filePath;
  String? get filePath => _filePath;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  DateTime? _startedAt;
  DateTime? get startedAt => _startedAt;
  Duration get elapsed =>
      _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  int _samplesRecorded = 0;
  int get samplesRecorded => _samplesRecorded;
  int get bytesWritten => _writer?.bytesWritten ?? 0;

  BiosignalFileWriter? _writer;
  BoardDescriptor? _descriptor;
  void Function(DecodedPacket)? _listener;
  int _seq = 0;
  int _startMicros = 0;

  bool get isRecording => _state == RecordingState.recording;

  Future<void> start() async {
    if (_state == RecordingState.recording) return;
    final descriptor = connection.descriptor;
    if (descriptor == null) {
      throw RecordingException('No board connected');
    }

    final dir = await _recordingsDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);

    final name = _newFileName(descriptor);
    final file = File(p.join(dir.path, name));
    _filePath = file.path;
    _descriptor = descriptor;

    _writer = BiosignalFileWriter(file);
    final meta = RecordingMetadata(
      deviceId: descriptor.id,
      deviceName: descriptor.displayName,
      firmwareVersion: 'unknown',
      channels: descriptor.channels
          .map((c) => ChannelInfo(
                id: c.id,
                name: c.label,
                unit: c.unit.name,
                samplingRate: c.sampleRateHz,
                minValue: c.displayMin,
                maxValue: c.displayMax,
              ))
          .toList(),
    );
    await _writer!.writeHeader(meta);

    _seq = 0;
    _samplesRecorded = 0;
    _errorMessage = null;
    _startedAt = DateTime.now();
    _startMicros = _startedAt!.microsecondsSinceEpoch;

    _listener = _onPacket;
    connection.addPacketListener(_listener!);

    _state = RecordingState.recording;
    notifyListeners();
  }

  Future<String?> stop() async {
    if (_state != RecordingState.recording) return null;
    if (_listener != null) {
      connection.removePacketListener(_listener!);
      _listener = null;
    }
    try {
      await _writer?.finalize();
    } catch (e) {
      _errorMessage = e.toString();
      _state = RecordingState.error;
      notifyListeners();
      return _filePath;
    }
    final savedAt = _filePath;
    _writer = null;
    _descriptor = null;
    _state = RecordingState.stopped;
    notifyListeners();
    return savedAt;
  }

  void _onPacket(DecodedPacket pkt) {
    final writer = _writer;
    final desc = _descriptor;
    if (writer == null || desc == null) return;
    if (pkt.channelSamples.isEmpty) return;

    // Find the burst length (samples per channel in this packet). Channels
    // with a different count get NaN-padded to the longest burst — that
    // happens only when a board emits asymmetric bursts, which none of the
    // pilot boards do.
    int burstLen = 0;
    for (final list in pkt.channelSamples.values) {
      if (list.length > burstLen) burstLen = list.length;
    }
    if (burstLen == 0) return;

    // Use the slowest channel to estimate per-burst duration, then linearly
    // interpolate timestamps within the burst. For boards where all channels
    // share a rate (every current descriptor), this is exact.
    double rate = desc.channels.isNotEmpty
        ? desc.channels.first.sampleRateHz
        : 1000.0;
    for (final c in desc.channels) {
      if (c.sampleRateHz > 0 && c.sampleRateHz < rate) rate = c.sampleRateHz;
    }
    final intervalMicros = (1e6 / rate).round();
    final nowMicros = DateTime.now().microsecondsSinceEpoch - _startMicros;
    final baseMicros = nowMicros - intervalMicros * (burstLen - 1);

    final samples = <MultiChannelSample>[];
    for (int i = 0; i < burstLen; i++) {
      final values = <String, double>{};
      for (final c in desc.channels) {
        final list = pkt.channelSamples[c.id];
        if (list == null || list.isEmpty) {
          values[c.id] = double.nan;
        } else if (i < list.length) {
          values[c.id] = list[i];
        } else {
          values[c.id] = list.last;
        }
      }
      samples.add(MultiChannelSample(
        sequenceNumber: _seq++,
        timestampMicros: baseMicros + intervalMicros * i,
        values: values,
      ));
    }

    // Fire-and-forget — writer is buffered, IOSink handles ordering.
    writer.writeSamples(samples);
    _samplesRecorded += samples.length;
    notifyListeners();
  }

  static Future<Directory> _recordingsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'ProtoCentral_Recordings'));
  }

  static String _newFileName(BoardDescriptor d) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}'
        '_${two(t.hour)}${two(t.minute)}${two(t.second)}';
    return '${d.id}_$stamp.hpd';
  }

  @override
  void dispose() {
    if (_listener != null) {
      try {
        connection.removePacketListener(_listener!);
      } catch (_) {}
    }
    super.dispose();
  }
}
