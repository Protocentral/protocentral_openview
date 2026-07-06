import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/smp_controller.dart';
import '../../../smp/smp_message.dart';
import '../../../theme/app_spacing.dart';

/// SMP / MCUmgr **Device Manager** — a top-level destination for managing any
/// SMP-enabled BLE device (its own connection, separate from the streaming
/// Connect flow). Phase 1: scan → connect → Device Info (OS group) + a raw SMP
/// console, with an **echo** smoke test that proves transport + framing + CBOR +
/// fragment reassembly end-to-end.
class DeviceManagerScreen extends StatelessWidget {
  const DeviceManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smp = context.watch<SmpController>();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('Device Manager', style: theme.textTheme.headlineMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Manage any SMP / MCUmgr device over BLE. Scan, connect, and use the '
            'OS group — start with an echo to confirm the link.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child:
                smp.isConnected ? _ConnectedView(smp: smp) : _ScanView(smp: smp),
          ),
        ],
      ),
    );
  }
}

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
// Connected view — Device Info + Console
// ---------------------------------------------------------------------------

class _ConnectedView extends StatelessWidget {
  final SmpController smp;
  const _ConnectedView({required this.smp});

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
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(smp.deviceLabel ?? 'Connected',
                          style: theme.textTheme.titleMedium),
                      Text(
                        'SMP-enabled'
                        '${smp.maxWriteLength != null ? '  ·  max write ${smp.maxWriteLength} B' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: smp.disconnect,
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: _DeviceInfoPanel()),
              SizedBox(width: AppSpacing.md),
              Expanded(flex: 2, child: _ConsolePanel()),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeviceInfoPanel extends StatefulWidget {
  const _DeviceInfoPanel();

  @override
  State<_DeviceInfoPanel> createState() => _DeviceInfoPanelState();
}

class _DeviceInfoPanelState extends State<_DeviceInfoPanel> {
  final _echoCtrl = TextEditingController(text: 'hello move');
  bool _busy = false;
  String? _result;
  bool _resultIsError = false;

  @override
  void dispose() {
    _echoCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(String label, Future<Object?> Function() action) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final r = await action();
      if (!mounted) return;
      setState(() {
        _result = '$label → ${r ?? 'ok'}';
        _resultIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = '$label failed: $e';
        _resultIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smp = context.watch<SmpController>();
    final os = smp.os;

    return Card(
      margin: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('Device Info · OS group',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text('MCUmgr OS management (group 0).',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const Divider(height: AppSpacing.lg),

          // Echo smoke test
          Text('Echo (smoke test)', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _echoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Text',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: (_busy || os == null)
                    ? null
                    : () => _run('echo',
                        () => os.echo(_echoCtrl.text)),
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Send'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Other OS-group actions
          Text('Actions', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _ActionChip(
                label: 'MCUmgr params',
                busy: _busy,
                enabled: os != null,
                onTap: () => _run('params', () => os!.mcumgrParams()),
              ),
              _ActionChip(
                label: 'Task stats',
                busy: _busy,
                enabled: os != null,
                onTap: () => _run('taskstat', () => os!.taskStat()),
              ),
              _ActionChip(
                label: 'Get datetime',
                busy: _busy,
                enabled: os != null,
                onTap: () => _run('datetime', () => os!.getDatetime()),
              ),
              _ActionChip(
                label: 'Set datetime (now)',
                busy: _busy,
                enabled: os != null,
                onTap: () => _run(
                    'set datetime', () async {
                  await os!.setDatetime(DateTime.now());
                  return 'sent';
                }),
              ),
              _ActionChip(
                label: 'Reset',
                busy: _busy,
                enabled: os != null,
                destructive: true,
                onTap: () => _confirmReset(context, smp),
              ),
            ],
          ),

          if (_result != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: _resultIsError
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _result!,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                  color: _resultIsError
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, SmpController smp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset device?'),
        content: const Text(
            'The device will reboot and the BLE link will drop.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) {
      await _run('reset', () async {
        await smp.os?.reset();
        return 'sent';
      });
    }
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final bool busy;
  final bool enabled;
  final bool destructive;
  final VoidCallback onTap;
  const _ActionChip({
    required this.label,
    required this.busy,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: (busy || !enabled) ? null : onTap,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: destructive ? theme.colorScheme.error : null,
      ),
      child: Text(label),
    );
  }
}

class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smp = context.watch<SmpController>();
    final entries = smp.console;

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
                Text('SMP console', style: theme.textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: entries.isEmpty ? null : smp.clearConsole,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const Divider(height: AppSpacing.sm),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text('No traffic yet.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: entries.length,
                      itemBuilder: (_, i) =>
                          _ConsoleLine(entry: entries[entries.length - 1 - i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsoleLine extends StatelessWidget {
  final ConsoleEntry entry;
  const _ConsoleLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = entry.message;
    final color = entry.outbound ? scheme.primary : scheme.secondary;
    final arrow = entry.outbound ? '→' : '←';
    final t = entry.timestamp;
    final ts = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    final payload = _previewPayload(m);
    final err = m.rc;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '$ts $arrow grp${m.group} id${m.id} seq${m.seq}  $payload'
        '${err != null ? '  rc=$err' : ''}',
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 11.5,
          height: 1.3,
          color: err != null ? scheme.error : color,
        ),
      ),
    );
  }

  static String _previewPayload(SmpMessage m) {
    if (m.payload.isEmpty) return '{}';
    final s = m.payload.entries
        .map((e) => '${e.key}:${_v(e.value)}')
        .join(' ');
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  static String _v(Object? v) {
    if (v is String) return '"$v"';
    if (v is Map) return '{${v.length}}';
    if (v is List) return '[${v.length}]';
    return '$v';
  }
}

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  final String text;
  const _ErrorBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: 16, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onErrorContainer)),
          ),
        ],
      ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
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
      ),
    );
  }
}
