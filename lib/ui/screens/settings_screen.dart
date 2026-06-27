import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Settings', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Theme'),
                subtitle: const Text('Dark (system)'),
                onTap: null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('Repaint cap'),
                subtitle: const Text('60 Hz (desktop), 30 Hz (mobile)'),
                onTap: null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Recording directory'),
                subtitle: const Text('Documents/ProtoCentral_Recordings'),
                onTap: null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Configurable in Phase 5.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
