import 'dart:async';
import 'dart:typed_data';

import 'smp_message.dart';
import 'smp_transport.dart';

/// Callback used to mirror traffic to the Console screen (raw log).
typedef SmpLogSink = void Function(SmpMessage message, {required bool outbound});

/// Request/response SMP client over any [SmpTransport].
///
/// Responsibilities:
///   - allocate an 8-bit rolling `seq` per request,
///   - match responses back to the awaiting request by `seq`,
///   - **reassemble** fragmented notifications into whole SMP frames,
///   - time out orphaned requests.
class SmpClient {
  SmpClient(this.transport, {this.log}) {
    _sub = transport.notifications.listen(_onBytes);
  }

  final SmpTransport transport;
  final SmpLogSink? log;

  StreamSubscription<Uint8List>? _sub;

  /// Pending requests keyed by seq.
  final Map<int, Completer<SmpMessage>> _pending = {};

  /// Rolling receive buffer for fragment reassembly.
  final BytesBuilder _rxBuffer = BytesBuilder(copy: false);

  int _nextSeq = 0;

  Duration timeout = const Duration(seconds: 10);

  int _allocSeq() {
    final int seq = _nextSeq;
    _nextSeq = (_nextSeq + 1) & 0xFF;
    return seq;
  }

  /// Send [request] and await the matching response.
  Future<SmpMessage> send({
    required SmpOp op,
    required int group,
    required int id,
    Map<String, Object?> payload = const {},
  }) {
    final int seq = _allocSeq();
    final SmpMessage req = SmpMessage(
      op: op,
      group: group,
      id: id,
      seq: seq,
      payload: payload,
    );

    final Completer<SmpMessage> completer = Completer<SmpMessage>();
    _pending[seq] = completer;
    log?.call(req, outbound: true);

    transport.write(req.toBytes()).catchError((Object e) {
      _pending.remove(seq);
      if (!completer.isCompleted) completer.completeError(e);
    });

    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(seq);
      throw SmpException.timeout(group, id, seq);
    });
  }

  /// Feed raw notification bytes; pull whole frames out of the rolling buffer.
  ///
  /// A single SMP response may span multiple GATT notifications, and a single
  /// notification may in principle carry more than one frame. Loop: read the
  /// header `len` (offset 2, BE u16), wait until `8 + len` bytes are buffered,
  /// slice one frame, dispatch it, and keep the remainder.
  void _onBytes(Uint8List chunk) {
    _rxBuffer.add(chunk);
    final Uint8List buffered = _rxBuffer.toBytes();
    int offset = 0;
    while (buffered.length - offset >= SmpMessage.headerLength) {
      final ByteData bd = ByteData.sublistView(buffered, offset);
      final int len = bd.getUint16(2);
      final int frameLen = SmpMessage.headerLength + len;
      if (buffered.length - offset < frameLen) break; // incomplete — wait
      final Uint8List frame = buffered.sublist(offset, offset + frameLen);
      offset += frameLen;
      _dispatch(frame);
    }
    // Retain any trailing partial frame.
    _rxBuffer.clear();
    if (offset < buffered.length) {
      _rxBuffer.add(buffered.sublist(offset));
    }
  }

  void _dispatch(Uint8List frame) {
    final SmpMessage rsp = SmpMessage.fromBytes(frame);
    log?.call(rsp, outbound: false);
    final Completer<SmpMessage>? c = _pending.remove(rsp.seq);
    if (c == null) return; // unsolicited / late
    if (!c.isCompleted) c.complete(rsp);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(SmpException('client disposed', -1, -1, -1));
      }
    }
    _pending.clear();
    _rxBuffer.clear();
  }
}

/// Thrown on SMP-level failures (non-zero rc, timeout, malformed frame).
class SmpException implements Exception {
  SmpException(this.message, this.group, this.id, this.seq, {this.rc});

  factory SmpException.timeout(int group, int id, int seq) =>
      SmpException('SMP request timed out', group, id, seq);

  factory SmpException.rc(int group, int id, int seq, int rc) =>
      SmpException('SMP rc=$rc', group, id, seq, rc: rc);

  final String message;
  final int group;
  final int id;
  final int seq;
  final int? rc;

  @override
  String toString() =>
      'SmpException($message, grp:0x${group.toRadixString(16)} id:$id seq:$seq'
      '${rc != null ? ' rc:$rc' : ''})';
}
