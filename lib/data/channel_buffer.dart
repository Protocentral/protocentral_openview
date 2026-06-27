import 'dart:typed_data';

/// Fixed-capacity ring buffer of doubles, per channel.
///
/// Tracks total samples written so consumers can detect new data without
/// listening to a stream.
class ChannelBuffer {
  final Float64List _data;
  int _writeIndex = 0;
  int _totalWritten = 0;

  ChannelBuffer(int capacity) : _data = Float64List(capacity);

  int get capacity => _data.length;
  int get totalWritten => _totalWritten;
  int get length =>
      _totalWritten < _data.length ? _totalWritten : _data.length;

  void push(double sample) {
    _data[_writeIndex] = sample;
    _writeIndex = (_writeIndex + 1) % _data.length;
    _totalWritten++;
  }

  void pushAll(List<double> samples) {
    for (final s in samples) {
      push(s);
    }
  }

  /// Copy the most-recent [n] samples (in chronological order) into [out].
  /// If fewer than [n] samples have been written, the leading slots are filled
  /// with NaN. Returns the actual number of valid samples written.
  int copyLatest(Float64List out, int n) =>
      copyWindow(out, n, endingAt: _totalWritten);

  /// Copy [n] samples ending at sample-index [endingAt] (chronological order)
  /// into [out]. Used by scrub: pass [endingAt] = anchored capture point so
  /// the view stays still while time advances.
  ///
  /// If the requested range is older than what the ring still holds, the
  /// portion that fell out of the window is filled with NaN.
  int copyWindow(Float64List out, int n, {required int endingAt}) {
    final cap = _data.length;
    // Inclusive upper bound: samples in [endingAt - n, endingAt).
    final upper = endingAt;
    final lower = upper - n;
    final oldestHeld = _totalWritten - length; // samples below this fell out

    int writtenValid = 0;
    for (int i = 0; i < n; i++) {
      final globalIdx = lower + i;
      if (globalIdx < oldestHeld || globalIdx >= _totalWritten) {
        out[i] = double.nan;
        continue;
      }
      // Map global sample index → ring slot.
      // _writeIndex points at the slot AFTER the newest sample.
      final offsetFromNewest = _totalWritten - 1 - globalIdx;
      int slot = _writeIndex - 1 - offsetFromNewest;
      slot = ((slot % cap) + cap) % cap;
      out[i] = _data[slot];
      writtenValid++;
    }
    return writtenValid;
  }

  /// Copy the raw ring contents in physical order (slot 0 .. capacity-1)
  /// into [out]. Used by sweep-mode rendering where the X-axis maps directly
  /// to ring slots and the write pointer is shown as a sweep cursor.
  /// Returns [_writeIndex] — the position of the sweep head (next write slot).
  int copyRaw(Float64List out) {
    final n = out.length < _data.length ? out.length : _data.length;
    for (int i = 0; i < n; i++) {
      out[i] = _data[i];
    }
    return _writeIndex;
  }

  void clear() {
    for (int i = 0; i < _data.length; i++) {
      _data[i] = 0;
    }
    _writeIndex = 0;
    _totalWritten = 0;
  }
}
