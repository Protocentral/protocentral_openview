import 'dart:typed_data';

/// One 2-D matrix frame.
class MatrixFrame {
  final int rows;
  final int cols;
  final Uint16List data; // row-major, length == rows * cols
  final int timestampUs;

  MatrixFrame({
    required this.rows,
    required this.cols,
    required this.data,
    required this.timestampUs,
  });

  int get pixelCount => rows * cols;
}

/// Ring buffer of recent matrix frames.
///
/// Only stores the latest [capacity] frames — older ones get overwritten.
/// The renderer reads `latest` every frame and doesn't iterate the history.
/// History exists so a future "frame stepper" can rewind a few seconds.
class MatrixBuffer {
  final int capacity;
  final List<MatrixFrame?> _ring;
  int _writeIndex = 0;
  int _totalWritten = 0;

  MatrixBuffer({this.capacity = 64}) : _ring = List.filled(capacity, null);

  int get totalWritten => _totalWritten;
  int get length =>
      _totalWritten < capacity ? _totalWritten : capacity;

  MatrixFrame? get latest {
    if (_totalWritten == 0) return null;
    final idx = (_writeIndex - 1 + capacity) % capacity;
    return _ring[idx];
  }

  /// [framesBack] = 0 → latest; 1 → previous; etc.
  MatrixFrame? frameAt({int framesBack = 0}) {
    if (_totalWritten == 0 || framesBack >= length) return null;
    final idx = (_writeIndex - 1 - framesBack + capacity * 2) % capacity;
    return _ring[idx];
  }

  void push(MatrixFrame frame) {
    _ring[_writeIndex] = frame;
    _writeIndex = (_writeIndex + 1) % capacity;
    _totalWritten++;
  }

  void clear() {
    for (var i = 0; i < _ring.length; i++) {
      _ring[i] = null;
    }
    _writeIndex = 0;
    _totalWritten = 0;
  }
}
