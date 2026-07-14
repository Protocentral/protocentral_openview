// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import Flutter
import UIKit

/// Scene lifecycle entry for Flutter's UIScene embedding (required on modern
/// iOS / Flutter 3.38+). Subclasses [FlutterSceneDelegate] so the engine and
/// plugins receive scene connect / foreground / background events.
///
/// Referenced from Info.plist as `$(PRODUCT_MODULE_NAME).SceneDelegate`.
class SceneDelegate: FlutterSceneDelegate {}
