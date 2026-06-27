/// Bitmask of supported transports for a board.
class TransportSupport {
  final bool ble;
  final bool usb;
  final bool wifi;

  const TransportSupport({this.ble = false, this.usb = false, this.wifi = false});

  bool get hasAny => ble || usb || wifi;
}

/// USB-serial profile for a board: vendor/product hints and link parameters.
class UsbProfile {
  final List<UsbIdMatch> idMatches;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final UsbParity parity;

  const UsbProfile({
    this.idMatches = const [],
    this.baudRate = 115200,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = UsbParity.none,
  });
}

class UsbIdMatch {
  final int vendorId;
  final int? productId;
  final String? productNameContains;
  const UsbIdMatch({required this.vendorId, this.productId, this.productNameContains});
}

enum UsbParity { none, odd, even }

/// BLE profile for a board.
class BleProfile {
  final String serviceUuid;
  final String streamCharacteristicUuid;
  final String? commandCharacteristicUuid;
  final List<String> nameAdvertisesContains;

  /// Whether the BLE notification stream uses the ProtoCentral framing
  /// (`0x0A 0xFA … 0x0B`). Some firmwares (e.g. Sensything OX) stream **raw**
  /// payloads with no framing — BLE already provides message boundaries — in
  /// which case set this false and provide [rawPacketType].
  final bool framed;

  /// When [framed] is false, each notification is treated as one raw payload
  /// of this packet type and decoded directly via the board's `PacketSpec`.
  final int rawPacketType;

  const BleProfile({
    required this.serviceUuid,
    required this.streamCharacteristicUuid,
    this.commandCharacteristicUuid,
    this.nameAdvertisesContains = const [],
    this.framed = true,
    this.rawPacketType = 0,
  });
}
