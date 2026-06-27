import 'package:flutter/foundation.dart';

import '../boards/board_descriptor.dart';
import '../boards/board_registry.dart';
import '../transport/ble_service.dart';
import '../transport/transport_service.dart';
import '../transport/usb_serial_service.dart';

/// One row in the scan results list: a transport target with the registry's
/// best guess at which descriptor it represents (if any).
class ScanResult {
  final TransportTarget target;
  final BoardDescriptor? suggestedDescriptor;
  const ScanResult({required this.target, this.suggestedDescriptor});
}

/// Coordinates scanning across USB + BLE transports.
class ScanController extends ChangeNotifier {
  final UsbSerialService usb;
  final BleService ble;

  ScanController({required this.usb, required this.ble});

  bool _scanning = false;
  bool get scanning => _scanning;

  List<ScanResult> _usbResults = const [];
  List<ScanResult> get usbResults => _usbResults;

  List<ScanResult> _bleResults = const [];
  List<ScanResult> get bleResults => _bleResults;

  String? _lastError;
  String? get lastError => _lastError;

  Future<void> refresh({bool includeBle = true, bool includeUsb = true}) async {
    if (_scanning) return;
    _scanning = true;
    _lastError = null;
    notifyListeners();
    try {
      if (includeUsb) {
        final targets = await usb.scan();
        _usbResults = targets.map(_annotate).toList(growable: false);
      } else {
        _usbResults = const [];
      }
      if (includeBle) {
        final targets = await ble.scan();
        _bleResults = targets.map(_annotate).toList(growable: false);
      } else {
        _bleResults = const [];
      }
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  ScanResult _annotate(TransportTarget target) {
    BoardDescriptor? suggested;
    if (target.kind == TransportKind.usb) {
      final vid = target.extra['vendorId'] as int?;
      final pid = target.extra['productId'] as int?;
      final desc = target.extra['description'] as String?;
      suggested = BoardRegistry.matchUsb(
        vendorId: vid,
        productId: pid,
        productName: desc,
      );
    } else if (target.kind == TransportKind.ble) {
      // BleService tags the matched descriptor id during the scan; fall back
      // to re-matching by the advertised service UUIDs if absent.
      final descriptorId = target.extra['descriptorId'] as String?;
      suggested = descriptorId != null
          ? BoardRegistry.byId(descriptorId)
          : BoardRegistry.matchBle(
              serviceUuids:
                  (target.extra['serviceUuids'] as List?)?.cast<String>(),
              advertisedName: target.displayName,
            );
    }
    return ScanResult(target: target, suggestedDescriptor: suggested);
  }
}
