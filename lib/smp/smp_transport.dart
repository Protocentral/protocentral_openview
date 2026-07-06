import 'dart:typed_data';

/// Connection state of an [SmpTransport].
enum SmpConnectionState { disconnected, connecting, connected, disconnecting }

/// Abstract byte-level transport under the SMP client.
///
/// This is the seam that keeps everything above it plugin-agnostic. The BLE
/// implementation ([SmpBleTransport], on `universal_ble`) is the one used by
/// OpenView; a serial/TCP transport could implement the same interface so the
/// identical [SmpClient] + group facades + UI work unchanged.
///
/// Contract: [write] sends one already-framed SMP request (header + CBOR).
/// Incoming device notifications — possibly fragmented — are delivered raw on
/// [notifications]; reassembly into whole SMP frames is the client's job.
abstract class SmpTransport {
  /// Human-readable id of the connected device (name or address), if known.
  String? get deviceLabel;

  /// Current connection state.
  SmpConnectionState get state;

  /// Broadcast stream of connection-state changes.
  Stream<SmpConnectionState> get stateChanges;

  /// Raw inbound bytes from the SMP characteristic notifications. One event is
  /// one GATT notification, which may be a partial SMP frame.
  Stream<Uint8List> get notifications;

  /// Negotiated payload chunk size hint (typically ATT MTU − 3). Used to bound
  /// image-upload chunking. May be null until connected/known.
  int? get maxWriteLength;

  /// Connect, resolve the SMP service + characteristic, and subscribe to
  /// notifications. Throws [SmpTransportException] if the device does not expose
  /// the SMP service (i.e. it is not an SMP-enabled device).
  Future<void> connect();

  /// Send one framed SMP request via write-without-response.
  Future<void> write(Uint8List frame);

  /// Disconnect and release GATT resources.
  Future<void> disconnect();
}

/// Thrown for transport-level failures (GATT errors, missing SMP service, …).
class SmpTransportException implements Exception {
  SmpTransportException(this.message);
  final String message;
  @override
  String toString() => 'SmpTransportException: $message';
}
