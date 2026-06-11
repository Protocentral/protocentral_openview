import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../boards/channel_spec.dart';
import '../../controllers/channel_controller.dart';
import '../../data/channel_buffer.dart';
import '../../theme/signal_colors.dart';

/// Multi-channel waveform chart (Phase 2.B).
///
/// State (window length, sweep vs scroll, pause + scrub, per-strip Y mode)
/// lives in [ChannelController]. The widget owns the [Ticker] that drives
/// repaints and the local cursor-hover state.
class MultiChannelWaveformChart extends StatefulWidget {
  final ChannelController controller;
  final int refreshHz;
  const MultiChannelWaveformChart({
    super.key,
    required this.controller,
    this.refreshHz = 30,
  });

  @override
  State<MultiChannelWaveformChart> createState() =>
      _MultiChannelWaveformChartState();
}

class _MultiChannelWaveformChartState extends State<MultiChannelWaveformChart>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int _frameTick = 0;

  /// Normalized cursor X in [0,1], or null if not hovering.
  /// Shared across all strips so the readout time-aligns.
  double? _cursorNormalizedX;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final periodMs = 1000 ~/ widget.refreshHz;
    if ((elapsed - _lastTick).inMilliseconds < periodMs) return;
    _lastTick = elapsed;
    if (mounted) setState(() => _frameTick++);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final signals = Theme.of(context).extension<SignalColors>() ??
        SignalColors.dark;

    if (controller.channels.isEmpty) {
      return Center(
        child: Text(
          'No channels declared on this descriptor.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return LayoutBuilder(builder: (ctx, box) {
      return MouseRegion(
        onHover: (e) {
          final w = box.maxWidth;
          if (w <= 0) return;
          final nx = (e.localPosition.dx / w).clamp(0.0, 1.0);
          if (nx != _cursorNormalizedX) {
            setState(() => _cursorNormalizedX = nx);
          }
        },
        onExit: (_) => setState(() => _cursorNormalizedX = null),
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            return Column(
              children: [
                for (final spec in controller.channels)
                  if (controller.strip(spec.id).visible)
                    Expanded(
                      child: _WaveformStrip(
                        spec: spec,
                        controller: controller,
                        color: _traceColor(spec.kind, signals),
                        gridColor: signals.gridLine,
                        labelColor: signals.axisLabel,
                        cursorColor: signals.cursor,
                        frameTick: _frameTick,
                        cursorNormalizedX: _cursorNormalizedX,
                      ),
                    ),
              ],
            );
          },
        ),
      );
    });
  }

  Color _traceColor(ChannelKind kind, SignalColors c) {
    switch (kind) {
      case ChannelKind.ecg:
        return c.ecg;
      case ChannelKind.ppg:
        return c.ppg;
      case ChannelKind.bioz:
        return c.bioz;
      case ChannelKind.resp:
        return c.resp;
      case ChannelKind.temp:
        return c.temp;
      case ChannelKind.gsr:
        return c.gsr;
      case ChannelKind.imu:
        return c.imuX;
      case ChannelKind.eeg:
        return c.eeg;
      case ChannelKind.capacitance:
        return c.ppgIr;
      case ChannelKind.derived:
      case ChannelKind.unknown:
        return c.axisLabel;
    }
  }
}

class _WaveformStrip extends StatelessWidget {
  final ChannelSpec spec;
  final ChannelController controller;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final Color cursorColor;
  final int frameTick;
  final double? cursorNormalizedX;

