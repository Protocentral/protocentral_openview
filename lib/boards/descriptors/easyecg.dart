// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import '../board_descriptor.dart';
import '../channel_spec.dart';
import '../decoders/easyecg_decoders.dart';
import '../metric_spec.dart';
import '../packet_spec.dart';
import '../transport_profile.dart';

final BoardDescriptor easyEcgDescriptor = BoardDescriptor(
  id: 'easyecg',
  displayName: 'easyECG Breakout',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true),
  usbProfile: const UsbProfile(
    baudRate: 57600,
  ),
  channels: const [
    ChannelSpec(
      id: 'ecg',
      label: 'ECG (filtered)',
      sampleRateHz: 125,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
      displayMin: -2048,
      displayMax: 2047,
    ),
    ChannelSpec(
      id: 'ecg_unfiltered',
      label: 'ECG (unfiltered)',
      sampleRateHz: 125,
      unit: SignalUnit.adc,
      kind: ChannelKind.ecg,
      displayMin: -2048,
      displayMax: 2047,
      optional: true,
    ),
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'ECG/HR/Status',
      expectedPayloadLength: 8,
      decode: decodeEasyEcgPkt2,
    ),
  ],
  metrics: const [
    MetricSpec(
      eventKey: 'heartRate',
      label: 'Heart rate',
      kind: MetricKind.heartRate,
      unit: 'bpm',
      zeroMeansNoData: true,
      qualityEventKey: 'signalStatus',
    ),
    MetricSpec(
      eventKey: 'signalStatus',
      label: 'Signal',
      kind: MetricKind.signalStatus,
      states: {
        0: MetricState('OK', MetricSeverity.ok),
        1: MetricState('Lead-off or mains pickup', MetricSeverity.warning),
        2: MetricState('Amplifier saturated', MetricSeverity.error),
      },
    ),
  ],
  notes: 'ProtoCentral easyECG single-lead ECG breakout (Qwiic), streamed '
      'through a host running the 04.OpenView Arduino example. signalStatus: '
      '0 = OK, 1 = lead-off or mains pickup, 2 = amplifier saturated.',
);
