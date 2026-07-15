// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

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

const _ppgIrChannel = ChannelSpec(
  id: 'ppgIr',
  label: 'PPG (IR)',
  sampleRateHz: 100,
  unit: SignalUnit.adc,
  kind: ChannelKind.ppg,
);

// ── BLE profile (HealthyPi 5) ───────────────────────────────────────────
//
// Unlike the Sensything family (one service, one characteristic), HealthyPi 5
// spreads its signals across **several GATT services**, with **one
// characteristic per signal** — no batching. OpenView subscribes to each and
// routes it to a synthetic per-signal packet type (see healthypi_decoders.dart:
// hpiBlePkt*). Every notification is RAW (no 0x0A…0x0B framing) and
// little-endian.
//
// UUIDs verified against ProtoCentral OpenView 2 (lib/globals.dart). Standard
// SIG services (HR 0x180D, PLX 0x1822, Health Thermometer 0x1809) are given in
// full 128-bit form; the transport matches either short or long forms.
//
// Characteristic → signal:
//   ECG_CHAR   (0x1424, in ECG service 0x1122) → ecg   (int32 LE run)
//   RESP_CHAR  (babe4a4c…)                       → bioz  (int32 LE run)
//   HIST_CHAR  (cd5c1525…, in HRV service)       → ppgRed(int16 LE run)
//   HR_CHAR    (0x2A37, HR service)              → heartRate (byte[1])
//   SPO2_CHAR  (0x2A5E, PLX service)             → spo2      (byte[1])
//   TEMP_CHAR  (0x2A6E, thermometer service)     → temperature (int16 LE ×0.01)
//   HRV_CHAR   (cd5ca86f…, HRV service)          → respRate  (byte[0])
// Commands are written to CMD_CHAR in the command/data service.
const _svcEcg = '00001122-0000-1000-8000-00805f9b34fb';
const _svcHrv = 'cd5c7491-4448-7db8-ae4c-d1da8cba36d0';
const _svcHr = '0000180d-0000-1000-8000-00805f9b34fb';
const _svcSpo2 = '00001822-0000-1000-8000-00805f9b34fb';
const _svcTemp = '00001809-0000-1000-8000-00805f9b34fb';
const _svcCmdData = '01bf7492-970f-8d96-d44d-9023c47faddc';

const _charEcg = '00001424-0000-1000-8000-00805f9b34fb';
const _charResp = 'babe4a4c-7789-11ed-a1eb-0242ac120002';
const _charPpg = 'cd5c1525-4448-7db8-ae4c-d1da8cba36d0';
const _charHr = '00002a37-0000-1000-8000-00805f9b34fb';
const _charSpo2 = '00002a5e-0000-1000-8000-00805f9b34fb';
const _charTemp = '00002a6e-0000-1000-8000-00805f9b34fb';
const _charHrv = 'cd5ca86f-4448-7db8-ae4c-d1da8cba36d0';
const _charCmd = '01bf1528-970f-8d96-d44d-9023c47faddc';

const _bleProfile = BleProfile(
  serviceUuid: _svcEcg,
  nameAdvertisesContains: ['healthypi', 'HealthyPi'],
  commandServiceUuid: _svcCmdData,
  commandCharacteristicUuid: _charCmd,
  streams: [
    BleStreamSpec(
        serviceUuid: _svcEcg, characteristicUuid: _charEcg, pktType: hpiBlePktEcg),
    BleStreamSpec(
        serviceUuid: _svcEcg, characteristicUuid: _charResp, pktType: hpiBlePktResp),
    BleStreamSpec(
        serviceUuid: _svcHrv, characteristicUuid: _charPpg, pktType: hpiBlePktPpg),
    BleStreamSpec(
        serviceUuid: _svcHr, characteristicUuid: _charHr, pktType: hpiBlePktHr),
    BleStreamSpec(
        serviceUuid: _svcSpo2, characteristicUuid: _charSpo2, pktType: hpiBlePktSpo2),
    BleStreamSpec(
        serviceUuid: _svcTemp, characteristicUuid: _charTemp, pktType: hpiBlePktTemp),
    BleStreamSpec(
        serviceUuid: _svcHrv,
        characteristicUuid: _charHrv,
        pktType: hpiBlePktRespRate),
  ],
);

final BoardDescriptor healthypiDescriptor = BoardDescriptor(
  id: 'healthypi',
  displayName: 'HealthyPi 5',
  manufacturer: 'ProtoCentral',
  transports: const TransportSupport(usb: true, ble: true, wifi: true),
  usbProfile: _usbProfile,
  bleProfile: _bleProfile,
  channels: const [
    _ecgChannel,
    _biozChannel,
    _ppgRedChannel,
    _ppgIrChannel,
  ],
  packets: [
    PacketSpec(
      pktType: 2,
      label: 'ECG/BioZ/PPG-Red/PPG-IR/Temp/SpO2/HR/RR',
      expectedPayloadLength: 22,
      decode: decodeHealthypiPkt2,
    ),
    // Firmware v1.0.0+ USB batch packets.
    PacketSpec(
      pktType: 3,
      label: 'ECG + Resp (BioZ)',
      expectedPayloadLength: 50,
      decode: decodeHealthypiPkt3,
    ),
    PacketSpec(
      pktType: 4,
      label: 'PPG-Red + Temp + SpO2',
      expectedPayloadLength: 19,
      decode: decodeHealthypiPkt4,
    ),
    // BLE per-characteristic packets (one signal each; see BleProfile above).
    PacketSpec(
        pktType: hpiBlePktEcg, label: 'BLE ECG', decode: decodeHealthypiBleEcg),
    PacketSpec(
        pktType: hpiBlePktResp, label: 'BLE Resp', decode: decodeHealthypiBleResp),
    PacketSpec(
        pktType: hpiBlePktPpg, label: 'BLE PPG', decode: decodeHealthypiBlePpg),
    PacketSpec(
        pktType: hpiBlePktHr, label: 'BLE HR', decode: decodeHealthypiBleHr),
    PacketSpec(
        pktType: hpiBlePktSpo2, label: 'BLE SpO2', decode: decodeHealthypiBleSpo2),
    PacketSpec(
        pktType: hpiBlePktTemp, label: 'BLE Temp', decode: decodeHealthypiBleTemp),
    PacketSpec(
        pktType: hpiBlePktRespRate,
        label: 'BLE RespRate',
        decode: decodeHealthypiBleRespRate),
  ],
  notes: 'HealthyPi 5 — nRF5340 MCU, ADS1293 ECG/BioZ, MAX30101 PPG. USB: '
      'combined packet 0x02, or firmware v1.0.0+ batch packets 0x03 (ECG+Resp) '
      'and 0x04 (PPG+Temp+SpO2). BLE: one characteristic per signal across '
      'several GATT services (ECG, HRV, HR, PLX, Thermometer), each streamed '
      'raw and routed to a synthetic per-signal packet type.',
);
