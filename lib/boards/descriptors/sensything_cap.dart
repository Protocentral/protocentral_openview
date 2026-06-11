import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/sensything_cap_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

/// Sensything CAP — 4-channel capacitive sensing front-end.
///
/// Wire format: 0x0A | 0xFA | len_LSB | len_MSB | 0x02 | <8 bytes> | 0x0B
/// Payload: 4 × int16 LE. BLE and USB are byte-identical.
final BoardDescriptor sensythingCapDescriptor = BoardDescriptor(
  id: 'sensything_cap',
  displayName: 'Sensything CAP',
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
    nameAdvertisesContains: ['Sensything', 'CAP'],
  ),
  channels: const [
    ChannelSpec(
      id: 'ch1',
      label: 'Channel 1',
      sampleRateHz: 100,
      unit: SignalUnit.adc,
      kind: ChannelKind.capacitance,
    ),
    ChannelSpec(
      id: 'ch2',
      label: 'Channel 2',
      sampleRateHz: 100,
      unit: SignalUnit.adc,
      kind: ChannelKind.capacitance,
    ),
    ChannelSpec(
      id: 'ch3',
      label: 'Channel 3',
      sampleRateHz: 100,
      unit: SignalUnit.adc,
      kind: ChannelKind.capacitance,
    ),
    ChannelSpec(
      id: 'ch4',
      label: 'Channel 4',
      sampleRateHz: 100,
      unit: SignalUnit.adc,
      kind: ChannelKind.capacitance,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: '4ch capacitance',
      expectedPayloadLength: 8,
      decode: decodeSensythingCapPkt2,
    ),
  ],
  notes: '4-channel capacitive front-end. BLE and USB share the same packet format (see SensythingBLE.cpp:142).',
);
