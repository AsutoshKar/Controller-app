import 'dart:typed_data';

import 'crc8.dart';

/// Frame types exchanged with the ESP32 receiver.
///
/// These values are part of the on-air contract with `sketch_nov22a` and must
/// not be changed without a matching firmware change.
class FrameType {
  FrameType._();

  /// App -> robot: periodic drive command, 5-byte payload.
  static const int drive = 0x01;

  /// App -> robot: firmware mode selection (M1/M2/M3), 1-byte payload.
  static const int setMode = 0x02;

  /// App -> robot: arm / disarm request, 1-byte payload.
  static const int arm = 0x05;

  /// App -> robot: emergency stop request. LEN 0 in the prior prototype.
  /// [FILL: verify length in `sketch_nov22a`].
  static const int eStop = 0x06;

  /// App -> robot: link keepalive. LEN 0 in the prior prototype.
  /// Never a substitute for DRIVE. [FILL: verify length in `sketch_nov22a`].
  static const int heartbeat = 0x07;

  /// Robot -> app: telemetry, 6-byte payload.
  static const int telemetry = 0x81;
}

/// DRIVE payload flag bits.
class DriveFlags {
  DriveFlags._();

  static const int armed = 0x01;
  static const int eStop = 0x02;
}

/// Robot state codes reported in telemetry byte 0.
class RobotState {
  RobotState._();

  static const int boot = 0;
  static const int disarmed = 1;
  static const int armed = 2;
  static const int failsafe = 3;
  static const int estop = 4;

  static String label(int state) {
    switch (state) {
      case boot:
        return 'BOOT';
      case disarmed:
        return 'DISARMED';
      case armed:
        return 'ARMED';
      case failsafe:
        return 'FAILSAFE';
      case estop:
        return 'ESTOP';
      default:
        return 'UNKNOWN($state)';
    }
  }
}

/// A decoded, CRC-valid telemetry frame.
class TelemetryFrame {
  const TelemetryFrame({
    required this.sequence,
    required this.state,
    required this.leftPercent,
    required this.rightPercent,
    required this.mode,
    required this.dropped,
  });

  /// Echo of the `SEQ` byte of the DRIVE frame this telemetry answers.
  final int sequence;

  /// One of [RobotState].
  final int state;

  /// Left motor output, -128..127 (%), as reported by the firmware.
  final int leftPercent;

  /// Right motor output, -128..127 (%), as reported by the firmware.
  final int rightPercent;

  /// Confirmed firmware mode, expected 1..3.
  final int mode;

  /// Cumulative dropped-frame counter reported by the firmware.
  final int dropped;
}

/// Builds and parses Wolve Bot binary frames.
///
/// Frame layout: `[0xA5][TYPE][SEQ][LEN][PAYLOAD...][CRC8]`
///
/// Everything here is pure Dart and side-effect free. No sockets, no
/// platform channels, so the wire format is unit-testable on the host.
class Protocol {
  Protocol._();

  static const int sof = 0xA5;

  /// Maximum payload bytes currently defined by any frame type.
  static const int maxPayloadLength = 6;

  /// Unsigned 8-bit sequence counter bound.
  static const int sequenceMask = 0xFF;

  /// Signed axis limits, in thousandths of full command.
  static const int minAxis = -1000;
  static const int maxAxis = 1000;

  static int _nextSequence = 0;

  /// Returns the next unsigned 8-bit sequence value, wrapping 255 -> 0.
  static int nextSequence() {
    final int value = _nextSequence;
    _nextSequence = (_nextSequence + 1) & sequenceMask;
    return value;
  }

  /// Resets the module-level sequence counter. Intended for tests.
  static void resetSequenceForTest([int value = 0]) {
    _nextSequence = value & sequenceMask;
  }

