// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import Flutter
import UIKit

/// App entry for the UIScene / implicit-engine embedding (Flutter 3.38+).
///
/// Plugins must be registered on the engine bridge. Registering only here (and
/// not in `application(_:didFinishLaunchingWithOptions:)`) is correct for the
/// scene lifecycle — do not also call `GeneratedPluginRegistrant.register(with:
/// self)` in `didFinishLaunching`, or plugins double-register.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
