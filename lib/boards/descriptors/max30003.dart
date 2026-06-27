import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/max30003_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor max30003Descriptor = BoardDescriptor(
  id: 'max30003',
  displayName: 'MAX30003 ECG Breakout',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true),
  usbProfile: const UsbProfile(
    baudRate: 115200,
    idMatches: [
      UsbIdMatch(vendorId: 0x10C4, productNameContains: 'CP210'),
      UsbIdMatch(vendorId: 0x1A86, productNameContains: 'CH340'),
    ],
  ),
  channels: const [
    ChannelSpec(
      id: 'ecg',
      label: 'ECG',
      sampleRateHz: 128,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'ECG + HR/RR',
      expectedPayloadLength: 12,
      decode: decodeMax30003Pkt2,
    ),
  ],
  notes: 'Maxim MAX30003 ECG analog front-end with on-chip HR/RR computation.',
);
