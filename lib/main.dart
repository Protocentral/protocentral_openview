import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'controllers/connection_controller.dart';
import 'controllers/recording_controller.dart';
import 'controllers/recordings_browser_controller.dart';
import 'controllers/scan_controller.dart';
import 'recording/recording_models.dart';
import 'transport/ble_service.dart';
import 'transport/usb_serial_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Build the full controller graph here so the close handler can reach
  // them directly. OpenViewApp registers them as Provider.value.
  final usb = UsbSerialService();
  final ble = BleService();
  final connection = ConnectionController(usb: usb, ble: ble);
  final scan = ScanController(usb: usb, ble: ble);
  final recording = RecordingController(connection: connection);
  final recordingsBrowser = RecordingsBrowserController();

  final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
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
      recording: recording,
    );
    windowManager.addListener(closer);
  }

  runApp(OpenViewApp(
    usb: usb,
    ble: ble,
    connection: connection,
    scan: scan,
    recording: recording,
    recordingsBrowser: recordingsBrowser,
  ));
}

class _CloseHandler with WindowListener {
  final UsbSerialService usb;
  final BleService ble;
  final RecordingController recording;
  _CloseHandler({
    required this.usb,
    required this.ble,
    required this.recording,
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
