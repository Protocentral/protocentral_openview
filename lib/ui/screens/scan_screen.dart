import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../boards/board_descriptor.dart';
import '../../boards/board_registry.dart';
import '../../controllers/connection_controller.dart';
import '../../controllers/scan_controller.dart';
import '../../theme/app_spacing.dart';
import '../../transport/transport_service.dart';
import '../../utils/platform_v3.dart';
import '../app_routes.dart';

/// Connect screen — single compact form: pick port + pick board → go.
///
/// Replaces the older multi-card "scan" UI. The route path stays /scan so
/// existing deep links keep working; only the visible label changes.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  String? _selectedPortId;
  BoardDescriptor _selectedBoard = BoardRegistry.all.first;
  bool _userOverrodeBoard = false;
  bool _connecting = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final scan = context.read<ScanController>();
    await scan.refresh(
      includeUsb: PlatformV3.canUseUsb,
      includeBle: false, // phase 1.b
    );
    if (!mounted) return;
    _reconcileSelection(scan);
  }

  /// After a refresh, keep the prior selection if it's still present,
  /// otherwise fall back to the first available port and refresh the
  /// auto-suggested board.
  void _reconcileSelection(ScanController scan) {
    final ids = scan.usbResults.map((r) => r.target.id).toList();
    String? next = _selectedPortId;
    if (next == null || !ids.contains(next)) {
      next = ids.isEmpty ? null : ids.first;
    }
    setState(() {
      _selectedPortId = next;
      if (!_userOverrodeBoard) {
        _selectedBoard = _suggestForPort(scan, next) ?? _selectedBoard;
      }
    });
  }

  BoardDescriptor? _suggestForPort(ScanController scan, String? portId) {
    if (portId == null) return null;
    final hit = scan.usbResults
        .where((r) => r.target.id == portId)
        .cast<ScanResult?>()
        .firstWhere((_) => true, orElse: () => null);
    return hit?.suggestedDescriptor;
  }

  ScanResult? _selectedResult(ScanController scan) {
    if (_selectedPortId == null) return null;
    for (final r in scan.usbResults) {
      if (r.target.id == _selectedPortId) return r;
    }
    return null;
  }

  Future<void> _connect() async {
    final scan = context.read<ScanController>();
    final result = _selectedResult(scan);
    if (result == null) return;
    setState(() {
      _connecting = true;
      _errorMsg = null;
    });
    try {
      await context.read<ConnectionController>().connect(
            target: result.target,
            descriptor: _selectedBoard,
          );
      if (mounted) context.go(AppRoutes.live);
    } catch (e) {
      if (mounted) setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scan = context.watch<ScanController>();
    final conn = context.watch<ConnectionController>();
    final connected = conn.status == TransportStatus.connected;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connect', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pick a port and a board.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (connected)
              _ConnectedCard(conn: conn)
            else
              _ConnectForm(
                scan: scan,
                selectedPortId: _selectedPortId,
                selectedBoard: _selectedBoard,
                connecting: _connecting,
                errorMsg: _errorMsg,
                onRefresh: _refresh,
                onPortChanged: (id) {
                  setState(() {
                    _selectedPortId = id;
                    _userOverrodeBoard = false;
                    _selectedBoard =
                        _suggestForPort(scan, id) ?? _selectedBoard;
                  });
                },
                onBoardChanged: (b) {
                  setState(() {
                    _selectedBoard = b;
                    _userOverrodeBoard = true;
                  });
                },
                onConnect: _connect,
              ),
          ],
        ),
      ),
    );
  }
}

class _ConnectForm extends StatelessWidget {
  final ScanController scan;
  final String? selectedPortId;
  final BoardDescriptor selectedBoard;
  final bool connecting;
  final String? errorMsg;
  final VoidCallback onRefresh;
  final void Function(String?) onPortChanged;
  final void Function(BoardDescriptor) onBoardChanged;
  final VoidCallback onConnect;

