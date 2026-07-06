import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

/// A peripheral discovered by the Developer scan (unfiltered).
class DevScanEntry {
  final String deviceId;
  final String? name;
  final int? rssi;
  final List<String> services;
  final bool isSystemDevice;

  const DevScanEntry({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.services,
    this.isSystemDevice = false,
  });

  String get displayName =>
      (name != null && name!.isNotEmpty) ? name! : '(unnamed)';
}

enum DevLogLevel { info, tx, rx, error }

class DevLogEntry {
  final DateTime time;
  final DevLogLevel level;
  final String text;
  const DevLogEntry(this.time, this.level, this.text);
}

/// Decoupled, **unfiltered** BLE playground controller for the Developer tab.
///
/// Intentionally does NOT go through [BleService]/`ConnectionController` — it
/// talks to `universal_ble` directly with **no board/registry filter**, so it
/// can scan, connect, discover services, and read / write / subscribe to *any*
/// BLE peripheral. Its purpose is the `universal_ble` hardware spike
/// (`SMP_INTEGRATION_HANDOFF.md` Phase 0) and general GATT poking; it is also
/// the natural groundwork for the future SMP Device Manager.
///
/// Because `universal_ble` is a static/singleton API, this coexists with the
/// streaming [BleService]: both use the stream APIs and the library's internal
/// command queue serialises access. Don't drive both at the same time.
class DeveloperBleController extends ChangeNotifier {
  // Convenience service UUIDs used to surface already-connected (bonded) system
  // devices — CoreBluetooth omits connected peripherals from scans (handoff
  // §5.2). Includes the Nordic SMP service (HealthyPi Move) + common GATT ones.
  static const List<String> _systemDeviceServices = [
    '8d53dc1d-1db7-4cd3-868b-8a527460aa84', // Nordic SMP / MCUmgr
    '180a', // Device Information
    '180d', // Heart Rate
    '180f', // Battery
  ];

  static const int _maxLog = 400;

  final Map<String, DevScanEntry> _devices = {};
  final List<DevLogEntry> _log = [];

  bool _scanning = false;
  bool _loadingSystem = false;
  bool _connecting = false;
  bool _hideUnnamed = false;
  String? _connectedId;
  String? _connectedName;
  int? _mtu;
  List<BleService> _services = const [];
  final Set<String> _notifying = {}; // characteristic uuids currently notifying

  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<bool>? _connSub;
  final Map<String, StreamSubscription<Uint8List>> _valueSubs = {};

  // --- Public state --------------------------------------------------------

  bool get scanning => _scanning;
  bool get loadingSystem => _loadingSystem;
  bool get connecting => _connecting;

  /// When true, devices advertising no name are hidden from [devices].
  bool get hideUnnamed => _hideUnnamed;
  set hideUnnamed(bool v) {
    if (_hideUnnamed == v) return;
    _hideUnnamed = v;
    notifyListeners();
  }
  bool get isConnected => _connectedId != null;
  String? get connectedId => _connectedId;
  String? get connectedName => _connectedName;
  int? get mtu => _mtu;
  List<BleService> get services => _services;

  /// Discovered devices, strongest signal first. Filters out unnamed devices
  /// when [hideUnnamed] is set.
  List<DevScanEntry> get devices {
    final list = _devices.values
        .where((d) => !_hideUnnamed || (d.name != null && d.name!.isNotEmpty))
        .toList();
    list.sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    return list;
  }

  List<DevLogEntry> get log => List.unmodifiable(_log);

  bool isNotifying(String characteristicUuid) =>
      _notifying.contains(characteristicUuid.toLowerCase());

  // --- Scanning ------------------------------------------------------------

  /// Start an **unfiltered** scan. Runs until [stopScan] or a safety auto-stop.
  Future<void> startScan() async {
    if (_scanning) return;
    if (!await _ensureAdapterOn()) {
      _addLog(DevLogLevel.error, 'Bluetooth is off or unavailable');
      return;
    }
    _devices.clear();
    _scanning = true;
    notifyListeners();
    _addLog(DevLogLevel.info, 'Scan started (no filter)');

    // Pull in already-connected/bonded system devices first (won't appear in a
    // normal scan on macOS).
    unawaited(refreshSystemDevices());

    _scanSub = UniversalBle.scanStream.listen((d) {
      _devices[d.deviceId] = DevScanEntry(
        deviceId: d.deviceId,
        name: d.name,
        rssi: d.rssi,
        services: d.services,
      );
      notifyListeners();
    }, onError: (Object e) {
      _addLog(DevLogLevel.error, 'Scan error: $e');
    });

    try {
      await UniversalBle.startScan();
    } catch (e) {
      _addLog(DevLogLevel.error, 'startScan failed: $e');
      await stopScan();
    }
  }