  /// Encodes a complete frame.
  static Uint8List encode({
    required int type,
    required int sequence,
    List<int> payload = const <int>[],
  }) {
    if (type < 0 || type > 0xFF) {
      throw ArgumentError.value(type, 'type', 'must be an unsigned byte');
    }
    if (sequence < 0 || sequence > 0xFF) {
      throw ArgumentError.value(sequence, 'sequence', 'must be an unsigned byte');
    }
    if (payload.length > 0xFF) {
      throw ArgumentError.value(payload.length, 'payload', 'too long for LEN byte');
    }
    final Uint8List frame = Uint8List(5 + payload.length);
    frame[0] = sof;
    frame[1] = type & 0xFF;
    frame[2] = sequence & 0xFF;
    frame[3] = payload.length & 0xFF;
    for (int i = 0; i < payload.length; i++) {
      frame[4 + i] = payload[i] & 0xFF;
    }
    frame[frame.length - 1] = Crc8.compute(frame, 1, frame.length - 1);
    return frame;
  }

  /// `0x01` DRIVE: flags + throttle + steering, both signed 16-bit LE.
  static Uint8List drive({
    required int sequence,
    required bool armed,
    required bool eStop,
    required int throttle,
    required int steering,
  }) {
    final int flags = (armed ? DriveFlags.armed : 0) | (eStop ? DriveFlags.eStop : 0);
    final int t = clampAxis(throttle);
    final int s = clampAxis(steering);
    return encode(
      type: FrameType.drive,
      sequence: sequence,
      payload: <int>[
        flags,
        t & 0xFF,
        (t >> 8) & 0xFF,
        s & 0xFF,
        (s >> 8) & 0xFF,
      ],
    );
  }

  /// `0x02` SET_MODE: mode id 1..3.
  static Uint8List setMode({required int sequence, required int mode}) {
    if (mode < 1 || mode > 3) {
      throw ArgumentError.value(mode, 'mode', 'must be 1..3');
    }
    return encode(type: FrameType.setMode, sequence: sequence, payload: <int>[mode]);
  }

  /// `0x05` ARM: 1 to arm, 0 to disarm.
  static Uint8List arm({required int sequence, required bool arm}) {
    return encode(type: FrameType.arm, sequence: sequence, payload: <int>[arm ? 1 : 0]);
  }

  /// `0x06` E_STOP. Prior prototype used LEN 0; the payload is left empty
  /// until the real sketch length is confirmed.
  static Uint8List eStop({required int sequence}) {
    return encode(type: FrameType.eStop, sequence: sequence);
  }

  /// `0x07` HEARTBEAT. Prior prototype used LEN 0.
  static Uint8List heartbeat({required int sequence}) {
    return encode(type: FrameType.heartbeat, sequence: sequence);
  }

  /// Validates and decodes a `0x81` telemetry frame.
  ///
  /// Returns `null` for any malformed frame: bad SOF, wrong type, wrong
  /// length, or CRC mismatch. Callers must treat `null` as "no data", never
  /// as a reason to consider the link live.
  static TelemetryFrame? parseTelemetry(Uint8List frame) {
    if (frame.length < 5) {
      return null;
    }
    if (frame[0] != sof) {
      return null;
    }
    if (frame[1] != FrameType.telemetry) {
      return null;
    }
    final int length = frame[3] & 0xFF;
    if (length != 6) {
      return null;
    }
    if (frame.length != 5 + length) {
      return null;
    }
    final int expectedCrc = frame[frame.length - 1] & 0xFF;
    if (Crc8.compute(frame, 1, frame.length - 1) != expectedCrc) {
      return null;
    }
    final int dropped = (frame[8] & 0xFF) | ((frame[9] & 0xFF) << 8);
    return TelemetryFrame(
      sequence: frame[2] & 0xFF,
      state: frame[4] & 0xFF,
      leftPercent: _toInt8(frame[5]),
      rightPercent: _toInt8(frame[6]),
      mode: frame[7] & 0xFF,
      dropped: dropped,
    );
  }

  static int _toInt8(int byte) {
    final int value = byte & 0xFF;
    return value < 0x80 ? value : value - 0x100;
  }

  static int clampAxis(int value) {
    if (value < minAxis) {
      return minAxis;
    }
    if (value > maxAxis) {
      return maxAxis;
    }
    return value;
  }
}

/// Utility for decoding little-endian signed 16-bit fields in tests.
int readInt16LE(List<int> bytes, int offset) {
  final int raw = (bytes[offset] & 0xFF) | ((bytes[offset + 1] & 0xFF) << 8);
  return raw < 0x8000 ? raw : raw - 0x10000;
}
