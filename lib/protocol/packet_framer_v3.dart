// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

/// ProtoCentral framing protocol — generic v3 framer.
///
/// Wire format:  [0x0A][0xFA][LEN_LSB][LEN_MSB][PKT_TYPE][...PAYLOAD...][0x0B]
///
/// Parameterized by an allow-list of packet types. Unknown packet types are
/// still surfaced (with `known = false`) so the Console screen can show them
/// as raw hex instead of silently dropping bytes.
class PacketFramer {
  static const int _sof1 = 0x0A;
  static const int _sof2 = 0xFA;
  static const int _eof = 0x0B;

  static const int _maxPayloadLen = 8192;
  static const Duration _timeout = Duration(milliseconds: 500);

  static const int _stateInit = 0;
  static const int _stateSof1 = 1;
  static const int _stateSof2 = 2;
  static const int _stateInPacket = 3;
  static const int _stateExpectEof = 4;

  int _state = _stateInit;
  int _pktLen = 0;
  int _pktType = 0;
  int _posCounter = 0;
  int _payloadIndex = 0;
  int _lastByteMs = 0;

  final Uint8List _payload = Uint8List(_maxPayloadLen);

  final Set<int> knownTypes;
  final void Function(FramedPacket packet) onPacket;
  final void Function(String message)? onError;

  final FramerStats stats = FramerStats();

  PacketFramer({
    required this.knownTypes,
    required this.onPacket,
    this.onError,
  });

  void reset() {
    _resetState();
    stats.reset();
  }

  void processChunk(Uint8List data) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final b in data) {
      _processByte(b, nowMs);
    }

    if (_state != _stateInit) {
      _lastByteMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  void processByte(int byte) {
    _processByte(byte, DateTime.now().millisecondsSinceEpoch);
  }

  void _emitPacket() {
    final known = knownTypes.contains(_pktType);

    stats.packetsReceived++;

    if (!known) {
      stats.unknownType++;
    }

    onPacket(
      FramedPacket(
        pktType: _pktType,
        payload: Uint8List.fromList(
          _payload.sublist(0, _payloadIndex),
        ),
        known: known,
      ),
    );
  }

  void _processByte(int rxch, int nowMs) {
    if (_state != _stateInit) {
      if (_lastByteMs > 0 &&
          (nowMs - _lastByteMs) > _timeout.inMilliseconds) {
        stats.droppedTimeout++;
        onError?.call('Packet timeout (${nowMs - _lastByteMs}ms)');
        _resetState();
      }

      _lastByteMs = nowMs;
    }

    switch (_state) {
      case _stateInit:
        if (rxch == _sof1) {
          _state = _stateSof1;
          _lastByteMs = nowMs;
        }
        return;

      case _stateSof1:
        if (rxch == _sof2) {
          _state = _stateSof2;
        } else {
          _state = _stateInit;
        }
        return;

      case _stateSof2:
        _pktLen = rxch;
        _posCounter = 1;
        _state = _stateInPacket;
        return;

      case _stateInPacket:
        _posCounter++;

        if (_posCounter == 2) {
          _pktLen = (rxch << 8) | _pktLen;

          if (_pktLen > _maxPayloadLen || _pktLen <= 0) {
            stats.droppedOversize++;
            onError?.call('Packet length $_pktLen out of range');
            _resetState();
            return;
          }

          _payloadIndex = 0;
        } else if (_posCounter == 3) {
          _pktType = rxch;
        } else if (_posCounter < 3 + _pktLen + 1) {
          if (_payloadIndex < _payload.length) {
            _payload[_payloadIndex++] = rxch;
          }
        } else {
          // Firmware appears to send:
          // PAYLOAD -> 0x00 -> 0x0B

          if (rxch == 0x00) {
            _state = _stateExpectEof;
            return;
          }

          if (rxch == _eof) {
            _emitPacket();
          } else {
            stats.droppedNoEof++;
            onError?.call(
              'Expected EOF 0x0B, got 0x${rxch.toRadixString(16)}',
            );
          }

          _resetState();
        }
        return;

      case _stateExpectEof:
        if (rxch == _eof) {
          _emitPacket();
        } else {
          stats.droppedNoEof++;
          onError?.call(
            'Expected 0x0B after 0x00, got 0x${rxch.toRadixString(16)}',
          );
        }

        _resetState();
        return;
    }
  }

  void _resetState() {
    _state = _stateInit;
    _pktLen = 0;
    _pktType = 0;
    _posCounter = 0;
    _payloadIndex = 0;
    _lastByteMs = 0;
  }
}

class FramedPacket {
  final int pktType;
  final Uint8List payload;
  final bool known;
  const FramedPacket({
    required this.pktType,
    required this.payload,
    required this.known,
  });
}

class FramerStats {
  int packetsReceived = 0;
  int droppedNoEof = 0;
  int droppedOversize = 0;
  int droppedTimeout = 0;
  int unknownType = 0;

  void reset() {
    packetsReceived = 0;
    droppedNoEof = 0;
    droppedOversize = 0;
    droppedTimeout = 0;
    unknownType = 0;
  }

  @override
  String toString() =>
      'FramerStats(ok=$packetsReceived, unknown=$unknownType, '
          'noEof=$droppedNoEof, oversize=$droppedOversize, timeout=$droppedTimeout)';
}
