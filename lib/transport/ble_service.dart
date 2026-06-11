import 'dart:async';
import 'dart:typed_data';

import 'transport_service.dart';

/// BLE transport — stubbed.
///
/// TODO(phase1.b): wire flutter_blue_plus end-to-end.
///   - scan() should filter by BoardDescriptor.bleProfile.serviceUuid
///   - connect() should: discover services, find the stream characteristic,
///     enable notifications, request MTU 247, then pipe notification bytes
///     into _bytesController.
///   - send() should write to the command characteristic if present.
class BleService extends TransportService {
  final _bytesController = StreamController<Uint8List>.broadcast();
  final _eventsController = StreamController<TransportEvent>.broadcast();

  TransportStatus _status = TransportStatus.idle;
  TransportTarget? _target;

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

  @override
  Future<List<TransportTarget>> scan({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _eventsController.add(const TransportEvent(
      TransportStatus.error,
      message: 'BLE not yet implemented in phase 1.a',
    ));
    return const [];
  }

  @override
  Future<void> connect(TransportTarget target) async {
    throw UnimplementedError('BLE transport — phase 1.b');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(Uint8List data) async {
    throw UnimplementedError('BLE transport — phase 1.b');
  }

  @override
  void dispose() {
    _bytesController.close();
    _eventsController.close();
    super.dispose();
  }
}
