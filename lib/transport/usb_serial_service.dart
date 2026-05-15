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
        final vid = _safeInt(() => p.vendorId);
        final pid = _safeInt(() => p.productId);
        targets.add(TransportTarget(
          kind: TransportKind.usb,
          id: name,
          displayName: display,
          subtitle: subtitle,
          extra: {
            'vendorId': vid,
            'productId': pid,
            'description': p.description,
          },
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

  int? _safeInt(int? Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> connect(TransportTarget target) async {
    if (_status == TransportStatus.connected) await disconnect();
    _target = target;
    _setStatus(TransportStatus.connecting);
    try {
      final p = SerialPort(target.id);
      if (!p.openReadWrite()) {
        throw StateError('Failed to open ${target.id}: '
            '${SerialPort.lastError?.message ?? 'unknown error'}');
      }
      final cfg = SerialPortConfig()
        ..baudRate = _baudRate
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);
      p.config = cfg;
      cfg.dispose();
      _port = p;
      _reader = SerialPortReader(p, timeout: 100);
      _readerSub = _reader!.stream.listen(
        (chunk) => _bytesController.add(chunk),
        onError: (e) => _eventsController.add(
            TransportEvent(TransportStatus.error, message: 'read error', error: e)),
      );
      _setStatus(TransportStatus.connected);
    } catch (e) {
      _setStatus(TransportStatus.error, message: e.toString());
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _setStatus(TransportStatus.disconnecting);
    await _readerSub?.cancel();
    _readerSub = null;
    _reader?.close();
    _reader = null;
    try {
      _port?.close();
    } catch (_) {}
    _port?.dispose();
    _port = null;
    _target = null;
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

  void _setStatus(TransportStatus s, {String? message}) {
    _status = s;
    _eventsController.add(TransportEvent(s, message: message));
    notifyListeners();
  }

  /// Synchronous best-effort shutdown. Safe to call multiple times.
  /// Run this from a window-close handler before the engine tears down.
  void shutdownSync() {
    _readerSub?.cancel();
    _readerSub = null;
    try {
      _reader?.close();
    } catch (_) {}
    _reader = null;
    try {
      _port?.close();
    } catch (_) {}
    try {
      _port?.dispose();
    } catch (_) {}
    _port = null;
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
