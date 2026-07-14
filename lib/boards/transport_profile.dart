// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

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

/// One notify-capable characteristic a board streams data from.
///
/// Boards like the Sensything family expose a single stream characteristic, but
/// others (e.g. HealthyPi 5) split their signals across **several**
/// characteristics — often in **different GATT services** — each carrying one
/// packet type. A [BleProfile] therefore holds a list of these.
class BleStreamSpec {
  /// GATT service that owns this characteristic.
  final String serviceUuid;

  /// The notify characteristic to subscribe to.
  final String characteristicUuid;

  /// Whether notifications on this characteristic use ProtoCentral framing
  /// (`0x0A 0xFA … 0x0B`). When false, each notification is one raw payload of
  /// [pktType], decoded directly via the board's `PacketSpec` (BLE already
  /// provides the message boundary).
  final bool framed;

  /// When [framed] is false, the packet type every notification on this
  /// characteristic is decoded as. Ignored when [framed] is true (the frame
  /// carries its own type byte).
  final int pktType;

  const BleStreamSpec({
    required this.serviceUuid,
    required this.characteristicUuid,
    this.framed = false,
    this.pktType = 0,
  });
}

/// BLE profile for a board.
///
/// Two shapes are supported:
///  * **Single-characteristic** (Sensything): set [serviceUuid] +
///    [streamCharacteristicUuid] + [framed]/[rawPacketType]. Leave [streams]
///    empty.
///  * **Multi-characteristic** (HealthyPi 5): populate [streams] with one
///    [BleStreamSpec] per notify characteristic — they may live in different
///    services. [serviceUuid] is still used for scan-time discovery/matching.
///
/// [resolvedStreams] normalizes both shapes into a single list the transport
/// iterates over, so callers never branch on which shape a board used.
class BleProfile {
  /// Primary/advertised service — used for scan matching and, in the
  /// single-characteristic shape, as the service holding the stream/command
  /// characteristics.
  final String serviceUuid;

  /// Single-characteristic stream (Sensything shape). Null when [streams] is
  /// used instead.
  final String? streamCharacteristicUuid;

  /// Multiple stream characteristics (HealthyPi 5 shape). Takes precedence over
  /// [streamCharacteristicUuid] when non-empty.
  final List<BleStreamSpec> streams;

  /// Service that owns the command characteristic. Defaults to [serviceUuid]
  /// when null — set it only when commands live in a different service.
  final String? commandServiceUuid;
  final String? commandCharacteristicUuid;
  final List<String> nameAdvertisesContains;

  /// Framing for the single-characteristic shape. See [BleStreamSpec.framed].
  final bool framed;

  /// Packet type for the single-characteristic shape when [framed] is false.
  final int rawPacketType;

  const BleProfile({
    required this.serviceUuid,
    this.streamCharacteristicUuid,
    this.streams = const [],
    this.commandServiceUuid,
    this.commandCharacteristicUuid,
    this.nameAdvertisesContains = const [],
    this.framed = true,
    this.rawPacketType = 0,
  });

  /// The concrete list of characteristics to subscribe to, collapsing the
  /// single-characteristic shape into the multi-stream form so the transport
  /// has one code path.
  List<BleStreamSpec> get resolvedStreams => streams.isNotEmpty
      ? streams
      : [
          BleStreamSpec(
            serviceUuid: serviceUuid,
            characteristicUuid: streamCharacteristicUuid ?? '',
            framed: framed,
            pktType: rawPacketType,
          ),
        ];
}
