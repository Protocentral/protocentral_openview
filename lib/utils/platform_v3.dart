// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Platform capability helpers for the v3 app.
class PlatformV3 {
  PlatformV3._();

  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static bool get canUseUsb => isDesktop;
  static bool get canUseBle {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux;
  }

  static bool get canUseWifi => isDesktop;
}
