// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/app_info_controller.dart';
import '../../controllers/recordings_browser_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/update_controller.dart';
import '../../theme/app_spacing.dart';
import '../../utils/platform_v3.dart';
import '../widgets/update_banner.dart';

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

        // --- Connection -------------------------------------------------
        // USB serial is desktop-only.
        if (PlatformV3.isDesktop) ...[
          _SectionCard(
            icon: Icons.usb,
            title: 'USB connection',
            subtitle: 'What to do when a USB board drops off, e.g. after a '
                'reset or a loose cable.',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: settings.autoReconnectUsb,
              title: const Text('Reconnect automatically'),
              subtitle: const Text(
                  'Keep the session open and reopen the port when the board '
                  'comes back (up to 30 s).'),
              onChanged: (v) =>
                  context.read<SettingsController>().setAutoReconnectUsb(v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // --- Recording --------------------------------------------------
        const _RecordingDirCard(),
        const SizedBox(height: AppSpacing.md),

        // --- Updates ----------------------------------------------------
        // Absent on store builds, where the store owns updating.
        if (context.watch<UpdateController>().isSupported) ...[
          const _UpdatesCard(),
          const SizedBox(height: AppSpacing.md),
        ],

        // --- About ------------------------------------------------------
        const _AboutCard(),
      ],
    );
  }
}

/// Update preferences. The manual check itself lives in [_AboutCard], next to
/// the version it is about — the familiar desktop "About → Check for
/// Updates…" idiom.
///
/// Only self-distributed desktop builds show this; on App Store / Play builds
/// [UpdateController.isSupported] is false and the card collapses away, so a
/// store user is never pointed at a GitHub zip.
class _UpdatesCard extends StatelessWidget {
  const _UpdatesCard();

  @override
  Widget build(BuildContext context) {
    final update = context.watch<UpdateController>();
    if (!update.isSupported) return const SizedBox.shrink();

    final settings = context.watch<SettingsController>();
    final found = update.info;
    final skipped = settings.skippedUpdateVersion;

    return _SectionCard(
      icon: Icons.system_update_alt,
      title: 'Updates',
      subtitle: 'OpenView checks GitHub Releases for a newer desktop build. '
          'It never installs anything on its own — downloads open in your '
          'browser.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: settings.autoCheckUpdates,
            title: const Text('Check for updates automatically'),
            subtitle: const Text('At most once a day, on startup.'),
            onChanged: (v) =>
                context.read<SettingsController>().setAutoCheckUpdates(v),
          ),
          if (found != null || skipped != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (found != null)
                  OutlinedButton.icon(
                    onPressed: () => showUpdateDetailsDialog(context),
                    icon: const Icon(Icons.description_outlined),
                    label: Text("What's new in ${found.version}"),
                  ),
                if (skipped != null)
                  TextButton.icon(
                    onPressed: () => context
                        .read<SettingsController>()
                        .setSkippedUpdateVersion(null),
                    icon: const Icon(Icons.undo),
                    label: Text('Un-skip $skipped'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One-line summary of where the update check stands, for the About card.
String _updateStatusLine(UpdateController update, SettingsController settings) {
  switch (update.status) {
    case UpdateStatus.checking:
      return 'Contacting GitHub…';
    case UpdateStatus.available:
      return 'OpenView ${update.info!.version} is available.';
    case UpdateStatus.failed:
      return update.error ?? 'The last check did not complete.';
    case UpdateStatus.upToDate:
      return 'You are running the latest release.';
    case UpdateStatus.idle:
      final last = settings.lastUpdateCheck;
      if (last == null) return 'Not checked for updates yet.';
      return 'Last checked ${_ago(DateTime.now().difference(last))}.';
  }
}

String _ago(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = context.watch<AppInfoController>();
    final update = context.watch<UpdateController>();

    return _SectionCard(
      icon: Icons.info_outline,
      title: 'About',
      subtitle: 'App identity and support details.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(AppInfoController.appName,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                )),
            subtitle: Text(
              info.isLoaded
                  ? '${info.version}'
                      '${info.buildNumber.isNotEmpty ? '+${info.buildNumber}' : ''}'
                  : '…',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.copy, size: 18),
            onLongPress: () async {
              final text = info.fullVersionString;
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied $text'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            onTap: () async {
              // Tap also copies — mobile-friendly (long-press is less discoverable).
              final text = info.fullVersionString;
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied $text'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          if (update.isSupported) ...[
            const Divider(height: AppSpacing.lg),
            const _UpdateCheckRow(),
          ],
          const Divider(height: AppSpacing.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(AppInfoController.companyName,
                style: theme.textTheme.titleSmall),
            subtitle: Text(AppInfoController.companyUrl,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            trailing: Icon(Icons.open_in_new,
                size: 18, color: scheme.onSurfaceVariant),
            onTap: () async {
              final uri = Uri.parse(AppInfoController.companyUrl);
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not open link: $e'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// "Check for updates" next to the version in About — where a desktop user
/// looks to answer "am I current?".
///
/// Reports through [runManualUpdateCheck]: the release-notes dialog when there
/// is an update, a snackbar when there isn't. The line above the button carries
/// the standing state (last checked / up to date / the error).
class _UpdateCheckRow extends StatelessWidget {
  const _UpdateCheckRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final update = context.watch<UpdateController>();
    final settings = context.watch<SettingsController>();
    final version = context.watch<AppInfoController>().version;

    return Row(
      children: [
        Expanded(
          child: Text(
            _updateStatusLine(update, settings),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: update.isChecking
              ? null
              : () => runManualUpdateCheck(context, version),
          icon: update.isChecking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          label: Text(update.isChecking ? 'Checking…' : 'Check for updates'),
        ),
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
