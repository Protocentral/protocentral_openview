// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../boards/metric_spec.dart';
import '../../boards/packet_spec.dart';
import '../../theme/app_spacing.dart';
import '../../theme/signal_colors.dart';

/// Places a board's readouts beside [child] (the chart), the way a patient
/// monitor does, or above it when there isn't the width. Boards that declare
/// no metrics get [child] unchanged.
class MetricsLayout extends StatelessWidget {
  /// Below this the chart needs the full width.
  static const double sideBySideMinWidth = 720;
  static const double _panelWidth = 184;

  final List<MetricSpec> metrics;

  /// Returns the current events; empty when there is no live reading.
  final ValueGetter<Map<String, num>> read;

  /// Sends a readout's [MetricSpec.action]. Without it, actions aren't shown.
  final ValueChanged<CommandSpec>? onCommand;
  final Widget child;

  const MetricsLayout({
    super.key,
    required this.metrics,
    required this.read,
    this.onCommand,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return child;
    return LayoutBuilder(
      builder: (_, constraints) {
        final panel = _MetricsPanel(
          metrics: metrics,
          read: read,
          onCommand: onCommand,
          width: constraints.maxWidth,
          vertical: constraints.maxWidth >= sideBySideMinWidth,
        );
        if (constraints.maxWidth >= sideBySideMinWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(width: _panelWidth, child: panel),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            panel,
            const SizedBox(height: AppSpacing.xs),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _MetricsPanel extends StatefulWidget {
  final List<MetricSpec> metrics;
  final ValueGetter<Map<String, num>> read;
  final ValueChanged<CommandSpec>? onCommand;
  final double width;
  final bool vertical;

  const _MetricsPanel({
    required this.metrics,
    required this.read,
    required this.onCommand,
    required this.width,
    required this.vertical,
  });

  @override
  State<_MetricsPanel> createState() => _MetricsPanelState();
}

class _MetricsPanelState extends State<_MetricsPanel> {
  /// Events arrive with every packet, too fast to read if drawn as they come.
  /// Polling also lets the readouts clear when the stream stops, when nothing
  /// else would trigger a rebuild.
  static const _refreshInterval = Duration(milliseconds: 250);

  /// Narrower tiles can't fit a label such as "Temperature" on one line.
  static const double _minTileWidth = 150;

  late Map<String, num> _values;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _values = Map.of(widget.read());
    _timer = Timer.periodic(_refreshInterval, (_) {
      final next = widget.read();
      if (!mapEquals(next, _values)) setState(() => _values = Map.of(next));
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final m in widget.metrics)
        _MetricTile(
          spec: m,
          values: _values,
          compact: !widget.vertical,
          onCommand: widget.onCommand,
        ),
    ];
    if (widget.vertical) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                tile,
              ],
            ],
          ),
        ),
      );
    }
    final perRow =
        (widget.width / _minTileWidth).floor().clamp(1, tiles.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < tiles.length; start += perRow) ...[
          if (start > 0) const SizedBox(height: AppSpacing.xs),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, tile) in tiles.skip(start).take(perRow).indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: tile),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final MetricSpec spec;
  final Map<String, num> values;
  final bool compact;
  final ValueChanged<CommandSpec>? onCommand;

  const _MetricTile({
    required this.spec,
    required this.values,
    required this.compact,
    required this.onCommand,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final signals = theme.extension<SignalColors>() ?? SignalColors.dark;
    return Container(
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            spec.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (spec.states.isEmpty)
            _value(theme, signals)
          else
            _state(theme, signals),
          if (_aboveWarning)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                spec.warnAboveText ?? 'Higher than expected',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: signals.qualityWarn),
              ),
            ),
          if (spec.action != null && onCommand != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: OutlinedButton(
                onPressed: () => onCommand!(spec.action!),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(spec.action!.label),
              ),
            ),
        ],
      ),
    );
  }

  /// The reading is above [MetricSpec.warnAbove].
  bool get _aboveWarning {
    final limit = spec.warnAbove;
    final raw = values[spec.eventKey];
    return limit != null && raw != null && raw > limit;
  }

  Widget _value(ThemeData theme, SignalColors signals) {
    final scheme = theme.colorScheme;
    final raw = values[spec.eventKey];
    final hasReading = raw != null && !(spec.zeroMeansNoData && raw == 0);
    final text = hasReading ? raw.toStringAsFixed(spec.fractionDigits) : '--';
    final qualityKey = spec.qualityEventKey;
    final suspect = qualityKey != null && (values[qualityKey] ?? 0) != 0;

    final Color color;
    if (!hasReading) {
      color = scheme.onSurfaceVariant;
    } else {
      final base = switch (spec.kind) {
        MetricKind.heartRate => signals.ecg,
        MetricKind.respRate => signals.resp,
        MetricKind.spo2 => signals.ppg,
        MetricKind.temperature => signals.temp,
        MetricKind.effort => signals.eeg,
        MetricKind.signalStatus => scheme.onSurface,
      };
      final shown = _aboveWarning ? signals.qualityWarn : base;
      color = suspect ? shown.withValues(alpha: 0.4) : shown;
    }

    return Semantics(
      label: hasReading
          ? '${spec.label} $text ${spec.unit}'
          : '${spec.label}, no reading',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              text,
              style: theme.textTheme.displayMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                // Keeps the digits from shifting as the value changes.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (spec.unit.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                spec.unit,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _state(ThemeData theme, SignalColors signals) {
    final scheme = theme.colorScheme;
    final raw = values[spec.eventKey];
    final state = spec.states[raw];

    final String text;
    final IconData icon;
    final Color color;
    if (raw == null) {
      text = 'No data';
      icon = Icons.remove_circle_outline;
      color = scheme.onSurfaceVariant;
    } else if (state == null) {
      text = 'Unknown ($raw)';
      icon = Icons.help_outline;
      color = signals.qualityWarn;
    } else {
      text = state.label;
      (icon, color) = switch (state.severity) {
        MetricSeverity.ok => (Icons.check_circle, signals.qualityGood),
        MetricSeverity.warning => (Icons.warning_amber, signals.qualityWarn),
        MetricSeverity.error => (Icons.error, signals.qualityBad),
      };
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
