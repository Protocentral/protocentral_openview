import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../boards/board_descriptor.dart';
import '../boards/packet_spec.dart';
import '../data/channel_buffer.dart';
import '../data/matrix_buffer.dart';
import '../protocol/decoded_packet.dart';
import '../protocol/packet_framer_v3.dart';
import '../protocol/packet_router.dart';
import '../transport/ble_service.dart';
import '../transport/transport_service.dart';
import '../transport/usb_serial_service.dart';

/// One decoded event for the live console (hex dump or routed event).
class ConsoleEntry {
  final DateTime when;
  final String kind; // 'rx', 'tx', 'event', 'unknown', 'error'
  final String text;
  const ConsoleEntry(this.when, this.kind, this.text);
}

/// Orchestrates a single live connection: picks the transport, opens it,
/// streams bytes through the framer and router, and exposes a console log
/// plus rolling counters.
class ConnectionController extends ChangeNotifier {
  final UsbSerialService usb;
  final BleService ble;

  ConnectionController({required this.usb, required this.ble});

  TransportService? _active;
  BoardDescriptor? _descriptor;
  PacketFramer? _framer;
  PacketRouter? _router;
  StreamSubscription<dynamic>? _bytesSub;
  StreamSubscription<dynamic>? _eventsSub;

  TransportStatus _status = TransportStatus.idle;
  TransportStatus get status => _status;

  BoardDescriptor? get descriptor => _descriptor;
  TransportTarget? get target => _active?.connectedTarget;
  TransportKind? get transportKind => _active?.kind;

  int _packetsOk = 0;
  int _packetsUnknown = 0;
  int _framerErrors = 0;
  int _bytesIn = 0;
  DateTime? _connectedAt;

  int get packetsOk => _packetsOk;
  int get packetsUnknown => _packetsUnknown;
  int get framerErrors => _framerErrors;
  int get bytesIn => _bytesIn;
  Duration get connectedFor => _connectedAt == null
      ? Duration.zero
      : DateTime.now().difference(_connectedAt!);

  /// Most-recent events from the router (HR, SpO2, etc.).
  final Map<String, num> latestEvents = {};

  /// Per-channel sample-count tally (for the dashboard placeholder).
  final Map<String, int> channelSampleCounts = {};

  /// Per-channel ring buffers, allocated at connect time from the descriptor.
  /// Sized to hold ~10 seconds of samples at each channel's declared rate
  /// (clamped to a sensible min/max).
  final Map<String, ChannelBuffer> channelBuffers = {};

  /// Per-matrix ring buffers (one per `MatrixSpec` on the descriptor).
  final Map<String, MatrixBuffer> matrixBuffers = {};

  /// Per-matrix frame counter (mirrors `channelSampleCounts`).
  final Map<String, int> matrixFrameCounts = {};

  /// Recent console log (bounded — keep ~500 most recent).
  final List<ConsoleEntry> console = [];
  static const int _consoleMax = 500;

  /// Listeners that want every decoded packet, in arrival order.
  /// Used by the recorder. Not a Stream because the writer is sync-friendly.
  final List<void Function(DecodedPacket)> _packetListeners = [];

  void addPacketListener(void Function(DecodedPacket) cb) {
    _packetListeners.add(cb);
  }

  void removePacketListener(void Function(DecodedPacket) cb) {
    _packetListeners.remove(cb);
  }

