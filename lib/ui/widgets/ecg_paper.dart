// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

/// Scale for drawing a channel like ECG paper: square boxes, with one large box
/// worth 0.2 s and 0.5 mV (the standard 25 mm/s and 10 mm/mV at gain ×1).
///
/// Boxes are square on screen rather than a literal 5 mm, so the time window
/// acts as the zoom. Gain changes the trace height but not the grid, as it does
/// on a real ECG machine.
class EcgPaper {
  static const double smallBoxSec = 0.04;
  static const double largeBoxSec = 0.2;
  static const double largeBoxMvAtUnityGain = 0.5;
  static const int smallBoxesPerLarge = 5;

  final double pxPerSec;
  final double countsPerMv;
  final double gain;

  const EcgPaper({
    required this.pxPerSec,
    required this.countsPerMv,
    this.gain = 1,
  });

  double get largeBoxPx => pxPerSec * largeBoxSec;
  double get smallBoxPx => pxPerSec * smallBoxSec;
  double get largeBoxMv => largeBoxMvAtUnityGain / gain;
  double get pxPerMv => largeBoxPx / largeBoxMv;
  double get pxPerCount => pxPerMv / countsPerMv;

  /// Signal value at the top of a strip of [height] with [baseline] centred.
  double maxValue(double baseline, double height) =>
      baseline + height / 2 / pxPerCount;

  /// Signal value at the bottom of a strip of [height] with [baseline] centred.
  double minValue(double baseline, double height) =>
      baseline - height / 2 / pxPerCount;

  /// Median of the non-NaN [samples]: the level the trace sits at. Unlike the
  /// midpoint of min and max, QRS peaks barely move it, and it follows slow
  /// baseline drift. Returns 0 when there are no samples.
  static double baselineOf(Float64List samples) {
    final valid = samples.where((v) => !v.isNaN).toList()..sort();
    if (valid.isEmpty) return 0;
    return valid[valid.length ~/ 2];
  }
}
