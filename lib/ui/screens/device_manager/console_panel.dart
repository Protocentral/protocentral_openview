// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

part of 'device_manager_screen.dart';

// SMP request/response console + export
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
                  onPressed:
                      entries.isEmpty ? null : () => _exportConsole(context, entries),
                  icon: const Icon(Icons.save_alt, size: 16),
                  label: const Text('Export'),
                ),
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

/// Save the SMP console to a `.log` file (one full line per request/response).
Future<void> _exportConsole(
    BuildContext context, List<ConsoleEntry> entries) async {
  final loc = await getSaveLocation(suggestedName: 'smp-console.log');
  if (loc == null) return;
  final b = StringBuffer();
  for (final e in entries) {
    final m = e.message;
    final dir = e.outbound ? 'TX' : 'RX';
    final payload =
        m.payload.entries.map((x) => '${x.key}=${_exportVal(x.value)}').join(' ');
    final rc = m.rc != null ? '  rc=${m.rc}' : '';
    b.writeln('${e.timestamp.toIso8601String()}  $dir  '
        'grp=${m.group} id=${m.id} seq=${m.seq}  {$payload}$rc');
  }
  await File(loc.path).writeAsString(b.toString());
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${entries.length} lines → ${loc.path}')),
    );
  }
}

String _exportVal(Object? v) {
  if (v is String) return '"$v"';
  if (v is List) return '<${v.length} bytes>';
  if (v is Map) return '{${v.length} keys}';
  return '$v';
}
