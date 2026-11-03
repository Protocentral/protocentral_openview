// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'transport_service.dart';

/// Desktop USB-serial transport via flutter_libserialport.
///
/// On mobile (Android/iOS) this class is never instantiated — see
/// `transport_factory.dart`. The `dart:io` `Platform` check inside `scan`
/// is a belt-and-braces guard.
class UsbSerialService extends TransportService {
  final _bytesController = StreamController<Uint8List>.broadcast();
  final _eventsController = StreamController<TransportEvent>.broadcast();

  TransportStatus _status = TransportStatus.idle;
  TransportTarget? _target;
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSub;
  int _baudRate = 115200;
  Future<void>? _teardown;
  // Bumped on every connect/disconnect so a late link-loss handler can tell
  // it has been superseded.
  int _session = 0;
  String? _serialNumber;

  @override
  TransportKind get kind => TransportKind.usb;

  @override
  TransportStatus get status => _status;

  @override
  TransportTarget? get connectedTarget => _target;

  @override
  Stream<Uint8List> get bytes => _bytesController.stream;

  @override
  Stream<TransportEvent> get events => _eventsController.stream;

  /// USB serial number of the most recently opened port, if the device
  /// reports one. Kept after the link drops so a reconnect can find the
  /// same board even if the OS gives it a different port name.
  String? get serialNumber => _serialNumber;

  /// Look for a port that was lost: the same port name first, else any port
  /// whose USB serial number matches [serialNumber]. Returns null if neither
  /// is present yet.
  TransportTarget? findPort(TransportTarget lost, {String? serialNumber}) {
    final List<String> names;
    try {
      names = SerialPort.availablePorts;
    } catch (_) {
      return null;
    }
    if (names.contains(lost.id)) return lost;
    if (serialNumber == null || serialNumber.isEmpty) return null;
    for (final name in names) {
      final p = SerialPort(name);
      try {
        if (p.serialNumber == serialNumber) {
          return TransportTarget(
            kind: TransportKind.usb,
            id: name,
            displayName: name,
            subtitle: lost.subtitle,
          );
        }
      } catch (_) {
        // Metadata can throw for in-use ports; skip them.
      } finally {
        p.dispose();
      }
    }
    return null;
  }

  /// Override the baud rate used on the next `connect()`. Boards declare
  /// their default in their `UsbProfile`.
  void setBaudRate(int baud) {
    _baudRate = baud;
  }

