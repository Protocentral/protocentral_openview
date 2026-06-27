import 'package:flutter/foundation.dart';

import '../boards/channel_spec.dart';
import '../data/channel_buffer.dart';

/// How a strip's Y-axis is scaled.
enum YMode {
  /// Recompute min/max from the visible window every frame.
  auto,

  /// User-fixed min/max.
  manual,
}

/// Trace direction / rendering mode for the whole chart.
enum SweepMode {
  /// Newest sample on the right; data scrolls left every frame.
  scroll,

  /// Fixed-position trace with a moving "sweep head" cursor that overwrites
  /// old data (oscilloscope-style).
  sweep,
}

/// Per-channel UI state owned by the controller.
class StripState {
  YMode yMode;
  double? yMin;
  double? yMax;
  bool visible;

  StripState({
    this.yMode = YMode.auto,
    this.yMin,
    this.yMax,
    this.visible = true,
  });
}

/// Owns chart-side state independent of the buffers and the renderer.
///
/// The renderer asks the controller "what sample index range should I draw,
/// for each channel?" and "what Y range applies?". The controller doesn't
/// touch widgets — it's pure state — so tests and Phase 3/4 features can
/// drive it without spinning up a widget tree.
class ChannelController extends ChangeNotifier {
  final List<ChannelSpec> channels;
  final Map<String, ChannelBuffer> buffers;

  ChannelController({required this.channels, required this.buffers}) {
    for (final c in channels) {
      _strips[c.id] = StripState();
    }
  }

  // ---- Global controls ----

  Duration _window = const Duration(seconds: 5);
  Duration get window => _window;
  set window(Duration v) {
    if (v == _window) return;
    _window = v;
    notifyListeners();
  }

  /// Available preset windows (seconds).
  static const presetWindows = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
  ];

  SweepMode _sweepMode = SweepMode.scroll;
  SweepMode get sweepMode => _sweepMode;
  set sweepMode(SweepMode v) {
    if (v == _sweepMode) return;
    _sweepMode = v;
    notifyListeners();
  }

  bool _paused = false;
  bool get paused => _paused;

  /// When paused, the global sample-index anchor that the renderer should
  /// treat as "now" — independent of the buffer's live total. Per-channel
  /// scrub is derived from this using each channel's sample rate.
  ///
  /// Stored as a normalized cursor in seconds-from-pause (0 = the moment we
  /// paused, negative = scrubbing backward).
  double _scrubOffsetSec = 0;
  double get scrubOffsetSec => _scrubOffsetSec;

  /// Sample-index snapshots taken at the moment of pause, per channel.
  /// On resume they're discarded.
  final Map<String, int> _pauseAnchor = {};

  void togglePause() => setPaused(!_paused);

  void setPaused(bool v) {
    if (_paused == v) return;
    _paused = v;
    if (_paused) {
      _pauseAnchor.clear();
      for (final c in channels) {
        _pauseAnchor[c.id] = buffers[c.id]?.totalWritten ?? 0;
      }
      _scrubOffsetSec = 0;
    } else {
      _scrubOffsetSec = 0;
      _pauseAnchor.clear();
    }
    notifyListeners();
  }

  /// Scrub backward (negative) or forward (toward 0) while paused.
  /// Clamped so the visible window can't run off the end of the buffer.
  void setScrub(double sec) {
    if (!_paused) return;
    // Clamp: most negative such that the window still has at least 1 sample.
    if (sec > 0) sec = 0;
    final maxBackwardSec = _maxScrubBackSec();
    if (sec < -maxBackwardSec) sec = -maxBackwardSec;
    if (sec == _scrubOffsetSec) return;
    _scrubOffsetSec = sec;
    notifyListeners();
  }

  double _maxScrubBackSec() {
    // The most we can scrub is the smallest buffer-window / rate among
    // visible channels minus the current window.
    double best = double.infinity;
    for (final c in channels) {
      final buf = buffers[c.id];
      final anchor = _pauseAnchor[c.id];
      if (buf == null || anchor == null) continue;
      final oldestHeld = anchor - buf.length;
      final secOfHistory =
          (anchor - oldestHeld - _windowSamples(c)) / c.sampleRateHz;
      if (secOfHistory < best) best = secOfHistory;
    }
    return best.isFinite && best > 0 ? best : 0;
  }

  // ---- Per-strip state ----

  final Map<String, StripState> _strips = {};
  StripState strip(String id) => _strips[id] ??= StripState();

  void setYMode(String id, YMode mode) {
    final s = strip(id);
    if (s.yMode == mode) return;
    s.yMode = mode;
    notifyListeners();
  }

  void setManualY(String id, double min, double max) {
    final s = strip(id);
    s.yMode = YMode.manual;
    s.yMin = min;
    s.yMax = max;
    notifyListeners();
  }

  // ---- Renderer queries ----

  int _windowSamples(ChannelSpec c) =>
      (c.sampleRateHz * _window.inMilliseconds / 1000)
          .round()
          .clamp(32, 32768);

  /// What sample index should the right-hand edge of the visible window
  /// correspond to for [channel]? In scroll mode this is the current total
  /// written, less the scrub offset (when paused).
  int endingSampleIndex(ChannelSpec channel) {
    final buf = buffers[channel.id];
    if (buf == null) return 0;
    final base = _paused
        ? (_pauseAnchor[channel.id] ?? buf.totalWritten)
        : buf.totalWritten;
    final scrubSamples = (_scrubOffsetSec * channel.sampleRateHz).round();
    return base + scrubSamples;
  }

  /// How many samples wide the visible window is for [channel].
  int visibleSamples(ChannelSpec channel) => _windowSamples(channel);
}
