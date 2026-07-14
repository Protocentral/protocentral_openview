// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/foundation.dart';
// Hide GATT-model [BleService] — this file's transport class has the same name.
import 'package:universal_ble/universal_ble.dart' hide BleService;

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

/// BLE transport via **`universal_ble`** (replaces the earlier
/// `flutter_blue_plus` integration).
///
/// BLE is available for boards that declare a [BleProfile] (currently
/// Sensything OX/CAP and HealthyPi 5). Scanning keeps only peripherals that
/// resolve via [BoardRegistry.matchBle] (advertised name and/or service UUID).
///
/// The active board's [BleProfile] is supplied by [ConnectionController] via
/// [setProfile] before [connect], mirroring the USB baud-rate hand-off.
/// Multi-characteristic profiles (HealthyPi 5) subscribe to every
/// [BleProfile.resolvedStreams] entry and emit tagged [BleFrame]s; single-char
/// profiles (Sensything) collapse to one stream via the same path.
///
/// **Plugin note (critical):** this branch standardizes on `universal_ble`
/// (BSD-3, all platforms incl. web). Older branches / `main` may still show
/// HealthyPi multi-char code written for `flutter_blue_plus` — port *logic*
/// here, do **not** reintroduce that package. universal_ble is a
/// **static/singleton** API keyed by `deviceId` (not device-object methods),
/// so this service holds the device id + resolved UUID strings. The
/// [TransportService] abstraction keeps the BLE plugin swappable — preserve it
/// (do not leak plugin types past this class).
class BleService extends TransportService {
  /// Flip to true to re-enable BLE bring-up diagnostics (characteristic list,
  /// notify status, per-second RX throughput).
  static const bool _verbose = false;

  BleService() {
    // Do NOT call platform channels from the constructor. On iOS the Flutter
    // engine can still be wiring plugins when controllers are built in main();
    // an early `setLogLevel` can stall launch. Logging is configured lazily
    // on first scan/connect instead.
  }

  bool _logLevelConfigured = false;

  /// Best-effort log-level setup — safe to call after plugins are ready.
  Future<void> _ensureLogLevel() async {
    if (_logLevelConfigured) return;
    _logLevelConfigured = true;
    try {
      // Silence verbose native logging — at 125 Hz the per-notification logs
      // flood the console. Raise to BleLogLevel.verbose only when debugging.
      await UniversalBle.setLogLevel(
          _verbose ? BleLogLevel.verbose : BleLogLevel.none);
    } catch (_) {
      // Plugin not ready / unsupported — ignore; scanning still works.
    }
  }

  final _bytesController = StreamController<Uint8List>.broadcast();
  final _eventsController = StreamController<TransportEvent>.broadcast();
  final _framesController = StreamController<BleFrame>.broadcast();

  TransportStatus _status = TransportStatus.idle;
  TransportTarget? _target;

  /// Profile for the next/active connection. Set by ConnectionController.
  BleProfile? _profile;

  // Active-connection handles. universal_ble is keyed by these strings rather
  // than by a device object.
  String? _deviceId;

  /// Resolved stream endpoints (service + char UUID) for teardown / diagnostics.
  final List<({String serviceUuid, String charUuid})> _streamEndpoints = [];

  /// Command write target (service + char). Falls back to the first stream char.
  String? _commandServiceUuid;
  String? _commandCharUuid;
  bool _writeWithoutResponse = false;

  final List<StreamSubscription<Uint8List>> _valueSubs = [];
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
    await _ensureLogLevel();
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
    // descriptor — by advertised service UUID *or* name. This is more robust
    // than an adapter-level service filter for devices that advertise their
    // name but not their primary service UUID.
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
    // Ignore peripherals that don't resolve to a BLE-capable descriptor.
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
      await _ensureLogLevel();
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

      // universal_ble's GATT service type is also named BleService — keep it
      // hidden (import) and work via the list elements' inferred types.
      dynamic findService(String uuid) {
        for (final s in services) {
          if (_sameUuid(s.uuid, uuid)) return s;
        }
        return null;
      }

      // Always dump the discovered GATT layout — useful for validating a
      // board's BleProfile. Also surface it in the app Console via a transport
      // event when verbose.
      final gatt = _describeGatt(services);
      if (_verbose) {
        debugPrint('[OV-BLE] discovered GATT:\n$gatt');
        _eventsController.add(TransportEvent(TransportStatus.connecting,
            message: 'GATT: $gatt'));
      }

      // Subscribe to every declared stream characteristic — they may live in
      // different services. Each notification is tagged with its stream's
      // framing/packet-type so downstream routing knows which decoder to use.
      // A declared-but-absent characteristic is skipped (not fatal) so a
      // partially-correct profile still streams what it can during bring-up.
      _rxWindowStart = null;
      final missing = <String>[];
      BleCharacteristic? firstStreamChar;
      String? firstStreamServiceUuid;

