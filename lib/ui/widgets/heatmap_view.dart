// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../boards/matrix_spec.dart';
import '../../data/matrix_buffer.dart';
import 'colormap.dart';

enum HeatmapScale {
  /// Map (min, max) of the current frame to (0, 255).
  auto,

  /// Use `MatrixSpec.minValue` / `MatrixSpec.maxValue`.
  fixed,
}

/// Renders a [MatrixBuffer] as a heatmap.
///
/// One [Ticker]-driven 30 Hz upload pipeline:
///   buffer.latest → uint16 pixels → scale → colormap LUT → RGBA → ui.Image
///
/// The image is rendered via [RawImage] so Flutter's normal compositor handles
/// resize / filterQuality. An overlay [CustomPaint] draws cell borders and
/// numeric values (when [showValues] is on and cells are large enough),
/// plus a crosshair when the cursor is hovering.
class HeatmapView extends StatefulWidget {
  final MatrixBuffer buffer;
  final MatrixSpec spec;
  final ColorMap colorMap;
  final HeatmapScale scaling;
  final int refreshHz;
  final FilterQuality filterQuality;
  final bool showValues;

  const HeatmapView({
    super.key,
    required this.buffer,
    required this.spec,
    required this.colorMap,
    this.scaling = HeatmapScale.auto,
    this.refreshHz = 30,
    this.filterQuality = FilterQuality.low,
    this.showValues = false,
  });

  @override
  State<HeatmapView> createState() => _HeatmapViewState();
}

