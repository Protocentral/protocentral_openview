// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'transport_service.dart';

/// Wi-Fi transport — a raw TCP client.
///
/// A board that streams the ProtoCentral framed protocol over Wi-Fi exposes a
/// TCP server (host:port); this transport opens a socket and pipes the byte
/// stream through unchanged, exactly like the USB and BLE transports.
///
/// There is no zero-config (mDNS) discovery yet, so [scan] returns nothing and
/// targets are created from a manually-entered host/port via [targetFor]. The
/// host and port travel in [TransportTarget.extra].
class WifiService extends TransportService {
  final _bytesController = StreamController<Uint8List>.broadcast();
  final _eventsController = StreamController<TransportEvent>.broadcast();

  TransportStatus _status = TransportStatus.idle;
  TransportTarget? _target;
  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSub;

  @override
  TransportKind get kind => TransportKind.wifi;

  @override
  TransportStatus get status => _status;

  @override
  TransportTarget? get connectedTarget => _target;

  @override
  Stream<Uint8List> get bytes => _bytesController.stream;

  @override
  Stream<TransportEvent> get events => _eventsController.stream;

  /// Build a target from a manually-entered host + port.
  static TransportTarget targetFor({required String host, required int port}) {
    return TransportTarget(
      kind: TransportKind.wifi,
      id: '$host:$port',
      displayName: '$host:$port',
      subtitle: 'Network device',
      extra: {'host': host, 'port': port},
    );
  }

  /// No auto-discovery yet — host/port are entered manually.
  @override
  Future<List<TransportTarget>> scan({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    return const [];
  }

  @override
  Future<void> connect(TransportTarget target) async {
    if (_status == TransportStatus.connected) await disconnect();
    final host = target.extra['host'] as String?;
    final port = target.extra['port'] as int?;
    if (host == null || port == null) {
      throw StateError('Wi-Fi target missing host/port');
    }
    _target = target;
    _setStatus(TransportStatus.connecting);
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 8),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      _socketSub = socket.listen(
        (chunk) => _bytesController.add(chunk),
        onError: (e) =>
            _setStatus(TransportStatus.error, message: 'socket error: $e'),
        onDone: () {
          if (_status == TransportStatus.connected) {
            _setStatus(TransportStatus.error, message: 'connection closed');
          }
        },
        cancelOnError: true,
      );
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
    final s = _socket;
    if (s == null) throw StateError('Wi-Fi transport not connected');
    s.add(data);
  }

  Future<void> _teardown() async {
    try {
      await _socketSub?.cancel();
    } catch (_) {}
    _socketSub = null;
    try {
      await _socket?.flush().timeout(const Duration(milliseconds: 200));
    } catch (_) {}
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _target = null;
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
