// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

part of 'device_manager_screen.dart';

// Connected shell — tab strip + console column
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
                  child: Builder(builder: (context) {
                    final showHs = smp.hasHealthStore;
                    final tabs = <String>[
                      'Device Info',
                      'Firmware (WIP)',
                      'Files',
                      if (showHs) 'Health Store',
                    ];
                    return DefaultTabController(
                      key: ValueKey(tabs.length),
                      length: tabs.length,
                      child: Column(
                        children: [
                          TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [for (final t in tabs) Tab(text: t)],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                const _DeviceInfoPanel(),
                                const _FirmwarePanel(),
                                const _FilesPanel(),
                                if (showHs) const _HealthStorePanel(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
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
