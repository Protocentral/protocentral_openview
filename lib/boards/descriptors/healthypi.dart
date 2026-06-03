import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/healthypi_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor healthypiDescriptor = BoardDescriptor(
  id: 'healthypi',
  displayName: 'HealthyPi 5',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true),
  usbProfile: const UsbProfile(
    baudRate: 230400,
    idMatches: [
      // nRF5340 USB CDC (HealthyPi 5 onboard MCU)
      UsbIdMatch(vendorId: 0x1915, productNameContains: 'nRF'),
      // Fallback: FTDI / CP210x on adapter boards
      UsbIdMatch(vendorId: 0x0403, productNameContains: 'FT232'),
      UsbIdMatch(vendorId: 0x10C4, productNameContains: 'CP210'),
    ],
  ),
  channels: const [
    ChannelSpec(
      id: 'ecg',
      label: 'ECG',
      sampleRateHz: 125,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
    ),
    ChannelSpec(
      id: 'bioz',
      label: 'BioZ / Respiration',
      sampleRateHz: 62,
      unit: SignalUnit.adc,
      kind: ChannelKind.bioz,
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
      pktType: 3,
      label: 'ECG/BioZ/HR/RespRate',
      expectedPayloadLength: 51,
      decode: decodeHealthypiPkt3,
    ),
    PacketSpec(
      pktType: 4,
      label: 'PPG/Temp/SpO2',
      expectedPayloadLength: 20,
      decode: decodeHealthypiPkt4,
    ),
  ],
  notes: 'HealthyPi 5 vital-signs HAT — nRF5340 MCU, ADS1293 ECG/BioZ, '
      'MAX30101 PPG. Sends two interleaved packet types (0x03 ECG/BioZ, '
      '0x04 PPG).',
);
