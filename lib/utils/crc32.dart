/// Standard IEEE 802.3 / zlib CRC-32 (reflected, init `0xFFFFFFFF`, final XOR
/// `0xFFFFFFFF`, polynomial `0xEDB88320`). Matches Zephyr's `crc32_ieee`, which
/// is what the HPI_HS RECORDS header `crc32` field is computed with.
class Crc32 {
  Crc32._();

  static final List<int> _table = _buildTable();

  static List<int> _buildTable() {
    final t = List<int>.filled(256, 0);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      t[n] = c & 0xFFFFFFFF;
    }
    return t;
  }

  /// Compute the CRC-32 of [bytes]. [seed] lets you continue a running CRC over
  /// multiple chunks (pass the previous result).
  static int compute(List<int> bytes, [int seed = 0]) {
    int crc = (seed ^ 0xFFFFFFFF) & 0xFFFFFFFF;
    for (final b in bytes) {
      crc = _table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
