import 'board_descriptor.dart';
import 'descriptors/ads1292r.dart';
import 'descriptors/ads1293.dart';
import 'descriptors/afe4490.dart';
import 'descriptors/healthypi.dart';
import 'descriptors/max30001.dart';
import 'descriptors/max30003.dart';
import 'descriptors/max86150.dart';
import 'descriptors/pulse_express.dart';
import 'descriptors/sensything_cap.dart';
import 'descriptors/sensything_ox.dart';
import 'descriptors/tinygsr.dart';
import 'descriptors/tmf8829.dart';

/// Canonical list of every board OpenView 3 supports.
///
/// Adding a new board: write a descriptor under `boards/descriptors/`, then
/// register it here. No other edits required anywhere in the app.
class BoardRegistry {
  BoardRegistry._();

  static final List<BoardDescriptor> all = [
    healthypiDescriptor,
    sensythingOxDescriptor,
    sensythingCapDescriptor,
    ads1293Descriptor,
    ads1292rDescriptor,
    afe4490Descriptor,
    max30003Descriptor,
    max30001Descriptor,
    max86150Descriptor,
    pulseExpressDescriptor,
    tinyGsrDescriptor,
    tmf8829Descriptor,
  ];

  static BoardDescriptor? byId(String id) {
    for (final b in all) {
      if (b.id == id) return b;
    }
    return null;
  }

  static Iterable<BoardDescriptor> usbCapable() =>
      all.where((b) => b.transports.usb);

  static Iterable<BoardDescriptor> bleCapable() =>
      all.where((b) => b.transports.ble);

  /// Find the BLE-capable descriptor for an advertised service UUID / device
  /// name. BLE is currently Sensything-only, so this only ever resolves to the
  /// Sensything descriptors. Returns null if no match.
  ///
  /// Advertised-name matching is tried **first**: Sensything OX and CAP share
  /// the same OpenView service UUID, so the name (`Sensything-OX` vs
  /// `Sensything-CAP`) is the only reliable discriminator. Service-UUID
  /// matching is the fallback for devices whose name we can't read.
  static BoardDescriptor? matchBle({
    List<String>? serviceUuids,
    String? advertisedName,
  }) {
    String norm(String s) => s.toLowerCase().replaceAll('-', '');

    // 1) Specific advertised-name match.
    if (advertisedName != null && advertisedName.isNotEmpty) {
      final lower = advertisedName.toLowerCase();
      for (final b in all) {
        final profile = b.bleProfile;
        if (profile == null) continue;
        if (profile.nameAdvertisesContains
            .any((n) => lower.contains(n.toLowerCase()))) {
          return b;
        }
      }
    }

    // 2) Service-UUID fallback.
    final advertised = serviceUuids?.map(norm).toList() ?? const [];
    for (final b in all) {
      final profile = b.bleProfile;
      if (profile == null) continue;
      final svc = norm(profile.serviceUuid);
      if (advertised.any((u) => u == svc || u.endsWith(svc) || svc.endsWith(u))) {
        return b;
      }
    }
    return null;
  }

  /// Find the first descriptor whose USB profile plausibly matches the given
  /// port name / VID / PID. Returns null if no match.
  static BoardDescriptor? matchUsb({
    int? vendorId,
    int? productId,
    String? productName,
  }) {
    for (final b in all) {
      final profile = b.usbProfile;
      if (profile == null) continue;
      for (final m in profile.idMatches) {
        if (vendorId != null && m.vendorId != vendorId) continue;
        if (m.productId != null &&
            productId != null &&
            m.productId != productId) continue;
        if (m.productNameContains != null &&
            productName != null &&
            !productName.toLowerCase().contains(
                m.productNameContains!.toLowerCase())) continue;
        return b;
      }
    }
    return null;
  }
}