  Future<void> stopScan() async {
    if (!_scanning && _scanSub == null) return;
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
    _scanning = false;
    notifyListeners();
    _addLog(DevLogLevel.info, 'Scan stopped (${_devices.length} found)');
  }

  /// Merge in system devices — peripherals **currently connected at the OS
  /// level** (by this or any other app). Note this returns only *actively
  /// connected* devices: a device that is merely *bonded* but disconnected will
  /// NOT appear here until it reconnects. On Apple, results are filtered to
  /// [_systemDeviceServices] (CoreBluetooth requires a service list).
  Future<void> refreshSystemDevices() async {
    if (_loadingSystem) return;
    _loadingSystem = true;
    notifyListeners();
    _addLog(DevLogLevel.info, 'Querying system (connected) devices…');
    try {
      final sys = await UniversalBle.getSystemDevices(
          withServices: _systemDeviceServices);
      for (final d in sys) {
        _devices[d.deviceId] = DevScanEntry(
          deviceId: d.deviceId,
          name: d.name,
          rssi: d.rssi,
          services: d.services,
          isSystemDevice: true,
        );
      }
      if (sys.isEmpty) {
        _addLog(DevLogLevel.info,
            'No system devices connected. (Bonded-but-disconnected devices '
            'won\'t appear — use Scan, or connect it in macOS Bluetooth first.)');
      } else {
        _addLog(DevLogLevel.info,
            '${sys.length} system device(s): '
            '${sys.map((d) => d.name ?? d.deviceId).join(', ')}');
      }
    } catch (e) {
      _addLog(DevLogLevel.error, 'getSystemDevices failed: $e');
    } finally {
      _loadingSystem = false;
      notifyListeners();
    }
  }

  // --- Connection ----------------------------------------------------------

  Future<void> connect(String deviceId, {String? name}) async {
    if (_connecting || _connectedId != null) return;
    await stopScan();
    _connecting = true;
    notifyListeners();
    _addLog(DevLogLevel.info, 'Connecting to ${name ?? deviceId}…');

    try {
      await UniversalBle.connect(deviceId,
          timeout: const Duration(seconds: 20));

      // Subscribe to connection changes only AFTER connect succeeds so a
      // replayed `disconnected` can't tear us down (handoff §5 gotcha 1).
      _connSub = UniversalBle.connectionStream(deviceId).listen((connected) {
        if (!connected && _connectedId == deviceId) {
          _addLog(DevLogLevel.error, 'Device disconnected');
          _resetConnection();
        }
      });

      try {
        _mtu = await UniversalBle.requestMtu(deviceId, 247);
      } catch (_) {
        _mtu = null;
      }

      final services = await UniversalBle.discoverServices(deviceId);
      _services = services;
      _connectedId = deviceId;
      _connectedName = name;
      _connecting = false;
      final charCount =
          services.fold<int>(0, (n, s) => n + s.characteristics.length);
      _addLog(DevLogLevel.info,
          'Connected · ${services.length} services, $charCount characteristics'
          '${_mtu != null ? ', MTU $_mtu' : ''}');
      _maybeNoteSmp(services);
      notifyListeners();
    } catch (e) {
      _connecting = false;
      _addLog(DevLogLevel.error, 'Connect failed: $e');
      await _teardown();
      notifyListeners();
    }
  }

  void _maybeNoteSmp(List<BleService> services) {
    final hasSmp = services.any(
        (s) => _sameUuid(s.uuid, '8d53dc1d-1db7-4cd3-868b-8a527460aa84'));
    if (hasSmp) {
      _addLog(DevLogLevel.info,
          'SMP / MCUmgr service present — this is an SMP-enabled device.');
    }
  }

  Future<void> disconnect() async {
    _addLog(DevLogLevel.info, 'Disconnecting…');
    await _teardown();
    notifyListeners();
  }

  // --- Characteristic operations ------------------------------------------

  Future<void> readCharacteristic(String service, String characteristic) async {
    final id = _connectedId;
    if (id == null) return;
    try {
      final value = await UniversalBle.read(id, service, characteristic);
      _addLog(DevLogLevel.rx,
          'READ ${_short(characteristic)}  ${_hex(value)}  "${_ascii(value)}"');
    } catch (e) {
      _addLog(DevLogLevel.error, 'Read failed (${_short(characteristic)}): $e');
    }
  }

