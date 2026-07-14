// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'controllers/connection_controller.dart';
import 'controllers/developer_ble_controller.dart';
import 'controllers/smp_controller.dart';
import 'controllers/recording_controller.dart';
import 'controllers/recordings_browser_controller.dart';
import 'controllers/scan_controller.dart';
import 'controllers/settings_controller.dart';
import 'recording/recording_models.dart';
import 'transport/ble_service.dart';
import 'transport/usb_serial_service.dart';
import 'transport/wifi_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[OV] main: binding ready');

  // Build the full controller graph here so the close handler can reach
  // them directly. OpenViewApp registers them as Provider.value.
  //
  // IMPORTANT (iOS launch): do not await platform plugins indefinitely before
  // runApp. path_provider / BLE channels can race plugin registration on
  // cold start (especially physical iOS 26 + Flutter 3.38+), which presents as
  // "Installing and launching…" hanging forever.
  final settings = SettingsController();
  try {
    await settings.load().timeout(const Duration(seconds: 4));
    debugPrint('[OV] main: settings loaded');
  } catch (e) {
    debugPrint('[OV] main: settings.load skipped/failed: $e');
  }

  final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  // USB is desktop-only. Instantiating UsbSerialService on mobile is fine
  // (scan returns empty; no serialport FFI until scan/connect), but we still
  // construct it so the same graph works on every platform.
  final usb = UsbSerialService();
  final ble = BleService();
  final wifi = WifiService();
  final connection = ConnectionController(usb: usb, ble: ble, wifi: wifi);
  final scan = ScanController(usb: usb, ble: ble);
  final developerBle = DeveloperBleController();
  final smp = SmpController();
  final recording =
      RecordingController(connection: connection, settings: settings);
  final recordingsBrowser = RecordingsBrowserController(settings: settings);
  debugPrint('[OV] main: controllers ready');

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: Size(1400, 900),
      minimumSize: Size(900, 600),
      title: 'OpenView',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // Intercept close so we can shut things down properly and avoid the
    // Flutter engine teardown crash (see _CloseHandler).
    await windowManager.setPreventClose(true);
    final closer = _CloseHandler(
      usb: usb,
      ble: ble,
      wifi: wifi,
      recording: recording,
      developerBle: developerBle,
      smp: smp,
    );
    windowManager.addListener(closer);
    debugPrint('[OV] main: desktop window ready');
  }

  debugPrint('[OV] main: runApp');
  runApp(OpenViewApp(
    usb: usb,
    ble: ble,
    wifi: wifi,
    settings: settings,
    connection: connection,
    scan: scan,
    recording: recording,
    recordingsBrowser: recordingsBrowser,
    developerBle: developerBle,
    smp: smp,
  ));
}

class _CloseHandler with WindowListener {
  final UsbSerialService usb;
  final BleService ble;
  final WifiService wifi;
  final RecordingController recording;
  final DeveloperBleController developerBle;
  final SmpController smp;
  _CloseHandler({
    required this.usb,
    required this.ble,
    required this.wifi,
    required this.recording,
    required this.developerBle,
    required this.smp,
  });

  bool _shuttingDown = false;

  @override
  void onWindowClose() async {
    if (_shuttingDown) return;
    _shuttingDown = true;

    // 1. Finalise an in-flight recording. Without this, the trailing INDX
    //    block never gets written and the file's `totalSamples` / duration
    //    headers stay zero. Data up to the last 64 KB block is already on
    //    disk regardless, so this is about cleanliness, not data loss.
    if (recording.state == RecordingState.recording) {
      try {
        await recording.stop();
      } catch (_) {}
    }

    // 2. Wait for the libserialport read worker to exit BEFORE closing the
    //    port FD. See UsbSerialService.shutdown for the why.
    try {
      await usb.shutdown();
    } catch (_) {}
    try {
      await ble.disconnect();
    } catch (_) {}
    try {
      await wifi.disconnect();
    } catch (_) {}
    try {
      await developerBle.disconnect();
    } catch (_) {}
    try {
      await smp.disconnect();
    } catch (_) {}

    // 3. Skip the Flutter engine teardown.
    //
    //    `windowManager.destroy()` triggers `[NSApplication terminate:]` →
    //    `flutter::Shell::~Shell()` → `SkGraphics::PurgeFontCache()` →
    //    `SkStrike::~SkStrike()` → `TFont::~TFont()` → `objc_release` on a
    //    freed pointer. That's a known crash in Flutter's macOS engine
    //    destructor in the font cache cleanup path.
    //
    //    Nothing useful happens between our shutdown completing and that
    //    crash, so we hard-exit. The OS reclaims FDs, isolates, memory.
    exit(0);
  }
}
