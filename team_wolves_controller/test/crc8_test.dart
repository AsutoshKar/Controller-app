import 'package:flutter_test/flutter_test.dart';
import 'package:team_wolves_controller/protocol/crc8.dart';

void main() {
  group('Crc8', () {
    test('matches the published CRC-8 check value', () {
      // CRC-8 (poly 0x07, init 0x00, no reflection) over "123456789" is 0xF4.
      expect(Crc8.compute('123456789'.codeUnits), 0xF4);
    });

    test('empty input yields the initial value', () {
      expect(Crc8.compute(<int>[]), 0x00);
    });

    test('a single zero byte yields zero', () {
      expect(Crc8.compute(<int>[0x00]), 0x00);
    });

    test('verifyFrame accepts a good frame and rejects a corrupt one', () {
      final List<int> frame = <int>[0xA5, 0x01, 0x07, 0x05, 0x01, 0x00, 0x00, 0x00, 0x00];
      frame.add(Crc8.compute(frame, 1, frame.length));
      expect(Crc8.verifyFrame(frame), isTrue);

      final List<int> corrupt = List<int>.from(frame);
      corrupt[corrupt.length - 1] ^= 0xFF;
      expect(Crc8.verifyFrame(corrupt), isFalse);
    });

    test('is order sensitive over the covered range', () {
      final List<int> a = <int>[0x01, 0x02, 0x03];
      final List<int> b = <int>[0x03, 0x02, 0x01];
      expect(Crc8.compute(a), isNot(Crc8.compute(b)));
    });
  });
}
