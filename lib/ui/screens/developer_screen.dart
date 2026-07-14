// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../controllers/developer_ble_controller.dart';
import '../../theme/app_spacing.dart';

/// Developer tab — **unfiltered** BLE playground for general-purpose GATT /
/// MCUmgr bring-up. Always in the main nav (not a hidden engineer mode).
///
/// Scans and connects to *any* BLE peripheral (no board/registry filter),
/// discovers its GATT table, and lets you read / write / subscribe to
/// characteristics. Fully decoupled from the streaming Connect flow and from
/// Device Manager's SMP link, so it can be used as a general BLE/MCUmgr test
/// tool alongside those destinations.
class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dev = context.watch<DeveloperBleController>();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('Developer', style: theme.textTheme.headlineMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Unfiltered BLE — scan and connect to any device. Discover GATT, '
            'read/write/notify characteristics. General-purpose BLE and MCUmgr '
            'bring-up tool (separate from streaming Connect and Device Manager).',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: dev.isConnected
                ? _GattExplorer(dev: dev)
                : _ScanView(dev: dev),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(height: 200, child: _LogPanel(dev: dev)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan view (disconnected)
// ---------------------------------------------------------------------------

class _ScanView extends StatelessWidget {
  final DeveloperBleController dev;
  const _ScanView({required this.dev});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = dev.devices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: dev.connecting
                  ? null
                  : (dev.scanning ? dev.stopScan : dev.startScan),
              icon: dev.scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: Text(dev.scanning ? 'Stop scan' : 'Scan'),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: dev.loadingSystem ? null : dev.refreshSystemDevices,
              icon: dev.loadingSystem
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.devices_other),
              label: const Text('System devices'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilterChip(
              selected: dev.hideUnnamed,
              onSelected: (v) => dev.hideUnnamed = v,
              avatar: Icon(
                dev.hideUnnamed ? Icons.filter_alt : Icons.filter_alt_outlined,
                size: 18,
              ),
              label: const Text('Hide unnamed'),
            ),
            const Spacer(),
            Text('${devices.length} found',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: devices.isEmpty
              ? _EmptyHint(
                  icon: dev.scanning
                      ? Icons.bluetooth_searching
                      : Icons.bluetooth_disabled,
                  text: dev.scanning
                      ? 'Scanning for any BLE device…'
                      : 'Tap Scan to discover nearby BLE devices.',
                )
              : ListView.separated(
                  itemCount: devices.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (_, i) => _DeviceTile(
                    entry: devices[i],
                    connecting: dev.connecting,
                    onConnect: () => dev.connect(devices[i].deviceId,
                        name: devices[i].name),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DevScanEntry entry;
  final bool connecting;
  final VoidCallback onConnect;
  const _DeviceTile({
    required this.entry,
    required this.connecting,
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
          child: Icon(
            entry.isSystemDevice ? Icons.link : Icons.bluetooth,
            color: theme.colorScheme.primary,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(entry.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium),
            ),
            if (entry.isSystemDevice) ...[
              const SizedBox(width: AppSpacing.xs),
              _MiniChip(label: 'system', color: theme.colorScheme.tertiary),
            ],
          ],
        ),
        subtitle: Text(
          '${entry.deviceId}'
          '${entry.services.isNotEmpty ? ' · ${entry.services.length} svc adv' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.rssi != null)
              Text('${entry.rssi} dBm',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: connecting ? null : onConnect,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GATT explorer (connected)
// ---------------------------------------------------------------------------

class _GattExplorer extends StatelessWidget {
  final DeveloperBleController dev;
  const _GattExplorer({required this.dev});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dev.connectedName ?? 'Connected',
                          style: theme.textTheme.titleMedium),
                      Text(
                        '${dev.connectedId}'
                        '${dev.mtu != null ? '  ·  MTU ${dev.mtu}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: dev.disconnect,
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: dev.services.isEmpty
              ? const _EmptyHint(
                  icon: Icons.list_alt,
                  text: 'No services discovered.',
                )
              : ListView(
                  children: [
                    for (final s in dev.services)
                      _ServiceCard(dev: dev, service: s),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final DeveloperBleController dev;
  final BleService service;
  const _ServiceCard({required this.dev, required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ExpansionTile(
        initiallyExpanded: service.characteristics.length <= 6,
        tilePadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        title: Text('Service ${_shortUuid(service.uuid)}',
            style: theme.textTheme.titleSmall),
        subtitle: Text(service.uuid,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'JetBrainsMono')),
        children: [
          for (final c in service.characteristics)
            _CharacteristicRow(
                dev: dev, serviceUuid: service.uuid, characteristic: c),
        ],
      ),
    );
  }
}

class _CharacteristicRow extends StatelessWidget {
  final DeveloperBleController dev;
  final String serviceUuid;
  final BleCharacteristic characteristic;
  const _CharacteristicRow({
    required this.dev,
    required this.serviceUuid,
    required this.characteristic,
  });

  bool _has(CharacteristicProperty p) =>
      characteristic.properties.contains(p);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final props = characteristic.properties;
    final canRead = _has(CharacteristicProperty.read);
    final canNotify = _has(CharacteristicProperty.notify) ||
        _has(CharacteristicProperty.indicate);
    final canWrite = _has(CharacteristicProperty.write) ||
        _has(CharacteristicProperty.writeWithoutResponse);
    final notifying = dev.isNotifying(characteristic.uuid);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  characteristic.uuid,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'JetBrainsMono'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Wrap(
                spacing: 4,
                children: [
                  for (final p in props) _PropChip(prop: p),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (canRead)
                _ActionButton(
                  label: 'Read',
                  icon: Icons.download,
                  onPressed: () => dev.readCharacteristic(
                      serviceUuid, characteristic.uuid),
                ),
              if (canNotify)
                _ActionButton(
                  label: notifying ? 'Stop' : 'Notify',
                  icon: notifying
                      ? Icons.notifications_off
                      : Icons.notifications_active,
                  active: notifying,
                  onPressed: () =>
                      dev.toggleNotify(serviceUuid, characteristic.uuid),
                ),
              if (canWrite)
                _ActionButton(
                  label: 'Write',
                  icon: Icons.upload,
                  onPressed: () => _showWriteDialog(context),
                ),
            ],
          ),
          const Divider(height: AppSpacing.md),
        ],
      ),
    );
  }

  Future<void> _showWriteDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final preferNoResp = !_has(CharacteristicProperty.write) &&
        _has(CharacteristicProperty.writeWithoutResponse);
    bool withoutResponse = preferNoResp;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Write ${_shortUuid(characteristic.uuid)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Bytes (hex)',
                  hintText: '0a fa 01 00',
                ),
                style: const TextStyle(fontFamily: 'JetBrainsMono'),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_has(CharacteristicProperty.write) &&
                  _has(CharacteristicProperty.writeWithoutResponse))
                CheckboxListTile(
                  value: withoutResponse,
                  onChanged: (v) =>
                      setState(() => withoutResponse = v ?? false),
                  title: const Text('Without response'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Write')),
          ],
        ),
      ),
    );

    if (result != true) return;
    final bytes = DeveloperBleController.parseHex(ctrl.text);
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid hex — need even digit count.')),
        );
      }
      return;
    }
    await dev.writeCharacteristic(serviceUuid, characteristic.uuid, bytes,
        withoutResponse: withoutResponse);
  }
}

