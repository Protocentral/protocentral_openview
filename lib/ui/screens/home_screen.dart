import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../boards/board_registry.dart';
import '../../controllers/connection_controller.dart';
import '../../theme/app_spacing.dart';
import '../../transport/transport_service.dart';
import '../app_routes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conn = context.watch<ConnectionController>();
    final connected = conn.status == TransportStatus.connected;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('OpenView', style: theme.textTheme.displaySmall),
        Text(
          'v3 alpha — desktop-first, Material 3',
          style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xl),
        _StatusCard(connected: connected, conn: conn),
        const SizedBox(height: AppSpacing.lg),
        Text('Quick actions', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.scan),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Scan for boards'),
            ),
            FilledButton.tonalIcon(
              onPressed: connected ? () => context.go(AppRoutes.console) : null,
              icon: const Icon(Icons.terminal),
              label: const Text('Open console'),
            ),
            OutlinedButton.icon(
              onPressed: connected ? conn.disconnect : null,
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Disconnect'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Supported boards (${BoardRegistry.all.length})',
            style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        ...BoardRegistry.all.map((b) => Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(b.displayName,
                              style: theme.textTheme.titleMedium),
                        ),
                        _TransportChips(
                          ble: b.transports.ble,
                          usb: b.transports.usb,
                          wifi: b.transports.wifi,
                        ),
                      ],
                    ),
                    if (b.notes.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(b.notes,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: b.channels
                          .map((c) => Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  '${c.label} · ${c.sampleRateHz.toStringAsFixed(0)} Hz',
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}

class _TransportChips extends StatelessWidget {
  final bool ble, usb, wifi;
  const _TransportChips({required this.ble, required this.usb, required this.wifi});

  @override
  Widget build(BuildContext context) {
    Widget pill(IconData i, String label) => Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(i, size: 14),
            label: Text(label),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (usb) pill(Icons.usb, 'USB'),
        if (ble) pill(Icons.bluetooth, 'BLE'),
        if (wifi) pill(Icons.wifi, 'Wi-Fi'),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool connected;
  final ConnectionController conn;
  const _StatusCard({required this.connected, required this.conn});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: connected ? scheme.tertiary : scheme.outlineVariant,
        shape: BoxShape.circle,
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            dot,
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected
                        ? '${conn.descriptor?.displayName ?? 'Connected'} · ${conn.transportKind?.name.toUpperCase() ?? ''}'
                        : 'Not connected',
                    style: theme.textTheme.titleMedium,
                  ),
                  if (connected)
                    Text(
                      '${conn.packetsOk} packets · ${conn.bytesIn} B · '
                      '${conn.connectedFor.inSeconds}s · '
                      '${conn.framerErrors} framer errors',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    )
                  else
                    Text(
                      'Scan for a board to start streaming.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
