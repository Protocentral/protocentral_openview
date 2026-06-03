import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/max86150_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor max86150Descriptor = BoardDescriptor(
  id: 'max86150',
  displayName: 'MAX86150 Breakout',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true),
  usbProfile: const UsbProfile(
    baudRate: 115200,
    idMatches: [
      UsbIdMatch(vendorId: 0x0403, productNameContains: 'FT232'),
      UsbIdMatch(vendorId: 0x10C4, productNameContains: 'CP210'),
      UsbIdMatch(vendorId: 0x2341, productNameContains: 'UNO R4'),
    ],
  ),
  channels: const [
    ChannelSpec(
      id: 'ecg',
      label: 'ECG',
      sampleRateHz: 200,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
    ),
    ChannelSpec(
      id: 'ppgRed',
      label: 'PPG (Red)',
      sampleRateHz: 200,
      unit: SignalUnit.adc,
      kind: ChannelKind.ppg,
    ),
    ChannelSpec(
      id: 'ppgIr',
      label: 'PPG (IR)',
      sampleRateHz: 200,
      unit: SignalUnit.adc,
      kind: ChannelKind.ppg,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'ECG/PPG Red+IR/HR/SpO2',
      expectedPayloadLength: 16,
      decode: decodeMax86150Pkt2,
    ),
  ],
  notes: 'Maxim MAX86150 integrated single-lead ECG (18-bit) and dual-LED '
      'PPG (18-bit Red + IR) AFE. ECG and PPG share the same packet. '
      'SpO2 and heart rate computed on-device.',
);
