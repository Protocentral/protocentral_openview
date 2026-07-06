import 'dart:typed_data';

import 'package:cbor/cbor.dart';

/// SMP operation codes (the low bit distinguishes request vs response).
enum SmpOp {
  readReq(0),
  readRsp(1),
  writeReq(2),
  writeRsp(3);

  const SmpOp(this.value);
  final int value;

  static SmpOp fromValue(int v) =>
      SmpOp.values.firstWhere((o) => o.value == v, orElse: () => SmpOp.readRsp);
}

/// A single SMP message: the 8-byte header plus a decoded CBOR map payload.
///
/// Wire header layout (see `SMP_INTEGRATION_HANDOFF.md` §3):
/// ```
///   0 op(1) 1 flags(1) 2 len(2, BE) 4 group(2, BE) 6 seq(1) 7 id(1)
/// ```
/// The payload that follows is a CBOR map of `len` bytes.
class SmpMessage {
  SmpMessage({
    required this.op,
    required this.group,
    required this.id,
    required this.seq,
    this.flags = 0,
    this.payload = const {},
  });

  final SmpOp op;
  final int group;
  final int id;
  final int seq;
  final int flags;

  /// Decoded CBOR map. For requests we encode this; for responses it is the
  /// parsed body (which may carry `rc` / `err` on failure).
  final Map<String, Object?> payload;

  static const int headerLength = 8;

  /// Encode this message (header + CBOR payload) to bytes ready for the transport.
  Uint8List toBytes() {
    final Uint8List cborBytes = Uint8List.fromList(
      cbor.encode(CborValue(payload)),
    );

    final Uint8List out = Uint8List(headerLength + cborBytes.length);
    final ByteData bd = ByteData.sublistView(out);
    bd.setUint8(0, op.value);
    bd.setUint8(1, flags);
    bd.setUint16(2, cborBytes.length); // big-endian by default
    bd.setUint16(4, group);
    bd.setUint8(6, seq);
    bd.setUint8(7, id);
    out.setRange(headerLength, out.length, cborBytes);
    return out;
  }

  /// Parse a complete SMP frame (header + full payload) from [bytes].
  ///
  /// Caller is responsible for reassembly: [bytes] must already contain at
  /// least `headerLength + len` bytes.
  static SmpMessage fromBytes(Uint8List bytes) {
    final ByteData bd = ByteData.sublistView(bytes);
    final int op = bd.getUint8(0);
    final int flags = bd.getUint8(1);
    final int len = bd.getUint16(2);
    final int group = bd.getUint16(4);
    final int seq = bd.getUint8(6);
    final int id = bd.getUint8(7);

    final Uint8List body = bytes.sublist(headerLength, headerLength + len);
    Map<String, Object?> payload = const {};
    if (body.isNotEmpty) {
      final Object? decoded = cbor.decode(body).toObject();
      if (decoded is Map) {
        payload = decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    }

    return SmpMessage(
      op: SmpOp.fromValue(op),
      group: group,
      id: id,
      seq: seq,
      flags: flags,
      payload: payload,
    );
  }

  /// The MCUmgr result code, normalising **both** error encodings:
  ///   - SMP v1: a top-level `{"rc": <int>}`.
  ///   - SMP v2: `{"err": {"group": <int>, "rc": <int>}}`.
  /// Returns null when the response carries no error field (success). A v1 `rc`
  /// of 0 (`EOK`) also reads as success → null.
  int? get rc {
    final v1 = payload['rc'];
    if (v1 is int) return v1 == 0 ? null : v1;
    final err = payload['err'];
    if (err is Map) {
      final code = err['rc'];
      if (code is int) return code == 0 ? null : code;
    }
    return null;
  }

  /// The management group of an SMP v2 `err`, if present (else null).
  int? get errGroup {
    final err = payload['err'];
    if (err is Map) {
      final g = err['group'];
      if (g is int) return g;
    }
    return null;
  }

  bool get isError => rc != null;

  @override
  String toString() =>
      'SMP(op:${op.name} grp:0x${group.toRadixString(16)} id:$id seq:$seq '
      'len:${payload.length} keys)';
}
