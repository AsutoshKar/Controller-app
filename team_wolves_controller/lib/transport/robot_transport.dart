import 'dart:typed_data';

/// Which radio path a transport uses.
enum TransportKind { udp, ble }

/// Coarse connection state reported to the controller and the UI.
enum TransportStatus { idle, connecting, connected, disconnected, error }

String transportStatusLabel(TransportStatus status) {
  switch (status) {
    case TransportStatus.idle:
      return 'IDLE';
    case TransportStatus.connecting:
      return 'CONNECTING';
    case TransportStatus.connected:
      return 'CONNECTED';
    case TransportStatus.disconnected:
      return 'DISCONNECTED';
    case TransportStatus.error:
      return 'ERROR';
  }
}

/// Callbacks a transport uses to hand inbound data and state back to its owner.
///
/// Exactly one listener is bound at a time. A transport must not retain a
/// listener after [RobotTransport.bind] is called again or after
/// [RobotTransport.dispose]; the controller relies on that to stop stale
/// callbacks from mutating a newer session.
abstract class TransportListener {
  /// A complete frame was received and passed framing checks.
  void onFrameReceived(Uint8List frame);

  /// Connection state changed. [detail] is human-readable and may be shown
  /// in the connection dialog.
  void onTransportStatus(TransportStatus status, String detail);

  /// Running counters, reported after every send or receive.
  void onTransportCounters(int txPackets, int rxPackets, int txBytes, int rxBytes);
}

/// A null object used to detach a transport without disposing it.
class _NullTransportListener implements TransportListener {
  const _NullTransportListener();

  @override
  void onFrameReceived(Uint8List frame) {}

  @override
  void onTransportStatus(TransportStatus status, String detail) {}

  @override
  void onTransportCounters(int txPackets, int rxPackets, int txBytes, int rxBytes) {}
}

/// Common contract for the Wi-Fi UDP and BLE fallback links.
///
/// Implementations own their sockets / BLE subscriptions and must:
///   * never queue an unbounded number of writes,
///   * drop or coalesce obsolete DRIVE frames in favour of control frames,
///   * stop all inbound callbacks after [disconnect] or [dispose].
abstract class RobotTransport {
  const RobotTransport();

  TransportKind get kind;

  TransportStatus get status;

  /// True once the transport is ready to carry a frame (socket bound, or BLE
  /// characteristics discovered). This is *not* proof of a live robot link;
  /// only valid telemetry proves that.
  bool get isReady;

  /// Short description for the connection dialog, e.g. `UDP 192.168.4.1:4210`.
  String get describe;

  void bind(TransportListener listener);

  /// Opens the link. Completes when the local resource is ready, or throws.
  Future<void> connect();

  /// Closes the link and releases platform resources where possible.
  Future<void> disconnect();

  /// Sends one frame. Must not throw for a normal transient failure; it
  /// should surface errors through [TransportListener.onTransportStatus].
  Future<void> send(Uint8List frame);

  /// Releases every subscription, timer and in-flight connection attempt.
  Future<void> dispose();

  /// Detaches the current listener without touching platform resources.
  void detach() {
    bind(const _NullTransportListener());
  }
}
