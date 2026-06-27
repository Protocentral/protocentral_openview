import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../recording/biosignal_file_reader.dart';
import '../recording/recording_file_info.dart';
import 'settings_controller.dart';

/// Owns the recordings directory listing + per-file header probe.
///
/// Cheap by default: lists the directory and parses each header. The full
/// sample iteration is left to consumers (replay, export) — we don't want
/// the browser to block on giant files.
class RecordingsBrowserController extends ChangeNotifier {
  final SettingsController settings;
  RecordingsBrowserController({required this.settings});

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  List<RecordingFileInfo> _recordings = const [];
  List<RecordingFileInfo> get recordings => _recordings;

  Directory? _dir;
  Directory? get directory => _dir;

  int get totalSize =>
      _recordings.fold<int>(0, (a, r) => a + r.sizeBytes);

  /// Resolve the recordings directory (creates it if missing) and scan.
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final dir = await settings.recordingsDirectory();
      _dir = dir;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final files = await dir
          .list(followLinks: false)
          .where((e) => e is File && e.path.toLowerCase().endsWith('.hpd'))
          .cast<File>()
          .toList();
      final infos = <RecordingFileInfo>[];
      for (final f in files) {
        infos.add(await _probe(f));
      }
      infos.sort((a, b) => b.modified.compareTo(a.modified));
      _recordings = infos;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<RecordingFileInfo> _probe(File file) async {
    final stat = await file.stat();
    BiosignalFileReader? reader;
    try {
      reader = BiosignalFileReader(file);
      await reader.open();
      final meta = await reader.readHeader();
      return RecordingFileInfo(
        file: file,
        sizeBytes: stat.size,
        modified: stat.modified,
        metadata: meta,
      );
    } catch (e) {
      return RecordingFileInfo(
        file: file,
        sizeBytes: stat.size,
        modified: stat.modified,
        metadata: null,
        error: e.toString(),
      );
    } finally {
      try {
        await reader?.close();
      } catch (_) {}
    }
  }

  Future<void> delete(RecordingFileInfo info) async {
    try {
      await info.file.delete();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return;
    }
    _recordings = _recordings.where((r) => r.file.path != info.file.path).toList();
    notifyListeners();
  }

  /// Reveal a file in Finder / Explorer / file manager. Best-effort —
  /// silently no-ops on platforms we don't have a recipe for.
  Future<void> revealInFinder(RecordingFileInfo info) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', info.file.path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', info.file.path]);
    } else if (Platform.isLinux) {
      // Best-effort: open the enclosing directory.
      await Process.run('xdg-open', [p.dirname(info.file.path)]);
    }
  }

  /// Reveal the (effective) recordings directory in the OS file manager.
  Future<void> revealDirectory() async {
    final dir = _dir ?? await settings.recordingsDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer.exe', [dir.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [dir.path]);
    }
  }
}
