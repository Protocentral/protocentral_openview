import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'transport/ble_service.dart';
import 'transport/usb_serial_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final usb = UsbSerialService();
  final ble = BleService();

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

    // Intercept window close so we can shut down the serial port before
    // the Flutter engine tears down. Without this, flutter_libserialport's
    // read worker can crash mid-read at exit (SIGSEGV in DartWorker).
    await windowManager.setPreventClose(true);
    final closer = _CloseHandler(usb: usb, ble: ble);
    windowManager.addListener(closer);
  }

  runApp(OpenViewApp(usb: usb, ble: ble));
}

class _CloseHandler with WindowListener {
  final UsbSerialService usb;
  final BleService ble;
  _CloseHandler({required this.usb, required this.ble});

  bool _shuttingDown = false;

  @override
  void onWindowClose() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    // Run synchronous, safe-to-call shutdowns first.
    usb.shutdownSync();
    try {
      await ble.disconnect();
    } catch (_) {}
    // Give the engine a tick to absorb the closures before destroy.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await windowManager.destroy();
  }
}