  Future<void> connect({
    required TransportTarget target,
    required BoardDescriptor descriptor,
  }) async {
    await disconnect();
    _descriptor = descriptor;

    // Pick the right transport for the target kind.
    final TransportService transport = switch (target.kind) {
      TransportKind.usb => usb,
      TransportKind.ble => ble,
      TransportKind.wifi => throw UnimplementedError('Wi-Fi transport deferred'),
    };

    // Set USB baud rate from descriptor.
    if (transport is UsbSerialService && descriptor.usbProfile != null) {
      transport.setBaudRate(descriptor.usbProfile!.baudRate);
    }

    _resetCounters();
    // Allocate one ring buffer per declared channel, sized for ~10 s window.
    for (final c in descriptor.channels) {
      final cap = (c.sampleRateHz * 10).round().clamp(512, 32768);
      channelBuffers[c.id] = ChannelBuffer(cap);
    }
    // One matrix buffer per declared matrix. ~5 s of frames at the declared
    // frame rate, clamped to a sensible min/max.
    for (final m in descriptor.matrices) {
      final cap = (m.frameRateHz * 5).round().clamp(16, 256);
      matrixBuffers[m.id] = MatrixBuffer(capacity: cap);
    }
    final knownTypes = descriptor.packets.map((p) => p.pktType).toSet();
    _framer = PacketFramer(
      knownTypes: knownTypes,
      onPacket: _onFramedPacket,
      onError: (msg) {
        _framerErrors++;
        _log('error', msg);
        notifyListeners();
      },
    );
    _router = PacketRouter(
      descriptor: descriptor,
      onChannel: (id, samples) {
        channelSampleCounts.update(id, (v) => v + samples.length,
            ifAbsent: () => samples.length);
        channelBuffers[id]?.pushAll(samples);
      },
      onMatrix: (id, payload) {
        final buf = matrixBuffers[id];
        if (buf == null) return;
        // Convert the raw byte buffer into a typed Uint16List view sized to
        // rows*cols. The decoder already produced a fresh, isolated buffer.
        final byteView = payload.data.asByteData();
        final n = payload.rows * payload.cols;
        final pixels = Uint16List(n);
        for (int i = 0; i < n; i++) {
          pixels[i] = byteView.getUint16(i * 2, Endian.little);
        }
        buf.push(MatrixFrame(
          rows: payload.rows,
          cols: payload.cols,
          data: pixels,
          timestampUs: payload.timestampUs,
        ));
        matrixFrameCounts.update(id, (v) => v + 1, ifAbsent: () => 1);
      },
      onEvent: (key, value) {
        latestEvents[key] = value;
        _log('event', '$key=$value');
      },
      onUnknown: (pktType, len) {
        _packetsUnknown++;
        _log('unknown', 'pktType=$pktType len=$len');
      },
      onDecodedPacket: (pkt) {
        if (_packetListeners.isEmpty) return;
        // Iterate over a snapshot so listeners can deregister themselves.
        for (final cb in List.of(_packetListeners)) {
          try {
            cb(pkt);
          } catch (e) {
            _log('error', 'packet listener: $e');
          }
        }
      },
    );

    _bytesSub = transport.bytes.listen(_onBytes);
    _eventsSub = transport.events.listen((e) => _onTransportEvent(e));
    _active = transport;

    await transport.connect(target);
    _connectedAt = DateTime.now();
    _setStatus(transport.status);
  }

  Future<void> disconnect() async {
    await _bytesSub?.cancel();
    await _eventsSub?.cancel();
    _bytesSub = null;
    _eventsSub = null;
    try {
      await _active?.disconnect();
    } catch (_) {}
    _active = null;
    _descriptor = null;
    _framer = null;
    _router = null;
    _setStatus(TransportStatus.idle);
  }

  /// Send a [CommandSpec]'s byte sequence on the active transport.
  ///
  /// No-op if there's no active connection. Logs every send to the console
  /// (tx kind) so it's traceable. Whether the board actually accepts the
  /// command is up to the firmware — OpenView observes the resulting data
  /// stream and adapts (e.g. the heatmap auto-resizes on the first frame
  /// with new rows/cols).
  Future<void> sendCommand(CommandSpec cmd) async {
    final transport = _active;
    if (transport == null || _status != TransportStatus.connected) {
      _log('tx', 'cmd ${cmd.id} ignored: not connected');
      return;
    }
    try {
      await transport.send(Uint8List.fromList(cmd.bytes));
      _log('tx', '${cmd.id} (${cmd.label}) — '
          '${cmd.bytes.length} B');
    } catch (e) {
      _log('error', 'send ${cmd.id}: $e');
    }
  }

  void _onBytes(Uint8List chunk) {
    _bytesIn += chunk.length;
    _framer?.processChunk(chunk);
    notifyListeners();
  }

  void _onFramedPacket(FramedPacket pkt) {
    if (pkt.known) _packetsOk++;
    _router?.route(pkt);
  }

  void _onTransportEvent(TransportEvent e) {
    _setStatus(e.status, log: e.message);
  }

  void _setStatus(TransportStatus s, {String? log}) {
    _status = s;
    if (log != null) _log('status', '$s: $log');
    notifyListeners();
  }

  void _log(String kind, String text) {
    console.add(ConsoleEntry(DateTime.now(), kind, text));
    if (console.length > _consoleMax) {
      console.removeRange(0, console.length - _consoleMax);
    }
  }

  void _resetCounters() {
    _packetsOk = 0;
    _packetsUnknown = 0;
    _framerErrors = 0;
    _bytesIn = 0;
    _connectedAt = null;
    latestEvents.clear();
    channelSampleCounts.clear();
    channelBuffers.clear();
    matrixBuffers.clear();
    matrixFrameCounts.clear();
    console.clear();
  }

  void clearConsole() {
    console.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _bytesSub?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