  @override
  Future<List<TransportTarget>> scan({
    Duration timeout = const Duration(seconds: 1),
  }) async {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return const [];
    }
    _setStatus(TransportStatus.scanning);
    final targets = <TransportTarget>[];
    try {
      for (final name in SerialPort.availablePorts) {
        final p = SerialPort(name);
        String display = name;
        String? subtitle;
        try {
          final desc = p.description ?? '';
          final manuf = p.manufacturer ?? '';
          if (desc.isNotEmpty) display = '$name — $desc';
          if (manuf.isNotEmpty) subtitle = manuf;
        } catch (_) {
          // Some platforms throw on metadata access for in-use ports.
        }
        targets.add(TransportTarget(
          kind: TransportKind.usb,
          id: name,
          displayName: display,
          subtitle: subtitle,
        ));
        p.dispose();
      }
    } catch (e) {
      _eventsController.add(TransportEvent(TransportStatus.error,
          message: 'scan failed', error: e));
    } finally {
      _setStatus(TransportStatus.idle);
    }
    return targets;
  }

  @override
  Future<void> connect(TransportTarget target) async {
    // Tear down any leftover port/reader (or wait out an in-flight
    // teardown), not just a cleanly-connected one.
    if (_teardown != null || _port != null || _reader != null) {
      await shutdown();
    }
    _session++;
    _target = target;
    _setStatus(TransportStatus.connecting);
    try {
      final p = SerialPort(target.id);
      if (!p.openReadWrite()) {
        final msg = SerialPort.lastError?.message ?? 'unknown error';
        p.dispose();
        throw StateError('Failed to open ${target.id}: $msg');
      }
      // Do NOT dispose `cfg` here: the `SerialPort.config` setter caches it
      // and `SerialPort.dispose()` frees it. Disposing it ourselves caused a
      // double `sp_free_config` (malloc abort) on the next disconnect.
      final cfg = SerialPortConfig()
        ..baudRate = _baudRate
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);
      p.config = cfg;
      try {
        _serialNumber = p.serialNumber;
      } catch (_) {
        _serialNumber = null;
      }
      _port = p;
      _reader = SerialPortReader(p, timeout: 100);
      // A read error or the stream closing means the device went away
      // (unplug, or a board reset re-enumerating USB).
      _readerSub = _reader!.stream.listen(
        (chunk) => _bytesController.add(chunk),
        onError: (Object e) => _handleLinkLost(e),
        onDone: () => _handleLinkLost(null),
      );
      _setStatus(TransportStatus.connected);
    } catch (e) {
      _setStatus(TransportStatus.error, message: e.toString());
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _session++;
    _setStatus(TransportStatus.disconnecting);
    await shutdown();
    _setStatus(TransportStatus.idle);
  }

  @override
  Future<void> send(Uint8List data) async {
    final p = _port;
    if (p == null) {
      throw StateError('USB transport not connected');
    }
    p.write(data);
  }

  void _setStatus(TransportStatus s, {String? message, Object? error}) {
    _status = s;
    _eventsController.add(TransportEvent(s, message: message, error: error));
    notifyListeners();
  }

  /// Release the port as soon as the device disappears, then report `lost`.
  /// Freeing the FD promptly lets the OS reuse the same port name when the
  /// device re-enumerates (on Linux a held FD bumps ttyACM0 to ttyACM1).
  Future<void> _handleLinkLost(Object? error) async {
    if (_status != TransportStatus.connected) return;
    final session = _session;
    _setStatus(TransportStatus.disconnecting, message: 'USB link lost');
    await shutdown();
    // A user disconnect/connect during the teardown owns the status now.
    if (session != _session) return;
    _setStatus(TransportStatus.lost,
        message: error == null ? 'device disconnected' : 'read error: $error',
        error: error);
  }

  /// Properly-ordered async shutdown. Use this from disconnect handlers and
  /// from the window-close handler.
  ///
  /// Order matters: `flutter_libserialport`'s native read worker is blocked
  /// in a 100 ms timeout `read()` syscall on the port's FD. If we close the
  /// port while the worker is mid-read, the FD goes away under it and the
  /// worker isolate crashes (SIGSEGV in DartWorker, cascading into the
  /// main thread). The sequence:
  ///
  ///   1. cancel the Dart-side subscription (no more events to listeners)
  ///   2. tell the reader to close (signals its worker to stop)
  ///   3. wait long enough for the worker's blocking read to time out and
  ///      the isolate to exit cleanly
  ///   4. only THEN close the port and dispose it
  ///
  /// Concurrent calls (e.g. a link-loss teardown and a user disconnect)
  /// share one in-flight teardown, so the port is never disposed twice.
  Future<void> shutdown({
    Duration readerSettleDelay = const Duration(milliseconds: 200),
  }) {
    return _teardown ??= _shutdown(readerSettleDelay)
        .whenComplete(() => _teardown = null);
  }

  Future<void> _shutdown(Duration readerSettleDelay) async {
    // Take ownership of the handles up front so nothing else can reach them.
    final sub = _readerSub;
    final reader = _reader;
    final port = _port;
    _readerSub = null;
    _reader = null;
    _port = null;
    try {
      await sub?.cancel();
    } catch (_) {}
    try {
      reader?.close();
    } catch (_) {}
    await Future<void>.delayed(readerSettleDelay);
    try {
      port?.close();
    } catch (_) {}
    try {
      port?.dispose();
    } catch (_) {}
    _target = null;
    _status = TransportStatus.idle;
  }

  /// Synchronous best-effort fallback for paths that can't await — chiefly
  /// `dispose()` during ChangeNotifier teardown.
  ///
  /// Cancels the subscription and signals the reader to close, but **does
  /// not** close the port: doing so synchronously is exactly the race that
  /// crashes the worker isolate. The FD is leaked here; the OS reclaims it
  /// when the process exits (which is the only context this path runs in).
  void shutdownSync() {
    try {
      _readerSub?.cancel();
    } catch (_) {}
    _readerSub = null;
    try {
      _reader?.close();
    } catch (_) {}
    _reader = null;
    _target = null;
    _status = TransportStatus.idle;
  }

  @override
  void dispose() {
    shutdownSync();
    if (!_bytesController.isClosed) _bytesController.close();
    if (!_eventsController.isClosed) _eventsController.close();
    super.dispose();
  }
}
