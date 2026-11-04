// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:collection';

/// What a [StreamDiagnosticsSnapshot] points to as the reason for uneven
/// streaming. These are starting points for a diagnosis, not proof.
enum StreamFinding {
  /// Too little has been measured to say anything.
  collecting,

  /// Frames take too long to reach the screen once built.
  slowRaster,

  /// Building frames, or other work on the UI thread, is holding things up.
  uiOverloaded,

  /// Frames are individually fast but there are too few of them.
  lowFrameRate,

  /// The app is keeping up, but data reaches it with long gaps.
  dataGaps,

  /// Nothing measured looks wrong.
  noneFound,
}

/// Percentiles of one timing over the measurement window.
class TimingSummary {
  final int count;
  final Duration p50;
  final Duration p95;
  final Duration max;

  const TimingSummary({
    this.count = 0,
    this.p50 = Duration.zero,
    this.p95 = Duration.zero,
    this.max = Duration.zero,
  });

  factory TimingSummary.of(Iterable<int> micros) {
    final sorted = micros.toList()..sort();
    if (sorted.isEmpty) return const TimingSummary();
    Duration at(double q) => Duration(
        microseconds: sorted[((sorted.length - 1) * q).round()]);
    return TimingSummary(
      count: sorted.length,
      p50: at(0.5),
      p95: at(0.95),
      max: Duration(microseconds: sorted.last),
    );
  }
}

/// One reading of everything [StreamDiagnostics] tracks.
class StreamDiagnosticsSnapshot {
  final double framesPerSecond;
  final TimingSummary build;
  final TimingSummary raster;
  final TimingSummary uiDelay;
  final TimingSummary dataGap;
  final double bytesPerSecond;
  final StreamFinding finding;

  const StreamDiagnosticsSnapshot({
    required this.framesPerSecond,
    required this.build,
    required this.raster,
    required this.uiDelay,
    required this.dataGap,
    required this.bytesPerSecond,
    required this.finding,
  });

  String get findingText => switch (finding) {
        StreamFinding.collecting => 'Collecting: keep the board streaming.',
        StreamFinding.slowRaster =>
          'Drawing is too slow for this machine\'s GPU.',
        StreamFinding.uiOverloaded =>
          'The UI thread is overloaded, which delays incoming data.',
        StreamFinding.lowFrameRate =>
          'Frames are fast but few, which suggests the display or compositor.',
        StreamFinding.dataGaps =>
          'The app is keeping up, but data arrives with long gaps.',
        StreamFinding.noneFound => 'No bottleneck found in this window.',
      };

  /// Plain text for pasting into a bug report.
  String report(String setup) {
    String ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);
    String line(String name, TimingSummary t) =>
        '$name: p50 ${ms(t.p50)} ms, p95 ${ms(t.p95)} ms, '
        'max ${ms(t.max)} ms (n=${t.count})';
    return [
      setup,
      'Frames: ${framesPerSecond.toStringAsFixed(1)} fps',
      line('Build', build),
      line('Raster', raster),
      line('UI delay', uiDelay),
      line('Data gap', dataGap),
      'Data rate: ${bytesPerSecond.toStringAsFixed(0)} B/s',
      'Finding: $findingText',
    ].join('\n');
  }
}

class _Sample {
  final DateTime at;
  final int micros;
  const _Sample(this.at, this.micros);
}

/// Rolling timings that show where streaming is being held up: drawing, the UI
/// thread, or the data itself.
///
/// Data gaps are measured when chunks reach the UI thread, so a busy UI thread
/// also shows up as gaps. That's why [StreamFinding.dataGaps] only applies once
/// the frame and UI timings look healthy.
class StreamDiagnostics {
  /// A gap this long is visible as a stall on the chart.
  static const noticeableDataGap = Duration(milliseconds: 100);

  /// Below this many frames in the window, percentiles mean little.
  static const _minFrames = 10;

