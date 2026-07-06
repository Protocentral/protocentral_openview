/// Statistical class of a metric type (from the HPI_HS registry).
///
///  - [discrete]   D — avg / min / max (HR, SpO2, temp, HRV…)
///  - [cumulative] C — sum (steps, energy)
///  - [event]      E — sparse events (BP spot, ECG-HR)
enum HsClass {
  discrete,
  cumulative,
  event,
  unknown;

  static HsClass fromKey(String? k) {
    switch (k) {
      case 'D':
        return HsClass.discrete;
      case 'C':
        return HsClass.cumulative;
      case 'E':
        return HsClass.event;
      default:
        return HsClass.unknown;
    }
  }

  String get label => switch (this) {
        HsClass.discrete => 'discrete',
        HsClass.cumulative => 'cumulative',
        HsClass.event => 'event',
        HsClass.unknown => '?',
      };
}

/// One entry of the self-describing HPI_HS **type registry**, returned by the
/// `TYPES` command. Clients must cache these by [id] and NEVER hard-code the
/// table — the device is authoritative (see docs HPI_HS_API §4).
class HsType {
  const HsType({
    required this.id,
    required this.key,
    required this.unit,
    required this.scale,
    required this.klass,
    required this.derived,
    this.healthKit,
    this.healthConnect,
  });

  /// Metric type id (e.g. 0x01 = hr). Matches the `type` byte in a sample.
  final int id;

  /// Short machine key (e.g. `hr`, `spo2`, `skin_temp`).
  final String key;

  /// Unit string (e.g. `bpm`, `%`, `degC`).
  final String unit;

  /// Divisor to real units: `real = value / scale`.
  final int scale;

  /// Statistical class (discrete/cumulative/event).
  final HsClass klass;

  /// Whether the metric is derived (computed) rather than directly measured.
  final bool derived;

  /// Apple HealthKit quantity type identifier a bridge maps to (nullable).
  final String? healthKit;

  /// Android Health Connect record a bridge maps to (nullable).
  final String? healthConnect;

  /// Build from a `TYPES` CBOR map entry.
  factory HsType.fromMap(Map<String, Object?> m) {
    return HsType(
      id: (m['id'] as num).toInt(),
      key: m['key'] as String? ?? '',
      unit: m['unit'] as String? ?? '',
      scale: (m['scale'] as num?)?.toInt() ?? 1,
      klass: HsClass.fromKey(m['class'] as String?),
      derived: (m['derived'] as bool?) ?? false,
      healthKit: m['hk'] as String?,
      healthConnect: m['hc'] as String?,
    );
  }

  /// Convert a raw fixed-point sample value to a real-unit double.
  double toReal(int value) => scale == 0 ? value.toDouble() : value / scale;

  @override
  String toString() => 'HsType(0x${id.toRadixString(16)} $key $unit /$scale)';
}
