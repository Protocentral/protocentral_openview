import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'package:mcumgr_dart/mcumgr_dart.dart';

/// SMP transport over BLE GATT, on `universal_ble`.
///
/// Nordic SMP service — a single characteristic used **both directions**
/// (write-without-response for requests, notify for responses):
///   - Service `8D53DC1D-1DB7-4CD3-868B-8A527460AA84`
///   - Characteristic `DA2E7828-FBCE-4E01-AE9E-261174997C48`
///
/// This is a **decoupled** BLE link — separate from the streaming `BleService`
/// (its own connection to a separate GATT service). A device is "SMP-enabled"
/// iff [connect] finds the SMP service; otherwise it throws
/// [SmpTransportException] and the caller shows a "not an SMP device" gate.
class SmpBleTransport implements SmpTransport {
  SmpBleTransport(this.deviceId, {String? name}) : _label = name;

  /// Nordic SMP GATT identifiers.
  static const String smpServiceUuid = '8d53dc1d-1db7-4cd3-868b-8a527460aa84';
  static const String smpCharUuid = 'da2e7828-fbce-4e01-ae9e-261174997c48';

  final String deviceId;
  String? _label;

  String? _serviceUuid;
  String? _charUuid;
  int? _maxWriteLength;

  final _notifController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<SmpConnectionState>.broadcast();
  SmpConnectionState _state = SmpConnectionState.disconnected;

  StreamSubscription<Uint8List>? _valueSub;
  StreamSubscription<bool>? _connSub;

  @override
  String? get deviceLabel => _label ?? deviceId;

  @override
  SmpConnectionState get state => _state;

  @override
  Stream<SmpConnectionState> get stateChanges => _stateController.stream;

  @override
  Stream<Uint8List> get notifications => _notifController.stream;

  @override
  int? get maxWriteLength => _maxWriteLength;

  @override
  Future<void> connect() async {
    _setState(SmpConnectionState.connecting);
    try {
      await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 20));

      // Subscribe to connection changes only AFTER connect succeeds, so a
      // replayed `disconnected` can't tear us down mid-bring-up.
      _connSub = UniversalBle.connectionStream(deviceId).listen((connected) {
        if (!connected && _state == SmpConnectionState.connected) {
          _setState(SmpConnectionState.disconnected);
        }
      });

      // MTU is best-effort / OS-managed on some platforms. maxWriteLength =
      // MTU − 3 (ATT header) bounds outbound frame chunking for image upload.
      // Request the max so DFU chunks are as large as the stack allows (fewer
      // request/response round-trips). On Apple this is OS-managed and returns
      // the auto-negotiated value regardless of the ask; on Android the ask
      // matters. maxWriteLength stays null if unknown (img_mgmt uses a safe
      // default then).
      try {
        final mtu = await UniversalBle.requestMtu(deviceId, 512);
        if (mtu > 3) _maxWriteLength = mtu - 3;
        debugPrint('[SMP-BLE] MTU=$mtu maxWrite=$_maxWriteLength');
      } catch (_) {}

      // Ask for a low-latency connection interval to speed up the serialized
      // upload loop. Android-only in universal_ble; a no-op/throw elsewhere.
      try {
        await UniversalBle.requestConnectionPriority(
            deviceId, BleConnectionPriority.highPerformance);
      } catch (_) {}

      final services = await UniversalBle.discoverServices(deviceId);
      final service = services.where((s) => _sameUuid(s.uuid, smpServiceUuid));
      if (service.isEmpty) {
        throw SmpTransportException(
            'Not an SMP-enabled device (SMP service $smpServiceUuid absent).');
      }
      _serviceUuid = service.first.uuid;

      final chars = service.first.characteristics
          .where((c) => _sameUuid(c.uuid, smpCharUuid));
      if (chars.isEmpty) {
        throw SmpTransportException(
            'SMP service present but characteristic $smpCharUuid missing.');
      }
      _charUuid = chars.first.uuid;

      // Pipe raw notifications into our broadcast stream before enabling them.
      _valueSub =
          UniversalBle.characteristicValueStream(deviceId, _charUuid!).listen(
        (data) {
          if (data.isNotEmpty) _notifController.add(Uint8List.fromList(data));
        },
        onError: (Object e) => debugPrint('[SMP-BLE] rx error: $e'),
      );
      await UniversalBle.subscribeNotifications(
          deviceId, _serviceUuid!, _charUuid!);

      _setState(SmpConnectionState.connected);
    } catch (e) {
      _setState(SmpConnectionState.disconnected);
      await _cleanup();
      rethrow;
    }
  }

  /// Re-query the negotiated MTU and update [maxWriteLength]. On macOS/iOS the
  /// MTU exchange completes shortly *after* connect, so the value read during
  /// [connect] can be the 23-byte default; call this once the link has settled
  /// (or right before a large transfer). Returns the new maxWriteLength.
  Future<int?> refreshMtu() async {
    try {
      final mtu = await UniversalBle.requestMtu(deviceId, 512);
      if (mtu > 3) _maxWriteLength = mtu - 3;
      debugPrint('[SMP-BLE] refreshMtu MTU=$mtu maxWrite=$_maxWriteLength');
    } catch (_) {}
    return _maxWriteLength;
  }

  @override
  Future<void> write(Uint8List frame) async {
    final serviceUuid = _serviceUuid;
    final charUuid = _charUuid;
    if (serviceUuid == null || charUuid == null) {
      throw SmpTransportException('SMP transport not connected');
    }
    await UniversalBle.write(deviceId, serviceUuid, charUuid, frame,
        withoutResponse: true);
  }

  @override
  Future<void> disconnect() async {
    _setState(SmpConnectionState.disconnecting);
    await _cleanup();
    try {
      await UniversalBle.disconnect(deviceId);
    } catch (_) {}
    _setState(SmpConnectionState.disconnected);
  }

  Future<void> _cleanup() async {
    try {
      await _valueSub?.cancel();
    } catch (_) {}
    _valueSub = null;
    try {
      await _connSub?.cancel();
    } catch (_) {}
    _connSub = null;
    _serviceUuid = null;
    _charUuid = null;
  }

  void _setState(SmpConnectionState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  /// Dispose the broadcast controllers. Call after [disconnect] when the
  /// transport is being discarded for good.
  Future<void> dispose() async {
    await _cleanup();
    if (!_notifController.isClosed) await _notifController.close();
    if (!_stateController.isClosed) await _stateController.close();
  }

  static bool _sameUuid(String a, String b) {
    final la = a.toLowerCase().replaceAll('-', '');
    final lb = b.toLowerCase().replaceAll('-', '');
    return la == lb || la.endsWith(lb) || lb.endsWith(la);
  }
}
