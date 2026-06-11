import 'dart:typed_data';

/// Little-endian primitives used by board decoders.
class Codec {
  Codec._();

  static int readInt32LE(Uint8List buf, int offset) {
    final v = buf[offset] |
        (buf[offset + 1] << 8) |
        (buf[offset + 2] << 16) |
        (buf[offset + 3] << 24);
    return v.toSigned(32);
  }

  static int readUint32LE(Uint8List buf, int offset) {
    return (buf[offset] |
            (buf[offset + 1] << 8) |
            (buf[offset + 2] << 16) |
            (buf[offset + 3] << 24)) &
        0xFFFFFFFF;
  }

  static int readUint16LE(Uint8List buf, int offset) {
    return buf[offset] | (buf[offset + 1] << 8);
  }

  static int readInt16LE(Uint8List buf, int offset) {
    return readUint16LE(buf, offset).toSigned(16);
  }

  static int signExtend16(int v) => (v & 0xFFFF).toSigned(16);

}
