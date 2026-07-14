// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

part of 'device_manager_screen.dart';

// Files panel (FS group — transfer by path)
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
