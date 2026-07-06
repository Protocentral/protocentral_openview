import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../boards/board_registry.dart';
import '../boards/transport_profile.dart';
import 'transport_service.dart';

/// One BLE notification, tagged with the routing info of the characteristic it
/// arrived on. Emitted on [BleService.frames] so the [ConnectionController] can
/// route each notification to the right decoder — essential for boards that
/// split signals across multiple characteristics (e.g. HealthyPi 5).
class BleFrame {
  /// True when the payload is a full ProtoCentral frame (`0x0A … 0x0B`).
  final bool framed;

  /// Packet type to decode the payload as when [framed] is false.
  final int pktType;

  final Uint8List payload;

  const BleFrame({
    required this.framed,
    required this.pktType,
    required this.payload,
  });
}

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
  final _framesController = StreamController<BleFrame>.broadcast();

  TransportStatus _status = TransportStatus.idle;
  TransportTarget? _target;

  /// Profile for the next/active connection. Set by ConnectionController.
  BleProfile? _profile;

  BluetoothDevice? _device;
  final List<BluetoothCharacteristic> _streamChars = [];
  BluetoothCharacteristic? _commandChar;
  final List<StreamSubscription<List<int>>> _valueSubs = [];
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

  /// Per-notification tagged stream. Each event carries the payload plus the
  /// framing/packet-type routing info of the characteristic it arrived on, so a
  /// board that streams different signals on different characteristics decodes
  /// correctly. [ConnectionController] listens here for BLE instead of [bytes].
  Stream<BleFrame> get frames => _framesController.stream;

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

      BluetoothService? findService(String uuid) {
        for (final s in services) {
          if (_sameUuid(s.uuid.str, uuid)) return s;
        }
        return null;
      }

      // Always dump the discovered GATT layout — this is how you find the real
      // service/characteristic UUIDs to fill into a board's BleProfile. It also
      // shows in the app Console via the transport event below.
      final gatt = _describeGatt(services);
      debugPrint('[OV-BLE] discovered GATT:\n$gatt');
      _eventsController.add(TransportEvent(TransportStatus.connecting,
          message: 'GATT: $gatt'));

      // Subscribe to every declared stream characteristic — they may live in
      // different services. Each notification is tagged with its stream's
      // framing/packet-type so downstream routing knows which decoder to use.
      // A declared-but-absent characteristic is skipped (not fatal) so a
      // partially-correct profile still streams what it can during bring-up.
      _rxWindowStart = null;
      final missing = <String>[];
      for (final spec in profile.resolvedStreams) {
        final service = findService(spec.serviceUuid);
        BluetoothCharacteristic? ch;
        if (service != null) {
          for (final c in service.characteristics) {
            if (_sameUuid(c.uuid.str, spec.characteristicUuid)) {
              ch = c;
              break;
            }
          }
        }
        // Fall back to a device-wide search — characteristic UUIDs are unique,
        // so this tolerates a stream declared under the wrong service.
        if (ch == null) {
          for (final s in services) {
            for (final c in s.characteristics) {
              if (_sameUuid(c.uuid.str, spec.characteristicUuid)) {
                ch = c;
                break;
              }
            }
            if (ch != null) break;
          }
        }
        if (ch == null) {
          missing.add(spec.characteristicUuid);
          debugPrint('[OV-BLE] declared stream characteristic '
              '${spec.characteristicUuid} (svc ${spec.serviceUuid}) not found '
              '— skipping');
          continue;
        }
        final characteristic = ch;
        _streamChars.add(characteristic);

        // lastValueStream fires on every notification (and reads). It is the
        // most reliably-delivered notification stream across FBP versions —
        // some setups don't surface notifications on onValueReceived.
        final sub = characteristic.lastValueStream.listen(
          (data) {
            _tallyRx(data);
            if (data.isEmpty) return;
            final bytes = Uint8List.fromList(data);
            _bytesController.add(bytes);
            _framesController.add(BleFrame(
              framed: spec.framed,
              pktType: spec.pktType,
              payload: bytes,
            ));
          },
          onError: (e) {
            debugPrint('[OV-BLE] rx error: $e');
            _eventsController.add(TransportEvent(TransportStatus.error,
                message: 'BLE read error', error: e));
          },
        );
        _valueSubs.add(sub);
        await characteristic.setNotifyValue(true);
        debugPrint('[OV-BLE] notify on ${characteristic.uuid.str} '
            '(pkt ${spec.pktType}, framed=${spec.framed}); '
            'isNotifying=${characteristic.isNotifying}');
      }

      // Nothing to stream from — surface the discovered layout so the profile
      // UUIDs can be corrected.
      if (_streamChars.isEmpty) {
        throw StateError('No declared stream characteristics found. '
            'Discovered GATT:\n$gatt');
      }
      if (missing.isNotEmpty) {
        _eventsController.add(TransportEvent(TransportStatus.connecting,
            message: 'Some characteristics not found (streaming anyway): '
                '${missing.join(', ')}'));
      }

      // Command characteristic — may be in its own service.
      if (profile.commandCharacteristicUuid != null) {
        final cmdServices = profile.commandServiceUuid != null
            ? [findService(profile.commandServiceUuid!)]
            : services;
        for (final s in cmdServices) {
          if (s == null) continue;
          final match = s.characteristics
              .where(
                  (c) => _sameUuid(c.uuid.str, profile.commandCharacteristicUuid!))
              .toList();
          if (match.isNotEmpty) {
            _commandChar = match.first;
            break;
          }
        }
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
    final c = _commandChar ??
        (_streamChars.isNotEmpty ? _streamChars.first : null);
    if (c == null) throw StateError('BLE transport not connected');
    // Prefer write-with-response when the characteristic supports it.
    final withoutResponse =
        !c.properties.write && c.properties.writeWithoutResponse;
    await c.write(data, withoutResponse: withoutResponse);
  }

  Future<void> _teardown() async {
    for (final sub in _valueSubs) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    _valueSubs.clear();
    try {
      await _connSub?.cancel();
    } catch (_) {}
    _connSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _streamChars.clear();
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

  /// Human-readable dump of discovered services and their characteristics
  /// (UUID + property flags). Used at connect time to help identify the real
  /// UUIDs for a board's BleProfile.
  static String _describeGatt(List<BluetoothService> services) {
    final sb = StringBuffer();
    for (final s in services) {
      sb.writeln('svc ${s.uuid.str}');
      for (final c in s.characteristics) {
        sb.writeln('  chr ${c.uuid.str} [${_props(c)}]');
      }
    }
    return sb.toString().trimRight();
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
    if (!_framesController.isClosed) _framesController.close();
    super.dispose();
  }
}