  const _WaveformStrip({
    required this.spec,
    required this.controller,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.cursorColor,
    required this.frameTick,
    required this.cursorNormalizedX,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buffer = controller.buffers[spec.id];
    final paused = controller.paused;
    final visibleSamples = controller.visibleSamples(spec);
    final sweep = controller.sweepMode == SweepMode.sweep && !paused;
    final endingAt = controller.endingSampleIndex(spec);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: buffer == null
            ? Center(child: Text('${spec.label} — no buffer'))
            : Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _WaveformPainter(
                          buffer: buffer,
                          visibleSamples: visibleSamples,
                          endingSampleIndex: endingAt,
                          sweepMode: sweep,
                          color: color,
                          gridColor: gridColor,
                          cursorColor: cursorColor,
                          cursorNormalizedX: cursorNormalizedX,
                          stripState: controller.strip(spec.id),
                          frameTick: frameTick,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 8,
                    child: _LabelBadge(
                      text: '${spec.label} · '
                          '${spec.sampleRateHz.toStringAsFixed(0)} Hz'
                          '${paused ? "  ⏸" : ""}'
                          '${sweep ? "  ↻" : ""}',
                      color: color,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 8,
                    child: _ValueBadge(
                      buffer: buffer,
                      visibleSamples: visibleSamples,
                      endingSampleIndex: endingAt,
                      cursorNormalizedX: cursorNormalizedX,
                      color: labelColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final ChannelBuffer buffer;
  final int visibleSamples;
  final int endingSampleIndex;
  final bool sweepMode;
  final Color color;
  final Color gridColor;
  final Color cursorColor;
  final double? cursorNormalizedX;
  final StripState stripState;
  final int frameTick;

  // Reused scratch buffers keyed by sample count.
  static final Map<int, Float64List> _scratch = {};

  _WaveformPainter({
    required this.buffer,
    required this.visibleSamples,
    required this.endingSampleIndex,
    required this.sweepMode,
    required this.color,
    required this.gridColor,
    required this.cursorColor,
    required this.cursorNormalizedX,
    required this.stripState,
    required this.frameTick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 2 || size.height < 2) return;

    final samples = _scratch.putIfAbsent(
        visibleSamples, () => Float64List(visibleSamples));

    final valid = buffer.copyWindow(samples, visibleSamples,
        endingAt: endingSampleIndex);

    // Grid
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), gridPaint);
    final faint = Paint()
      ..color = gridColor.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (int g = 1; g < 5; g++) {
      final x = size.width * g / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), faint);
    }

    if (valid < 2) return;

    // Determine Y range.
    double minV, maxV;
    if (stripState.yMode == YMode.manual &&
        stripState.yMin != null &&
        stripState.yMax != null) {
      minV = stripState.yMin!;
      maxV = stripState.yMax!;
    } else {
      minV = double.infinity;
      maxV = double.negativeInfinity;
      for (int i = 0; i < visibleSamples; i++) {
        final v = samples[i];
        if (v.isNaN) continue;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
      if (!minV.isFinite || !maxV.isFinite) return;
      double range = maxV - minV;
      if (range < 1e-9) range = 1;
      final pad = range * 0.08;
      minV -= pad;
      maxV += pad;
    }
    double range = maxV - minV;
    if (range < 1e-9) range = 1;

    final tracePaint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset toScreen(int chronoIdx, double v) {
      final double xFrac;
      if (sweepMode) {
        // Newest sample sits at the sweep-head position; older samples
        // wrap around to the left of the head. Sweep head moves left-to-
        // right then wraps.
        // sweepHead position (in [0, visibleSamples-1]) for the newest valid sample:
        final newestIdx = visibleSamples - 1; // chronologically newest in window
        final head = endingSampleIndex % visibleSamples;
        final offsetFromNewest = newestIdx - chronoIdx; // 0 for newest
        int sx = head - offsetFromNewest;
        sx = ((sx % visibleSamples) + visibleSamples) % visibleSamples;
        xFrac = sx / (visibleSamples - 1);
      } else {
        xFrac = chronoIdx / (visibleSamples - 1);
      }
      final x = size.width * xFrac;
      final y = size.height - ((v - minV) / range) * size.height;
      return Offset(x, y);
    }

    // Build path(s). In sweep mode the screen-X mapping wraps, so we break
    // the path at wraps to avoid a long diagonal connecting line.
    final path = Path();
    double? lastX;
    bool started = false;
    for (int i = 0; i < visibleSamples; i++) {
      final v = samples[i];
      if (v.isNaN) {
        started = false;
        continue;
      }
      final p = toScreen(i, v);
      final lx = lastX;
      if (!started || (lx != null && (p.dx - lx).abs() > size.width * 0.5)) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
      lastX = p.dx;
    }
    canvas.drawPath(path, tracePaint);

    // Sweep head indicator
    if (sweepMode) {
      final head = endingSampleIndex % visibleSamples;
      final hx = size.width * head / (visibleSamples - 1);
      final headPaint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(hx, 0), Offset(hx, size.height), headPaint);
    }

    // Cursor
    final cx = cursorNormalizedX;
    if (cx != null) {
      final x = size.width * cx;
      final cursorPaint = Paint()
        ..color = cursorColor.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), cursorPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.frameTick != frameTick ||
      old.color != color ||
      old.visibleSamples != visibleSamples ||
      old.endingSampleIndex != endingSampleIndex ||
      old.sweepMode != sweepMode ||
      old.cursorNormalizedX != cursorNormalizedX;
}

class _LabelBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _LabelBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, color: color),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Right-edge value badge.
/// - Cursor not hovering: shows the latest sample.
/// - Cursor hovering: shows the value at cursor X in chronological window.
class _ValueBadge extends StatelessWidget {
  final ChannelBuffer buffer;
  final int visibleSamples;
  final int endingSampleIndex;
  final double? cursorNormalizedX;
  final Color color;

  const _ValueBadge({
    required this.buffer,
    required this.visibleSamples,
    required this.endingSampleIndex,
    required this.cursorNormalizedX,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scratch = Float64List(visibleSamples);
    buffer.copyWindow(scratch, visibleSamples, endingAt: endingSampleIndex);
    double value;
    final cx = cursorNormalizedX;
    if (cx != null) {
      final idx = (cx * (visibleSamples - 1)).round();
      value = scratch[idx.clamp(0, visibleSamples - 1)];
    } else {
      value = scratch[visibleSamples - 1];
    }
    final text = value.isNaN
        ? '—'
        : (value.abs() >= 1e6
            ? value.toStringAsExponential(2)
            : value.toStringAsFixed(1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}
