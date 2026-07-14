// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';
import 'package:provider/provider.dart';

import '../../../controllers/smp_controller.dart';
import '../../../mcumgr/hpi_hs.dart';
import '../../../models/hs_record.dart';
import '../../../models/hs_sample.dart';
import '../../../models/hs_summary.dart';
import '../../../models/hs_type.dart';
import '../../../theme/app_spacing.dart';

part 'scan_reconnect_view.dart';
part 'connected_view.dart';
part 'device_info_panel.dart';
part 'firmware_panel.dart';
part 'files_panel.dart';
part 'health_store_panel.dart';
part 'console_panel.dart';
part 'shared_widgets.dart';

/// SMP / MCUmgr **Device Manager** — top-level destination for managing any
/// SMP-enabled BLE device (own connection, separate from the streaming Connect
/// flow). OS / Image / FS groups for any MCUmgr device; Health Store when the
/// ProtoCentral HPI_HS vendor group answers HELLO. Full firmware install
/// (upload → test → reset → confirm) is advanced / WIP.
class DeviceManagerScreen extends StatelessWidget {
  const DeviceManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smp = context.watch<SmpController>();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('Device Manager', style: theme.textTheme.headlineMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Manage any SMP / MCUmgr device over BLE — Device Info, Files, '
            'and (advanced) firmware update. Scan, connect, start with an '
            'echo to confirm the link.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: smp.reconnecting
                ? _ReconnectingView(smp: smp)
                : smp.isConnected
                    ? _ConnectedView(smp: smp)
                    : _ScanView(smp: smp),
          ),
        ],
      ),
    );
  }
}
