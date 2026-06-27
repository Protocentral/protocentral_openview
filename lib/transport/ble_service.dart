import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../boards/board_registry.dart';
import '../boards/transport_profile.dart';
import 'transport_service.dart';

/// BLE transport via flutter_blue_plus.
///
/// BLE is currently available only for the **Sensything family** of devices —
/// they are the only boards that declare a [BleProfile]. Scanning is therefore
/// filtered to the GATT service UUIDs advertised by BLE-capable descriptors in
/// the registry, so non-Sensything peripherals never appear in the results.
///
/// The active board's [BleProfile] (service + characteristic UUIDs) is supplied
/// by [ConnectionController] via [setProfile] before [connect], mirroring the
/// way the USB transport receives its baud rate.
class BleService extends TransportService {
  /// Flip to true to re-enable BLE bring-up diagnostics (characteristic list,
  /// notify status, per-second RX throughput).
  static const bool _verbose = false;

  BleService() {
    // Silence flutter_blue_plus's verbose native logging — at 125 Hz the
    // per-notification "[FBP-iOS] didUpdateValueForCharacteristic" lines flood
    // the console. Raise to LogLevel.verbose only when debugging the stack.
    FlutterBluePlus.setLogLevel(_verbose ? LogLevel.verbose : LogLevel.none);
  }

  final _bytesController = StreamController<Uint8List>.broadcast();
  final _eventsController = StreamController<TransportEvent>.broadcast();

  TransportStatus _status = TransportStatus.idle;
  TransportTarget? _target;

  /// Profile for the next/active connection. Set by ConnectionController.
  BleProfile? _profile;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _streamChar;
  BluetoothCharacteristic? _commandChar;
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

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
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final t = _toTarget(r);
        if (t != null) found[t.id] = t;
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      // Wait for the timed scan to actually finish before returning results.
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.isScanning.where((on) => !on).first;
      }
    } catch (e) {
      _eventsController.add(TransportEvent(TransportStatus.error,
          message: 'BLE scan failed', error: e));
    } finally {
      await sub.cancel();
      _setStatus(TransportStatus.idle);
    }
    return found.values.toList(growable: false);
  }

  /// Map a flutter_blue_plus scan result to a transport target, annotating the
  /// matched descriptor id when the advertised name/service identifies one.
  TransportTarget? _toTarget(ScanResult r) {
    final advName = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : r.device.platformName;
    final serviceUuids =
        r.advertisementData.serviceUuids.map((g) => g.str).toList();
    final desc = BoardRegistry.matchBle(
      serviceUuids: serviceUuids,
      advertisedName: advName,
    );
    // BLE is Sensything-only: ignore peripherals that don't resolve to a
    // BLE-capable descriptor.
    if (desc == null) return null;
    return TransportTarget(
      kind: TransportKind.ble,
      id: r.device.remoteId.str,
      displayName: advName.isEmpty ? r.device.remoteId.str : advName,
      subtitle: desc.displayName,
      extra: {
        'rssi': r.rssi,
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
      final device = BluetoothDevice.fromId(target.id);
      _device = device;

      // Surface unexpected drops as transport events.
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected &&
            _status == TransportStatus.connected) {
          _setStatus(TransportStatus.error, message: 'BLE link lost');
        }
      });

      await device.connect(timeout: const Duration(seconds: 15));

      // Larger MTU = fewer notification fragments for our packet stream.
      // No-op / unsupported on some platforms (e.g. macOS) — ignore failures.
      try {
        await device.requestMtu(247);
      } catch (_) {}

      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => _sameUuid(s.uuid.str, profile.serviceUuid),
        orElse: () =>
            throw StateError('Service ${profile.serviceUuid} not found'),
      );

      if (_verbose) {
        debugPrint('[OV-BLE] service ${service.uuid.str} characteristics: '
            '${service.characteristics.map((c) => '${c.uuid.str}(${_props(c)})').join(', ')}');
      }

      _streamChar = service.characteristics.firstWhere(
        (c) => _sameUuid(c.uuid.str, profile.streamCharacteristicUuid),
        orElse: () => throw StateError('Stream characteristic not found'),
      );
      if (profile.commandCharacteristicUuid != null) {
        for (final c in service.characteristics) {
          if (_sameUuid(c.uuid.str, profile.commandCharacteristicUuid!)) {
            _commandChar = c;
            break;
          }
        }
      }

      // lastValueStream fires on every notification (and reads). It is the
      // most reliably-delivered notification stream across FBP versions —
      // some setups don't surface notifications on onValueReceived.
      _rxWindowStart = null;
      _valueSub = _streamChar!.lastValueStream.listen(
        (data) {
          _tallyRx(data);
          if (data.isNotEmpty) _bytesController.add(Uint8List.fromList(data));
        },
        onError: (e) {
          debugPrint('[OV-BLE] rx error: $e');
          _eventsController.add(TransportEvent(TransportStatus.error,
              message: 'BLE read error', error: e));
        },
      );
      await _streamChar!.setNotifyValue(true);
      if (_verbose) {
        debugPrint('[OV-BLE] setNotifyValue(true) done; '
            'isNotifying=${_streamChar!.isNotifying}');
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
    final c = _commandChar ?? _streamChar;
    if (c == null) throw StateError('BLE transport not connected');
    // Prefer write-with-response when the characteristic supports it.
    final withoutResponse =
        !c.properties.write && c.properties.writeWithoutResponse;
    await c.write(data, withoutResponse: withoutResponse);
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
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _streamChar = null;
    _commandChar = null;
    _target = null;
  }

  Future<bool> _ensureAdapterOn() async {
    if (!await FlutterBluePlus.isSupported) return false;
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
      return true;
    }
    try {
      final state = await FlutterBluePlus.adapterState
          .where((s) =>
              s == BluetoothAdapterState.on ||
              s == BluetoothAdapterState.unavailable ||
              s == BluetoothAdapterState.unauthorized)
          .first
          .timeout(const Duration(seconds: 4));
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
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
  static String _props(BluetoothCharacteristic c) {
    final p = c.properties;
    final s = StringBuffer();
    if (p.notify) s.write('N');
    if (p.indicate) s.write('I');
    if (p.read) s.write('R');
    if (p.write) s.write('W');
    if (p.writeWithoutResponse) s.write('w');
    return s.isEmpty ? '-' : s.toString();
  }

  static bool _sameUuid(String a, String b) {
    // flutter_blue_plus may return short (16-bit) or full 128-bit forms;
    // compare on the suffix so both shapes match.
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
