import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/ads1293_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor ads1293Descriptor = BoardDescriptor(
  id: 'ads1293',
  displayName: 'ADS1293 Breakout',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true),
  usbProfile: const UsbProfile(
    baudRate: 115200,
    idMatches: [
      UsbIdMatch(vendorId: 0x0403, productNameContains: 'FT232'),
      UsbIdMatch(vendorId: 0x10C4, productNameContains: 'CP210'),
      // Arduino Uno R4 Minima (recommended host board)
      UsbIdMatch(vendorId: 0x2341, productNameContains: 'UNO R4'),
    ],
  ),
  channels: const [
    ChannelSpec(
      id: 'ch1',
      label: 'Lead I',
      sampleRateHz: 128,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
    ),
    ChannelSpec(
      id: 'ch2',
      label: 'Lead II',
      sampleRateHz: 128,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
    ),
    ChannelSpec(
      id: 'ch3',
      label: 'V1 / Lead III',
      sampleRateHz: 128,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: '3-Lead ECG',
      expectedPayloadLength: 12,
      decode: decodeAds1293Pkt2,
    ),
  ],
  notes: 'TI ADS1293 3-channel 24-bit ECG AFE. Supports 3-lead and 5-lead '
      'configurations (Lead I, Lead II, V1).',
);
