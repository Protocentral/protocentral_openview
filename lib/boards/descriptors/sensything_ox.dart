import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/sensything_ox_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor sensythingOxDescriptor = BoardDescriptor(
  id: 'sensything_ox',
  displayName: 'Sensything OX',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true, ble: true),
  usbProfile: const UsbProfile(
    baudRate: 115200,
    idMatches: [
      UsbIdMatch(vendorId: 0x10C4, productNameContains: 'CP210'),
      UsbIdMatch(vendorId: 0x1A86, productNameContains: 'CH340'),
    ],
  ),
  bleProfile: const BleProfile(
    serviceUuid: 'cd5c0001-4448-7db8-ae4c-d1da8cba36d0',
    streamCharacteristicUuid: 'cd5c0002-4448-7db8-ae4c-d1da8cba36d0',
    nameAdvertisesContains: ['Sensything', 'OX'],
  ),
  channels: const [
    ChannelSpec(
      id: 'ecg',
      label: 'ECG',
      sampleRateHz: 128,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
    ),
    ChannelSpec(
      id: 'ppg',
      label: 'PPG',
      sampleRateHz: 128,
      unit: SignalUnit.adc,
      kind: ChannelKind.ppg,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'ECG/PPG/SpO2/HR',
      expectedPayloadLength: 10,
      decode: decodeSensythingOxPkt2,
    ),
  ],
  notes: 'AFE4490-based pulse oximetry + ECG front-end.',
);
