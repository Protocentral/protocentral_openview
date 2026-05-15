import 'dart:async';

import 'package:flutter/foundation.dart';

enum TransportKind { ble, usb, wifi }

enum TransportStatus { idle, scanning, connecting, connected, disconnecting, error }

class TransportEvent {
  final TransportStatus status;
  final String? message;
  final Object? error;
  const TransportEvent(this.status, {this.message, this.error});

  @override
  String toString() =>
      'TransportEvent($status${message != null ? ': $message' : ''})';
}

/// A discoverable target (a USB port, BLE peripheral, TCP host, etc.).
class TransportTarget {
  final TransportKind kind;
  final String id;
  final String displayName;
  final String? subtitle;
  final Map<String, Object?> extra;

  const TransportTarget({
    required this.kind,
    required this.id,
    required this.displayName,
    this.subtitle,
    this.extra = const {},
  });

  @override
  String toString() => '$displayName ($id)';
}

/// Shared interface every transport must implement.
abstract class TransportService extends ChangeNotifier {
  TransportKind get kind;
  TransportStatus get status;
  TransportTarget? get connectedTarget;

  Stream<Uint8List> get bytes;
  Stream<TransportEvent> get events;

  Future<List<TransportTarget>> scan({Duration timeout = const Duration(seconds: 4)});

  Future<void> connect(TransportTarget target);

  Future<void> disconnect();

  Future<void> send(Uint8List data);
}
