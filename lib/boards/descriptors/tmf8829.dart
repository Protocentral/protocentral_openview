import '../board_descriptor.dart';
import '../decoders/tmf8829_decoders.dart';
import '../matrix_spec.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

/// ProtoCentral TMF8829 dToF ranging board.
///
/// Sensor: ams-OSRAM TMF8829. Supports per-session-fixed pixel grids from
/// 8×8 up to 48×32. Each frame is distance in millimetres (uint16, 0 = no
/// return). Frame rate ~10 Hz at full resolution.
final BoardDescriptor tmf8829Descriptor = BoardDescriptor(
  id: 'tmf8829',
  displayName: 'TMF8829 dToF',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true),
  usbProfile: const UsbProfile(
    baudRate: 921600,
    idMatches: [
      UsbIdMatch(vendorId: 0x10C4, productNameContains: 'CP210'),
      UsbIdMatch(vendorId: 0x1A86, productNameContains: 'CH340'),
    ],
  ),
  matrices: const [
    MatrixSpec(
      id: 'depth_map',
      label: 'Depth (TMF8829)',
      rows: 48,
      cols: 32,
      frameRateHz: 10,
      dtype: MatrixDataType.uint16,
      semantics: MatrixSemantics.depth,
      colorMap: 'viridis',
      minValue: 0,
      maxValue: 4000, // 4 m typical max range
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 6,
      label: 'dToF depth frame',
      decode: decodeTmf8829Pkt6,
    ),
  ],
  notes:
      'ams-OSRAM TMF8829 direct Time-of-Flight ranging. Per-frame rows/cols '
      'are read from the packet payload so the same descriptor handles all '
      'supported grid modes (8×8 through 48×32). Distance in mm; 0 = no return.',
);
