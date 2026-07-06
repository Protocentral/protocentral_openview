import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../mcumgr/img_mgmt.dart';
import '../mcumgr/os_mgmt.dart';
import '../smp/smp_ble_transport.dart';
import '../smp/smp_client.dart';
import '../smp/smp_message.dart';
import '../smp/smp_transport.dart';

/// A pickable SMP device from a scan.
class SmpScanTarget {
  final String deviceId;
  final String? name;
  final int? rssi;
  final bool isSystemDevice;
  const SmpScanTarget({
    required this.deviceId,
    required this.name,
    required this.rssi,
    this.isSystemDevice = false,
  });

  String get displayName =>
      (name != null && name!.isNotEmpty) ? name! : '(unnamed)';
}

/// One line in the raw SMP console log.
class ConsoleEntry {
  ConsoleEntry(this.message, {required this.outbound})
      : timestamp = DateTime.now();
  final SmpMessage message;
  final bool outbound;
  final DateTime timestamp;
}

/// Owns the **SMP / MCUmgr Device Manager** subsystem — a decoupled BLE link
/// (its own connection, separate from the streaming `ConnectionController`).
///
/// Scans broadly, connects to a chosen device, gates on the SMP service, and
/// exposes the MCUmgr group facades (Phase 1: [os]) plus a raw request/response
/// console. `universal_ble`'s command queue serialises access, so this coexists
/// with the streaming `BleService`; don't drive both BLE flows at once.
class SmpController extends ChangeNotifier {
  // Convenience service filters for already-connected (bonded) system devices —
  // CoreBluetooth omits connected peripherals from scans (handoff §5.2).
  static const List<String> _systemDeviceServices = [
    SmpBleTransport.smpServiceUuid,
    '180a', // Device Information
    '180f', // Battery
  ];

  static const int _maxConsole = 1000;

  final Map<String, SmpScanTarget> _devices = {};
  final List<ConsoleEntry> console = <ConsoleEntry>[];

  bool _scanning = false;
  bool _loadingSystem = false;
  bool _connecting = false;
  String? _error;

  SmpBleTransport? _transport;
  SmpClient? _client;
  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<SmpConnectionState>? _stateSub;

  SmpConnectionState _state = SmpConnectionState.disconnected;

  /// MCUmgr group facades — non-null only while connected.
  OsMgmt? os;
  ImgMgmt? img;

  // --- Public state --------------------------------------------------------

  bool get scanning => _scanning;
  bool get loadingSystem => _loadingSystem;
  bool get connecting => _connecting;
  bool get isConnected => _state == SmpConnectionState.connected;
  SmpConnectionState get state => _state;
  String? get error => _error;
  String? get deviceLabel => _transport?.deviceLabel;
  int? get maxWriteLength => _transport?.maxWriteLength;

  /// Discoverable devices, strongest signal first. Unnamed peripherals are
  /// always hidden here — an SMP device the user wants to manage advertises a
  /// name, and the noise of nameless beacons is not useful in this list.
  List<SmpScanTarget> get devices {
    final list = _devices.values
        .where((t) => t.name != null && t.name!.isNotEmpty)
        .toList();
    list.sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    return list;
  }

  // --- Scanning ------------------------------------------------------------

