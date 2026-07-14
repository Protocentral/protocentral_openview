// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

/// Models for `.hpd` recordings — kept binary-compatible with HealthyPi
/// Studio's `BIOSIG` v1 format so files round-trip between the two apps.
///
/// Lifted (with light trim) from healthypi_studio/lib/models/recording_models.dart.

enum RecordingState { idle, recording, paused, stopped, error }

class RecordingStatus {
  final RecordingState state;
  final Duration elapsedTime;
  final int samplesRecorded;
  final int fileSizeBytes;
  final String? errorMessage;
  final DateTime timestamp;

  RecordingStatus({
    required this.state,
    required this.elapsedTime,
    required this.samplesRecorded,
    required this.fileSizeBytes,
    this.errorMessage,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'RecordingStatus($state, $elapsedTime, samples=$samplesRecorded)';
}

class ChannelInfo {
  final String id;
  final String name;
  final String unit;
  final double samplingRate;
  final double gainFactor;
  final double offset;
  final double minValue;
  final double maxValue;

  const ChannelInfo({
    required this.id,
    required this.name,
    required this.unit,
    required this.samplingRate,
    this.gainFactor = 1.0,
    this.offset = 0.0,
    this.minValue = -1000,
    this.maxValue = 1000,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'unit': unit,
        'samplingRate': samplingRate,
        'gainFactor': gainFactor,
        'offset': offset,
        'minValue': minValue,
        'maxValue': maxValue,
      };

  factory ChannelInfo.fromJson(Map<String, dynamic> json) => ChannelInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        unit: json['unit'] as String,
        samplingRate: (json['samplingRate'] as num).toDouble(),
        gainFactor: (json['gainFactor'] as num?)?.toDouble() ?? 1.0,
        offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
        minValue: (json['minValue'] as num?)?.toDouble() ?? -1000,
        maxValue: (json['maxValue'] as num?)?.toDouble() ?? 1000,
      );
}

class SubjectMetadata {
  final String? subjectId;
  final int? age;
  final String? gender;
  final String? condition;
  final String? notes;

  const SubjectMetadata({
    this.subjectId,
    this.age,
    this.gender,
    this.condition,
    this.notes,
  });
}

class SessionMetadata {
  final String protocolName;
  final String? location;
  final String? operator;
  final String? notes;
  final Map<String, String> customTags;
  final DateTime startTime;

  SessionMetadata({
    required this.protocolName,
    this.location,
    this.operator,
    this.notes,
    this.customTags = const {},
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();
}

class MultiChannelSample {
  final int sequenceNumber;
  final int timestampMicros;
  final Map<String, double> values;

  const MultiChannelSample({
    required this.sequenceNumber,
    required this.timestampMicros,
    required this.values,
  });
}

class EventMarker {
  final int sequenceNumber;
  final int timestampMicros;
  final String type;
  final String description;
  final DateTime recordedAt;

  EventMarker({
    required this.sequenceNumber,
    required this.timestampMicros,
    required this.type,
    required this.description,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();
}

class RecordingMetadata {
  static const int formatVersion = 1;
  static const String fileSignature = 'BIOSIG';

  final String fileFormatVersion;
  final String deviceId;
  final String deviceName;
  final String firmwareVersion;
  final DateTime createdAt;
  final List<ChannelInfo> channels;
  final SubjectMetadata? subjectMetadata;
  final SessionMetadata? sessionMetadata;
  final Duration recordingDuration;
  final int totalSamples;

  RecordingMetadata({
    this.fileFormatVersion = '1.0',
    required this.deviceId,
    this.deviceName = 'ProtoCentral',
    this.firmwareVersion = '1.0.0',
    DateTime? createdAt,
    required this.channels,
    this.subjectMetadata,
    this.sessionMetadata,
    this.recordingDuration = Duration.zero,
    this.totalSamples = 0,
  }) : createdAt = createdAt ?? DateTime.now();
}

class RecordingException implements Exception {
  final String message;
  RecordingException(this.message);
  @override
  String toString() => 'RecordingException: $message';
}