class _HeatmapViewState extends State<HeatmapView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  ui.Image? _image;
  int _lastFrameSerial = -1;
  double _displayMin = 0;
  double _displayMax = 1;
  Offset? _cursorLocal;
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final periodMs = 1000 ~/ widget.refreshHz;
    if ((elapsed - _lastTick).inMilliseconds < periodMs) return;
    _lastTick = elapsed;
    final serial = widget.buffer.totalWritten;
    if (serial == _lastFrameSerial) return;
    final frame = widget.buffer.latest;
    if (frame == null) return;
    _lastFrameSerial = serial;
    _rebuildImage(frame);
  }

  Future<void> _rebuildImage(MatrixFrame frame) async {
    final rgba = _buildRgba(frame);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      frame.cols,
      frame.rows,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    final img = await completer.future;
    if (!mounted) {
      img.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = img;
    });
  }

  Uint8List _buildRgba(MatrixFrame frame) {
    final n = frame.pixelCount;
    double minV;
    double maxV;
    switch (widget.scaling) {
      case HeatmapScale.fixed:
        minV = widget.spec.minValue;
        maxV = widget.spec.maxValue;
        break;
      case HeatmapScale.auto:
        minV = double.infinity;
        maxV = double.negativeInfinity;
        for (int i = 0; i < n; i++) {
          final v = frame.data[i].toDouble();
          if (v == 0) continue; // treat 0 (no return) as transparent-equivalent
          if (v < minV) minV = v;
          if (v > maxV) maxV = v;
        }
        if (!minV.isFinite || !maxV.isFinite) {
          minV = 0;
          maxV = 1;
        }
        if (maxV - minV < 1e-9) maxV = minV + 1;
        break;
    }
    _displayMin = minV;
    _displayMax = maxV;

    final lut = widget.colorMap.lut;
    final span = maxV - minV;
    final rgba = Uint8List(n * 4);
    for (int i = 0; i < n; i++) {
      final raw = frame.data[i];
      if (raw == 0) {
        rgba[i * 4 + 0] = 0;
        rgba[i * 4 + 1] = 0;
        rgba[i * 4 + 2] = 0;
        rgba[i * 4 + 3] = 255;
        continue;
      }
      double t = (raw.toDouble() - minV) / span;
      if (t < 0) t = 0;
      if (t > 1) t = 1;
      final idx = (t * 255).round() * 4;
      rgba[i * 4 + 0] = lut[idx + 0];
      rgba[i * 4 + 1] = lut[idx + 1];
      rgba[i * 4 + 2] = lut[idx + 2];
      rgba[i * 4 + 3] = 255;
    }
    return rgba;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = widget.spec;
    final image = _image;
    final frame = widget.buffer.latest;

    return LayoutBuilder(builder: (ctx, box) {
      _lastSize = box.biggest;
      return MouseRegion(
        onHover: (e) => setState(() => _cursorLocal = e.localPosition),
        onExit: (_) => setState(() => _cursorLocal = null),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                RawImage(
                  image: image,
                  fit: BoxFit.fill,
                  filterQuality: widget.filterQuality,
                )
              else
                Center(
                  child: Text(
                    'Waiting for frames…',
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              if (widget.showValues && frame != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GridValuesPainter(
                      frame: frame,
                      colorMap: widget.colorMap,
                      displayMin: _displayMin,
                      displayMax: _displayMax,
                      gridColor: theme.colorScheme.onSurface,
                      serial: _lastFrameSerial,
                    ),
                  ),
                ),
              if (_cursorLocal != null && frame != null)
                CustomPaint(
                  painter: _CrosshairPainter(
                    cursor: _cursorLocal!,
                    cols: frame.cols,
                    rows: frame.rows,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              Positioned(
                top: 6,
                left: 8,
                child: _Badge(
                  text: frame == null
                      ? '${spec.label} · waiting'
                      : '${spec.label} · ${frame.cols}×${frame.rows} · '
                          '${widget.colorMap.displayName}',
                  scheme: theme.colorScheme,
                ),
              ),
              Positioned(
                top: 6,
                right: 8,
                child: _Badge(
                  text: frame == null
                      ? 'range —'
                      : 'range ${_displayMin.toStringAsFixed(0)} – '
                          '${_displayMax.toStringAsFixed(0)} mm',
                  scheme: theme.colorScheme,
                ),
              ),
              if (_cursorLocal != null && frame != null && _lastSize != null)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: _Badge(
                    text: _cursorReadout(frame),
                    scheme: theme.colorScheme,
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  String _cursorReadout(MatrixFrame frame) {
    final size = _lastSize;
    final cur = _cursorLocal;
    if (size == null || cur == null) return '';
    final cx = (cur.dx / size.width * frame.cols)
        .floor()
        .clamp(0, frame.cols - 1);
    final ry = (cur.dy / size.height * frame.rows)
        .floor()
        .clamp(0, frame.rows - 1);
    final v = frame.data[ry * frame.cols + cx];
    final mm = v == 0 ? '—' : '$v mm';
    return '($cx, $ry)  $mm';
  }
}

/// Draws thin cell borders and the numeric distance value inside each cell.
///
/// Skips drawing on cells smaller than ~28×18 px (text would be illegible);
/// at 8×8 / 16×16 grids this is fine, at 48×32 it auto-suppresses the text
/// and just shows borders.
///
/// Text color picks black or white based on the cell color's luminance so
/// the digits stay readable across the whole colormap.
class _GridValuesPainter extends CustomPainter {
  final MatrixFrame frame;
  final ColorMap colorMap;
  final double displayMin;
  final double displayMax;
  final Color gridColor;
  final int serial;

  _GridValuesPainter({
    required this.frame,
    required this.colorMap,
    required this.displayMin,
    required this.displayMax,
    required this.gridColor,
    required this.serial,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final cellW = size.width / frame.cols;
    final cellH = size.height / frame.rows;

    // Cell borders.
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.18)
      ..strokeWidth = 0.5;
    for (int c = 1; c < frame.cols; c++) {
      final x = c * cellW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (int r = 1; r < frame.rows; r++) {
      final y = r * cellH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Skip text when cells are too small to read.
    if (cellW < 28 || cellH < 18) return;

    final fontSize = (cellH * 0.34).clamp(8.0, 14.0);
    final span = (displayMax - displayMin) < 1e-9
        ? 1.0
        : (displayMax - displayMin);
    final lut = colorMap.lut;

    for (int r = 0; r < frame.rows; r++) {
      for (int c = 0; c < frame.cols; c++) {
        final v = frame.data[r * frame.cols + c];
        if (v == 0) continue; // no-return: skip text on the black cell

        // Cell brightness from the LUT entry that was used to color it.
        double t = (v.toDouble() - displayMin) / span;
        if (t < 0) t = 0;
        if (t > 1) t = 1;
        final idx = (t * 255).round() * 4;
        final lr = lut[idx];
        final lg = lut[idx + 1];
        final lb = lut[idx + 2];
        final luma = 0.299 * lr + 0.587 * lg + 0.114 * lb;
        final textColor = luma > 140 ? Colors.black : Colors.white;

        final tp = TextPainter(
          text: TextSpan(
            text: _fmt(v),
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: cellW);
        final tx = c * cellW + (cellW - tp.width) / 2;
        final ty = r * cellH + (cellH - tp.height) / 2;
        tp.paint(canvas, Offset(tx, ty));
      }
    }
  }

  /// Compact mm formatting: 0..999 → "n", 1000..9999 → "n.nk", >=10k → "nk".
  static String _fmt(int v) {
    if (v < 1000) return '$v';
    if (v < 10000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '${(v / 1000).round()}k';
  }

  @override
  bool shouldRepaint(_GridValuesPainter old) =>
      old.serial != serial ||
      old.colorMap.id != colorMap.id ||
      old.displayMin != displayMin ||
      old.displayMax != displayMax ||
      old.gridColor != gridColor;
}

class _CrosshairPainter extends CustomPainter {
  final Offset cursor;
  final int cols;
  final int rows;
  final Color color;

  _CrosshairPainter({
    required this.cursor,
    required this.cols,
    required this.rows,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    // Snap to pixel-cell centers so the crosshair feels like a pointer to
    // the cell value (rather than a free-floating line).
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final cx = ((cursor.dx / cellW).floor() + 0.5) * cellW;
    final cy = ((cursor.dy / cellH).floor() + 0.5) * cellH;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) =>
      old.cursor != cursor ||
      old.cols != cols ||
      old.rows != rows ||
      old.color != color;
}

class _Badge extends StatelessWidget {
  final String text;
  final ColorScheme scheme;
  const _Badge({required this.text, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 11,
          fontFamily: 'JetBrainsMono',
        ),
      ),
    );
  }
}
