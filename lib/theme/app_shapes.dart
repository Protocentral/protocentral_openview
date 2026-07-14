// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

/// ProtoCentral Design System v3 — shape tokens.
class AppShapes {
  AppShapes._();

  static const double radiusNone = 0;
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 28;
  static const double radiusFull = 9999;

  static final BorderRadius brXs = BorderRadius.circular(radiusXs);
  static final BorderRadius brSm = BorderRadius.circular(radiusSm);
  static final BorderRadius brMd = BorderRadius.circular(radiusMd);
  static final BorderRadius brLg = BorderRadius.circular(radiusLg);
  static final BorderRadius brXl = BorderRadius.circular(radiusXl);

  static final RoundedRectangleBorder cardShape =
      RoundedRectangleBorder(borderRadius: brMd);
  static final RoundedRectangleBorder buttonShape =
      RoundedRectangleBorder(borderRadius: brSm);
}
