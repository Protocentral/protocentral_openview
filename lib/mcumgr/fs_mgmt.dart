import 'dart:typed_data';

import '../smp/smp_client.dart';
import '../smp/smp_message.dart';

/// Progress callback: (bytesTransferred, total). Total may be 0/unknown until
/// the first response for a download.
typedef FsProgress = void Function(int done, int total);

/// MCUmgr **Filesystem management group** (group id 8).
///
/// Transfer files to/from the device's filesystem (e.g. LittleFS `/lfs`) by
/// absolute path. Covers `stat` (size), `download`, and `upload`.
///
/// **Scope note:** stock Zephyr fs_mgmt exposes only per-file transfer + status —
/// there is **no directory listing and no delete** command in the base group, so
/// this is a file-transfer facade (you must know the path), not a browser. A
/// device would need a vendor extension (or the HPI_HS group) to enumerate/delete.
class FsMgmt {
  FsMgmt(this.client, {int? Function()? maxWriteLength})
      : _maxWriteLength = maxWriteLength;

  final SmpClient client;

  /// Provider for the transport's ATT MTU − 3 (read dynamically). Bounds the
  /// upload data chunk so each write-without-response fits one frame.
  final int? Function()? _maxWriteLength;

  static const int group = 8;

  static const int idFile = 0; // download (read) / upload (write) by offset
  static const int idStatus = 1; // file status (size)

  SmpMessage _check(SmpMessage rsp) {
    final code = rsp.rc;
    if (code != null) {
      throw SmpException(rsp.errorLabel ?? 'rc=$code', rsp.group, rsp.id,
          rsp.seq,
          rc: code);
    }
    return rsp;
  }

  /// File size in bytes. Requires `CONFIG_MCUMGR_GRP_FS_FILE_STATUS` on the
  /// device; throws (rc) otherwise.
  Future<int> stat(String path) async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: idStatus,
      payload: {'name': path},
    ));
    final len = rsp.payload['len'];
    return len is int ? len : 0;
  }

  /// Download [path] by looping `read {name, off}` until the whole file (the
  /// `len` from the first response) has arrived.
  Future<Uint8List> download(String path, {FsProgress? onProgress}) async {
    final out = BytesBuilder(copy: false);
    int total = -1;
    int off = 0;
    onProgress?.call(0, 0);
    while (true) {
      final rsp = _check(await client.send(
        op: SmpOp.readReq,
        group: group,
        id: idFile,
        payload: {'name': path, 'off': off},
      ));
      if (total < 0) {
        final len = rsp.payload['len'];
        total = len is int ? len : 0;
      }
      final data = rsp.payload['data'];
      final bytes = (data is List) ? Uint8List.fromList(data.cast<int>()) : Uint8List(0);
      out.add(bytes);
      off += bytes.length;
      onProgress?.call(off, total);
      if (bytes.isEmpty || off >= total) break;
    }
    return out.toBytes();
  }

  /// Data bytes per upload request, sized to fit one write (MTU − overhead −
  /// the `name` string, which rides in every request).
  int _chunkSize(String name, int off) {
    final maxWrite = _maxWriteLength?.call() ?? 180;
    // SMP header (8) + CBOR overhead for {name, off, data, len}; the path string
    // is sent on every request. Reserve generously.
    final reserve = (off == 0 ? 44 : 36) + name.length;
    return (maxWrite - reserve).clamp(16, 512);
  }

  /// Steady-state upload chunk for [path] (diagnostics/UI).
  int steadyChunkSize(String path) => _chunkSize(path, 1);

  /// Upload [data] to [path] by looping `write {name, off, data, len(first)}`,
  /// advancing to the device-returned offset.
  Future<void> upload(String path, Uint8List data,
      {FsProgress? onProgress}) async {
    int off = 0;
    onProgress?.call(0, data.length);
    while (off < data.length) {
      final chunk = _chunkSize(path, off);
      final end = (off + chunk < data.length) ? off + chunk : data.length;
      final slice = data.sublist(off, end);

      final map = <String, Object?>{
        'name': path,
        'off': off,
        'data': Uint8List.fromList(slice),
        if (off == 0) 'len': data.length,
      };
      final rsp = _check(await client.send(
        op: SmpOp.writeReq,
        group: group,
        id: idFile,
        payload: map,
      ));
      final next = rsp.payload['off'];
      off = (next is int && next > off) ? next : end;
      onProgress?.call(off, data.length);
    }
  }
}
