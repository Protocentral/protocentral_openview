// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/easyemg_decoders.dart';
import '../metric_spec.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor easyEmgDescriptor = BoardDescriptor(
  id: 'easyemg',
  displayName: 'easyEMG Breakout',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true),
  usbProfile: const UsbProfile(
    baudRate: 57600,
  ),
  channels: const [
    ChannelSpec(
      id: 'emg',
      label: 'sEMG',
      sampleRateHz: 125,
      unit: SignalUnit.adc,
      kind: ChannelKind.emg,
      displayMin: -2048,
      displayMax: 2047,
    ),
    ChannelSpec(
      id: 'emg_envelope',
      label: 'RMS envelope',
      sampleRateHz: 125,
      unit: SignalUnit.adc,
      kind: ChannelKind.emg,
      displayMin: 0,
      displayMax: 2048,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'sEMG/Envelope/%MVC',
      expectedPayloadLength: 8,
      decode: decodeEasyEmgPkt2,
    ),
  ],
  metrics: const [
    MetricSpec(
      eventKey: 'percentMvc',
      label: 'Effort (MVC)',
      kind: MetricKind.effort,
      unit: '%',
    ),
  ],
  notes: 'ProtoCentral easyEMG surface EMG breakout (Qwiic), streamed through '
      'a host running the 06.OpenView Arduino example. By default the sketch '
      'records a 5-second maximum contraction at startup and sends no packets '
      'until that finishes; %MVC stays 0 if the step is disabled.',
);
