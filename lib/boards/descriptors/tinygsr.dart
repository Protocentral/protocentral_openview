// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/tinygsr_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor tinyGsrDescriptor = BoardDescriptor(
  id: 'tinygsr',
  displayName: 'tinyGSR Breakout',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true),
  usbProfile: const UsbProfile(
    baudRate: 57600,
    idMatches: [
      UsbIdMatch(vendorId: 0x0403, productNameContains: 'FT232'),
      UsbIdMatch(vendorId: 0x10C4, productNameContains: 'CP210'),
      UsbIdMatch(vendorId: 0x2341, productNameContains: 'UNO R4'),
    ],
  ),
  channels: const [
    ChannelSpec(
      id: 'gsr',
      label: 'GSR/EDA',
      sampleRateHz: 10,
      unit: SignalUnit.adc,
      kind: ChannelKind.gsr,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'GSR/Resistance',
      expectedPayloadLength: 8,
      decode: decodeTinyGsrPkt2,
    ),
  ],
  notes: 'ProtoCentral tinyGSR Galvanic Skin Response (GSR) / '
      'Electrodermal Activity (EDA) breakout. Qwiic / STEMMA QT compatible. '
      'Raw 24-bit ADC count and derived skin resistance are streamed at ~10 Hz.',
);
