// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

part of 'device_manager_screen.dart';

// Firmware panel (Image group — DFU, advanced / WIP)
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
          'Advanced next step (WIP): Test & Reset to try the image on next boot, '
          'then Confirm only after a healthy boot.');
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
        title: const Text('Test & reset? (advanced)'),
        content: const Text(
          'This is the experimental install path (work in progress).\n\n'
          'It marks the uploaded image pending and reboots the device so '
          'MCUboot can try it once. The BLE link will drop. A failed or '
          'unconfirmed image can leave the device on a temporary test image '
          'until the next reboot.\n\n'
          'Only proceed if you know the image is correctly signed for this '
          'device and you have a recovery path.',
        ),
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
        const SizedBox(height: AppSpacing.sm),
        // Full DFU (upload → test → reset → confirm) is built but not fully
        // hardware-validated across devices — keep it visible for advanced use.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiaryContainer
                .withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.tertiary.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.science_outlined,
                  size: 20, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Work in progress · advanced use only',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reading image slots is supported. The full DFU install '
                      'path (upload → Test & Reset → Confirm) is experimental: '
                      'use only if you know MCUboot/signing for this device. '
                      'A bad image or incomplete confirm can require recovery.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_slots.isEmpty)
          Text('Tap refresh to read the device\'s image slots.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          for (final s in _slots) _SlotTile(slot: s),
        const Divider(height: AppSpacing.lg),

        // Update flow (experimental full DFU)
        Row(
          children: [
            Expanded(
              child: Text('Update (advanced / WIP)',
                  style: theme.textTheme.titleSmall),
            ),
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
        Text(
          'Prefer a known-good signed image for this board. Upload stages the '
          'file; Test & Reset reboots into it once; Confirm makes it permanent '
          'only after a healthy boot.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
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
