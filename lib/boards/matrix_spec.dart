/// Describes a 2-D matrix stream (e.g., a 48x48 depth-map).
class MatrixSpec {
  final String id;
  final String label;
  final int rows;
  final int cols;
  final double frameRateHz;
  final MatrixDataType dtype;
  final MatrixSemantics semantics;
  final String colorMap;
  final double minValue;
  final double maxValue;

  const MatrixSpec({
    required this.id,
    required this.label,
    required this.rows,
    required this.cols,
    required this.frameRateHz,
    required this.dtype,
    required this.semantics,
    this.colorMap = 'viridis',
    this.minValue = 0,
    this.maxValue = 255,
  });

  int get cellCount => rows * cols;
  int get bytesPerFrame => cellCount * dtype.byteSize;
}

enum MatrixDataType {
  uint8(1),
  uint16(2),
  int16(2),
  float32(4);

  final int byteSize;
  const MatrixDataType(this.byteSize);
}

enum MatrixSemantics { depth, pressure, temperature, capacitance, generic }
