import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../controllers/recordings_browser_controller.dart';
import '../../recording/recording_file_info.dart';
import '../../theme/app_spacing.dart';
import '../app_routes.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  bool _autoRefreshed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_autoRefreshed) {
        _autoRefreshed = true;
        context.read<RecordingsBrowserController>().refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final browser = context.watch<RecordingsBrowserController>();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recordings',
                        style: theme.textTheme.headlineMedium),
                    Text(
                      browser.directory == null
                          ? '…'
                          : browser.directory!.path,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: browser.loading ? null : browser.refresh,
                icon: browser.loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _SummaryStrip(browser: browser),
          if (browser.error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  browser.error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: browser.recordings.isEmpty && !browser.loading
                ? _EmptyState(theme: theme)
                : ListView.separated(
                    itemCount: browser.recordings.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (_, i) => _RecordingTile(
                      info: browser.recordings[i],
                      onOpen: () => _openReplay(
                          context, browser.recordings[i]),
                      onDetail: () => _showDetail(
                          context, browser.recordings[i]),
                      onDelete: () =>
                          _confirmDelete(context, browser, browser.recordings[i]),
                      onReveal: () =>
                          browser.revealInFinder(browser.recordings[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openReplay(BuildContext ctx, RecordingFileInfo info) {
    if (!info.isValid) {
      _showDetail(ctx, info);
      return;
    }
    ctx.go('${AppRoutes.replay}?file=${Uri.encodeQueryComponent(info.file.path)}');
  }

  Future<void> _confirmDelete(
      BuildContext ctx, RecordingsBrowserController b, RecordingFileInfo info) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text(info.fileName),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await b.delete(info);
  }

  void _showDetail(BuildContext ctx, RecordingFileInfo info) {
    showDialog<void>(
      context: ctx,
      builder: (_) => _DetailDialog(info: info),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final RecordingsBrowserController browser;
  const _SummaryStrip({required this.browser});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String fmt(int b) {
      if (b < 1024) return '$b B';
      if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _Pill(label: 'Files', value: '${browser.recordings.length}'),
        _Pill(label: 'Total', value: fmt(browser.totalSize)),
        _Pill(
          label: 'Invalid',
          value: '${browser.recordings.where((r) => !r.isValid).length}',
          accent: theme.colorScheme.errorContainer,
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;
  const _Pill({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: accent ?? theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          Text(value,
              style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  final RecordingFileInfo info;
  final VoidCallback onOpen;
  final VoidCallback onDetail;
  final VoidCallback onDelete;
  final VoidCallback onReveal;
  const _RecordingTile({
    required this.info,
    required this.onOpen,
    required this.onDetail,
    required this.onDelete,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = info.metadata;
    final invalid = !info.isValid;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant);

    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(
                invalid
                    ? Icons.error_outline
                    : Icons.audio_file_outlined,
                color: invalid
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.fileName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    if (invalid)
                      Text('Unreadable: ${info.error ?? "header parse failed"}',
                          style: subtitleStyle?.copyWith(
                              color: theme.colorScheme.error))
                    else
                      Text(
                        '${meta!.deviceName} · '
                        '${meta.channels.length} ch · '
                        '${info.durationFormatted} · '
                        '${info.sizeFormatted} · '
                        '${_fmtDate(info.modified)}',
                        style: subtitleStyle,
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (key) {
                  switch (key) {
                    case 'open':
                      onOpen();
                      break;
                    case 'reveal':
                      onReveal();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                    case 'detail':
                      onDetail();
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Open in replay')),
                  PopupMenuItem(value: 'detail', child: Text('Details')),
                  PopupMenuItem(value: 'reveal', child: Text('Reveal in folder')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}

class _DetailDialog extends StatelessWidget {
  final RecordingFileInfo info;
  const _DetailDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = info.metadata;

    return AlertDialog(
      title: Text(info.fileName, style: theme.textTheme.titleLarge),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (meta == null) ...[
                Text('Header could not be parsed.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error)),
                if (info.error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(info.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.error)),
                ],
              ] else ...[
                _KV(k: 'Device', v: '${meta.deviceName} (${meta.deviceId})'),
                _KV(k: 'Format', v: 'BIOSIG v${meta.fileFormatVersion}'),
                _KV(k: 'Firmware', v: meta.firmwareVersion),
                _KV(k: 'Created', v: meta.createdAt.toLocal().toString()),
                _KV(k: 'Size', v: info.sizeFormatted),
                _KV(k: 'Duration', v: info.durationFormatted),
                _KV(k: 'Total samples',
                    v: meta.totalSamples > 0 ? '${meta.totalSamples}' : '—'),
                const SizedBox(height: AppSpacing.md),
                Text('Channels (${meta.channels.length})',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                ...meta.channels.map((c) => Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${c.id}  ·  ${c.name}  ·  '
                        '${c.samplingRate.toStringAsFixed(0)} Hz  ·  ${c.unit}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace'),
                      ),
                    )),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(info.file.path,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}

class _KV extends StatelessWidget {
  final String k;
  final String v;
  const _KV({required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(k,
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant))),
          Expanded(
              child: Text(v,
                  style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined,
              size: 56, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text('No recordings yet', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Connect a board, open Live, and tap Record.',
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
