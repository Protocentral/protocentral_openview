/// A single at-a-glance summary metric (one dashboard card).
class HsSummaryCard {
  const HsSummaryCard({required this.label, required this.value, this.unit});
  final String label;
  final String value;
  final String? unit;
}

/// Typed view over the HPI_HS `SUMMARY` response.
///
/// The exact CBOR keys of `struct hpi_hs_summary` are not fully pinned in the
/// public contract, so this maps a set of **candidate keys** to friendly labels
/// and renders every other key generically — it never assumes a fixed shape.
/// Nested maps (e.g. an `hr` sub-map) are flattened one level.
class HsSummary {
  const HsSummary(this.cards, this.raw);

  final List<HsSummaryCard> cards;
  final Map<String, Object?> raw;

  /// Known keys → (label, unit). Also used to prettify nested `parent.child`.
  static const Map<String, (String, String?)> _labels = {
    'resting_hr': ('Resting HR', 'bpm'),
    'rest_hr': ('Resting HR', 'bpm'),
    'hr_min': ('HR min', 'bpm'),
    'hr_avg': ('HR avg', 'bpm'),
    'hr_mean': ('HR avg', 'bpm'),
    'hr_max': ('HR max', 'bpm'),
    'spo2': ('SpO₂', '%'),
    'spo2_avg': ('SpO₂ (overnight)', '%'),
    'spo2_overnight': ('SpO₂ (overnight)', '%'),
    'skin_temp': ('Skin temp', '°C'),
    'temp_delta': ('Temp Δ', '°C'),
    'temp_dev': ('Temp Δ', '°C'),
    'temp_nights': ('Temp baseline nights', null),
    'hrv': ('HRV', 'ms'),
    'hrv_sdnn': ('HRV SDNN', 'ms'),
    'hrv_rmssd': ('HRV RMSSD', 'ms'),
    'steps': ('Steps', null),
    'energy': ('Active energy', 'kcal'),
    'active_energy': ('Active energy', 'kcal'),
    'stress': ('Stress', null),
    'last_stress': ('Last stress', null),
    'dev': ('Device', null),
    'ts': ('Timestamp', null),
    'day': ('Day', null),
  };

  factory HsSummary.fromMap(Map<String, Object?> m) {
    final cards = <HsSummaryCard>[];

    void add(String key, Object? value) {
      if (value == null) return;
      if (value is Map) {
        // Flatten one level: key.child
        value.forEach((k, v) => add('$key.$k', v));
        return;
      }
      final base = key.contains('.') ? key.split('.').last : key;
      final match = _labels[key] ?? _labels[base];
      final label = match?.$1 ?? _humanize(key);
      final unit = match?.$2;
      cards.add(HsSummaryCard(
        label: label,
        value: _fmt(value),
        unit: unit,
      ));
    }

    m.forEach(add);
    return HsSummary(cards, m);
  }

  static String _fmt(Object? v) {
    if (v is double) {
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    }
    if (v is List) return '[${v.length}]';
    return '$v';
  }

  static String _humanize(String key) {
    final s = key.replaceAll('_', ' ').replaceAll('.', ' · ');
    return s.isEmpty ? key : s[0].toUpperCase() + s.substring(1);
  }
}
