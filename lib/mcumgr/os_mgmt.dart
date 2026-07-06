import '../smp/smp_client.dart';
import '../smp/smp_message.dart';

/// MCUmgr **OS management group** (group id 0).
///
/// Covers echo (the Phase-1 smoke test), mcumgr params, task/mpstat, **datetime
/// get/set** (id 4), and **reset** (id 5).
class OsMgmt {
  OsMgmt(this.client);

  final SmpClient client;

  static const int group = 0;

  // Command ids within the OS group.
  static const int idEcho = 0;
  static const int idTaskStat = 2;
  static const int idMpStat = 3;
  static const int idDatetime = 4;
  static const int idReset = 5;
  static const int idMcumgrParams = 6;

  /// Throw an [SmpException] if [rsp] carries a non-zero MCUmgr result code
  /// (SMP v1 `rc` or SMP v2 `err`), with a human-readable label.
  SmpMessage _check(SmpMessage rsp) {
    final code = rsp.rc;
    if (code != null) {
      throw SmpException(rsp.errorLabel ?? 'rc=$code', rsp.group, rsp.id,
          rsp.seq,
          rc: code);
    }
    return rsp;
  }

  /// Echo — round-trips a string. The Phase-1 smoke test.
  Future<String?> echo(String text) async {
    final rsp = _check(await client.send(
      op: SmpOp.writeReq,
      group: group,
      id: idEcho,
      payload: {'d': text},
    ));
    return rsp.payload['r'] as String?;
  }

  /// MCUmgr transport params (buffer size/count) — used to size upload chunks.
  Future<Map<String, Object?>> mcumgrParams() async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: idMcumgrParams,
    ));
    return rsp.payload; // { "buf_size", "buf_count" }
  }

  /// Task statistics (per-thread stack/runtime).
  Future<Map<String, Object?>> taskStat() async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: idTaskStat,
    ));
    return rsp.payload; // { "tasks": { name: {...} } }
  }

  /// Read the device RTC. Returns the device's datetime string (RFC3339-ish).
  Future<String?> getDatetime() async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: idDatetime,
    ));
    return rsp.payload['datetime'] as String?;
  }

  /// Set the device RTC. Zephyr's os-mgmt datetime parser expects an
  /// ISO-8601-ish `YYYY-MM-DDTHH:MM:SS` string; send UTC.
  Future<void> setDatetime(DateTime when) async {
    final s = when.toUtc().toIso8601String();
    _check(await client.send(
      op: SmpOp.writeReq,
      group: group,
      id: idDatetime,
      payload: {'datetime': s},
    ));
  }

  /// Reboot the device. (The device typically drops the link right after ack.)
  Future<void> reset() async {
    _check(await client.send(
      op: SmpOp.writeReq,
      group: group,
      id: idReset,
    ));
  }
}
