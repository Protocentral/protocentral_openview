import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/hs_record.dart';
import '../models/hs_sample.dart';
import '../models/hs_type.dart';
import '../smp/smp_client.dart';
import '../smp/smp_message.dart';
import '../utils/crc32.dart';

/// Result of a `HELLO` handshake.
class HsHello {
  const HsHello({
    required this.schema,
    required this.group,
    required this.dev,
    required this.head,
    required this.types,
  });

  final int schema; // HPI_HS_SCHEMA_VERSION
  final int group; // HPI_HS_GROUP_VERSION
  final String dev; // device serial
  final int head; // newest seq available
  final int types; // number of registry entries
}

/// One page of a `SYNC` pull.
class HsSyncPage {
  const HsSyncPage({
    required this.samples,
    required this.next,
    required this.more,
  });

  final List<HsSample> samples;
  final int next; // cursor to resume from
  final bool more; // whether further pages remain
}

/// Result of a full record download.
class HsRecordDownload {
  const HsRecordDownload({required this.data, required this.crcOk});
  final Uint8List data;

  /// True if the reassembled payload's CRC-32 matched the header's `crc32`
  /// (or the header carried no crc, i.e. `crc32 == 0`).
  final bool crcOk;
}

/// Client for the **custom HPI_HS MCUmgr group** (id `0x1000`) — the ProtoCentral
/// Health Store. Full contract in the HealthyPi Move `docs/HPI_HS_API.md`.
/// Gated: only surfaced when [hello] succeeds against a device that implements it.
class HpiHs {
  HpiHs(this.client);

  final SmpClient client;

  /// Vendor-range group id for the Health Store.
  static const int group = 0x1000;

  // Command ids (§6).
  static const int cmdHello = 0;
  static const int cmdTypes = 1;
  static const int cmdSync = 2;
  static const int cmdSummary = 3;
  static const int cmdRecords = 4;
  static const int cmdAck = 5;

  SmpMessage _check(SmpMessage rsp) {
    final code = rsp.rc;
    if (code != null) {
      throw SmpException(rsp.errorLabel ?? 'rc=$code', rsp.group, rsp.id,
          rsp.seq,
          rc: code);
    }
    return rsp;
  }

  /// `HELLO` — handshake; check schema/group and note `head` (newest seq).
  Future<HsHello> hello() async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdHello,
    ));
    final p = rsp.payload;
    return HsHello(
      schema: (p['schema'] as num?)?.toInt() ?? 0,
      group: (p['group'] as num?)?.toInt() ?? 0,
      dev: p['dev'] as String? ?? '',
      head: (p['head'] as num?)?.toInt() ?? 0,
      types: (p['types'] as num?)?.toInt() ?? 0,
    );
  }

  /// `TYPES` — fetch the registry once and cache by id. Never hard-code it.
  Future<Map<int, HsType>> types({int from = 0}) async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdTypes,
      payload: {'from': from},
    ));
    final arr = (rsp.payload['types'] as List?) ?? const [];
    if (arr.isNotEmpty) {
      // One-time diagnostic: dump the raw shape of the first entry so wire-key
      // / value-type surprises are visible in the console.
      debugPrint('[HPI_HS] TYPES[0] raw = ${arr.first}');
    }
    final out = <int, HsType>{};
    for (final e in arr) {
      if (e is Map) {
        try {
          final t = HsType.fromMap(e.map((k, v) => MapEntry(k.toString(), v)));
          out[t.id] = t;
        } catch (err) {
          debugPrint('[HPI_HS] skipped a TYPES entry: $err  raw=$e');
        }
      }
    }
    return out;
  }

  /// `SYNC` — the workhorse. Pull one page of samples from [since].
  Future<HsSyncPage> sync({required int since, int max = 256}) async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdSync,
      payload: {'since': since, 'max': max},
    ));
    final recs = rsp.payload['recs'];
    final bytes = recs is Uint8List
        ? recs
        : Uint8List.fromList(((recs as List?) ?? const []).cast<int>());
    return HsSyncPage(
      samples: HsSample.listFromBytes(bytes),
      next: (rsp.payload['next'] as num?)?.toInt() ?? since,
      more: (rsp.payload['more'] as bool?) ?? false,
    );
  }

  /// Convenience: fully drain from [since] to head, page by page.
  Future<List<HsSample>> syncAll({
    int since = 0,
    int max = 256,
    void Function(int fetched)? onProgress,
  }) async {
    final all = <HsSample>[];
    int cursor = since;
    while (true) {
      final page = await sync(since: cursor, max: max);
      all.addAll(page.samples);
      onProgress?.call(all.length);
      cursor = page.next;
      if (!page.more) break;
    }
    return all;
  }

  /// `SUMMARY` — today card + baselines (resting HR, temp Δ, HRV, steps…).
  Future<Map<String, Object?>> summary() async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdSummary,
    ));
    return rsp.payload;
  }

  /// `RECORDS list` — list episodic raw-signal sessions from [since].
  Future<List<HsRecordHeader>> recordsList({int since = 0}) async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdRecords,
      payload: {'op': 'list', 'since': since},
    ));
    final arr = (rsp.payload['recs'] as List?) ?? const [];
    return arr
        .whereType<Map>()
        .map((e) => HsRecordHeader.fromMap(e.cast<Object?, Object?>()))
        .toList();
  }

  /// `RECORDS get` — fetch a chunk of a record's raw payload.
  Future<({Uint8List data, bool eof})> recordsGet({
    required int id,
    required int off,
    required int len,
  }) async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdRecords,
      payload: {'op': 'get', 'id': id, 'off': off, 'len': len},
    ));
    final data = rsp.payload['data'];
    final bytes = data is Uint8List
        ? data
        : Uint8List.fromList(((data as List?) ?? const []).cast<int>());
    return (data: bytes, eof: (rsp.payload['eof'] as bool?) ?? false);
  }

  /// Download a full record: loop `RECORDS get` by offset until `eof`,
  /// reassemble the payload, and CRC-32 verify it against the header `crc32`.
  Future<HsRecordDownload> downloadRecord(
    HsRecordHeader header, {
    int chunk = 512,
    void Function(int done, int total)? onProgress,
  }) async {
    final out = BytesBuilder(copy: false);
    int off = 0;
    final total = header.byteLen;
    onProgress?.call(0, total);
    while (true) {
      final res = await recordsGet(id: header.id, off: off, len: chunk);
      out.add(res.data);
      off += res.data.length;
      onProgress?.call(off, total);
      if (res.eof || res.data.isEmpty || (total > 0 && off >= total)) break;
    }
    final bytes = out.toBytes();
    final crcOk = header.crc32 == 0
        ? true
        : Crc32.compute(bytes) == (header.crc32 & 0xFFFFFFFF);
    return HsRecordDownload(data: bytes, crcOk: crcOk);
  }

  /// `RECORDS ack` — device may drop that record after sync.
  Future<void> recordsAck(int id) async {
    _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdRecords,
      payload: {'op': 'ack', 'id': id},
    ));
  }

  /// `ACK` — tell the device the highest durably-stored seq (retention hook).
  Future<void> ack(int seq) async {
    _check(await client.send(
      op: SmpOp.writeReq,
      group: group,
      id: cmdAck,
      payload: {'acked': seq},
    ));
  }
}
