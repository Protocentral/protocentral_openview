// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

/// Describes a single 1-D time-series stream from a board.
class ChannelSpec {
  final String id;
  final String label;
  final double sampleRateHz;
  final SignalUnit unit;
  final ChannelKind kind;
  final double displayMin;
  final double displayMax;
  final List<FilterPreset> defaultFilters;

  /// Starts hidden in the live view, with a toggle to show it. Mainly for
  /// diagnostic traces; the channel is still buffered and recorded.
  final bool optional;

  const ChannelSpec({
    required this.id,
    required this.label,
    required this.sampleRateHz,
    required this.unit,
    required this.kind,
    this.displayMin = -1,
    this.displayMax = 1,
    this.defaultFilters = const [],
    this.optional = false,
  });
}

enum SignalUnit {
  mv,
  uv,
  adc,
  celsius,
  ohm,
  microSiemens,
  nanoSiemens,
  percent,
  bpm,
  rpm,
  none,
}

enum ChannelKind {
  ecg,
  ppg,
  bioz,
  resp,
  temp,
  gsr,
  imu,
  eeg,
  emg,
  capacitance,
  derived,
  unknown,
}

class FilterPreset {
  final String name;
  final FilterKind kind;
  final double? cutoffLow;
  final double? cutoffHigh;
  final int order;
  final bool enabledByDefault;

  const FilterPreset({
    required this.name,
    required this.kind,
    this.cutoffLow,
    this.cutoffHigh,
    this.order = 2,
    this.enabledByDefault = false,
  });
}

enum FilterKind { lowpass, highpass, bandpass, bandstop, notch }
