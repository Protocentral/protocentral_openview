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
  final ConnectionController connection;
  final ScanController scan;
  final RecordingController recording;
  final RecordingsBrowserController recordingsBrowser;

  const OpenViewApp({
    super.key,
    required this.usb,
    required this.ble,
    required this.connection,
    required this.scan,
    required this.recording,
    required this.recordingsBrowser,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UsbSerialService>.value(value: usb),
        ChangeNotifierProvider<BleService>.value(value: ble),
        ChangeNotifierProvider<ConnectionController>.value(value: connection),
        ChangeNotifierProvider<ScanController>.value(value: scan),
        ChangeNotifierProvider<RecordingController>.value(value: recording),
        ChangeNotifierProvider<RecordingsBrowserController>.value(
            value: recordingsBrowser),
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
