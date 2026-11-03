// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/platform_v3.dart';

/// App-wide, user-configurable settings (Phase 5).
///
/// Persisted as a small JSON file in the application-support directory — no
/// extra native plugin (shared_preferences) required, which keeps the mobile
/// build surface minimal. [load] is awaited once in `main()` before the app is
/// built so the initial theme / repaint cap are correct on first frame.
class SettingsController extends ChangeNotifier {
  static const _fileName = 'openview_settings.json';
  static const repaintOptions = <int>[30, 60, 120];
  static const _recordingsFolder = 'ProtoCentral_Recordings';

  ThemeMode _themeMode = ThemeMode.dark;
  int _repaintHz = PlatformV3.isDesktop ? 60 : 30;
  String? _recordingDir; // null → default under Documents/
  bool _autoCheckUpdates = true;
  bool _autoReconnectUsb = true;
  DateTime? _lastUpdateCheck;
  String? _skippedUpdateVersion;

  ThemeMode get themeMode => _themeMode;
  int get repaintHz => _repaintHz;

  /// Custom recordings directory, or null when using the default location.
  String? get recordingDirOverride => _recordingDir;
  bool get isDefaultRecordingDir => _recordingDir == null;

  /// Whether OpenView may check GitHub Releases for a newer desktop build on
  /// startup. Only self-distributed builds ever check (see UpdateChannel),
  /// but the preference is stored for every platform so toggling it on a
  /// store build is harmless.
  bool get autoCheckUpdates => _autoCheckUpdates;

  /// Whether a USB link that drops on its own (unplug, board reset) is
  /// reopened automatically when the port comes back.
  bool get autoReconnectUsb => _autoReconnectUsb;

  /// When the last update check completed, used to keep it to once a day.
  DateTime? get lastUpdateCheck => _lastUpdateCheck;

  /// A release the user asked not to be reminded about, e.g. `3.3.0`.
  String? get skippedUpdateVersion => _skippedUpdateVersion;

  File? _file;

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, _fileName));
      _file = file;
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _themeMode = _parseTheme(json['themeMode'] as String?) ?? _themeMode;
      final hz = json['repaintHz'] as int?;
      if (hz != null && repaintOptions.contains(hz)) _repaintHz = hz;
      final dirOverride = json['recordingDir'] as String?;
      if (dirOverride != null && dirOverride.trim().isNotEmpty) {
        _recordingDir = dirOverride;
      }
      _autoCheckUpdates = json['autoCheckUpdates'] as bool? ?? _autoCheckUpdates;
      _autoReconnectUsb = json['autoReconnectUsb'] as bool? ?? _autoReconnectUsb;
      final lastCheck = json['lastUpdateCheck'] as String?;
      if (lastCheck != null) _lastUpdateCheck = DateTime.tryParse(lastCheck);
      final skipped = json['skippedUpdateVersion'] as String?;
      if (skipped != null && skipped.trim().isNotEmpty) {
        _skippedUpdateVersion = skipped;
      }
    } catch (_) {
      // Corrupt / unreadable settings — fall back to defaults silently.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setRepaintHz(int hz) async {
    if (hz == _repaintHz || !repaintOptions.contains(hz)) return;
    _repaintHz = hz;
    notifyListeners();
    await _save();
  }

  /// Set a custom recordings directory (creating it if needed), or pass null
  /// to revert to the default location. Throws if the path can't be created.
  Future<void> setRecordingDir(String? path) async {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _recordingDir = null;
    } else {
      final dir = Directory(trimmed);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _recordingDir = dir.path;
    }
    notifyListeners();
    await _save();
  }

  Future<void> setAutoCheckUpdates(bool enabled) async {
    if (enabled == _autoCheckUpdates) return;
    _autoCheckUpdates = enabled;
    notifyListeners();
    await _save();
  }

  Future<void> setAutoReconnectUsb(bool enabled) async {
    if (enabled == _autoReconnectUsb) return;
    _autoReconnectUsb = enabled;
    notifyListeners();
    await _save();
  }

  /// Stamp the update check clock. Called after every completed check —
  /// including one that found nothing — so a quiet repo doesn't cause a
  /// request on every launch.
  Future<void> markUpdateChecked() async {
    _lastUpdateCheck = DateTime.now();
    await _save();
  }

  /// Suppress reminders for [version] (pass null to clear).
  Future<void> setSkippedUpdateVersion(String? version) async {
    if (version == _skippedUpdateVersion) return;
    _skippedUpdateVersion = version;
    notifyListeners();
    await _save();
  }

  /// Resolve the effective recordings directory (default or override).
  Future<Directory> recordingsDirectory() async {
    final override = _recordingDir;
    if (override != null && override.trim().isNotEmpty) {
      return Directory(override);
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, _recordingsFolder));
  }

  Future<void> _save() async {
    try {
      final file = _file ??= File(p.join(
          (await getApplicationSupportDirectory()).path, _fileName));
      await file.writeAsString(jsonEncode({
        'themeMode': _themeMode.name,
        'repaintHz': _repaintHz,
        'recordingDir': _recordingDir,
        'autoCheckUpdates': _autoCheckUpdates,
        'autoReconnectUsb': _autoReconnectUsb,
        'lastUpdateCheck': _lastUpdateCheck?.toIso8601String(),
        'skippedUpdateVersion': _skippedUpdateVersion,
      }));
    } catch (_) {
      // Best-effort persistence; ignore write failures.
    }
  }

  static ThemeMode? _parseTheme(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
}
