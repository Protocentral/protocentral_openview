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

  /// Accepts either the letter string (`D`/`C`/`E`) or a small integer code the
  /// firmware may send instead (0=D, 1=C, 2=E).
  static HsClass fromAny(Object? v) {
    if (v is String) return fromKey(v);
    if (v is num) {
      switch (v.toInt()) {
        case 0:
          return HsClass.discrete;
        case 1:
          return HsClass.cumulative;
        case 2:
          return HsClass.event;
      }
    }
    return HsClass.unknown;
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

  /// Build from a `TYPES` CBOR map entry. Tolerant of the firmware sending a
  /// field with a different-than-documented CBOR type (e.g. `class` as an int
  /// code, `derived` as 0/1, numeric `key`/`unit`) — never throws on a type
  /// mismatch.
  factory HsType.fromMap(Map<String, Object?> m) {
    return HsType(
      id: _int(m['id']),
      key: _str(m['key']),
      unit: _str(m['unit']),
      scale: _int(m['scale'], 1),
      klass: HsClass.fromAny(m['class']),
      derived: _bool(m['derived']),
      healthKit: _strOrNull(m['hk']),
      healthConnect: _strOrNull(m['hc']),
    );
  }

  static int _int(Object? v, [int fallback = 0]) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static String _str(Object? v, [String fallback = '']) =>
      v == null ? fallback : v.toString();

  static String? _strOrNull(Object? v) =>
      (v == null || (v is String && v.isEmpty)) ? null : v.toString();

  static bool _bool(Object? v) =>
      v == true || v == 1 || v == '1' || v == 'true';

  /// Convert a raw fixed-point sample value to a real-unit double.
  double toReal(int value) => scale == 0 ? value.toDouble() : value / scale;

  @override
  String toString() => 'HsType(0x${id.toRadixString(16)} $key $unit /$scale)';
}
