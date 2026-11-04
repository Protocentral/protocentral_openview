// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

import '../../controllers/channel_controller.dart';
import '../../theme/app_spacing.dart';

/// Switches channels with a known mV scale between ECG paper and auto-fit.
class PaperScaleControls extends StatelessWidget {
  final ChannelController chart;
  const PaperScaleControls({super.key, required this.chart});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Paper'),
              icon: Icon(Icons.grid_on, size: 18),
            ),
            ButtonSegment(
              value: false,
              label: Text('Auto'),
              icon: Icon(Icons.fit_screen, size: 18),
            ),
          ],
          selected: {chart.paperMode},
          onSelectionChanged: (s) => chart.paperMode = s.first,
          showSelectedIcon: false,
        ),
        if (chart.paperMode) _GainMenu(chart: chart),
      ],
    );
  }
}

class _GainMenu extends StatelessWidget {
  final ChannelController chart;
  const _GainMenu({required this.chart});

  static String _label(double gain) =>
      '×${gain == gain.roundToDouble() ? gain.toInt() : gain}';

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (ctx, controller, _) => OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.height, size: 18),
        label: Text('Gain ${_label(chart.paperGain)}'),
      ),
      menuChildren: [
        for (final g in ChannelController.paperGains)
          MenuItemButton(
            onPressed: () => chart.paperGain = g,
            child: Text(_label(g)),
          ),
      ],
    );
  }
}
