import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/sensything_ox_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor sensythingOxDescriptor = BoardDescriptor(
  id: 'sensything_ox',
  displayName: 'Sensything OX',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true, ble: true, wifi: true),
  usbProfile: const UsbProfile(
    baudRate: 115200,
    idMatches: [
      UsbIdMatch(vendorId: 0x10C4, productNameContains: 'CP210'),
      UsbIdMatch(vendorId: 0x1A86, productNameContains: 'CH340'),
    ],
  ),
  // OpenView-compatible Sensything BLE service (SensythingBLE.cpp:59-67, :103).
  // BLE streams RAW, unframed 8-byte payloads (ECG int32 + PPG int32) — no
  // 0x0A 0xFA … 0x0B wrapper — so decode each notification directly as pkt 2.
  bleProfile: const BleProfile(
    serviceUuid: '0001A7D3-D8A4-4FEA-8174-1736E808C066',
    streamCharacteristicUuid: '0002A7D3-D8A4-4FEA-8174-1736E808C066',
    nameAdvertisesContains: ['Sensything-OX'],
    framed: false,
    rawPacketType: 2,
  ),
  // AFE4400 pulse oximeter: two PPG waveforms (IR + Red). SpO2 and heart
  // rate are scalar events, not waveforms.
  // sampleRateHz must match the firmware's stream rate — the chart's time
  // window (1s/5s/…) is derived from it. Firmware streams at 125 Hz.
  channels: const [
    ChannelSpec(
      id: 'ppgIr',
      label: 'PPG (IR)',
      sampleRateHz: 125,
      unit: SignalUnit.adc,
      kind: ChannelKind.ppg,
    ),
    ChannelSpec(
      id: 'ppgRed',
      label: 'PPG (Red)',
      sampleRateHz: 125,
      unit: SignalUnit.adc,
      kind: ChannelKind.ppg,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'IR/Red/SpO2/HR',
      expectedPayloadLength: 8,
      decode: decodeSensythingOxPkt2,
    ),
  ],
  notes: 'AFE4400-based pulse oximeter. BLE streams 8-byte samples: '
      'IR, Red, SpO2, HR (4 × int16 LE).',
);
