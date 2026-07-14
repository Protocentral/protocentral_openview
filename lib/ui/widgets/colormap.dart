// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

/// One palette as a 256-entry RGBA lookup table.
class ColorMap {
  final String id;
  final String displayName;

  /// Length-1024 RGBA buffer (256 × 4).
  final Uint8List lut;

  const ColorMap({
    required this.id,
    required this.displayName,
    required this.lut,
  });

  /// Build a colormap from a small list of (position, R, G, B) control points,
  /// linearly interpolated to a 256-entry LUT.
  factory ColorMap.fromControlPoints({
    required String id,
    required String displayName,
    required List<({double t, int r, int g, int b})> stops,
  }) {
    assert(stops.length >= 2);
    final lut = Uint8List(256 * 4);
    int next = 1;
    for (int i = 0; i < 256; i++) {
      final t = i / 255.0;
      while (next < stops.length - 1 && t > stops[next].t) {
        next++;
      }
      final a = stops[next - 1];
      final b = stops[next];
      final span = (b.t - a.t).clamp(1e-9, 1.0);
      final f = ((t - a.t) / span).clamp(0.0, 1.0);
      lut[i * 4 + 0] = (a.r + (b.r - a.r) * f).round();
      lut[i * 4 + 1] = (a.g + (b.g - a.g) * f).round();
      lut[i * 4 + 2] = (a.b + (b.b - a.b) * f).round();
      lut[i * 4 + 3] = 255;
    }
    return ColorMap(id: id, displayName: displayName, lut: lut);
  }
}

/// Built-in colormaps. Approximations via control-point interpolation —
/// perceptually close to the matplotlib originals, ~1 kB of LUT each.
class ColorMaps {
  ColorMaps._();

  /// Default — perceptually uniform, dark-to-bright, color-blind friendly.
  static final viridis = ColorMap.fromControlPoints(
    id: 'viridis',
    displayName: 'Viridis',
    stops: const [
      (t: 0.00, r: 68, g: 1, b: 84),
      (t: 0.13, r: 71, g: 44, b: 122),
      (t: 0.25, r: 59, g: 81, b: 139),
      (t: 0.38, r: 44, g: 113, b: 142),
      (t: 0.50, r: 33, g: 144, b: 141),
      (t: 0.63, r: 39, g: 173, b: 129),
      (t: 0.75, r: 92, g: 200, b: 99),
      (t: 0.88, r: 170, g: 220, b: 50),
      (t: 1.00, r: 253, g: 231, b: 37),
    ],
  );

  /// High-contrast spectral — good for depth where you want to see structure.
  static final turbo = ColorMap.fromControlPoints(
    id: 'turbo',
    displayName: 'Turbo',
    stops: const [
      (t: 0.00, r: 48, g: 18, b: 59),
      (t: 0.10, r: 70, g: 86, b: 199),
      (t: 0.25, r: 42, g: 165, b: 234),
      (t: 0.40, r: 31, g: 220, b: 174),
      (t: 0.55, r: 122, g: 235, b: 74),
      (t: 0.70, r: 233, g: 207, b: 50),
      (t: 0.85, r: 245, g: 122, b: 51),
      (t: 1.00, r: 122, g: 4, b: 3),
    ],
  );

  /// Hot — black → red → yellow → white. Familiar from thermal imaging.
  static final hot = ColorMap.fromControlPoints(
    id: 'hot',
    displayName: 'Hot',
    stops: const [
      (t: 0.00, r: 0, g: 0, b: 0),
      (t: 0.33, r: 230, g: 0, b: 0),
      (t: 0.66, r: 255, g: 230, b: 0),
      (t: 1.00, r: 255, g: 255, b: 255),
    ],
  );

  /// Plain grayscale.
  static final grayscale = ColorMap.fromControlPoints(
    id: 'grayscale',
    displayName: 'Grayscale',
    stops: const [
      (t: 0.0, r: 0, g: 0, b: 0),
      (t: 1.0, r: 255, g: 255, b: 255),
    ],
  );

  static final List<ColorMap> all = [viridis, turbo, hot, grayscale];

  static ColorMap byId(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => viridis);
}
