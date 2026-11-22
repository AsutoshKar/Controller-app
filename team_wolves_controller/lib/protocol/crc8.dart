import 'dart:typed_data';

/// CRC-8 used by the Wolve Bot ESP32 receiver.
///
/// Polynomial `0x07`, initial value `0x00`, no reflection, no final XOR.
/// The check value is computed from the `TYPE` byte through the end of the
/// payload; the `SOF` byte and the CRC byte itself are excluded.
///
/// This is a pure Dart, dependency-free implementation so it can be unit
/// tested on the host VM without a device or plugin.
class Crc8 {
  Crc8._();

  /// CRC-8-ATM / "CRC-8" polynomial.
  static const int polynomial = 0x07;

  /// Initial register value.
  static const int initialValue = 0x00;

  static final Uint8List _table = _buildTable();

  static Uint8List _buildTable() {
    final Uint8List table = Uint8List(256);
    for (int byte = 0; byte < 256; byte++) {
      int crc = byte;
      for (int bit = 0; bit < 8; bit++) {
        if ((crc & 0x80) != 0) {
          crc = ((crc << 1) ^ polynomial) & 0xFF;
        } else {
          crc = (crc << 1) & 0xFF;
        }
      }
      table[byte] = crc;
    }
    return table;
  }

  /// Computes CRC-8 over [bytes] from [start] (inclusive) to `end`
  /// (exclusive, defaults to `bytes.length`).
  static int compute(List<int> bytes, [int start = 0, int? end]) {
    final int last = end ?? bytes.length;
    int crc = initialValue;
    for (int i = start; i < last; i++) {
      crc = _table[(crc ^ (bytes[i] & 0xFF)) & 0xFF];
    }
    return crc & 0xFF;
  }

  /// Verifies a complete frame of the shape
  /// `[SOF][TYPE][SEQ][LEN][PAYLOAD...][CRC]`.
  static bool verifyFrame(List<int> frame) {
    if (frame.length < 6) {
      return false;
    }
    final int expected = frame[frame.length - 1] & 0xFF;
    return compute(frame, 1, frame.length - 1) == expected;
  }
}
