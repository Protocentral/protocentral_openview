import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/pulse_express_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor pulseExpressDescriptor = BoardDescriptor(
  id: 'pulse_express',
  displayName: 'Pulse Express',
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
      id: 'ppgIr',
      label: 'PPG (IR)',
      sampleRateHz: 100,
      unit: SignalUnit.adc,
      kind: ChannelKind.ppg,
    ),
    ChannelSpec(
      id: 'ppgRed',
      label: 'PPG (Red)',
      sampleRateHz: 100,
      unit: SignalUnit.adc,
      kind: ChannelKind.ppg,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'PPG IR+Red',
      expectedPayloadLength: 4,
      decode: decodePulseExpressPkt2,
    ),
  ],
  notes: 'Maxim MAX32664D bio-sensor hub + MAX30102 optical sensor. '
      'The MAX32664 runs the SpO2 and heart-rate algorithm internally; '
      'the host receives pre-computed vitals alongside the raw PPG waveform.',
);
