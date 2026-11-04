// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

/// Describes a scalar event the live view shows as a large readout beside the
/// chart, instead of a plain `key: value` chip in the header.
///
/// Readouts sit next to the chart, so only boards with channels declare them.
class MetricSpec {
  /// Key in [DecodedPacket.events] this readout displays.
  final String eventKey;
  final String label;
  final MetricKind kind;
  final String unit;
  final int fractionDigits;

  /// The firmware sends 0 for "no reading yet", so show a placeholder instead.
  final bool zeroMeansNoData;

  /// Event that reports signal quality for this value (0 = OK). The value is
  /// dimmed while that event is non-zero, because it may be out of date.
  final String? qualityEventKey;

  /// Text for each value of a coded event. When set, the readout shows the
  /// matching state rather than a number.
  final Map<int, MetricState> states;

  const MetricSpec({
    required this.eventKey,
    required this.label,
    required this.kind,
    this.unit = '',
    this.fractionDigits = 0,
    this.zeroMeansNoData = false,
    this.qualityEventKey,
    this.states = const {},
  });
}

class MetricState {
  final String label;
  final MetricSeverity severity;

  const MetricState(this.label, this.severity);
}

enum MetricKind { heartRate, respRate, spo2, temperature, effort, signalStatus }

enum MetricSeverity { ok, warning, error }

// Vitals shared across boards. Declare one only after confirming the board's
// firmware really sends it: several decoders name fields the sketches leave
// empty. All of these use 0 for "no reading".

const heartRateMetric = MetricSpec(
  eventKey: 'heartRate',
  label: 'Heart rate',
  kind: MetricKind.heartRate,
  unit: 'bpm',
  zeroMeansNoData: true,
);

const respRateMetric = MetricSpec(
  eventKey: 'respRate',
  label: 'Respiration',
  kind: MetricKind.respRate,
  unit: 'br/min',
  zeroMeansNoData: true,
);

const spo2Metric = MetricSpec(
  eventKey: 'spo2',
  label: 'SpO₂',
  kind: MetricKind.spo2,
  unit: '%',
  zeroMeansNoData: true,
);

const temperatureMetric = MetricSpec(
  eventKey: 'temperature',
  label: 'Temperature',
  kind: MetricKind.temperature,
  unit: '°C',
  fractionDigits: 1,
  zeroMeansNoData: true,
);
