// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/ads1292r_decoders.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor ads1292rDescriptor = BoardDescriptor(
  id: 'ads1292r',
  displayName: 'ADS1292R Breakout',
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
      id: 'ecg',
      label: 'ECG',
      sampleRateHz: 125,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
    ),
    ChannelSpec(
      id: 'resp',
      label: 'Respiration',
      sampleRateHz: 125,
      unit: SignalUnit.adc,
      kind: ChannelKind.resp,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'ECG/Resp/HR/RR',
      expectedPayloadLength: 8,
      decode: decodeAds1292rPkt2,
    ),
  ],
  notes: 'TI ADS1292R 2-channel ECG/respiration analog front-end.',
);
