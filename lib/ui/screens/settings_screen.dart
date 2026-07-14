// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/recordings_browser_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../theme/app_spacing.dart';

/// Phase 5 — user-configurable settings: theme, live repaint cap, and the
/// recordings directory. Backed by [SettingsController] (persisted to JSON).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Settings', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.lg),

        // --- Appearance -------------------------------------------------
        _SectionCard(
          icon: Icons.palette_outlined,
          title: 'Theme',
          subtitle: 'Light, dark, or follow the system.',
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('Dark'),
              ),
            ],
            selected: {settings.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                context.read<SettingsController>().setThemeMode(s.first),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // --- Performance ------------------------------------------------
        _SectionCard(
          icon: Icons.speed_outlined,
          title: 'Live repaint cap',
          subtitle: 'Maximum redraw rate for live waveforms and heatmaps. '
              'Lower saves CPU/battery.',
          child: SegmentedButton<int>(
            segments: [
              for (final hz in SettingsController.repaintOptions)
                ButtonSegment(value: hz, label: Text('$hz Hz')),
            ],
            selected: {settings.repaintHz},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                context.read<SettingsController>().setRepaintHz(s.first),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // --- Recording --------------------------------------------------
        const _RecordingDirCard(),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  const _SectionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _RecordingDirCard extends StatefulWidget {
  const _RecordingDirCard();

  @override
  State<_RecordingDirCard> createState() => _RecordingDirCardState();
}

class _RecordingDirCardState extends State<_RecordingDirCard> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: context.read<SettingsController>().recordingDirOverride ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final settings = context.read<SettingsController>();
    try {
      await settings.setRecordingDir(_ctrl.text);
      if (mounted) {
        _ctrl.text = settings.recordingDirOverride ?? '';
        _toast('Recording directory updated.');
      }
    } catch (e) {
      _toast('Could not set directory: $e');
    }
  }

  /// Open the native folder picker and apply the chosen directory. Falls back
  /// gracefully on platforms where directory selection isn't supported (the
  /// manual text field remains usable there).
  Future<void> _browse() async {
    final settings = context.read<SettingsController>();
    try {
      final path = await getDirectoryPath(
        initialDirectory: settings.recordingDirOverride,
      );
      if (path == null) return; // cancelled
      await settings.setRecordingDir(path);
      if (mounted) {
        _ctrl.text = settings.recordingDirOverride ?? '';
        _toast('Recording directory updated.');
      }
    } catch (e) {
      _toast('Folder picker unavailable here — type a path instead.');
    }
  }

  Future<void> _reset() async {
    await context.read<SettingsController>().setRecordingDir(null);
    if (mounted) {
      _ctrl.clear();
      _toast('Reverted to the default location.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();

    return _SectionCard(
      icon: Icons.folder_outlined,
      title: 'Recording directory',
      subtitle: 'Where `.hpd` captures are saved.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Effective path (resolves the default async).
          FutureBuilder(
            future: settings.recordingsDirectory(),
            builder: (context, snap) {
              final path = snap.data?.path ?? '…';
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      path,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'JetBrainsMono',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (settings.isDefaultRecordingDir)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: Text('default',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              labelText: 'Custom directory (absolute path)',
              prefixIcon: Icon(Icons.drive_file_move_outline),
              hintText: '/Users/you/Documents/MyRecordings',
            ),
            onSubmitted: (_) => _apply(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: _browse,
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse…'),
              ),
              OutlinedButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.check),
                label: const Text('Apply typed path'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    context.read<RecordingsBrowserController>().revealDirectory(),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Reveal'),
              ),
              if (!settings.isDefaultRecordingDir)
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset to default'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
