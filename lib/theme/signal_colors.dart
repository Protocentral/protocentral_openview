// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

/// Plot-specific colors that don't belong in the M3 palette.
/// Accessed via `Theme.of(context).extension<SignalColors>()`.
@immutable
class SignalColors extends ThemeExtension<SignalColors> {
  final Color ecg;
  final Color ppg;
  final Color ppgRed;
  final Color ppgIr;
  final Color bioz;
  final Color resp;
  final Color temp;
  final Color eeg;
  final Color gsr;
  final Color imuX;
  final Color imuY;
  final Color imuZ;
  final Color qualityGood;
  final Color qualityWarn;
  final Color qualityBad;
  final Color gridLine;
  final Color axisLabel;
  final Color cursor;

  const SignalColors({
    required this.ecg,
    required this.ppg,
    required this.ppgRed,
    required this.ppgIr,
    required this.bioz,
    required this.resp,
    required this.temp,
    required this.eeg,
    required this.gsr,
    required this.imuX,
    required this.imuY,
    required this.imuZ,
    required this.qualityGood,
    required this.qualityWarn,
    required this.qualityBad,
    required this.gridLine,
    required this.axisLabel,
    required this.cursor,
  });

  static const SignalColors dark = SignalColors(
    ecg: Color(0xFFF59E0B),
    ppg: Color(0xFF34D399),
    ppgRed: Color(0xFFF87171),
    ppgIr: Color(0xFFFBBF24),
    bioz: Color(0xFF6FB3CC),
    resp: Color(0xFFA78BFA),
    temp: Color(0xFFFB923C),
    eeg: Color(0xFF34D399),
    gsr: Color(0xFFF472B6),
    imuX: Color(0xFF60A5FA),
    imuY: Color(0xFF34D399),
    imuZ: Color(0xFFF472B6),
    qualityGood: Color(0xFF4ADE80),
    qualityWarn: Color(0xFFFB923C),
    qualityBad: Color(0xFFF87171),
    gridLine: Color(0xFF3A444A),
    axisLabel: Color(0xFF8C9498),
    cursor: Color(0xFFFBBF24),
  );

  static const SignalColors light = SignalColors(
    ecg: Color(0xFFB45309),
    ppg: Color(0xFF047857),
    ppgRed: Color(0xFFDC2626),
    ppgIr: Color(0xFF92400E),
    bioz: Color(0xFF2C6E84),
    resp: Color(0xFF5B21B6),
    temp: Color(0xFFC2410C),
    eeg: Color(0xFF047857),
    gsr: Color(0xFF9D174D),
    imuX: Color(0xFF1D4ED8),
    imuY: Color(0xFF047857),
    imuZ: Color(0xFF9D174D),
    qualityGood: Color(0xFF16A34A),
    qualityWarn: Color(0xFFEA580C),
    qualityBad: Color(0xFFDC2626),
    gridLine: Color(0xFFE7EAEC),
    axisLabel: Color(0xFF5A6266),
    cursor: Color(0xFFB45309),
  );

  @override
  SignalColors copyWith({
    Color? ecg,
    Color? ppg,
    Color? ppgRed,
    Color? ppgIr,
    Color? bioz,
    Color? resp,
    Color? temp,
    Color? eeg,
    Color? gsr,
    Color? imuX,
    Color? imuY,
    Color? imuZ,
    Color? qualityGood,
    Color? qualityWarn,
    Color? qualityBad,
    Color? gridLine,
    Color? axisLabel,
    Color? cursor,
  }) {
    return SignalColors(
      ecg: ecg ?? this.ecg,
      ppg: ppg ?? this.ppg,
      ppgRed: ppgRed ?? this.ppgRed,
      ppgIr: ppgIr ?? this.ppgIr,
      bioz: bioz ?? this.bioz,
      resp: resp ?? this.resp,
      temp: temp ?? this.temp,
      eeg: eeg ?? this.eeg,
      gsr: gsr ?? this.gsr,
      imuX: imuX ?? this.imuX,
      imuY: imuY ?? this.imuY,
      imuZ: imuZ ?? this.imuZ,
      qualityGood: qualityGood ?? this.qualityGood,
      qualityWarn: qualityWarn ?? this.qualityWarn,
      qualityBad: qualityBad ?? this.qualityBad,
      gridLine: gridLine ?? this.gridLine,
      axisLabel: axisLabel ?? this.axisLabel,
      cursor: cursor ?? this.cursor,
    );
  }

  @override
  SignalColors lerp(ThemeExtension<SignalColors>? other, double t) {
    if (other is! SignalColors) return this;
    return SignalColors(
      ecg: Color.lerp(ecg, other.ecg, t)!,
      ppg: Color.lerp(ppg, other.ppg, t)!,
      ppgRed: Color.lerp(ppgRed, other.ppgRed, t)!,
      ppgIr: Color.lerp(ppgIr, other.ppgIr, t)!,
      bioz: Color.lerp(bioz, other.bioz, t)!,
      resp: Color.lerp(resp, other.resp, t)!,
      temp: Color.lerp(temp, other.temp, t)!,
      eeg: Color.lerp(eeg, other.eeg, t)!,
      gsr: Color.lerp(gsr, other.gsr, t)!,
      imuX: Color.lerp(imuX, other.imuX, t)!,
      imuY: Color.lerp(imuY, other.imuY, t)!,
      imuZ: Color.lerp(imuZ, other.imuZ, t)!,
      qualityGood: Color.lerp(qualityGood, other.qualityGood, t)!,
      qualityWarn: Color.lerp(qualityWarn, other.qualityWarn, t)!,
      qualityBad: Color.lerp(qualityBad, other.qualityBad, t)!,
      gridLine: Color.lerp(gridLine, other.gridLine, t)!,
      axisLabel: Color.lerp(axisLabel, other.axisLabel, t)!,
      cursor: Color.lerp(cursor, other.cursor, t)!,
    );
  }
}