  final Duration window;
  final DateTime Function() _now;
  final DateTime _startedAt;

  final _build = ListQueue<_Sample>();
  final _raster = ListQueue<_Sample>();
  final _uiDelay = ListQueue<_Sample>();
  final _dataGap = ListQueue<_Sample>();
  final _bytes = ListQueue<_Sample>();
  DateTime? _lastChunkAt;

  StreamDiagnostics({
    this.window = const Duration(seconds: 5),
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        _startedAt = (now ?? DateTime.now)();

  void recordFrame({required Duration build, required Duration raster}) {
    final at = _now();
    _build.addLast(_Sample(at, build.inMicroseconds));
    _raster.addLast(_Sample(at, raster.inMicroseconds));
  }

  /// How much later than scheduled a UI-thread timer actually ran.
  void recordUiDelay(Duration delay) {
    _uiDelay.addLast(_Sample(_now(), delay.inMicroseconds));
  }

  void recordChunk(int bytes) {
    final at = _now();
    final last = _lastChunkAt;
    if (last != null) {
      _dataGap.addLast(_Sample(at, at.difference(last).inMicroseconds));
    }
    _lastChunkAt = at;
    _bytes.addLast(_Sample(at, bytes));
  }

  /// Summarises the current window. [frameBudget] is the time one frame may
  /// take at the repaint cap in use.
  StreamDiagnosticsSnapshot snapshot({required Duration frameBudget}) {
    final now = _now();
    for (final q in [_build, _raster, _uiDelay, _dataGap, _bytes]) {
      while (q.isNotEmpty && now.difference(q.first.at) > window) {
        q.removeFirst();
      }
    }

    var measuredMicros = now.difference(_startedAt).inMicroseconds;
    if (measuredMicros > window.inMicroseconds) {
      measuredMicros = window.inMicroseconds;
    }
    final seconds = measuredMicros / Duration.microsecondsPerSecond;
    double perSecond(num v) => seconds > 0 ? v / seconds : 0;

    final build = TimingSummary.of(_build.map((s) => s.micros));
    final raster = TimingSummary.of(_raster.map((s) => s.micros));
    final uiDelay = TimingSummary.of(_uiDelay.map((s) => s.micros));
    final dataGap = TimingSummary.of(_dataGap.map((s) => s.micros));
    final fps = perSecond(build.count);

    return StreamDiagnosticsSnapshot(
      framesPerSecond: fps,
      build: build,
      raster: raster,
      uiDelay: uiDelay,
      dataGap: dataGap,
      bytesPerSecond:
          perSecond(_bytes.fold<int>(0, (sum, s) => sum + s.micros)),
      finding: _findingFor(
        fps: fps,
        build: build,
        raster: raster,
        uiDelay: uiDelay,
        dataGap: dataGap,
        frameBudget: frameBudget,
      ),
    );
  }

  StreamFinding _findingFor({
    required double fps,
    required TimingSummary build,
    required TimingSummary raster,
    required TimingSummary uiDelay,
    required TimingSummary dataGap,
    required Duration frameBudget,
  }) {
    if (raster.count < _minFrames) return StreamFinding.collecting;
    if (raster.p95 > frameBudget) return StreamFinding.slowRaster;
    if (build.p95 > frameBudget || uiDelay.p95 > frameBudget) {
      return StreamFinding.uiOverloaded;
    }
    // A display can't show more than its own refresh rate, whatever the cap.
    const commonRefreshHz = 60.0;
    final capHz = Duration.microsecondsPerSecond / frameBudget.inMicroseconds;
    final expectedHz = capHz < commonRefreshHz ? capHz : commonRefreshHz;
    if (fps < expectedHz * 0.75) return StreamFinding.lowFrameRate;
    if (dataGap.p95 > noticeableDataGap) return StreamFinding.dataGaps;
    return StreamFinding.noneFound;
  }
}
