// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/max30001_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor max30001Descriptor = BoardDescriptor(
  id: 'max30001',
  displayName: 'MAX30001 ECG & BioZ Breakout',
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
      sampleRateHz: 128,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
    ),
    ChannelSpec(
      id: 'bioz',
      label: 'BioZ / Respiration',
      sampleRateHz: 128,
      unit: SignalUnit.adc,
      kind: ChannelKind.bioz,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'ECG/BioZ/HR/RR',
      expectedPayloadLength: 12,
      decode: decodeMax30001Pkt2,
    ),
  ],
  notes: 'Maxim MAX30001 single-lead 18-bit ECG and 19-bit bio-impedance '
      '(BioZ) AFE. BioZ channel used for thoracic impedance respiration '
      'monitoring. R-R interval and heart rate derived on-device via the '
      'RTOR engine.',
);
