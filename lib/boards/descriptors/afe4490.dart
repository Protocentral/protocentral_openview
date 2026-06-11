import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/afe4490_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor afe4490Descriptor = BoardDescriptor(
  id: 'afe4490',
  displayName: 'AFE4490 Breakout',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true),
  usbProfile: const UsbProfile(
    baudRate: 57600,
    idMatches: [
      UsbIdMatch(vendorId: 0x0403, productNameContains: 'FT232'),
      UsbIdMatch(vendorId: 0x10C4, productNameContains: 'CP210'),
    ],
  ),
  channels: const [
    ChannelSpec(
      id: 'ppgRed',
      label: 'PPG (Red)',
      sampleRateHz: 100,
      unit: SignalUnit.adc,
      kind: ChannelKind.ppg,
    ),
    ChannelSpec(
      id: 'ppgIr',
      label: 'PPG (IR)',
      sampleRateHz: 100,
      unit: SignalUnit.adc,
      kind: ChannelKind.ppg,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'PPG Red+IR/HR/SpO2',
      expectedPayloadLength: 10,
      decode: decodeAfe4490Pkt2,
    ),
  ],
  notes: 'TI AFE4490 22-bit dual-LED pulse-oximetry front-end. '
      'Accepts standard Nellcor-compatible DB9 SpO2 finger probe. '
      'SpO2 and heart rate computed on-device.',
);
