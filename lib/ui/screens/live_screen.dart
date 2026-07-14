// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../boards/board_descriptor.dart';
import '../../boards/matrix_spec.dart';
import '../../boards/packet_spec.dart';
import '../../controllers/channel_controller.dart';
import '../../controllers/connection_controller.dart';
import '../../controllers/recording_controller.dart';
import '../../controllers/recordings_browser_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../recording/recording_models.dart';
import '../../theme/app_spacing.dart';
import '../../transport/transport_service.dart';
import '../widgets/colormap.dart';
import '../widgets/heatmap_view.dart';
import '../widgets/multi_channel_waveform_chart.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  ChannelController? _chart;
  String? _chartForDescriptorId;

  /// Selected colormap per matrix id (defaults from MatrixSpec).
  final Map<String, ColorMap> _matrixColorMaps = {};
  final Map<String, HeatmapScale> _matrixScales = {};
  final Map<String, bool> _matrixShowValues = {};

  /// Currently selected board command id (TMF8829: a grid-mode CommandSpec).
  /// Persists for the lifetime of the screen state.
  String? _selectedCommandId;

  ChannelController? _ensureChart(ConnectionController conn) {
    final desc = conn.descriptor!;
    if (desc.channels.isEmpty) {
      _chart?.dispose();
      _chart = null;
      _chartForDescriptorId = null;
      return null;
    }
    if (_chart == null || _chartForDescriptorId != desc.id) {
      _chart?.dispose();
      _chart = ChannelController(
        channels: desc.channels,
        buffers: conn.channelBuffers,
      );
      _chartForDescriptorId = desc.id;
    }
    return _chart;
  }

  ColorMap _colorMapFor(String matrixId, String defaultId) {
    return _matrixColorMaps[matrixId] ??= ColorMaps.byId(defaultId);
  }

  HeatmapScale _scaleFor(String matrixId) =>
      _matrixScales[matrixId] ??= HeatmapScale.auto;

  /// Default values-overlay on for small declared grids (≤ 256 cells),
  /// off for dense ones. User toggle persists per matrix.
  bool _showValuesFor(String matrixId, int declaredRows, int declaredCols) {
    return _matrixShowValues[matrixId] ??=
        (declaredRows * declaredCols) <= 256;
  }

  @override
  void dispose() {
    _chart?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conn = context.watch<ConnectionController>();
    final repaintHz = context.watch<SettingsController>().repaintHz;
    final connected = conn.status == TransportStatus.connected;

    if (!connected) {
      // Drop any prior chart controller — the descriptor is gone.
      if (_chart != null) {
        _chart?.dispose();
        _chart = null;
        _chartForDescriptorId = null;
      }
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart,
                  size: 56, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: AppSpacing.md),
              Text('Live view', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Connect a board from the Connect tab to begin streaming.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final descriptor = conn.descriptor!;
    final chart = _ensureChart(conn);
    final hasMatrices = descriptor.matrices.isNotEmpty;

    // Build the main body: chart on top (if present), heatmap(s) below.
    final bodyChildren = <Widget>[];
    if (chart != null) {
      bodyChildren.add(_Controls(chart: chart));
      bodyChildren.add(const SizedBox(height: AppSpacing.sm));
      bodyChildren.add(Expanded(
        child: MultiChannelWaveformChart(controller: chart, refreshHz: repaintHz),
      ));
      bodyChildren.add(AnimatedBuilder(
        animation: chart,
        builder: (_, __) {
          if (!chart.paused) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: _ScrubBar(chart: chart, descriptor: descriptor),
          );
        },
      ));
    }
    if (hasMatrices) {
      if (chart != null) {
        bodyChildren.add(const SizedBox(height: AppSpacing.sm));
      }
      if (descriptor.commands.isNotEmpty) {
        bodyChildren.add(_ModeBar(
          descriptor: descriptor,
          activeMatrix: descriptor.matrices.first,
          selectedId: _selectedCommandId,
          onSelected: (cmd) {
            setState(() => _selectedCommandId = cmd.id);
            conn.sendCommand(cmd);
          },
        ));
        bodyChildren.add(const SizedBox(height: AppSpacing.xs));
      }
      for (final m in descriptor.matrices) {
        final buf = conn.matrixBuffers[m.id];
        if (buf == null) continue;
        final showValues = _showValuesFor(m.id, m.rows, m.cols);
        bodyChildren.add(_MatrixControls(
          matrixId: m.id,
          colorMap: _colorMapFor(m.id, m.colorMap),
          scale: _scaleFor(m.id),
          showValues: showValues,
          onColorMap: (c) =>
              setState(() => _matrixColorMaps[m.id] = c),
          onScale: (s) => setState(() => _matrixScales[m.id] = s),
          onShowValues: (v) =>
              setState(() => _matrixShowValues[m.id] = v),
        ));
        bodyChildren.add(const SizedBox(height: AppSpacing.xs));
        bodyChildren.add(Expanded(
          flex: chart == null ? 1 : 1,
          child: HeatmapView(
            buffer: buf,
            spec: m,
            colorMap: _colorMapFor(m.id, m.colorMap),
            scaling: _scaleFor(m.id),
            showValues: showValues,
            refreshHz: repaintHz,
          ),
        ));
      }
    }
    if (bodyChildren.isEmpty) {
      bodyChildren.add(Expanded(
        child: Center(
          child: Text(
            'Connected, but the descriptor has no channels or matrices.',
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(conn: conn),
          const SizedBox(height: AppSpacing.sm),
          ...bodyChildren,
        ],
      ),
    );
  }
}

/// Renders the descriptor's `commands` (TMF8829's grid-mode commands) as a
/// SegmentedButton. Initial highlight defaults to the command whose label
/// matches the active matrix's declared `rows×cols` (so 48×32 is highlighted
/// out of the box for the TMF8829 descriptor). No command is sent until the
/// user actually picks one.
class _ModeBar extends StatelessWidget {
  final BoardDescriptor descriptor;
  final MatrixSpec activeMatrix;
  final String? selectedId;
  final void Function(CommandSpec) onSelected;

  const _ModeBar({
    required this.descriptor,
    required this.activeMatrix,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commands = descriptor.commands;
    if (commands.isEmpty) return const SizedBox.shrink();

    // Default highlight: match the active matrix's declared rows×cols
    // against each command's label. Falls back to the last command.
    final defaultLabel = '${activeMatrix.rows}×${activeMatrix.cols}';
    final activeId = selectedId ??
        (commands.firstWhere(
          (c) => c.label == defaultLabel,
          orElse: () => commands.last,
        )).id;

    // SegmentedButton renders fine up to ~4 segments. If we ever add more
    // board commands, swap to a MenuAnchor.
    return Row(
      children: [
        Icon(Icons.grid_view_outlined,
            size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Text('Mode',
            style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(width: AppSpacing.sm),
        SegmentedButton<String>(
          segments: [
            for (final c in commands)
              ButtonSegment(value: c.id, label: Text(c.label)),
          ],
          selected: {activeId},
          onSelectionChanged: (s) {
            final id = s.first;
            final cmd = commands.firstWhere((c) => c.id == id);
            onSelected(cmd);
          },
          showSelectedIcon: false,
        ),
      ],
    );
  }
}

class _MatrixControls extends StatelessWidget {
  final String matrixId;
  final ColorMap colorMap;
  final HeatmapScale scale;
  final bool showValues;
  final void Function(ColorMap) onColorMap;
  final void Function(HeatmapScale) onScale;
  final void Function(bool) onShowValues;

  const _MatrixControls({
    required this.matrixId,
    required this.colorMap,
    required this.scale,
    required this.showValues,
    required this.onColorMap,
    required this.onScale,
    required this.onShowValues,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MenuAnchor(
          builder: (ctx, controller, _) => OutlinedButton.icon(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.palette_outlined, size: 18),
            label: Text(colorMap.displayName),
          ),
          menuChildren: [
            for (final m in ColorMaps.all)
              MenuItemButton(
                onPressed: () => onColorMap(m),
                child: Text(m.displayName),
              ),
          ],
        ),
        SegmentedButton<HeatmapScale>(
          segments: const [
            ButtonSegment(
              value: HeatmapScale.auto,
              label: Text('Auto'),
              icon: Icon(Icons.auto_graph, size: 18),
            ),
            ButtonSegment(
              value: HeatmapScale.fixed,
              label: Text('Fixed'),
              icon: Icon(Icons.straighten, size: 18),
            ),
          ],
          selected: {scale},
          onSelectionChanged: (s) => onScale(s.first),
          showSelectedIcon: false,
        ),
        FilterChip(
          selected: showValues,
          onSelected: onShowValues,
          avatar: Icon(
            showValues ? Icons.grid_on : Icons.grid_off,
            size: 16,
          ),
          label: const Text('Values'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final ConnectionController conn;
  const _Header({required this.conn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descriptor = conn.descriptor!;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(descriptor.displayName, style: theme.textTheme.headlineSmall),
              Text(
                '${conn.transportKind?.name.toUpperCase()} · '
                '${conn.packetsOk} pkts · ${conn.framerErrors} errors · '
                '${conn.connectedFor.inSeconds}s',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (conn.latestEvents.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.xs,
            children: conn.latestEvents.entries
                .map((e) => Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${e.key}: ${e.value}'),
                    ))
                .toList(),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        const _RecordButton(),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: conn.disconnect,
          icon: const Icon(Icons.power_settings_new),
          label: const Text('Disconnect'),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  final ChannelController chart;
  const _Controls({required this.chart});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: chart,
      builder: (ctx, _) {
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: chart.togglePause,
              icon: Icon(chart.paused ? Icons.play_arrow : Icons.pause),
              label: Text(chart.paused ? 'Resume' : 'Pause'),
            ),
            SegmentedButton<SweepMode>(
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
            _WindowMenu(chart: chart),
          ],
        );
      },
    );
  }
}

class _WindowMenu extends StatelessWidget {
  final ChannelController chart;
  const _WindowMenu({required this.chart});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (ctx, controller, _) => OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.timer_outlined, size: 18),
        label: Text('${chart.window.inSeconds}s window'),
      ),
      menuChildren: [
        for (final w in ChannelController.presetWindows)
          MenuItemButton(
            onPressed: () => chart.window = w,
            child: Text('${w.inSeconds}s'),
          ),
      ],
    );
  }
}

class _ScrubBar extends StatelessWidget {
  final ChannelController chart;
  final dynamic descriptor;
  const _ScrubBar({required this.chart, required this.descriptor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use the slowest channel as the scrub-extent reference (gives the user
    // the most history to play with).
    final slowest = chart.channels
        .map((c) => c.sampleRateHz)
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);
    // Heuristic max scrub: 30 s buffer minus current window.
    final maxBack = (30.0 - chart.window.inSeconds.toDouble())
        .clamp(1.0, 60.0);
    // ignore: unused_local_variable
    final _ = slowest; // kept so future per-channel scrub bounds can use it

    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(Icons.fast_rewind,
                color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${chart.scrubOffsetSec.toStringAsFixed(1)}s',
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            Expanded(
              child: Slider(
                value: chart.scrubOffsetSec,
                min: -maxBack,
                max: 0,
                onChanged: (v) => chart.setScrub(v),
              ),
            ),
            Text('now',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer)),
          ],
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton();

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecordingController>();
    final theme = Theme.of(context);
    final recording = rec.state == RecordingState.recording;

    return FilledButton.icon(
      onPressed: () => recording ? _stop(context, rec) : _start(context, rec),
      style: FilledButton.styleFrom(
        backgroundColor:
            recording ? theme.colorScheme.error : theme.colorScheme.secondary,
        foregroundColor: recording
            ? theme.colorScheme.onError
            : theme.colorScheme.onSecondary,
      ),
      icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
      label: Text(recording
          ? '● ${_fmt(rec.elapsed)} · ${_kb(rec.bytesWritten)}'
          : 'Record'),
    );
  }

  Future<void> _start(BuildContext context, RecordingController rec) async {
    try {
      await rec.start();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Record failed: $e')),
        );
      }
    }
  }

  Future<void> _stop(BuildContext context, RecordingController rec) async {
    final saved = await rec.stop();
    if (!context.mounted) return;
    // Refresh the recordings browser so the new file shows up immediately
    // when the user switches to that tab.
    context.read<RecordingsBrowserController>().refresh();
    if (saved != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $saved')),
      );
    }
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  static String _kb(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
