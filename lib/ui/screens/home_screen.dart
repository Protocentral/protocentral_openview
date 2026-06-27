import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../boards/board_registry.dart';
import '../../controllers/connection_controller.dart';
import '../../controllers/recordings_browser_controller.dart';
import '../../recording/recording_file_info.dart';
import '../../theme/app_spacing.dart';
import '../../transport/transport_service.dart';
import '../app_routes.dart';

/// Dashboard home: a full-width connection hero (Connect CTA when idle, live
/// status when streaming) over a responsive row of Recent recordings + Board
/// library summary cards. The full per-board catalogue lives on the Connect
/// tab — home stays a launchpad, not a reference sheet.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Probe the recordings directory once so the Recent card has data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecordingsBrowserController>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Side-by-side secondary cards on anything wider than a phone.
        final wide = constraints.maxWidth >= 720;
        final secondary = <Widget>[
          const _RecentRecordingsCard(),
          const _BoardLibraryCard(),
        ];

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _HeroCard(conn: conn),
            const SizedBox(height: AppSpacing.lg),
            if (wide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: secondary[0]),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: secondary[1]),
                  ],
                ),
              )
            else ...[
              secondary[0],
              const SizedBox(height: AppSpacing.lg),
              secondary[1],
            ],
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Connection hero
// ─────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final ConnectionController conn;
  const _HeroCard({required this.conn});

  @override
  Widget build(BuildContext context) {
    final connected = conn.status == TransportStatus.connected;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: connected ? scheme.surfaceContainerHigh : scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: connected ? _ConnectedHero(conn: conn) : const _IdleHero(),
      ),
    );
  }
}

class _IdleHero extends StatelessWidget {
  const _IdleHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Dot(color: scheme.outline),
            const SizedBox(width: AppSpacing.sm),
            Text('Not connected',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onPrimaryContainer)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Connect a board to start streaming',
            style: theme.textTheme.headlineSmall
                ?.copyWith(color: scheme.onPrimaryContainer)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Plug in over USB, or scan for nearby BLE devices.',
          style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.scan),
              icon: const Icon(Icons.cable),
              label: const Text('Connect a board'),
            ),
            const SizedBox(width: AppSpacing.md),
            Icon(Icons.usb, size: 16, color: scheme.onPrimaryContainer),
            const SizedBox(width: AppSpacing.xs),
            Text('USB', style: theme.textTheme.labelMedium),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.bluetooth, size: 16, color: scheme.onPrimaryContainer),
            const SizedBox(width: AppSpacing.xs),
            Text('BLE', style: theme.textTheme.labelMedium),
          ],
        ),
      ],
    );
  }
}

class _ConnectedHero extends StatelessWidget {
  final ConnectionController conn;
  const _ConnectedHero({required this.conn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Dot(color: scheme.secondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${conn.descriptor?.displayName ?? 'Connected'} · '
                '${conn.transportKind?.name.toUpperCase() ?? ''}',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.xl,
          runSpacing: AppSpacing.md,
          children: [
            _Stat(label: 'Packets', value: '${conn.packetsOk}'),
            _Stat(label: 'Received', value: _fmtBytes(conn.bytesIn)),
            _Stat(label: 'Uptime', value: '${conn.connectedFor.inSeconds}s'),
            _Stat(
              label: 'Framer errors',
              value: '${conn.framerErrors}',
              emphasis: conn.framerErrors > 0,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.live),
              icon: const Icon(Icons.show_chart),
              label: const Text('Open Live'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => context.go(AppRoutes.console),
              icon: const Icon(Icons.terminal),
              label: const Text('Console'),
            ),
            OutlinedButton.icon(
              onPressed: conn.disconnect,
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Disconnect'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;
  const _Stat({required this.label, required this.value, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: emphasis ? scheme.error : scheme.onSurface,
            fontFeatures: const [],
          ),
        ),
        Text(label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Recent recordings
// ─────────────────────────────────────────────────────────────────────────

class _RecentRecordingsCard extends StatelessWidget {
  const _RecentRecordingsCard();

  @override
  Widget build(BuildContext context) {
    final browser = context.watch<RecordingsBrowserController>();
    final recent = browser.recordings.take(3).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.folder_outlined,
              title: 'Recent recordings',
              action: TextButton(
                onPressed: () => context.go(AppRoutes.recordings),
                child: const Text('All'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (browser.loading && recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (recent.isEmpty)
              _EmptyHint(
                icon: Icons.fiber_manual_record_outlined,
                text: 'No recordings yet. Connect a board and hit record on '
                    'the Live screen.',
              )
            else
              ...recent.map((r) => _RecordingTile(info: r)),
          ],
        ),
      ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  final RecordingFileInfo info;
  const _RecordingTile({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      leading: Icon(
        info.isValid ? Icons.graphic_eq : Icons.error_outline,
        color: info.isValid
            ? theme.colorScheme.primary
            : theme.colorScheme.error,
      ),
      title: Text(info.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${_relative(info.modified)} · ${info.sizeFormatted} · '
          '${info.durationFormatted}'),
      onTap: info.isValid
          ? () => context.go('${AppRoutes.replay}?file=${Uri.encodeComponent(info.file.path)}')
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Board library summary
// ─────────────────────────────────────────────────────────────────────────

class _BoardLibraryCard extends StatelessWidget {
  const _BoardLibraryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = BoardRegistry.all;
    final usb = all.where((b) => b.transports.usb).length;
    final ble = all.where((b) => b.transports.ble).length;
    final wifi = all.where((b) => b.transports.wifi).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.dashboard_customize_outlined,
              title: 'Board library',
              action: TextButton(
                onPressed: () => context.go(AppRoutes.scan),
                child: const Text('Browse'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${all.length}', style: theme.textTheme.displaySmall),
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('boards supported',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (usb > 0) _TransportStat(Icons.usb, 'USB', usb),
                if (ble > 0) _TransportStat(Icons.bluetooth, 'BLE', ble),
                if (wifi > 0) _TransportStat(Icons.wifi, 'Wi-Fi', wifi),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TransportStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  const _TransportStat(this.icon, this.label, this.count);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 14),
      label: Text('$label · $count'),
      labelStyle: theme.textTheme.labelMedium,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared bits
// ─────────────────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? action;
  const _CardHeader({required this.icon, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (action != null) action!,
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _relative(DateTime when) {
  final d = DateTime.now().difference(when);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${when.year}-${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';
}
