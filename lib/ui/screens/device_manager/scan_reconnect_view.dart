// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

part of 'device_manager_screen.dart';

// Scan (disconnected) + reconnecting views
// ---------------------------------------------------------------------------
// Scan view (disconnected)
// ---------------------------------------------------------------------------

class _ScanView extends StatelessWidget {
  final SmpController smp;
  const _ScanView({required this.smp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = smp.devices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: smp.connecting
                  ? null
                  : (smp.scanning ? smp.stopScan : smp.startScan),
              icon: smp.scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: Text(smp.scanning ? 'Stop scan' : 'Scan'),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: smp.loadingSystem ? null : smp.refreshSystemDevices,
              icon: smp.loadingSystem
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.devices_other),
              label: const Text('System devices'),
            ),
            const Spacer(),
            if (smp.connecting)
              Row(
                children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Connecting…', style: theme.textTheme.labelMedium),
                ],
              )
            else
              Text('${devices.length} found',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        if (smp.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _ErrorBanner(text: smp.error!),
        ],
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: devices.isEmpty
              ? _EmptyHint(
                  icon: smp.scanning
                      ? Icons.bluetooth_searching
                      : Icons.dns_outlined,
                  text: smp.scanning
                      ? 'Scanning for BLE devices…'
                      : 'Tap Scan to find SMP-enabled devices. The SMP service '
                          'is not advertised, so all BLE devices are listed — '
                          'we verify SMP support on connect.',
                )
              : ListView.separated(
                  itemCount: devices.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (_, i) => _DeviceTile(
                    target: devices[i],
                    enabled: !smp.connecting,
                    onConnect: () =>
                        smp.connect(devices[i].deviceId, name: devices[i].name),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final SmpScanTarget target;
  final bool enabled;
  final VoidCallback onConnect;
  const _DeviceTile({
    required this.target,
    required this.enabled,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(target.isSystemDevice ? Icons.link : Icons.bluetooth,
              color: theme.colorScheme.primary, size: 20),
        ),
        title: Text(target.displayName,
            overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
        subtitle: Text(target.deviceId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (target.rssi != null)
              Text('${target.rssi} dBm',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: enabled ? onConnect : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reconnecting view — shown after an unexpected drop while auto-retrying
// ---------------------------------------------------------------------------

class _ReconnectingView extends StatelessWidget {
  final SmpController smp;
  const _ReconnectingView({required this.smp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 32, height: 32, child: CircularProgressIndicator()),
          const SizedBox(height: AppSpacing.md),
          Text('Reconnecting to ${smp.deviceLabel ?? 'device'}…',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text('The link dropped (e.g. the device rebooted). Retrying…',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: smp.disconnect,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