      for (final spec in profile.resolvedStreams) {
        BleCharacteristic? ch;
        String? resolvedServiceUuid;

        final service = findService(spec.serviceUuid);
        if (service != null) {
          for (final c in service.characteristics as List<BleCharacteristic>) {
            if (_sameUuid(c.uuid, spec.characteristicUuid)) {
              ch = c;
              resolvedServiceUuid = service.uuid as String;
              break;
            }
          }
        }
        // Fall back to a device-wide search — characteristic UUIDs are unique,
        // so this tolerates a stream declared under the wrong service.
        if (ch == null) {
          for (final s in services) {
            for (final c in s.characteristics) {
              if (_sameUuid(c.uuid, spec.characteristicUuid)) {
                ch = c;
                resolvedServiceUuid = s.uuid;
                break;
              }
            }
            if (ch != null) break;
          }
        }
        if (ch == null || resolvedServiceUuid == null) {
          missing.add(spec.characteristicUuid);
          debugPrint('[OV-BLE] declared stream characteristic '
              '${spec.characteristicUuid} (svc ${spec.serviceUuid}) not found '
              '— skipping');
          continue;
        }

        final characteristic = ch;
        final serviceUuid = resolvedServiceUuid;
        firstStreamChar ??= characteristic;
        firstStreamServiceUuid ??= serviceUuid;
        _streamEndpoints
            .add((serviceUuid: serviceUuid, charUuid: characteristic.uuid));

        // Subscribe to the value stream before enabling notifications so no
        // early notification is missed. Stream is keyed by characteristic UUID.
        final sub = UniversalBle.characteristicValueStream(
          deviceId,
          characteristic.uuid,
        ).listen(
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
          onError: (Object e) {
            debugPrint('[OV-BLE] rx error: $e');
            _eventsController.add(TransportEvent(TransportStatus.error,
                message: 'BLE read error', error: e));
          },
        );
        _valueSubs.add(sub);
        await UniversalBle.subscribeNotifications(
            deviceId, serviceUuid, characteristic.uuid);
        if (_verbose) {
          debugPrint('[OV-BLE] notify on ${characteristic.uuid} '
              '(pkt ${spec.pktType}, framed=${spec.framed})');
        }
      }

      if (_streamEndpoints.isEmpty) {
        throw StateError('No declared stream characteristics found. '
            'Discovered GATT:\n$gatt');
      }
      if (missing.isNotEmpty) {
        _eventsController.add(TransportEvent(TransportStatus.connecting,
            message: 'Some characteristics not found (streaming anyway): '
                '${missing.join(', ')}'));
      }

      // Command characteristic — may be in its own service.
      BleCharacteristic? commandChar;
      if (profile.commandCharacteristicUuid != null) {
        final cmdUuid = profile.commandCharacteristicUuid!;
        final prefer = <dynamic>[
          if (profile.commandServiceUuid != null)
            findService(profile.commandServiceUuid!)
          else
            ...services,
        ];
        for (final s in prefer) {
          if (s == null) continue;
          for (final c in s.characteristics as List<BleCharacteristic>) {
            if (_sameUuid(c.uuid, cmdUuid)) {
              commandChar = c;
              _commandServiceUuid = s.uuid as String;
              _commandCharUuid = c.uuid;
              break;
            }
          }
          if (commandChar != null) break;
        }
        // Device-wide fallback if not under the preferred service.
        if (commandChar == null) {
          for (final s in services) {
            for (final c in s.characteristics) {
              if (_sameUuid(c.uuid, cmdUuid)) {
                commandChar = c;
                _commandServiceUuid = s.uuid;
                _commandCharUuid = c.uuid;
                break;
              }
            }
            if (commandChar != null) break;
          }
        }
      }

      // Decide write mode for the send() path from the characteristic that will
      // carry host→board commands (command char if present, else first stream).
      final writeChar = commandChar ?? firstStreamChar;
      if (writeChar != null) {
        _writeWithoutResponse =
            !writeChar.properties.contains(CharacteristicProperty.write) &&
                writeChar.properties
                    .contains(CharacteristicProperty.writeWithoutResponse);
      }
      // If no dedicated command char, send() uses the first stream endpoint.
      if (_commandCharUuid == null && firstStreamChar != null) {
        _commandServiceUuid = firstStreamServiceUuid;
        _commandCharUuid = firstStreamChar.uuid;
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
    final serviceUuid = _commandServiceUuid;
    final charUuid = _commandCharUuid;
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
    final deviceId = _deviceId;
    if (deviceId != null) {
      try {
        await UniversalBle.disconnect(deviceId);
      } catch (_) {}
    }
    _deviceId = null;
    _streamEndpoints.clear();
    _commandServiceUuid = null;
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

  /// Human-readable GATT dump for diagnostics / profile bring-up.
  String _describeGatt(List<dynamic> services) {
    final buf = StringBuffer();
    for (final s in services) {
      buf.writeln('  svc ${s.uuid}');
      for (final c in s.characteristics as List<BleCharacteristic>) {
        buf.writeln('    char ${c.uuid} (${_props(c)})');
      }
    }
    return buf.toString().trimRight();
  }

  /// Tally raw notification throughput and emit a once-per-second summary to
  /// the system log, e.g. `[OV-BLE] 1s: 11 notifs, 88 B/s, sizes={8}`. This
  /// pins down whether the device is under-sending (firmware) vs the app
  /// dropping data (it isn't — every notification is counted here).
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
    if (!_framesController.isClosed) _framesController.close();
    super.dispose();
  }
}
