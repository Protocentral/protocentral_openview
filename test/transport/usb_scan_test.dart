// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:OpenView/controllers/scan_controller.dart';
import 'package:OpenView/transport/ble_service.dart';
import 'package:OpenView/transport/transport_service.dart';
import 'package:OpenView/transport/usb_serial_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const loadError = "Failed to load dynamic library 'libserialport.so': "
      "version `GLIBC_2.42' not found";

  ScanController controllerFor(List<String> Function() listPorts) =>
      ScanController(
        usb: UsbSerialService(listPorts: listPorts),
        ble: BleService(),
      );

  test('a failed port listing reaches the caller and resets the status',
      () async {
    final usb = UsbSerialService(listPorts: () => throw ArgumentError(loadError));

    await expectLater(usb.scan(), throwsArgumentError);
    expect(usb.status, TransportStatus.idle);
  });

  test('the scan controller reports the failure instead of no devices',
      () async {
    final scan = controllerFor(() => throw ArgumentError(loadError));

    await scan.refresh(includeBle: false);

    expect(scan.lastError, contains('GLIBC_2.42'));
    expect(scan.usbResults, isEmpty);
    expect(scan.scanning, isFalse);
  });

  test('a failed rescan drops ports from the previous scan', () async {
    var fail = false;
    final scan = controllerFor(
        () => fail ? throw ArgumentError(loadError) : const <String>[]);

    await scan.refresh(includeBle: false);
    expect(scan.lastError, isNull);

    fail = true;
    await scan.refresh(includeBle: false);
    expect(scan.lastError, isNotNull);
    expect(scan.usbResults, isEmpty);
  });

  test('no ports and no error stays a clean empty result', () async {
    final scan = controllerFor(() => const []);

    await scan.refresh(includeBle: false);

    expect(scan.lastError, isNull);
    expect(scan.usbResults, isEmpty);
  });
}
