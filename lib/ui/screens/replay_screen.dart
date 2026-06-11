import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../controllers/channel_controller.dart';
import '../../controllers/replay_session.dart';
import '../../theme/app_spacing.dart';
import '../widgets/multi_channel_waveform_chart.dart';

class ReplayScreen extends StatefulWidget {
  /// Absolute path to the `.hpd` file.
  final String filePath;
  const ReplayScreen({super.key, required this.filePath});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  late final ReplaySession _session;
  ChannelController? _chart;

  @override
  void initState() {
    super.initState();
    _session = ReplaySession(file: File(widget.filePath));
    _session.addListener(_onSessionChanged);
    _session.load();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (_chart == null && _session.channels.isNotEmpty) {
      setState(() {
        _chart = ChannelController(
          channels: _session.channels,
          buffers: _session.buffers,
        );
      });
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _chart?.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: AnimatedBuilder(
        animation: session,
        builder: (ctx, _) {
          if (session.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (session.error != null) {
            return _ErrorView(error: session.error!);
          }
          final chart = _chart;
          if (chart == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(session: session, onClose: () => context.go('/recordings')),
              const SizedBox(height: AppSpacing.sm),
              _Controls(session: session, chart: chart),
              const SizedBox(height: AppSpacing.sm),
              Expanded(child: MultiChannelWaveformChart(controller: chart)),
              const SizedBox(height: AppSpacing.sm),
              _Seekbar(session: session),
              const SizedBox(height: 4),
              _Footer(session: session, theme: theme),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ReplaySession session;
  final VoidCallback onClose;
  const _Header({required this.session, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = session.metadata;
    final name = session.file.uri.pathSegments.last;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'REPLAY',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    m?.deviceName ?? name,
                    style: theme.textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              Text(
                name,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'JetBrainsMono'),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: onClose,
          icon: const Icon(Icons.close),
          label: const Text('Close'),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  final ReplaySession session;
  final ChannelController chart;
  const _Controls({required this.session, required this.chart});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: session.togglePlay,
          icon: Icon(session.playing ? Icons.pause : Icons.play_arrow),
          label: Text(session.playing ? 'Pause' : 'Play'),
        ),
        SegmentedButton<double>(
          segments: [
            for (final r in ReplaySession.presetRates)
              ButtonSegment(
                value: r,
                label: Text('${r}×'),
              ),
          ],
          selected: {session.rate},
          onSelectionChanged: (s) => session.setRate(s.first),
          showSelectedIcon: false,
        ),
        AnimatedBuilder(
          animation: chart,
          builder: (_, __) => SegmentedButton<SweepMode>(
            segments: const [
              ButtonSegment(
                value: SweepMode.scroll,
                label: Text('Scroll'),
                icon: Icon(Icons.swap_horiz, size: 18),
              ),
              ButtonSegment(
                value: SweepMode.sweep,
                label: Text('Sweep'),
                icon: Icon(Icons.refresh, size: 18),
              ),
            ],
            selected: {chart.sweepMode},
            onSelectionChanged: (s) => chart.sweepMode = s.first,
            showSelectedIcon: false,
          ),
        ),
      ],
    );
  }
}

class _Seekbar extends StatelessWidget {
  final ReplaySession session;
  const _Seekbar({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(_fmtDuration(session.position),
            style: theme.textTheme.labelMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()])),
        Expanded(
          child: Slider(
            value: session.normalizedPosition.clamp(0.0, 1.0),
            onChanged: (v) => session.seekNormalized(v),
          ),
        ),
        Text(_fmtDuration(session.duration),
            style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

class _Footer extends StatelessWidget {
  final ReplaySession session;
  final ThemeData theme;
  const _Footer({required this.session, required this.theme});

  @override
  Widget build(BuildContext context) {
    final m = session.metadata;
    final fw = m == null
        ? ''
        : 'fw ${m.firmwareVersion}  ·  ${m.channels.length} ch  ·  '
            '${session.baseRateHz.toStringAsFixed(0)} Hz';
    return Row(
      children: [
        Expanded(
          child: Text(fw,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
        ),
        Text(
          '${session.playhead} / ${session.totalSamples} samples',
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: theme.colorScheme.onErrorContainer),
              const SizedBox(height: AppSpacing.sm),
              Text('Could not open recording',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer)),
              const SizedBox(height: AppSpacing.xs),
              Text(error,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer)),
            ],
          ),
        ),
      ),
    );
  }
}
