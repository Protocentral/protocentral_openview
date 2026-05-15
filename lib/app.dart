import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/connection_controller.dart';
import 'controllers/recording_controller.dart';
import 'controllers/recordings_browser_controller.dart';
import 'controllers/scan_controller.dart';
import 'theme/app_theme.dart';
import 'transport/ble_service.dart';
import 'transport/usb_serial_service.dart';
import 'ui/app_routes.dart';

class OpenViewApp extends StatelessWidget {
  final UsbSerialService usb;
  final BleService ble;

  const OpenViewApp({super.key, required this.usb, required this.ble});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UsbSerialService>.value(value: usb),
        ChangeNotifierProvider<BleService>.value(value: ble),
        ChangeNotifierProxyProvider2<UsbSerialService, BleService,
            ScanController>(
          create: (_) => ScanController(usb: usb, ble: ble),
          update: (_, u, b, prev) => prev ?? ScanController(usb: u, ble: b),
        ),
        ChangeNotifierProxyProvider2<UsbSerialService, BleService,
            ConnectionController>(
          create: (_) => ConnectionController(usb: usb, ble: ble),
          update: (_, u, b, prev) =>
              prev ?? ConnectionController(usb: u, ble: b),
        ),
        ChangeNotifierProxyProvider<ConnectionController, RecordingController>(
          create: (ctx) => RecordingController(
            connection: ctx.read<ConnectionController>(),
          ),
          update: (_, conn, prev) =>
              prev ?? RecordingController(connection: conn),
        ),
        ChangeNotifierProvider<RecordingsBrowserController>(
          create: (_) => RecordingsBrowserController(),
        ),
      ],
      child: MaterialApp.router(
        title: 'OpenView',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        routerConfig: AppRoutes.router,
      ),
    );
  }
}
