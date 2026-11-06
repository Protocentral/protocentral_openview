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
      // Over 100% means the MVC came from a weak contraction. Library 1.1.0
      // refuses weak ones and raises the MVC on a stronger contraction, so
      // this shows only with older firmware or MVC_AUTO_RAISE off.
      warnAbove: 100,
      warnAboveText: 'Above your MVC: record it again',
    ),
    MetricSpec(
      eventKey: 'mvcStep',
      label: 'MVC',
      kind: MetricKind.signalStatus,
      states: {
        0: MetricState('Not recorded', MetricSeverity.warning),
        1: MetricState('Relax…', MetricSeverity.warning),
        2: MetricState('Contract hard now', MetricSeverity.warning),
        3: MetricState('Too weak: try again', MetricSeverity.error),
        4: MetricState('Recorded', MetricSeverity.ok),
      },
      // 'm' makes the 06.OpenView sketch run its MVC step again: 2 s relaxed,
      // then 5 s of the hardest contraction you can hold.
      action: CommandSpec(
        id: 'easyemg_record_mvc',
        label: 'Record MVC',
        bytes: [0x6D],
      ),
    ),
  ],
  notes: 'ProtoCentral easyEMG surface EMG breakout (Qwiic), streamed through '
      'a host running the 06.OpenView Arduino example at 500 Hz, shown in µV '
      'at the electrodes on a fixed scale. The sketch filters before sending: '
      'a 20 Hz high-pass and a notch on every mains harmonic up to 450 Hz '
      '(library 1.1.0 or later). Power the host from a battery when the '
      'electrodes are on a person. %MVC stays 0 until a maximum contraction '
      '(MVC) is recorded: after reset, or with Record MVC, relax for 2 s, then '
      'contract as hard as you can for 5 s while the board LED is lit. The MVC '
      'tile shows each step (library 1.1.0 or later).',
);
