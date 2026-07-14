// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'recording_models.dart';

/// One row in the recordings list.
class RecordingFileInfo {
  final File file;
  final int sizeBytes;
  final DateTime modified;

  /// Parsed header — null if the file was unreadable / corrupt.
  final RecordingMetadata? metadata;

  /// First parse error, if any.
  final String? error;

  const RecordingFileInfo({
    required this.file,
    required this.sizeBytes,
    required this.modified,
    this.metadata,
    this.error,
  });

  String get fileName => file.uri.pathSegments.last;
  bool get isValid => metadata != null;

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Approximate duration from `totalSamples / max sample rate`. Without a
  /// finalize-time rewrite of the header this is currently 0; we fall back
  /// to computing from file size and channel count.
  Duration get estimatedDuration {
    final m = metadata;
    if (m == null || m.channels.isEmpty) return Duration.zero;
    if (m.recordingDuration > Duration.zero) return m.recordingDuration;
    // Per-sample bytes inside a DATA block: 4 seq + 8 ts + 8 * channels.
    final perSample = 4 + 8 + 8 * m.channels.length;
    // Header + per-block overhead is small — close enough for browser display.
    final approxSamples = sizeBytes ~/ perSample;
    double rate = 1;
    for (final c in m.channels) {
      if (c.samplingRate > rate) rate = c.samplingRate;
    }
    if (rate <= 0) return Duration.zero;
    return Duration(milliseconds: (approxSamples * 1000 / rate).round());
  }

  String get durationFormatted {
    final d = estimatedDuration;
    if (d == Duration.zero) return '—';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}
