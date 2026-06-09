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
    healthypiDescriptorCombined,
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
