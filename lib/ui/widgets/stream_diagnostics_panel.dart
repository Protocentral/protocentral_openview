// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../controllers/stream_diagnostics.dart';
import '../../theme/app_spacing.dart';
import '../../theme/signal_colors.dart';

/// Live timings for working out why streaming looks uneven on a given machine.
///
/// It lives on the Live screen because that's what it measures: screens aren't
/// kept mounted, so from anywhere else the chart wouldn't be drawing at all.
/// Measuring only happens while the panel is open.
class StreamDiagnosticsPanel extends StatefulWidget {
  final Duration frameBudget;

  /// Connects the panel to incoming chunks; passed null on dispose.
  final void Function(void Function(int bytes)? onChunk) attachChunks;

  /// Describes the machine and session for the copied report.
  final String Function() describeSetup;

  const StreamDiagnosticsPanel({
    super.key,
    required this.frameBudget,
    required this.attachChunks,
    required this.describeSetup,
  });

  @override
  State<StreamDiagnosticsPanel> createState() => _StreamDiagnosticsPanelState();
}

class _StreamDiagnosticsPanelState extends State<StreamDiagnosticsPanel> {
  static const _probeInterval = Duration(milliseconds: 10);
  static const _displayInterval = Duration(seconds: 1);

  final _diagnostics = StreamDiagnostics();
  final _sinceProbe = Stopwatch();
  late final Timer _probe;
  late final Timer _display;
  late StreamDiagnosticsSnapshot _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _diagnostics.snapshot(frameBudget: widget.frameBudget);
    widget.attachChunks(_diagnostics.recordChunk);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _sinceProbe.start();
    _probe = Timer.periodic(_probeInterval, (_) {
      final late = _sinceProbe.elapsed - _probeInterval;
      _sinceProbe
        ..reset()
        ..start();
      _diagnostics.recordUiDelay(late.isNegative ? Duration.zero : late);
    });
    _display = Timer.periodic(_displayInterval, (_) {
      setState(() {
        _snapshot = _diagnostics.snapshot(frameBudget: widget.frameBudget);
      });
    });
  }

  @override
  void dispose() {
    _probe.cancel();
    _display.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    widget.attachChunks(null);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _diagnostics.recordFrame(build: t.buildDuration, raster: t.rasterDuration);
    }
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(
        ClipboardData(text: _snapshot.report(widget.describeSetup())));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Performance report copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final signals = theme.extension<SignalColors>() ?? SignalColors.dark;
    final s = _snapshot;

    final (IconData icon, Color color) = switch (s.finding) {
      StreamFinding.collecting => (Icons.hourglass_empty, scheme.onSurfaceVariant),
      StreamFinding.noneFound => (Icons.check_circle, signals.qualityGood),
      _ => (Icons.warning_amber, signals.qualityWarn),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _Stat('Frames', '${s.framesPerSecond.toStringAsFixed(0)} fps'),
              _Stat('Build p95', _ms(s.build.p95)),
              _Stat('Raster p95', _ms(s.raster.p95)),
              _Stat('UI delay p95', _ms(s.uiDelay.p95)),
              _Stat('Data gap p95 / max',
                  '${_ms(s.dataGap.p95)} / ${_ms(s.dataGap.max)}'),
              _Stat('Frame budget', _ms(widget.frameBudget)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  s.findingText,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
              TextButton.icon(
                onPressed: _copyReport,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy report'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _ms(Duration d) =>
      '${(d.inMicroseconds / 1000).toStringAsFixed(1)} ms';
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: theme.textTheme.labelLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