  const _ConnectForm({
    required this.scan,
    required this.selectedPortId,
    required this.selectedBoard,
    required this.connecting,
    required this.errorMsg,
    required this.onRefresh,
    required this.onPortChanged,
    required this.onBoardChanged,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final hasUsb = PlatformV3.canUseUsb;
    final results = scan.usbResults;
    final canConnect = selectedPortId != null && !connecting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Port row -------------------------------------------------
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedPortId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      prefixIcon: Icon(Icons.usb),
                    ),
                    items: results.isEmpty
                        ? const [
                            DropdownMenuItem<String>(
                              value: null,
                              enabled: false,
                              child: Text('No ports found'),
                            ),
                          ]
                        : results
                            .map((r) => DropdownMenuItem(
                                  value: r.target.id,
                                  child: Text(
                                    r.target.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                    onChanged: results.isEmpty ? null : onPortChanged,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filledTonal(
                  tooltip: 'Refresh ports',
                  onPressed: scan.scanning ? null : onRefresh,
                  icon: scan.scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // --- Board row ------------------------------------------------
            DropdownButtonFormField<BoardDescriptor>(
              initialValue: selectedBoard,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Board',
                prefixIcon: Icon(Icons.developer_board),
              ),
              items: BoardRegistry.all
                  .map((b) => DropdownMenuItem(
                        value: b,
                        child: Text(b.displayName),
                      ))
                  .toList(),
              onChanged: (b) {
                if (b != null) onBoardChanged(b);
              },
            ),
            const SizedBox(height: AppSpacing.sm),

            // --- Hints / detection / errors ------------------------------
            _Hints(
              hasUsb: hasUsb,
              results: results,
              scanning: scan.scanning,
              selectedPortId: selectedPortId,
              selectedBoard: selectedBoard,
              errorMsg: errorMsg,
              scanError: scan.lastError,
            ),
            const SizedBox(height: AppSpacing.lg),

            // --- Connect button ------------------------------------------
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: canConnect ? onConnect : null,
                icon: connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(connecting ? 'Connecting…' : 'Connect'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hints extends StatelessWidget {
  final bool hasUsb;
  final List<ScanResult> results;
  final bool scanning;
  final String? selectedPortId;
  final BoardDescriptor selectedBoard;
  final String? errorMsg;
  final String? scanError;

  const _Hints({
    required this.hasUsb,
    required this.results,
    required this.scanning,
    required this.selectedPortId,
    required this.selectedBoard,
    required this.errorMsg,
    required this.scanError,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hints = <Widget>[];

    if (errorMsg != null) {
      hints.add(_HintLine(
        icon: Icons.error_outline,
        color: theme.colorScheme.error,
        text: errorMsg!,
      ));
    } else if (scanError != null) {
      hints.add(_HintLine(
        icon: Icons.warning_amber,
        color: theme.colorScheme.error,
        text: 'Port scan: $scanError',
      ));
    }

    if (!hasUsb) {
      hints.add(_HintLine(
        icon: Icons.phone_iphone,
        color: theme.colorScheme.onSurfaceVariant,
        text: 'Mobile build — USB unavailable. BLE arrives in phase 1.b.',
      ));
    } else if (results.isEmpty && !scanning) {
      hints.add(_HintLine(
        icon: Icons.info_outline,
        color: theme.colorScheme.onSurfaceVariant,
        text: 'No USB devices found. Plug a board in and tap refresh.',
      ));
    } else if (selectedPortId != null) {
      final r = results.firstWhere(
        (x) => x.target.id == selectedPortId,
        orElse: () => results.first,
      );
      final suggested = r.suggestedDescriptor;
      if (suggested != null && suggested.id == selectedBoard.id) {
        hints.add(_HintLine(
          icon: Icons.auto_awesome,
          color: theme.colorScheme.tertiary,
          text: 'Auto-detected: ${suggested.displayName}',
        ));
      } else if (suggested != null) {
        hints.add(_HintLine(
          icon: Icons.info_outline,
          color: theme.colorScheme.onSurfaceVariant,
          text: 'Detected ${suggested.displayName}, but you picked '
              '${selectedBoard.displayName}.',
        ));
      }
      if (r.target.subtitle != null && r.target.subtitle!.isNotEmpty) {
        hints.add(_HintLine(
          icon: Icons.memory,
          color: theme.colorScheme.onSurfaceVariant,
          text: r.target.subtitle!,
        ));
      }
    }

    if (hints.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < hints.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          hints[i],
        ],
      ],
    );
  }
}

class _HintLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _HintLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _ConnectedCard extends StatelessWidget {
  final ConnectionController conn;
  const _ConnectedCard({required this.conn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${conn.descriptor?.displayName ?? "Connected"} '
                    '· ${conn.transportKind?.name.toUpperCase() ?? ""}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              conn.target?.displayName ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _Stat(label: 'Packets', value: '${conn.packetsOk}'),
                _Stat(label: 'Unknown', value: '${conn.packetsUnknown}'),
                _Stat(label: 'Errors', value: '${conn.framerErrors}'),
                _Stat(
                  label: 'Uptime',
                  value: '${conn.connectedFor.inSeconds}s',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => context.go(AppRoutes.live),
                  icon: const Icon(Icons.show_chart),
                  label: const Text('Open live view'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: conn.disconnect,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
