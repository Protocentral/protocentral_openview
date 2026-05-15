import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../boards/channel_spec.dart';
import '../data/channel_buffer.dart';
import '../recording/biosignal_file_reader.dart';
import '../recording/recording_models.dart';

/// One playback session for a `.hpd` file.
///
/// Loads all samples into memory (typical recordings are a few minutes, tens
/// of MB). For very long files we'd switch to lazy file iteration; not
/// worth the complexity right now.
///
/// Owns its own [ChannelBuffer]s so the existing [MultiChannelWaveformChart]
/// + [ChannelController] stack just works against them — no chart changes.
class ReplaySession extends ChangeNotifier {
  final File file;
  RecordingMetadata? _meta;
  RecordingMetadata? get metadata => _meta;

  /// All loaded samples, in file order.
  List<MultiChannelSample> _samples = const [];
  int get totalSamples => _samples.length;

  /// Effective sample rate used for time math (slowest declared channel,
  /// since all current pilot boards run synchronized channels).
  double _baseRateHz = 1;
  double get baseRateHz => _baseRateHz;

  /// Per-channel ring buffer keyed by `ChannelInfo.id`. Sized for ~10 s
  /// at the file's base rate.
  final Map<String, ChannelBuffer> buffers = {};

  /// Channel specs synthesised from the file's `ChannelInfo` so the chart
  /// can pick trace colors etc.
  List<ChannelSpec> _channels = const [];
  List<ChannelSpec> get channels => _channels;

  bool _loading = false;
  String? _error;
  bool get loading => _loading;
  String? get error => _error;

  bool _playing = false;
  bool get playing => _playing;

  double _rate = 1.0;
  double get rate => _rate;
  static const presetRates = <double>[0.25, 0.5, 1.0, 2.0, 4.0];

  /// Current playhead, in samples from the start of the recording.
  int _playhead = 0;
  int get playhead => _playhead;
  Duration get position => Duration(
      microseconds: (_playhead * 1e6 / _baseRateHz).round());
  Duration get duration => Duration(
      microseconds: (_samples.length * 1e6 / _baseRateHz).round());

  /// Playhead as a fraction of total length in [0,1].
  double get normalizedPosition =>
      _samples.isEmpty ? 0 : _playhead / _samples.length;

  Timer? _ticker;
  static const _tickPeriod = Duration(milliseconds: 33);
  DateTime? _lastTickWall;

  ReplaySession({required this.file});

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    BiosignalFileReader? reader;
    try {
      reader = BiosignalFileReader(file);
      await reader.open();
      _meta = await reader.readHeader();
      _samples = await reader.readSamples().toList();
      _baseRateHz = _meta!.channels.isEmpty
          ? 1.0
          : _meta!.channels.map((c) => c.samplingRate).reduce(
              (a, b) => a < b ? a : b);
      if (_baseRateHz <= 0) _baseRateHz = 1.0;
      _channels = _meta!.channels.map(_specForInfo).toList();
      _allocateBuffers();
      _seekTo(0, prefill: true);
    } catch (e) {
      _error = e.toString();
    } finally {
      try {
        await reader?.close();
      } catch (_) {}
      _loading = false;
      notifyListeners();
    }
  }

  void play() {
    if (_playing || _samples.isEmpty) return;
    // If at end, snap back to start before playing.
    if (_playhead >= _samples.length) _seekTo(0, prefill: true);
    _playing = true;
    _lastTickWall = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickPeriod, (_) => _tick());
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  void togglePlay() => _playing ? pause() : play();

  void setRate(double r) {
    _rate = r;
    _lastTickWall = DateTime.now();
    notifyListeners();
  }

  /// Seek by normalized position in [0,1].
  void seekNormalized(double v) {
    if (_samples.isEmpty) return;
    final idx = (v.clamp(0.0, 1.0) * _samples.length).round();
    _seekTo(idx, prefill: true);
    notifyListeners();
  }

  /// Seek by sample index.
  void seekToSample(int idx) {
    _seekTo(idx.clamp(0, _samples.length), prefill: true);
    notifyListeners();
  }

  void _tick() {
    if (!_playing) return;
    final now = DateTime.now();
    final dt = now.difference(_lastTickWall ?? now);
    _lastTickWall = now;

    final advanceSamples =
        (_baseRateHz * _rate * dt.inMicroseconds / 1e6).round();
    if (advanceSamples <= 0) return;

    final target = (_playhead + advanceSamples).clamp(0, _samples.length);
    _pushRange(_playhead, target);
    _playhead = target;
    if (_playhead >= _samples.length) {
      pause();
    } else {
      notifyListeners();
    }
  }

  void _allocateBuffers() {
    buffers.clear();
    for (final c in _channels) {
      final cap = (c.sampleRateHz * 10).round().clamp(512, 32768);
      buffers[c.id] = ChannelBuffer(cap);
    }
  }

  /// Seek implementation. Clears buffers then pre-fills the last ~10 s of
  /// history up to [idx], so the chart shows something instead of NaN.
  void _seekTo(int idx, {bool prefill = false}) {
    _playhead = idx.clamp(0, _samples.length);
    for (final b in buffers.values) {
      b.clear();
    }
    if (prefill && _playhead > 0) {
      final prefillSamples = (_baseRateHz * 10).round();
      final start = (_playhead - prefillSamples).clamp(0, _samples.length);
      _pushRange(start, _playhead);
    }
  }

  void _pushRange(int start, int end) {
    if (start >= end) return;
    for (int i = start; i < end; i++) {
      final s = _samples[i];
      for (final entry in s.values.entries) {
        buffers[entry.key]?.push(entry.value);
      }
    }
  }

  static ChannelSpec _specForInfo(ChannelInfo info) {
    return ChannelSpec(
      id: info.id,
      label: info.name.isEmpty ? info.id : info.name,
      sampleRateHz: info.samplingRate,
      unit: SignalUnit.adc,
      kind: _kindForId(info.id),
      displayMin: info.minValue,
      displayMax: info.maxValue,
    );
  }

  /// Best-guess channel kind from the channel id so trace colors match the
  /// live view. Falls back to `unknown`.
  static ChannelKind _kindForId(String id) {
    final low = id.toLowerCase();
    if (low.contains('ecg')) return ChannelKind.ecg;
    if (low.contains('eeg')) return ChannelKind.eeg;
    if (low.contains('ppg')) return ChannelKind.ppg;
    if (low.contains('bioz') || low.contains('imp')) return ChannelKind.bioz;
    if (low.contains('resp')) return ChannelKind.resp;
    if (low.contains('temp')) return ChannelKind.temp;
    if (low.contains('gsr') || low.contains('eda')) return ChannelKind.gsr;
    if (low.startsWith('imu') || low.startsWith('acc') ||
        low.startsWith('gyro')) {
      return ChannelKind.imu;
    }
    if (low.startsWith('cap') || low.startsWith('ch')) {
      return ChannelKind.capacitance;
    }
    return ChannelKind.unknown;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
