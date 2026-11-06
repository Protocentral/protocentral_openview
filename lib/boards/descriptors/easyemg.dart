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
    baudRate: 115200,
  ),
  // Fixed ranges, in µV at the electrodes, so rest and contraction keep their
  // real proportions on screen. Sized from a bench recording of repeated
  // forearm flexes: sEMG peaks reached about 2.2 mV and the envelope about
  // 620 µV, against about 25 µV at rest.
  channels: const [
    ChannelSpec(
      id: 'emg',
      label: 'sEMG (µV)',
      sampleRateHz: 500,
      unit: SignalUnit.uv,
      kind: ChannelKind.emg,
      displayMin: -2500,
      displayMax: 2500,
      fixedRange: true,
    ),
    ChannelSpec(
      id: 'emg_envelope',
      label: 'RMS envelope (µV)',
      sampleRateHz: 500,
      unit: SignalUnit.uv,
      kind: ChannelKind.emg,
      displayMin: 0,
      displayMax: 700,
      fixedRange: true,
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
      'a host running the 06.OpenView Arduino example at 500 Hz, shown in µV '
      'at the electrodes on a fixed scale. The sketch filters before sending: '
      'a 20 Hz high-pass and a notch on every mains harmonic up to 450 Hz '
      '(library 1.1.0 or later). Power the host from a battery when the '
      'electrodes are on a person. %MVC stays 0 until the sketch has recorded '
      'a maximum contraction, which runs for 5 seconds while the on-board LED '
      'is lit after reset.',
);