// ---------------------------------------------------------------------------
// Activity log
// ---------------------------------------------------------------------------

class _LogPanel extends StatelessWidget {
  final DeveloperBleController dev;
  const _LogPanel({required this.dev});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = dev.log;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.terminal,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
                Text('Activity', style: theme.textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: entries.isEmpty ? null : dev.clearLog,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const Divider(height: AppSpacing.sm),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text('No activity yet.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: entries.length,
                      itemBuilder: (_, i) {
                        final e = entries[entries.length - 1 - i];
                        return _LogLine(entry: e);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final DevLogEntry entry;
  const _LogLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (entry.level) {
      DevLogLevel.error => scheme.error,
      DevLogLevel.tx => scheme.primary,
      DevLogLevel.rx => scheme.secondary,
      DevLogLevel.info => scheme.onSurfaceVariant,
    };
    final t = entry.time;
    final ts = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '$ts  ${entry.text}',
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 11.5,
          color: color,
          height: 1.3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared widgets
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: active
          ? FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: Icon(icon, size: 16),
              label: Text(label),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 16),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
    );
  }
}

class _PropChip extends StatelessWidget {
  final CharacteristicProperty prop;
  const _PropChip({required this.prop});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (prop) {
      CharacteristicProperty.read => 'R',
      CharacteristicProperty.write => 'W',
      CharacteristicProperty.writeWithoutResponse => 'w',
      CharacteristicProperty.notify => 'N',
      CharacteristicProperty.indicate => 'I',
      CharacteristicProperty.broadcast => 'B',
      CharacteristicProperty.authenticatedSignedWrites => 'S',
      CharacteristicProperty.extendedProperties => 'E',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: theme.textTheme.labelSmall
              ?.copyWith(fontFamily: 'JetBrainsMono')),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.sm),
          Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

String _shortUuid(String uuid) {
  final u = uuid.toLowerCase().replaceAll('-', '');
  if (u.length >= 8 && u.startsWith('0000')) return '0x${u.substring(4, 8)}';
  return u.length <= 8 ? uuid : '…${u.substring(u.length - 6)}';
}