  Future<void> writeCharacteristic(
    String service,
    String characteristic,
    Uint8List value, {
    required bool withoutResponse,
  }) async {
    final id = _connectedId;
    if (id == null) return;
    try {
      await UniversalBle.write(id, service, characteristic, value,
          withoutResponse: withoutResponse);
      _addLog(DevLogLevel.tx,
          'WRITE ${_short(characteristic)}  ${_hex(value)}'
          '${withoutResponse ? '  (no-rsp)' : ''}');
    } catch (e) {
      _addLog(DevLogLevel.error, 'Write failed (${_short(characteristic)}): $e');
    }
  }

  Future<void> toggleNotify(String service, String characteristic) async {
    final id = _connectedId;
    if (id == null) return;
    final key = characteristic.toLowerCase();
    try {
      if (_notifying.contains(key)) {
        await UniversalBle.unsubscribe(id, service, characteristic);
        await _valueSubs.remove(key)?.cancel();
        _notifying.remove(key);
        _addLog(DevLogLevel.info, 'Unsubscribed ${_short(characteristic)}');
      } else {
        _valueSubs[key] =
            UniversalBle.characteristicValueStream(id, characteristic).listen(
          (data) {
            _addLog(DevLogLevel.rx,
                'NOTIFY ${_short(characteristic)}  ${_hex(data)}  "${_ascii(data)}"');
          },
          onError: (Object e) {
            _addLog(DevLogLevel.error, 'Notify error: $e');
          },
        );
        await UniversalBle.subscribeNotifications(id, service, characteristic);
        _notifying.add(key);
        _addLog(DevLogLevel.info, 'Subscribed ${_short(characteristic)}');
      }
      notifyListeners();
    } catch (e) {
      _addLog(DevLogLevel.error, 'Notify toggle failed: $e');
    }
  }

  void clearLog() {
    _log.clear();
    notifyListeners();
  }

  // --- Internals -----------------------------------------------------------

  Future<void> _teardown() async {
    for (final s in _valueSubs.values) {
      await s.cancel();
    }
    _valueSubs.clear();
    await _connSub?.cancel();
    _connSub = null;
    final id = _connectedId;
    if (id != null) {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
    _resetConnection();
  }

  void _resetConnection() {
    _connectedId = null;
    _connectedName = null;
    _connecting = false;
    _mtu = null;
    _services = const [];
    _notifying.clear();
    for (final s in _valueSubs.values) {
      s.cancel();
    }
    _valueSubs.clear();
    notifyListeners();
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

  void _addLog(DevLogLevel level, String text) {
    _log.add(DevLogEntry(DateTime.now(), level, text));
    if (_log.length > _maxLog) _log.removeRange(0, _log.length - _maxLog);
    notifyListeners();
  }

  static String _short(String uuid) {
    final u = uuid.toLowerCase().replaceAll('-', '');
    // Show the 16-bit short form when it's a standard SIG UUID, else last 4.
    if (u.length >= 8 && u.startsWith('0000')) {
      return '0x${u.substring(4, 8)}';
    }
    return u.length <= 8 ? u : '…${u.substring(u.length - 4)}';
  }

  static String _hex(List<int> d) {
    if (d.isEmpty) return '(empty)';
    final n = d.length < 40 ? d.length : 40;
    final s = [
      for (var i = 0; i < n; i++) d[i].toRadixString(16).padLeft(2, '0')
    ].join(' ');
    return d.length > n ? '$s …' : s;
  }

  static String _ascii(List<int> d) {
    final b = StringBuffer();
    for (final c in d.take(32)) {
      b.write(c >= 0x20 && c < 0x7f ? String.fromCharCode(c) : '.');
    }
    return b.toString();
  }

  static bool _sameUuid(String a, String b) {
    final la = a.toLowerCase().replaceAll('-', '');
    final lb = b.toLowerCase().replaceAll('-', '');
    return la == lb || la.endsWith(lb) || lb.endsWith(la);
  }

  /// Parse a hex string like "0a fa 01", "0AFA01", or "0x0A,0xFA" into bytes.
  /// Strips all non-hex characters and requires an even number of digits.
  /// Returns null on invalid input.
  static Uint8List? parseHex(String input) {
    final digits = input.replaceAll(RegExp(r'0[xX]'), '').replaceAll(
          RegExp(r'[^0-9a-fA-F]'),
          '',
        );
    if (digits.isEmpty || digits.length.isOdd) return null;
    final out = Uint8List(digits.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(digits.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _teardown();
    super.dispose();
  }
}
