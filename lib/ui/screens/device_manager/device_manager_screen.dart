import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/smp_controller.dart';
import '../../../mcumgr/img_mgmt.dart';
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
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: DefaultTabController(
                    length: 3,
                    child: Column(
                      children: [
                        const TabBar(
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            Tab(text: 'Device Info'),
                            Tab(text: 'Firmware'),
                            Tab(text: 'Files'),
                          ],
                        ),
                        const Expanded(
                          child: TabBarView(
                            children: [
                              _DeviceInfoPanel(),
                              _FirmwarePanel(),
                              _FilesPanel(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(flex: 2, child: _ConsolePanel()),
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

// ---------------------------------------------------------------------------
// Firmware panel (Image group — DFU)
// ---------------------------------------------------------------------------

class _FirmwarePanel extends StatefulWidget {
  const _FirmwarePanel();

  @override
  State<_FirmwarePanel> createState() => _FirmwarePanelState();
}

class _FirmwarePanelState extends State<_FirmwarePanel> {
  List<ImageSlot> _slots = const [];
  bool _loadingList = false;

  Uint8List? _fileBytes;
  String? _fileName;

  bool _uploading = false;
  int _sent = 0;
  int _total = 0;
  DateTime? _uploadStart;
  List<int>? _lastSha;

  bool _busy = false; // test/confirm/erase in flight
  String? _status;
  bool _statusIsError = false;

  void _setStatus(String s, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = s;
      _statusIsError = error;
    });
  }

  Future<void> _refreshList(SmpController smp) async {
    final img = smp.img;
    if (img == null) return;
    setState(() => _loadingList = true);
    try {
      final slots = await img.list();
      if (mounted) setState(() => _slots = slots);
    } catch (e) {
      _setStatus('Image list failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _pickFile() async {
    const group = XTypeGroup(
      label: 'firmware',
      extensions: ['bin', 'img', 'signed'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _fileBytes = bytes;
      _fileName = file.name;
      _lastSha = null;
      _status = null;
    });
  }

  Future<void> _upload(SmpController smp) async {
    final img = smp.img;
    final bytes = _fileBytes;
    if (img == null || bytes == null) return;
    // MTU settles just after connect on macOS/iOS — re-query so chunking uses
    // the real value, then refuse if it's too small for DFU to work.
    await smp.refreshMtu();
    final mw = smp.maxWriteLength;
    if (mw != null && mw < 64) {
      _setStatus(
          'MTU too small (max write $mw B → the negotiated ATT MTU is only '
          '${mw + 3}). A firmware image can\'t be chunked this small. This is a '
          'device firmware setting — raise CONFIG_BT_L2CAP_TX_MTU (and the ACL '
          'RX/TX buffer sizes) on the Move so it negotiates a larger MTU.',
          error: true);
      return;
    }
    setState(() {
      _uploading = true;
      _sent = 0;
      _total = bytes.length;
      _uploadStart = DateTime.now();
      _status = null;
    });
    try {
      final sha = await img.upload(bytes, onProgress: (sent, total) {
        if (mounted) setState(() => _sent = sent);
      });
      _lastSha = sha;
      _setStatus('Upload complete (${bytes.length} bytes). '
          'Now Test & Reset to install on next boot.');
      await _refreshList(smp);
    } catch (e) {
      _setStatus('Upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _testAndReset(BuildContext context, SmpController smp) async {
    final sha = _lastSha;
    if (sha == null || smp.img == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test & reset?'),
        content: const Text(
            'Marks the uploaded image pending and reboots the device to install '
            'it. The BLE link will drop.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Test & Reset')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await smp.img!.test(sha);
      await smp.os?.reset();
      _setStatus('Image marked for test; device rebooting…');
    } catch (e) {
      _setStatus('Test/reset failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _progressLine() {
    final pct = _total == 0 ? 0 : (100 * _sent / _total).round();
    final start = _uploadStart;
    if (start == null || _sent == 0) return '$_sent / $_total B  ($pct%)';
    final secs = DateTime.now().difference(start).inMilliseconds / 1000.0;
    if (secs < 0.5) return '$_sent / $_total B  ($pct%)';
    final rate = _sent / secs; // B/s
    final remain = (_total - _sent) / (rate <= 0 ? 1 : rate);
    return '$_sent / $_total B  ($pct%)  ·  '
        '${(rate / 1024).toStringAsFixed(1)} kB/s  ·  '
        'ETA ${remain.toStringAsFixed(0)}s';
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _setStatus('$label ok');
    } catch (e) {
      _setStatus('$label failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smp = context.watch<SmpController>();
    final img = smp.img;
    final busy = _busy || _uploading;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Firmware · Image group',
                  style: theme.textTheme.titleMedium),
            ),
            IconButton(
              tooltip: 'Refresh image list',
              onPressed:
                  (img == null || _loadingList) ? null : () => _refreshList(smp),
              icon: _loadingList
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_slots.isEmpty)
          Text('Tap refresh to read the device\'s image slots.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          for (final s in _slots) _SlotTile(slot: s),
        const Divider(height: AppSpacing.lg),

        // Update flow
        Row(
          children: [
            Expanded(
                child:
                    Text('Update', style: theme.textTheme.titleSmall)),
            if (img != null)
              Text(
                'max write ${smp.maxWriteLength ?? '—'} B · '
                '~${img.steadyChunkSize} B/chunk',
                style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'JetBrainsMono',
                    color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : _pickFile,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Select file'),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _fileName == null
                    ? 'No file selected (.bin / .img / .signed)'
                    : '$_fileName  ·  ${_fileBytes!.length} B',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_uploading) ...[
          LinearProgressIndicator(
            value: _total == 0 ? null : _sent / _total,
          ),
          const SizedBox(height: 4),
          Text(_progressLine(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontFamily: 'JetBrainsMono')),
          const SizedBox(height: AppSpacing.sm),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: (img == null || _fileBytes == null || busy)
                  ? null
                  : () => _upload(smp),
              icon: const Icon(Icons.upload, size: 16),
              label: const Text('Upload'),
            ),
            OutlinedButton.icon(
              onPressed: (_lastSha == null || busy)
                  ? null
                  : () => _testAndReset(context, smp),
              icon: const Icon(Icons.system_update_alt, size: 16),
              label: const Text('Test & Reset'),
            ),
            OutlinedButton.icon(
              onPressed: (img == null || busy)
                  ? null
                  : () => _run('confirm', () => img.confirm(const [])),
              icon: const Icon(Icons.verified, size: 16),
              label: const Text('Confirm running'),
            ),
            OutlinedButton(
              onPressed: (img == null || busy)
                  ? null
                  : () => _run('erase', () => img.erase()),
              style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error),
              child: const Text('Erase slot'),
            ),
          ],
        ),

        if (_status != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: _statusIsError
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _status!,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 12,
                color: _statusIsError
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SlotTile extends StatelessWidget {
  final ImageSlot slot;
  const _SlotTile({required this.slot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flags = <String>[
      if (slot.active) 'active',
      if (slot.confirmed) 'confirmed',
      if (slot.pending) 'pending',
      if (slot.permanent) 'permanent',
      if (slot.bootable) 'bootable',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            slot.slot == 0 ? Icons.memory : Icons.sd_storage,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'image ${slot.image} · slot ${slot.slot}  ·  v${slot.version}',
                  style: theme.textTheme.bodyMedium,
                ),
                Text('sha ${slot.shortHash}…',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'JetBrainsMono',
                        color: theme.colorScheme.onSurfaceVariant)),
                if (flags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 4,
                      children: [for (final f in flags) _MiniTag(f)],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  const _MiniTag(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
    );
  }
}

// ---------------------------------------------------------------------------
// Files panel (FS group — transfer by path)
// ---------------------------------------------------------------------------

class _FilesPanel extends StatefulWidget {
  const _FilesPanel();

  @override
  State<_FilesPanel> createState() => _FilesPanelState();
}

class _FilesPanelState extends State<_FilesPanel> {
  final _pathCtrl = TextEditingController(text: '/lfs/');
  final _targetCtrl = TextEditingController(text: '/lfs/');

  Uint8List? _localBytes;
  String? _localName;

  bool _busy = false;
  int _done = 0;
  int _total = 0;
  String? _op; // 'download' | 'upload' | null
  String? _status;
  bool _statusIsError = false;

  @override
  void dispose() {
    _pathCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  void _setStatus(String s, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = s;
      _statusIsError = error;
    });
  }

  Future<void> _stat(SmpController smp) async {
    final fs = smp.fs;
    if (fs == null) return;
    setState(() => _busy = true);
    try {
      final size = await fs.stat(_pathCtrl.text.trim());
      _setStatus('${_pathCtrl.text.trim()} → $size bytes');
    } catch (e) {
      _setStatus('Stat failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(SmpController smp) async {
    final fs = smp.fs;
    if (fs == null) return;
    final path = _pathCtrl.text.trim();
    if (path.isEmpty || path.endsWith('/')) {
      _setStatus('Enter a full file path to download.', error: true);
      return;
    }
    final suggested = path.split('/').last;
    final loc = await getSaveLocation(suggestedName: suggested);
    if (loc == null) return;
    setState(() {
      _busy = true;
      _op = 'download';
      _done = 0;
      _total = 0;
      _status = null;
    });
    try {
      final bytes = await fs.download(path, onProgress: (d, t) {
        if (mounted) setState(() {
          _done = d;
          _total = t;
        });
      });
      await File(loc.path).writeAsBytes(bytes);
      _setStatus('Downloaded ${bytes.length} B → ${loc.path}');
    } catch (e) {
      _setStatus('Download failed: $e', error: true);
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _op = null;
      });
    }
  }

  Future<void> _pickLocal() async {
    final file = await openFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _localBytes = bytes;
      _localName = file.name;
      if (_targetCtrl.text.isEmpty || _targetCtrl.text.endsWith('/')) {
        _targetCtrl.text = '${_targetCtrl.text}${file.name}';
      }
      _status = null;
    });
  }

  Future<void> _upload(SmpController smp) async {
    final fs = smp.fs;
    final bytes = _localBytes;
    if (fs == null || bytes == null) return;
    final path = _targetCtrl.text.trim();
    if (path.isEmpty || path.endsWith('/')) {
      _setStatus('Enter a full target path.', error: true);
      return;
    }
    await smp.refreshMtu();
    setState(() {
      _busy = true;
      _op = 'upload';
      _done = 0;
      _total = bytes.length;
      _status = null;
    });
    try {
      await fs.upload(path, bytes, onProgress: (d, t) {
        if (mounted) setState(() => _done = d);
      });
      _setStatus('Uploaded ${bytes.length} B → $path');
    } catch (e) {
      _setStatus('Upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _op = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smp = context.watch<SmpController>();
    final fs = smp.fs;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Files · FS group', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Transfer files by absolute path (e.g. /lfs/log.dat). Stock MCUmgr '
          'fs_mgmt has no directory listing or delete — you must know the path.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Divider(height: AppSpacing.lg),

        // Download
        Text('Download', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _pathCtrl,
          decoration: const InputDecoration(
            labelText: 'Device path',
            isDense: true,
            hintText: '/lfs/log.dat',
          ),
          style: const TextStyle(fontFamily: 'JetBrainsMono'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: (fs == null || _busy) ? null : () => _stat(smp),
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('Stat'),
            ),
            FilledButton.icon(
              onPressed: (fs == null || _busy) ? null : () => _download(smp),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Download'),
            ),
          ],
        ),
        const Divider(height: AppSpacing.lg),

        // Upload
        Text('Upload', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickLocal,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Select file'),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _localName == null
                    ? 'No local file selected'
                    : '$_localName  ·  ${_localBytes!.length} B',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _targetCtrl,
          decoration: const InputDecoration(
            labelText: 'Target path',
            isDense: true,
            hintText: '/lfs/upload.dat',
          ),
          style: const TextStyle(fontFamily: 'JetBrainsMono'),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: (fs == null || _localBytes == null || _busy)
              ? null
              : () => _upload(smp),
          icon: const Icon(Icons.upload, size: 16),
          label: const Text('Upload'),
        ),

        if (_busy && _op != null) ...[
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: (_total == 0) ? null : _done / _total,
          ),
          const SizedBox(height: 4),
          Text(
            '${_op == 'download' ? 'Downloading' : 'Uploading'}  '
            '$_done${_total > 0 ? ' / $_total' : ''} B',
            style: theme.textTheme.labelSmall
                ?.copyWith(fontFamily: 'JetBrainsMono'),
          ),
        ],

        if (_status != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: _statusIsError
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _status!,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 12,
                color: _statusIsError
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ],
    );
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
