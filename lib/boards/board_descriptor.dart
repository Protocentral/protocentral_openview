import 'channel_spec.dart';
import 'matrix_spec.dart';
import 'packet_spec.dart';
import 'transport_profile.dart';

/// Self-contained declaration of a ProtoCentral board.
///
/// Adding a new board = one descriptor file + (optionally) decoder functions.
/// No edits required to UI, transport, or recording code.
class BoardDescriptor {
  final String id;
  final String displayName;
  final String manufacturer;
  final TransportSupport transports;
  final BleProfile? bleProfile;
  final UsbProfile? usbProfile;
  final List<ChannelSpec> channels;
  final List<MatrixSpec> matrices;
  final List<PacketSpec> packets;
  final List<CommandSpec> commands;
  final String notes;

  const BoardDescriptor({
    required this.id,
    required this.displayName,
    required this.manufacturer,
    required this.transports,
    this.bleProfile,
    this.usbProfile,
    this.channels = const [],
    this.matrices = const [],
    this.packets = const [],
    this.commands = const [],
    this.notes = '',
  });

  ChannelSpec? channel(String id) {
    for (final c in channels) {
      if (c.id == id) return c;
    }
    return null;
  }

  PacketSpec? packet(int pktType) {
    for (final p in packets) {
      if (p.pktType == pktType) return p;
    }
    return null;
  }
}
