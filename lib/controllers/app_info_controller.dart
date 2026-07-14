// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// App identity + package version, loaded once at startup.
///
/// Exposed via Provider so the global footer, navigation rail brand mark, and
/// Settings can all show the same real [version] / [buildNumber] from
/// `package_info_plus` (sourced from `pubspec.yaml`).
class AppInfoController extends ChangeNotifier {
  static const appName = 'OpenView';
  static const companyName = 'ProtoCentral Electronics';
  static const companyUrl = 'https://protocentral.com';

  String _version = '';
  String _buildNumber = '';
  bool _loaded = false;

  /// Semantic version string, e.g. `3.0.0`. Empty until [load] completes.
  String get version => _version;

  /// Build number (Android/iOS CFBundleVersion), e.g. `131`.
  String get buildNumber => _buildNumber;

  bool get isLoaded => _loaded;

  /// Short label for chrome: `3.0.0` or `—` while unknown.
  String get versionLabel =>
      _version.isEmpty ? '—' : _version;

  /// Display form used in the rail / footer: `v3.0.0`.
  String get versionPrefixed =>
      _version.isEmpty ? '…' : 'v$_version';

  /// Full identity for copy / support: `OpenView 3.0.0+131`.
  String get fullVersionString {
    if (_version.isEmpty) return appName;
    if (_buildNumber.isEmpty) return '$appName $_version';
    return '$appName $_version+$_buildNumber';
  }

  /// Load from the platform package info. Safe to call with a timeout from
  /// `main` so a slow plugin cannot block first frame forever.
  Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _buildNumber = info.buildNumber;
      // Prefer package display name when non-empty, but keep the product name
      // "OpenView" as the user-facing brand (pubspec name may differ).
    } catch (e) {
      debugPrint('[OV] AppInfoController.load failed: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }
}
