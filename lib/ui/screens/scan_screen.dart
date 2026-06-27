import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../boards/board_descriptor.dart';
import '../../boards/board_registry.dart';
import '../../controllers/connection_controller.dart';
import '../../controllers/scan_controller.dart';
import '../../theme/app_spacing.dart';
import '../../transport/transport_service.dart';
import '../../transport/wifi_service.dart';
import '../../utils/platform_v3.dart';
import '../app_routes.dart';

/// Connect screen — pick a transport, then a device + board → go.
///
/// USB lists serial ports; BLE scans for ProtoCentral **Sensything** devices
/// (the only boards that speak BLE); Wi-Fi takes a manual host:port.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late TransportKind _transport;
  String? _selectedDeviceId;
  late BoardDescriptor _selectedBoard;
  bool _userOverrodeBoard = false;
  bool _connecting = false;
  String? _errorMsg;

  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '3000');

  @override
  void initState() {
    super.initState();
    // Default to the most likely transport for the platform.
    _transport = PlatformV3.canUseUsb ? TransportKind.usb : TransportKind.ble;
    _selectedBoard = _boardsFor(_transport).first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  /// Boards that support the given transport (BLE → Sensything family only).
  List<BoardDescriptor> _boardsFor(TransportKind kind) {
    final list = switch (kind) {
      TransportKind.usb => BoardRegistry.all.where((b) => b.transports.usb),
      TransportKind.ble => BoardRegistry.all.where((b) => b.transports.ble),
      TransportKind.wifi => BoardRegistry.all.where((b) => b.transports.wifi),
    }.toList();
    return list.isEmpty ? BoardRegistry.all : list;
  }

  List<ScanResult> _results(ScanController scan) =>
      _transport == TransportKind.ble ? scan.bleResults : scan.usbResults;

  Future<void> _refresh() async {
    if (!mounted || _transport == TransportKind.wifi) return;
    final scan = context.read<ScanController>();
    await scan.refresh(
      includeUsb: _transport == TransportKind.usb && PlatformV3.canUseUsb,
      includeBle: _transport == TransportKind.ble && PlatformV3.canUseBle,
    );
    if (!mounted) return;
    _reconcileSelection(scan);
  }

  void _reconcileSelection(ScanController scan) {
    final results = _results(scan);
    final ids = results.map((r) => r.target.id).toList();
    String? next = _selectedDeviceId;
    if (next == null || !ids.contains(next)) {
      next = ids.isEmpty ? null : ids.first;
    }
    setState(() {
      _selectedDeviceId = next;
      if (!_userOverrodeBoard) {
        _selectedBoard = _suggestForDevice(scan, next) ?? _selectedBoard;
      }
    });
  }

  BoardDescriptor? _suggestForDevice(ScanController scan, String? deviceId) {
    if (deviceId == null) return null;
    for (final r in _results(scan)) {
      if (r.target.id == deviceId) return r.suggestedDescriptor;
    }
    return null;
  }

  ScanResult? _selectedResult(ScanController scan) {
    if (_selectedDeviceId == null) return null;
    for (final r in _results(scan)) {
      if (r.target.id == _selectedDeviceId) return r;
    }
    return null;
  }

  void _onTransportChanged(TransportKind kind) {
    setState(() {
      _transport = kind;
      _selectedDeviceId = null;
      _userOverrodeBoard = false;
      final boards = _boardsFor(kind);
      if (!boards.contains(_selectedBoard)) _selectedBoard = boards.first;
      _errorMsg = null;
    });
    _refresh();
  }

  Future<void> _connect() async {
    final scan = context.read<ScanController>();
    TransportTarget? target;

    if (_transport == TransportKind.wifi) {
      final host = _hostCtrl.text.trim();
      final port = int.tryParse(_portCtrl.text.trim());
      if (host.isEmpty || port == null) {
        setState(() => _errorMsg = 'Enter a valid host and port.');
        return;
      }
      target = WifiService.targetFor(host: host, port: port);
    } else {
      target = _selectedResult(scan)?.target;
    }
    if (target == null) return;

    setState(() {
      _connecting = true;
      _errorMsg = null;
    });
    try {
      await context.read<ConnectionController>().connect(
            target: target,
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
              'Pick a transport, a device, and a board.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (connected)
              _ConnectedCard(conn: conn)
            else
              _ConnectForm(
                transport: _transport,
                scan: scan,
                results: _results(scan),
                boards: _boardsFor(_transport),
                selectedDeviceId: _selectedDeviceId,
                selectedBoard: _selectedBoard,
                hostCtrl: _hostCtrl,
                portCtrl: _portCtrl,
                connecting: _connecting,
                errorMsg: _errorMsg,
                onTransportChanged: _onTransportChanged,
                onRefresh: _refresh,
                onDeviceChanged: (id) {
                  setState(() {
                    _selectedDeviceId = id;
                    _userOverrodeBoard = false;
                    _selectedBoard =
                        _suggestForDevice(scan, id) ?? _selectedBoard;
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
  final TransportKind transport;
  final ScanController scan;
  final List<ScanResult> results;
  final List<BoardDescriptor> boards;
  final String? selectedDeviceId;
  final BoardDescriptor selectedBoard;
  final TextEditingController hostCtrl;
  final TextEditingController portCtrl;
  final bool connecting;
  final String? errorMsg;
  final void Function(TransportKind) onTransportChanged;
  final VoidCallback onRefresh;
  final void Function(String?) onDeviceChanged;
  final void Function(BoardDescriptor) onBoardChanged;
  final VoidCallback onConnect;

  const _ConnectForm({
    required this.transport,
    required this.scan,
    required this.results,
    required this.boards,
    required this.selectedDeviceId,
    required this.selectedBoard,
    required this.hostCtrl,
    required this.portCtrl,
    required this.connecting,
    required this.errorMsg,
    required this.onTransportChanged,
    required this.onRefresh,
    required this.onDeviceChanged,
    required this.onBoardChanged,
    required this.onConnect,
  });

  bool get _isWifi => transport == TransportKind.wifi;

  bool get _canConnect {
    if (connecting) return false;
    // Wi-Fi host/port are validated in onConnect (the field text isn't
    // observed here); device transports gate on a selection.
    return _isWifi ? true : selectedDeviceId != null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TransportSelector(
              selected: transport,
              onChanged: onTransportChanged,
            ),
            const SizedBox(height: AppSpacing.lg),

            // --- Device / address row -----------------------------------
            if (_isWifi)
              _WifiFields(hostCtrl: hostCtrl, portCtrl: portCtrl)
            else
              _DeviceRow(
                transport: transport,
                results: results,
                scanning: scan.scanning,
                selectedDeviceId: selectedDeviceId,
                onRefresh: onRefresh,
                onDeviceChanged: onDeviceChanged,
              ),
            const SizedBox(height: AppSpacing.md),

            // --- Board row ----------------------------------------------
            DropdownButtonFormField<BoardDescriptor>(
              initialValue: boards.contains(selectedBoard) ? selectedBoard : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Board',
                prefixIcon: Icon(Icons.developer_board),
              ),
              items: boards
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

            _Hints(
              transport: transport,
              results: results,
              scanning: scan.scanning,
              selectedDeviceId: selectedDeviceId,
              selectedBoard: selectedBoard,
              errorMsg: errorMsg,
              scanError: scan.lastError,
            ),
            const SizedBox(height: AppSpacing.lg),

            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _canConnect ? onConnect : null,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransportSelector extends StatelessWidget {
  final TransportKind selected;
  final void Function(TransportKind) onChanged;
  const _TransportSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final segments = <ButtonSegment<TransportKind>>[
      if (PlatformV3.canUseUsb)
        const ButtonSegment(
          value: TransportKind.usb,
          icon: Icon(Icons.usb),
          label: Text('USB'),
        ),
      if (PlatformV3.canUseBle)
        const ButtonSegment(
          value: TransportKind.ble,
          icon: Icon(Icons.bluetooth),
          label: Text('BLE'),
        ),
      const ButtonSegment(
        value: TransportKind.wifi,
        icon: Icon(Icons.wifi),
        label: Text('Wi-Fi'),
      ),
    ];
    // SegmentedButton needs the selection to be one of the segments.
    final values = segments.map((s) => s.value).toSet();
    final sel = values.contains(selected) ? selected : segments.first.value;

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<TransportKind>(
        segments: segments,
        selected: {sel},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final TransportKind transport;
  final List<ScanResult> results;
  final bool scanning;
  final String? selectedDeviceId;
  final VoidCallback onRefresh;
  final void Function(String?) onDeviceChanged;

  const _DeviceRow({
    required this.transport,
    required this.results,
    required this.scanning,
    required this.selectedDeviceId,
    required this.onRefresh,
    required this.onDeviceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isBle = transport == TransportKind.ble;
    final label = isBle ? 'Device' : 'Port';
    final icon = isBle ? Icons.bluetooth : Icons.usb;
    final empty = isBle ? 'No devices found' : 'No ports found';

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: selectedDeviceId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(icon),
            ),
            items: results.isEmpty
                ? [
                    DropdownMenuItem<String>(
                      value: null,
                      enabled: false,
                      child: Text(empty),
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
            onChanged: results.isEmpty ? null : onDeviceChanged,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filledTonal(
          tooltip: isBle ? 'Scan for devices' : 'Refresh ports',
          onPressed: scanning ? null : onRefresh,
          icon: scanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(isBle ? Icons.bluetooth_searching : Icons.refresh),
        ),
      ],
    );
  }
}

class _WifiFields extends StatelessWidget {
  final TextEditingController hostCtrl;
  final TextEditingController portCtrl;
  const _WifiFields({required this.hostCtrl, required this.portCtrl});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: hostCtrl,
            decoration: const InputDecoration(
              labelText: 'Host / IP',
              prefixIcon: Icon(Icons.lan),
              hintText: '192.168.1.50',
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 1,
          child: TextField(
            controller: portCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Port'),
          ),
        ),
      ],
    );
  }
}

class _Hints extends StatelessWidget {
  final TransportKind transport;
  final List<ScanResult> results;
  final bool scanning;
  final String? selectedDeviceId;
  final BoardDescriptor selectedBoard;
  final String? errorMsg;
  final String? scanError;

  const _Hints({
    required this.transport,
    required this.results,
    required this.scanning,
    required this.selectedDeviceId,
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
        text: 'Scan: $scanError',
      ));
    }

    if (transport == TransportKind.ble) {
      hints.add(_HintLine(
        icon: Icons.info_outline,
        color: theme.colorScheme.onSurfaceVariant,
        text: 'BLE is currently available only for ProtoCentral Sensything '
            'devices.',
      ));
      if (results.isEmpty && !scanning) {
        hints.add(_HintLine(
          icon: Icons.bluetooth_disabled,
          color: theme.colorScheme.onSurfaceVariant,
          text: 'No Sensything devices found. Power one on and tap scan.',
        ));
      }
    } else if (transport == TransportKind.wifi) {
      hints.add(_HintLine(
        icon: Icons.info_outline,
        color: theme.colorScheme.onSurfaceVariant,
        text: 'Wi-Fi is currently available only for ProtoCentral Sensything '
            'and HealthyPi devices. Enter the device\'s IP address and TCP '
            'port.',
      ));
    } else {
      // USB
      if (results.isEmpty && !scanning) {
        hints.add(_HintLine(
          icon: Icons.info_outline,
          color: theme.colorScheme.onSurfaceVariant,
          text: 'No USB devices found. Plug a board in and tap refresh.',
        ));
      } else if (selectedDeviceId != null) {
        final r = results.firstWhere(
          (x) => x.target.id == selectedDeviceId,
          orElse: () => results.first,
        );
        final suggested = r.suggestedDescriptor;
        if (suggested != null && suggested.id == selectedBoard.id) {
          hints.add(_HintLine(
            icon: Icons.auto_awesome,
            color: theme.colorScheme.secondary,
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
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
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
                    color: theme.colorScheme.secondary,
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
