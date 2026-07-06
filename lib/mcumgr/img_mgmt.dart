import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../smp/smp_client.dart';
import '../smp/smp_message.dart';

/// One image slot entry from `image list` (image group state read).
class ImageSlot {
  const ImageSlot({
    required this.image,
    required this.slot,
    required this.version,
    required this.hash,
    required this.bootable,
    required this.pending,
    required this.confirmed,
    required this.active,
    required this.permanent,
  });

  final int image;
  final int slot; // 0 = primary (running), 1 = secondary (staged)
  final String version;
  final Uint8List hash;
  final bool bootable;
  final bool pending;
  final bool confirmed;
  final bool active;
  final bool permanent;

  static ImageSlot fromMap(Map<Object?, Object?> m) {
    Uint8List hashBytes() {
      final h = m['hash'];
      if (h is List) return Uint8List.fromList(h.cast<int>());
      return Uint8List(0);
    }

    bool flag(String k) => m[k] == true;
    int intOr(String k, int d) => m[k] is int ? m[k] as int : d;

    return ImageSlot(
      image: intOr('image', 0),
      slot: intOr('slot', 0),
      version: (m['version'] ?? '?').toString(),
      hash: hashBytes(),
      bootable: flag('bootable'),
      pending: flag('pending'),
      confirmed: flag('confirmed'),
      active: flag('active'),
      permanent: flag('permanent'),
    );
  }

  String get hashHex =>
      hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String get shortHash =>
      hash.isEmpty ? '—' : hashHex.substring(0, hashHex.length.clamp(0, 12));
}

/// Progress callback for [ImgMgmt.upload]: (bytesSent, total).
typedef UploadProgress = void Function(int sent, int total);

/// MCUmgr **Image management group** (group id 1) — the DFU flow.
///
/// list/state → upload (chunked, hashed, resumable) → test → reset → confirm.
///
/// The upload logic mirrors HealthyPi Studio's proven `imageUpload()`: the first
/// request carries `image` + `len` + `sha`; every request carries `off` + `data`;
/// the device replies with the **next offset it expects**, which drives the loop
/// (so it also resumes correctly if the device jumps the offset).
class ImgMgmt {
  ImgMgmt(this.client, {int? Function()? maxWriteLength})
      : _maxWriteLength = maxWriteLength;

  final SmpClient client;

  /// Provider for the current ATT MTU − 3 hint from the transport. Read
  /// **dynamically** (not cached) because MTU negotiation on macOS/iOS settles
  /// slightly after connect. Each upload request is a single write-without-
  /// response, so the whole SMP frame (8-byte header + CBOR) must fit within
  /// this. Null / null-result → conservative default.
  final int? Function()? _maxWriteLength;

  int? get maxWriteLength => _maxWriteLength?.call();

  static const int group = 1;
  static const int idState = 0; // list / set state (test/confirm)
  static const int idUpload = 1;
  static const int idErase = 5;

  /// Throw on a non-zero MCUmgr result code (v1 `rc` / v2 `err`), with a
  /// human-readable label (e.g. "image: flash open failed (rc=10)").
  SmpMessage _check(SmpMessage rsp) {
    final code = rsp.rc;
    if (code != null) {
      throw SmpException(rsp.errorLabel ?? 'rc=$code', rsp.group, rsp.id,
          rsp.seq,
          rc: code);
    }
    return rsp;
  }

  /// List images and slot state.
  Future<List<ImageSlot>> list() async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: idState,
    ));
    final images = rsp.payload['images'];
    if (images is! List) return const <ImageSlot>[];
    return images
        .whereType<Map>()
        .map((e) => ImageSlot.fromMap(e.cast<Object?, Object?>()))
        .toList();
  }

  /// Data bytes per upload request for the frame at [off]. The first request
  /// also carries `image` + `len` + a 32-byte `sha`, so it reserves more.
  int _chunkSize(int off) {
    final maxWrite = maxWriteLength ?? 180; // safe when MTU is unknown
    // SMP header (8) + CBOR map/key/int overhead; the first frame adds the
    // 32-byte sha + len + image. Reserve generously to stay within one write.
    final reserve = off == 0 ? 90 : 28;
    return (maxWrite - reserve).clamp(32, 512);
  }

  /// The steady-state data chunk size (bytes per upload request after the
  /// first), for display/diagnostics.
  int get steadyChunkSize => _chunkSize(1);

  /// Upload a signed image to the secondary slot. Returns the image's SHA-256
  /// (pass it to [test] afterwards). [imageIndex] selects the MCUboot image
  /// (0 = primary MCU, 1 = second core, …).
  Future<List<int>> upload(
    Uint8List image, {
    int imageIndex = 0,
    UploadProgress? onProgress,
  }) async {
    final sha = crypto.sha256.convert(image).bytes;
    int off = 0;
    onProgress?.call(0, image.length);
    while (off < image.length) {
      final chunk = _chunkSize(off);
      final end = (off + chunk < image.length) ? off + chunk : image.length;
      final data = image.sublist(off, end);

      final map = <String, Object?>{
        if (off == 0) ...{
          'image': imageIndex,
          'len': image.length,
          'sha': Uint8List.fromList(sha),
        },
        'off': off,
        'data': Uint8List.fromList(data),
      };

      final rsp = _check(await client.send(
        op: SmpOp.writeReq,
        group: group,
        id: idUpload,
        payload: map,
      ));

      // The device tells us the next offset it expects.
      final next = rsp.payload['off'];
      off = (next is int && next > off) ? next : end;
      onProgress?.call(off, image.length);
    }
    return sha;
  }

  /// Mark the staged image for test on next boot (by its [hash] = SHA-256).
  Future<void> test(List<int> hash) async {
    _check(await client.send(
      op: SmpOp.writeReq,
      group: group,
      id: idState,
      payload: {'hash': Uint8List.fromList(hash), 'confirm': false},
    ));
  }

  /// Confirm the running image (make it permanent) — after a successful boot.
  /// Pass an empty [hash] to confirm the currently-running image.
  Future<void> confirm(List<int> hash) async {
    _check(await client.send(
      op: SmpOp.writeReq,
      group: group,
      id: idState,
      payload: {'hash': Uint8List.fromList(hash), 'confirm': true},
    ));
  }

  /// Erase the secondary slot.
  Future<void> erase() async {
    _check(await client.send(
      op: SmpOp.writeReq,
      group: group,
      id: idErase,
    ));
  }
}
