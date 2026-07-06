import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../boards/board_registry.dart';
import '../boards/transport_profile.dart';
import 'transport_service.dart';

/// BLE transport via `universal_ble`.
///
/// BLE is currently available only for the **Sensything family** of devices —
/// they are the only boards that declare a [BleProfile]. Scanning is therefore
/// filtered to the GATT service UUIDs advertised by BLE-capable descriptors in
/// the registry, so non-Sensything peripherals never appear in the results.
///
/// The active board's [BleProfile] (service + characteristic UUIDs) is supplied
/// by [ConnectionController] via [setProfile] before [connect], mirroring the
/// way the USB transport receives its baud rate.
///
/// **Plugin note:** BLE is provided by `universal_ble` (BSD-3, all platforms
/// incl. web). It is a **static/singleton** API keyed by `deviceId` (not
/// device-object methods), so this service holds the device id + resolved
/// service/characteristic UUIDs as strings. The [TransportService] abstraction
/// keeps the BLE plugin swappable — preserve it.
class BleService extends TransportService {
  /// Flip to true to re-enable BLE bring-up diagnostics (characteristic list,
  /// notify status, per-second RX throughput).
  static const bool _verbose = false;

  BleService() {
    // Silence verbose native logging — at 125 Hz the per-notification logs
    // flood the console. Raise to BleLogLevel.verbose only when debugging the
    // stack. (No-op in release builds — universal_ble gates logging on kDebugMode.)
    UniversalBle.setLogLevel(_verbose ? BleLogLevel.verbose : BleLogLevel.none);
  }

  final _bytesController = StreamController<Uint8List>.broadcast();
  final _eventsController = StreamController<TransportEvent>.broadcast();

  TransportStatus _status = TransportStatus.idle;
  TransportTarget? _target;

  /// Profile for the next/active connection. Set by ConnectionController.
  BleProfile? _profile;

  // Active-connection handles. universal_ble is keyed by these strings rather
  // than by a device object.
  String? _deviceId;
  String? _serviceUuid;
  String? _streamCharUuid;
  String? _commandCharUuid;
  bool _writeWithoutResponse = false;

  StreamSubscription<Uint8List>? _valueSub;
  StreamSubscription<bool>? _connSub;

  // Per-second RX throughput tally (diagnostic).
  int _rxCount = 0;
  int _rxBytes = 0;
  final Set<int> _rxSizes = {};
  String _rxLastHex = '';
  DateTime? _rxWindowStart;

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  TransportStatus get status => _status;

  @override
  TransportTarget? get connectedTarget => _target;

  @override
  Stream<Uint8List> get bytes => _bytesController.stream;

  @override
  Stream<TransportEvent> get events => _eventsController.stream;

  /// Supply the BLE GATT profile for the board about to be connected.
  void setProfile(BleProfile profile) {
    _profile = profile;
  }

