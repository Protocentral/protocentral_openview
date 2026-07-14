// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/app_info_controller.dart';
import 'controllers/connection_controller.dart';
import 'controllers/developer_ble_controller.dart';
import 'controllers/recording_controller.dart';
import 'controllers/smp_controller.dart';
import 'controllers/recordings_browser_controller.dart';
import 'controllers/scan_controller.dart';
import 'controllers/settings_controller.dart';
import 'theme/app_theme.dart';
import 'transport/ble_service.dart';
import 'transport/usb_serial_service.dart';
import 'transport/wifi_service.dart';
import 'ui/app_routes.dart';

class OpenViewApp extends StatelessWidget {
  final UsbSerialService usb;
  final BleService ble;
  final WifiService wifi;
  final SettingsController settings;
  final AppInfoController appInfo;
  final ConnectionController connection;
  final ScanController scan;
  final RecordingController recording;
  final RecordingsBrowserController recordingsBrowser;
  final DeveloperBleController developerBle;
  final SmpController smp;

  const OpenViewApp({
    super.key,
    required this.usb,
    required this.ble,
    required this.wifi,
    required this.settings,
    required this.appInfo,
    required this.connection,
    required this.scan,
    required this.recording,
    required this.recordingsBrowser,
    required this.developerBle,
    required this.smp,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UsbSerialService>.value(value: usb),
        ChangeNotifierProvider<BleService>.value(value: ble),
        ChangeNotifierProvider<WifiService>.value(value: wifi),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AppInfoController>.value(value: appInfo),
        ChangeNotifierProvider<ConnectionController>.value(value: connection),
        ChangeNotifierProvider<ScanController>.value(value: scan),
        ChangeNotifierProvider<RecordingController>.value(value: recording),
        ChangeNotifierProvider<RecordingsBrowserController>.value(
            value: recordingsBrowser),
        ChangeNotifierProvider<DeveloperBleController>.value(
            value: developerBle),
        ChangeNotifierProvider<SmpController>.value(value: smp),
      ],
      child: Consumer<SettingsController>(
        builder: (_, settings, __) => MaterialApp.router(
          title: 'OpenView',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          routerConfig: AppRoutes.router,
        ),
      ),
    );
  }
}
