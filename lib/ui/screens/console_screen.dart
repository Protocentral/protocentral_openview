import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/connection_controller.dart';
import '../../theme/app_spacing.dart';
import '../../transport/transport_service.dart';

class ConsoleScreen extends StatelessWidget {
  const ConsoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conn = context.watch<ConnectionController>();
    final connected = conn.status == TransportStatus.connected;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Console', style: theme.textTheme.headlineMedium),
              ),
              OutlinedButton.icon(
                onPressed: connected ? conn.clearConsole : null,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Counters(conn: conn, connected: connected),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: conn.console.isEmpty
                    ? Center(
                        child: Text(
                          connected
                              ? 'Waiting for packets…'
                              : 'Not connected. Open Scan and connect a board.',
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        itemCount: conn.console.length,
                        itemBuilder: (_, i) {
                          final e = conn.console[conn.console.length - 1 - i];
                          return _ConsoleLine(entry: e);
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Counters extends StatelessWidget {
  final ConnectionController conn;
  final bool connected;
  const _Counters({required this.conn, required this.connected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(IconData icon, String label, String value) => Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    Text(value,
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ])),
                  ],
                ),
              ],
            ),
          ),
        );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        tile(Icons.check_circle_outline, 'Packets', '${conn.packetsOk}'),
        tile(Icons.help_outline, 'Unknown', '${conn.packetsUnknown}'),
        tile(Icons.error_outline, 'Errors', '${conn.framerErrors}'),
        tile(Icons.download_outlined, 'Bytes in', _formatBytes(conn.bytesIn)),
        tile(Icons.timer_outlined, 'Uptime',
            connected ? '${conn.connectedFor.inSeconds}s' : '—'),
      ],
    );
  }

  String _formatBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _ConsoleLine extends StatelessWidget {
  final ConsoleEntry entry;
  const _ConsoleLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color kindColor(String kind) {
      switch (kind) {
        case 'event':
          return scheme.tertiary;
        case 'unknown':
          return scheme.secondary;
        case 'error':
          return scheme.error;
        case 'status':
          return scheme.primary;
        default:
          return scheme.onSurfaceVariant;
      }
    }

    const mono = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 12,
      height: 1.4,
    );
    final t = entry.when;
    final ts = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
      child: RichText(
        text: TextSpan(
          style: mono.copyWith(color: scheme.onSurface),
          children: [
            TextSpan(
              text: '$ts  ',
              style: mono.copyWith(color: scheme.onSurfaceVariant),
            ),
            TextSpan(
              text: entry.kind.padRight(8),
              style: mono.copyWith(color: kindColor(entry.kind)),
            ),
            const TextSpan(text: '  '),
            TextSpan(text: entry.text),
          ],
        ),
      ),
    );
  }
}