  @override
  Future<List<TransportTarget>> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!await _ensureAdapterOn()) {
      _eventsController.add(const TransportEvent(
        TransportStatus.error,
        message: 'Bluetooth is off or unavailable',
      ));
      return const [];
    }

    _setStatus(TransportStatus.scanning);
    final found = <String, TransportTarget>{};

    // Scan broadly and keep only peripherals that resolve to a BLE-capable
    // (Sensything) descriptor — by advertised service UUID *or* name. This is
    // more robust than an adapter-level service filter for devices that
    // advertise their name but not their primary service UUID.
    final sub = UniversalBle.scanStream.listen((device) {
      final t = _toTarget(device);
      if (t != null) found[t.id] = t;
    });

    try {
      await UniversalBle.startScan();
      // universal_ble's startScan has no timeout — bound it ourselves.
      await Future<void>.delayed(timeout);
    } catch (e) {
      _eventsController.add(TransportEvent(TransportStatus.error,
          message: 'BLE scan failed', error: e));
    } finally {
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      await sub.cancel();
      _setStatus(TransportStatus.idle);
    }
    return found.values.toList(growable: false);
  }

  /// Map a universal_ble scan result to a transport target, annotating the
  /// matched descriptor id when the advertised name/service identifies one.
  TransportTarget? _toTarget(BleDevice device) {
    final advName = device.name ?? '';
    final serviceUuids = device.services;
    final desc = BoardRegistry.matchBle(
      serviceUuids: serviceUuids,
      advertisedName: advName,
    );
    // BLE is Sensything-only: ignore peripherals that don't resolve to a
    // BLE-capable descriptor.
    if (desc == null) return null;
    return TransportTarget(
      kind: TransportKind.ble,
      id: device.deviceId,
      displayName: advName.isEmpty ? device.deviceId : advName,
      subtitle: desc.displayName,
      extra: {
        'rssi': device.rssi,
        'descriptorId': desc.id,
        'serviceUuids': serviceUuids,
      },
    );
  }

  @override
  Future<void> connect(TransportTarget target) async {
    if (_status == TransportStatus.connected) await disconnect();
    final profile = _profile;
    if (profile == null) {
      throw StateError('BLE profile not set for this board');
    }
    _target = target;
    _setStatus(TransportStatus.connecting);

    try {
      final deviceId = target.id;
      _deviceId = deviceId;

      await UniversalBle.connect(deviceId,
          timeout: const Duration(seconds: 15));

      // Subscribe to connection-state changes *after* connecting so we don't
      // catch a replayed `disconnected` that would tear down mid-flight
      // (see SMP_INTEGRATION_HANDOFF.md §5 gotcha 1).
      _connSub = UniversalBle.connectionStream(deviceId).listen((connected) {
        if (!connected && _status == TransportStatus.connected) {
          _setStatus(TransportStatus.error, message: 'BLE link lost');
        }
      });

      // Larger MTU = fewer notification fragments for our packet stream.
      // Best-effort / OS-managed on some platforms (e.g. macOS) — ignore
      // failures.
      try {
        await UniversalBle.requestMtu(deviceId, 247);
      } catch (_) {}

      final services = await UniversalBle.discoverServices(deviceId);
      final service = services.firstWhere(
        (s) => _sameUuid(s.uuid, profile.serviceUuid),
        orElse: () =>
            throw StateError('Service ${profile.serviceUuid} not found'),
      );
      _serviceUuid = service.uuid;

      if (_verbose) {
        debugPrint('[OV-BLE] service ${service.uuid} characteristics: '
            '${service.characteristics.map((c) => '${c.uuid}(${_props(c)})').join(', ')}');
      }

      final streamChar = service.characteristics.firstWhere(
        (c) => _sameUuid(c.uuid, profile.streamCharacteristicUuid),
        orElse: () => throw StateError('Stream characteristic not found'),
      );
      _streamCharUuid = streamChar.uuid;

      BleCharacteristic? commandChar;
      if (profile.commandCharacteristicUuid != null) {
        for (final c in service.characteristics) {
          if (_sameUuid(c.uuid, profile.commandCharacteristicUuid!)) {
            commandChar = c;
            _commandCharUuid = c.uuid;
            break;
          }
        }
      }

      // Decide write mode for the send() path from the characteristic that will
      // carry host→board commands (command char if present, else stream char).
      final writeChar = commandChar ?? streamChar;
      _writeWithoutResponse =
          !writeChar.properties.contains(CharacteristicProperty.write) &&
              writeChar.properties
                  .contains(CharacteristicProperty.writeWithoutResponse);

      // Subscribe to the value stream before enabling notifications so no
      // early notification is missed.
      _rxWindowStart = null;
      _valueSub = UniversalBle.characteristicValueStream(
        deviceId,
        streamChar.uuid,
      ).listen(
        (data) {
          _tallyRx(data);
          if (data.isNotEmpty) _bytesController.add(Uint8List.fromList(data));
        },
        onError: (Object e) {
          debugPrint('[OV-BLE] rx error: $e');
          _eventsController.add(TransportEvent(TransportStatus.error,
              message: 'BLE read error', error: e));
        },
      );
      await UniversalBle.subscribeNotifications(
          deviceId, service.uuid, streamChar.uuid);
      if (_verbose) {
        debugPrint('[OV-BLE] subscribeNotifications done on ${streamChar.uuid}');
      }

      _setStatus(TransportStatus.connected);
    } catch (e) {
      _setStatus(TransportStatus.error, message: e.toString());
      await _teardown();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _setStatus(TransportStatus.disconnecting);
    await _teardown();
    _setStatus(TransportStatus.idle);
  }

  @override
  Future<void> send(Uint8List data) async {
    final deviceId = _deviceId;
    final serviceUuid = _serviceUuid;
    final charUuid = _commandCharUuid ?? _streamCharUuid;
    if (deviceId == null || serviceUuid == null || charUuid == null) {
      throw StateError('BLE transport not connected');
    }
    await UniversalBle.write(
      deviceId,
      serviceUuid,
      charUuid,
      data,
      withoutResponse: _writeWithoutResponse,
    );
  }

  Future<void> _teardown() async {
    try {
      await _valueSub?.cancel();
    } catch (_) {}
    _valueSub = null;
    try {
      await _connSub?.cancel();
    } catch (_) {}
    _connSub = null;
    final deviceId = _deviceId;
    if (deviceId != null) {
      try {
        await UniversalBle.disconnect(deviceId);
      } catch (_) {}
    }
    _deviceId = null;
    _serviceUuid = null;
    _streamCharUuid = null;
    _commandCharUuid = null;
    _writeWithoutResponse = false;
    _target = null;
  }

  Future<bool> _ensureAdapterOn() async {
    final state = await UniversalBle.getBluetoothAvailabilityState();
    if (state == AvailabilityState.poweredOn) return true;
    try {
      final s = await UniversalBle.availabilityStream
          .where((s) =>
              s == AvailabilityState.poweredOn ||
              s == AvailabilityState.unsupported ||
              s == AvailabilityState.unauthorized)
          .first
          .timeout(const Duration(seconds: 4));
      return s == AvailabilityState.poweredOn;
    } catch (_) {
      return (await UniversalBle.getBluetoothAvailabilityState()) ==
          AvailabilityState.poweredOn;
    }
  }

  /// Tally raw notification throughput and emit a once-per-second summary to
  /// the system log, e.g. `[OV-BLE] 1s: 11 notifs, 88 B/s, sizes={8}`. This
  /// pins down whether the OX is under-sending (firmware) vs the app dropping
  /// data (it isn't — every notification is counted here).
  void _tallyRx(List<int> data) {
    if (!_verbose) return;
    _rxCount++;
    _rxBytes += data.length;
    _rxSizes.add(data.length);
    _rxLastHex = _hex(data);
    final now = DateTime.now();
    _rxWindowStart ??= now;
    if (now.difference(_rxWindowStart!).inMilliseconds >= 1000) {
      debugPrint('[OV-BLE] 1s: $_rxCount notifs, $_rxBytes B/s, '
          'sizes=$_rxSizes, last=[$_rxLastHex]');
      _rxCount = 0;
      _rxBytes = 0;
      _rxSizes.clear();
      _rxWindowStart = now;
    }
  }

  static String _hex(List<int> d) {
    final n = d.length < 24 ? d.length : 24;
    final s = [
      for (var i = 0; i < n; i++) d[i].toRadixString(16).padLeft(2, '0')
    ].join(' ');
    return d.length > n ? '$s …' : s;
  }

  /// Compact property tag, e.g. 'NR' for notify+read.
  static String _props(BleCharacteristic c) {
    final p = c.properties;
    final s = StringBuffer();
    if (p.contains(CharacteristicProperty.notify)) s.write('N');
    if (p.contains(CharacteristicProperty.indicate)) s.write('I');
    if (p.contains(CharacteristicProperty.read)) s.write('R');
    if (p.contains(CharacteristicProperty.write)) s.write('W');
    if (p.contains(CharacteristicProperty.writeWithoutResponse)) s.write('w');
    return s.isEmpty ? '-' : s.toString();
  }

  static bool _sameUuid(String a, String b) {
    // UUIDs may arrive as short (16-bit) or full 128-bit forms; compare on the
    // suffix so both shapes match.
    final la = a.toLowerCase().replaceAll('-', '');
    final lb = b.toLowerCase().replaceAll('-', '');
    return la == lb || la.endsWith(lb) || lb.endsWith(la);
  }

  void _setStatus(TransportStatus s, {String? message}) {
    _status = s;
    _eventsController.add(TransportEvent(s, message: message));
    notifyListeners();
  }

  @override
  void dispose() {
    _teardown();
    if (!_bytesController.isClosed) _bytesController.close();
    if (!_eventsController.isClosed) _eventsController.close();
    super.dispose();
  }
}
