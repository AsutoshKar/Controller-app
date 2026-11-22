import 'dart:typed_data';

import 'package:team_wolves_controller/protocol/protocol.dart';
import 'package:team_wolves_controller/transport/robot_transport.dart';

/// In-memory transport used by controller tests.
///
/// It never touches a socket or a Bluetooth adapter, and it records every
/// frame so a test can assert on exactly what would have gone on the air.
class FakeTransport extends RobotTransport {
  FakeTransport({this.kind = TransportKind.udp});

  @override
  final TransportKind kind;

  final List<Uint8List> sent = <Uint8List>[];
  bool ready = false;
  bool failConnect = false;
  int connectCalls = 0;
  int disposeCalls = 0;

  TransportListener _listener = const _Detached();

  @override
  TransportStatus get status =>
      ready ? TransportStatus.connected : TransportStatus.idle;

  @override
  bool get isReady => ready;

  @override
  String get describe => 'FAKE ${kind.name}';

  @override
  void bind(TransportListener listener) {
    _listener = listener;
  }

  @override
  Future<void> connect() async {
    connectCalls++;
    if (failConnect) {
      throw StateError('connect failed');
    }
    ready = true;
    _listener.onTransportStatus(TransportStatus.connected, 'FAKE CONNECTED');
  }

  @override
  Future<void> disconnect() async {
    ready = false;
  }

  @override
  Future<void> send(Uint8List frame) async {
    sent.add(Uint8List.fromList(frame));
    _listener.onTransportCounters(sent.length, 0, frame.length, 0);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    ready = false;
  }

  /// Delivers a frame as if it came off the radio.
  void emit(Uint8List frame) => _listener.onFrameReceived(frame);

  /// Delivers a link state change as if the radio reported it.
  void emitStatus(TransportStatus status, String detail) =>
      _listener.onTransportStatus(status, detail);

  List<Uint8List> ofType(int type) =>
      sent.where((Uint8List frame) => frame[1] == type).toList();
}

class _Detached implements TransportListener {
  const _Detached();

  @override
  void onFrameReceived(Uint8List frame) {}

  @override
  void onTransportStatus(TransportStatus status, String detail) {}

  @override
  void onTransportCounters(int txPackets, int rxPackets, int txBytes, int rxBytes) {}
}

/// Builds a CRC-valid telemetry frame for tests.
Uint8List telemetryFrame({
  int sequence = 0,
  int state = RobotState.disarmed,
  int left = 0,
  int right = 0,
  int mode = 2,
  int dropped = 0,
}) {
  return Protocol.encode(
    type: FrameType.telemetry,
    sequence: sequence,
    payload: <int>[
      state,
      left & 0xFF,
      right & 0xFF,
      mode,
      dropped & 0xFF,
      (dropped >> 8) & 0xFF,
    ],
  );
}