  Future<void> startScan() async {
    if (_scanning) return;
    if (!await _ensureAdapterOn()) {
      _error = 'Bluetooth is off or unavailable';
      notifyListeners();
      return;
    }
    _devices.clear();
    _error = null;
    _scanning = true;
    notifyListeners();

    unawaited(refreshSystemDevices());

    _scanSub = UniversalBle.scanStream.listen((d) {
      _devices[d.deviceId] = SmpScanTarget(
        deviceId: d.deviceId,
        name: d.name,
        rssi: d.rssi,
      );
      notifyListeners();
    }, onError: (Object e) {
      _error = 'Scan error: $e';
      notifyListeners();
    });

    try {
      await UniversalBle.startScan();
    } catch (e) {
      _error = 'startScan failed: $e';
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
  }

  Future<void> refreshSystemDevices() async {
    if (_loadingSystem) return;
    _loadingSystem = true;
    notifyListeners();
    try {
      final sys = await UniversalBle.getSystemDevices(
          withServices: _systemDeviceServices);
      for (final d in sys) {
        _devices[d.deviceId] = SmpScanTarget(
          deviceId: d.deviceId,
          name: d.name,
          rssi: d.rssi,
          isSystemDevice: true,
        );
      }
    } catch (_) {
      // Non-fatal; system-device query is best-effort.
    } finally {
      _loadingSystem = false;
      notifyListeners();
    }
  }

  // --- Connection ----------------------------------------------------------

  Future<void> connect(String deviceId, {String? name}) async {
    if (_connecting || isConnected) return;
    await stopScan();
    _connecting = true;
    _error = null;
    notifyListeners();

    final transport = SmpBleTransport(deviceId, name: name);
    _transport = transport;
    _stateSub = transport.stateChanges.listen((s) {
      _state = s;
      notifyListeners();
      // The device dropped the link on its own (e.g. it rebooted after
      // `os reset`) — tear the subsystem down so no transport/controllers leak.
      if (s == SmpConnectionState.disconnected && !_tearingDown) {
        unawaited(_teardown());
      }
    });

    try {
      await transport.connect(); // throws if not an SMP device
      _client = SmpClient(transport, log: _log);
      os = OsMgmt(_client!);
      // Read maxWriteLength dynamically — MTU negotiation settles just after
      // connect on macOS/iOS, so a value cached here would be the 23-byte
      // default.
      img = ImgMgmt(_client!, maxWriteLength: () => _transport?.maxWriteLength);
      _connecting = false;
      notifyListeners();
      // Poll the MTU for a few seconds so the header/chunk size reflect the
      // negotiated value once the exchange completes.
      unawaited(_settleMtu());
    } catch (e) {
      _connecting = false;
      _error = e.toString();
      await _teardown();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _teardown();
    notifyListeners();
  }

  /// Re-query the negotiated MTU now (e.g. right before a firmware upload).
  Future<void> refreshMtu() async {
    await _transport?.refreshMtu();
    notifyListeners();
  }

  /// Poll the MTU for a few seconds after connect. macOS/iOS negotiate the ATT
  /// MTU just after the connection is up, so the value read during connect is
  /// often the 23-byte default; this lets the header + chunk size reflect the
  /// real value once it settles. Stops early once it rises above the default.
  Future<void> _settleMtu() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_transport == null) return; // disconnected meanwhile
      final before = _transport!.maxWriteLength;
      await _transport!.refreshMtu();
      final after = _transport!.maxWriteLength;
      if (after != before) notifyListeners();
      if ((after ?? 0) > 20) return; // negotiated a real MTU — done
    }
  }

  bool _tearingDown = false;

  Future<void> _teardown() async {
    if (_tearingDown) return;
    _tearingDown = true;
    try {
      await _stateSub?.cancel();
      _stateSub = null;
      await _client?.dispose();
      _client = null;
      os = null;
      img = null;
      final t = _transport;
      _transport = null;
      if (t != null) {
        try {
          await t.disconnect();
        } catch (_) {}
        await t.dispose();
      }
      _state = SmpConnectionState.disconnected;
    } finally {
      _tearingDown = false;
    }
  }

  // --- Console -------------------------------------------------------------

  void _log(SmpMessage message, {required bool outbound}) {
    console.add(ConsoleEntry(message, outbound: outbound));
    if (console.length > _maxConsole) console.removeAt(0);
    notifyListeners();
  }

  void clearConsole() {
    console.clear();
    notifyListeners();
  }

  // --- Internals -----------------------------------------------------------

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

  @override
  void dispose() {
    _scanSub?.cancel();
    _teardown();
    super.dispose();
  }
}
