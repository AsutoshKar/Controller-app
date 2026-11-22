import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:team_wolves_controller/protocol/crc8.dart';
import 'package:team_wolves_controller/protocol/protocol.dart';

void main() {
  group('Protocol frame encoding', () {
    test('DRIVE is 10 bytes with the documented layout', () {
      final Uint8List frame = Protocol.drive(
        sequence: 7,
        armed: true,
        eStop: false,
        throttle: -1000,
        steering: 1000,
      );

      expect(frame.length, 10);
      expect(frame[0], 0xA5);
      expect(frame[1], FrameType.drive);
      expect(frame[2], 7);
      expect(frame[3], 5);
      expect(frame[4], 0x01);
      expect(readInt16LE(frame, 5), -1000);
      expect(readInt16LE(frame, 7), 1000);
      expect(frame[9], Crc8.compute(frame, 1, 9));
    });

    test('E-STOP flag sets bit 0x02 in the DRIVE flags byte', () {
      final Uint8List frame = Protocol.drive(
        sequence: 1,
        armed: true,
        eStop: true,
        throttle: 0,
        steering: 0,
      );
      expect(frame[4], 0x03);
    });

    test('SET_MODE is 6 bytes and carries the mode id', () {
      final Uint8List frame = Protocol.setMode(sequence: 2, mode: 3);
      expect(frame.length, 6);
      expect(frame[1], FrameType.setMode);
      expect(frame[3], 1);
      expect(frame[4], 3);
    });

    test('ARM carries 1 to arm and 0 to disarm', () {
      expect(Protocol.arm(sequence: 0, arm: true)[4], 1);
      expect(Protocol.arm(sequence: 0, arm: false)[4], 0);
    });

    test('E_STOP and HEARTBEAT use LEN 0', () {
      final Uint8List stop = Protocol.eStop(sequence: 3);
      expect(stop.length, 6);
      expect(stop[1], FrameType.eStop);
      expect(stop[3], 0);

      final Uint8List beat = Protocol.heartbeat(sequence: 3);
      expect(beat.length, 6);
      expect(beat[1], FrameType.heartbeat);
      expect(beat[3], 0);
    });

    test('axes are clamped to -1000..1000', () {
      final Uint8List frame = Protocol.drive(
        sequence: 0,
        armed: false,
        eStop: false,
        throttle: 99999,
        steering: -99999,
      );
      expect(readInt16LE(frame, 5), 1000);
      expect(readInt16LE(frame, 7), -1000);
    });

    test('signed little-endian fields round-trip both directions', () {
      for (final int value in <int>[-1000, -1, 0, 1, 999, 1000]) {
        final Uint8List frame = Protocol.drive(
          sequence: 0,
          armed: false,
          eStop: false,
          throttle: value,
          steering: -value,
        );
        expect(readInt16LE(frame, 5), value);
        expect(readInt16LE(frame, 7), -value);
      }
    });
  });

  group('Protocol sequence', () {
    test('wraps 255 -> 0', () {
      Protocol.resetSequenceForTest(255);
      expect(Protocol.nextSequence(), 255);
      expect(Protocol.nextSequence(), 0);
    });

    test('resets for tests', () {
      Protocol.resetSequenceForTest(0);
      expect(Protocol.nextSequence(), 0);
      expect(Protocol.nextSequence(), 1);
    });
  });

  group('Protocol telemetry parsing', () {
    Uint8List build({
      int sequence = 42,
      int state = 2,
      int left = 0x9C,
      int right = 0x64,
      int mode = 2,
      int droppedLo = 0x34,
      int droppedHi = 0x12,
    }) {
      return Protocol.encode(
        type: FrameType.telemetry,
        sequence: sequence,
        payload: <int>[state, left, right, mode, droppedLo, droppedHi],
      );
    }

    test('decodes a valid 11-byte telemetry frame', () {
      final TelemetryFrame? t = Protocol.parseTelemetry(build());
      expect(t, isNotNull);
      expect(t!.sequence, 42);
      expect(t.state, RobotState.armed);
      expect(t.leftPercent, -100); // 0x9C as int8
      expect(t.rightPercent, 100);
      expect(t.mode, 2);
      expect(t.dropped, 0x1234);
    });

    test('total frame length is 11 bytes for LEN 6', () {
      expect(build().length, 11);
    });

    test('rejects a bad start-of-frame byte', () {
      final Uint8List frame = build();
      frame[0] = 0x5A;
      expect(Protocol.parseTelemetry(frame), isNull);
    });

    test('rejects a CRC mismatch', () {
      final Uint8List frame = build();
      frame[frame.length - 1] ^= 0xFF;
      expect(Protocol.parseTelemetry(frame), isNull);
    });

    test('rejects a truncated frame', () {
      final Uint8List frame = build();
      expect(Protocol.parseTelemetry(frame.sublist(0, frame.length - 1)), isNull);
    });

    test('rejects a wrong LEN field', () {
      final Uint8List frame = Protocol.encode(
        type: FrameType.telemetry,
        sequence: 1,
        payload: <int>[1, 2, 3, 4, 5],
      );
      expect(Protocol.parseTelemetry(frame), isNull);
    });

    test('rejects a frame of the wrong type', () {
      final Uint8List frame = Protocol.setMode(sequence: 1, mode: 2);
      expect(Protocol.parseTelemetry(frame), isNull);
    });

    test('rejects an empty buffer', () {
      expect(Protocol.parseTelemetry(Uint8List(0)), isNull);
    });

    test('state labels are human readable', () {
      expect(RobotState.label(RobotState.boot), 'BOOT');
      expect(RobotState.label(RobotState.disarmed), 'DISARMED');
      expect(RobotState.label(RobotState.armed), 'ARMED');
      expect(RobotState.label(RobotState.failsafe), 'FAILSAFE');
      expect(RobotState.label(RobotState.estop), 'ESTOP');
      expect(RobotState.label(99), 'UNKNOWN(99)');
    });
  });
}
