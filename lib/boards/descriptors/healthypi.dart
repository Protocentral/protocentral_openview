import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/healthypi_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

const _usbProfile = UsbProfile(
  //baudRate: 230400,
  baudRate: 115200,
  idMatches: [
    // nRF5340 USB CDC (HealthyPi 5 onboard MCU)
    UsbIdMatch(vendorId: 0x1915, productNameContains: 'nRF'),
    // Fallback: FTDI / CP210x on adapter boards
    UsbIdMatch(vendorId: 0x0403, productNameContains: 'FT232'),
    UsbIdMatch(vendorId: 0x10C4, productNameContains: 'CP210'),
  ],
);

// ── Shared: channel specs (reused across firmware variants) ─────────────

const _ecgChannel = ChannelSpec(
  id: 'ecg',
  label: 'ECG',
  sampleRateHz: 125,
  unit: SignalUnit.adc,
  kind: ChannelKind.ecg,
);

const _biozChannel = ChannelSpec(
  id: 'bioz',
  label: 'BioZ / Respiration',
  sampleRateHz: 62,
  unit: SignalUnit.adc,
  kind: ChannelKind.bioz,
);

const _ppgRedChannel = ChannelSpec(
  id: 'ppgRed',
  label: 'PPG (Red)',
  sampleRateHz: 100,
  unit: SignalUnit.adc,
  kind: ChannelKind.ppg,
);

// ppgIr is exclusive to the combined FW (pktType 5); not produced by batch FW.
const _ppgIrChannel = ChannelSpec(
  id: 'ppgIr',
  label: 'PPG (IR)',
  sampleRateHz: 100,
  unit: SignalUnit.adc,
  kind: ChannelKind.ppg,
);


// ── combined single-sample packet ───────────────────────
//
// Targets firmware that sends one unified packet type per sample tick:
//   pktType 5 — ECG + BioZ + PPG-Red + PPG-IR, all time-aligned,
//               with a per-sample BioZ validity flag (bioZSkip).
//
// Channels: ECG · BioZ · PPG-Red · PPG-IR

final BoardDescriptor healthypiDescriptor = BoardDescriptor(
  id: 'healthypi',
  displayName: 'HealthyPi 5',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true, wifi: true),
  usbProfile: _usbProfile,
  channels: const [
    _ecgChannel,
    _biozChannel,
    _ppgRedChannel,
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'ECG/BioZ/PPG-Red/PPG-IR/Temp/SpO2/HR/RR',
      expectedPayloadLength: 22,
      decode: decodeHealthypiPkt2,
    ),
  ],
  notes: 'HealthyPi 5 — Combined firmware. nRF5340 MCU, ADS1293 ECG/BioZ, '
      'MAX30101 PPG. Single packet type 0x05 carries one sample of every '
      'channel per tick, with per-sample BioZ validity flag (bioZSkip).',
);

