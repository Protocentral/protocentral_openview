// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

part of 'device_manager_screen.dart';

// Device Info panel (OS group)
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
