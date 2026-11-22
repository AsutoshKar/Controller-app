import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'robot_transport.dart';

/// Wi-Fi SoftAP/UDP transport — the primary, lowest-latency path.
///
/// The phone joins the robot's access point in the OS Wi-Fi settings. The app
/// then binds an *ephemeral* local IPv4 port and pushes DRIVE frames to
/// `192.168.4.1:4210`; telemetry replies arrive on the same socket.
///
/// Design notes:
///   * A bound socket is not a live robot link. Liveness comes only from
///     CRC-valid telemetry decoded by the controller.
///   * The socket is bound to the Wi-Fi interface address when one can be
///     found, so Android does not route the frames out of cellular data when
///     the AP has no internet.
///   * [send] never blocks and never buffers more than one datagram.
class UdpTransport extends RobotTransport {
  UdpTransport({this.robotAddress = defaultRobotAddress, this.robotPort = defaultRobotPort});

  static const String defaultRobotAddress = '192.168.4.1';
  static const int defaultRobotPort = 4210;

  /// Robot SoftAP address.
  final String robotAddress;

  /// Robot UDP port.
  final int robotPort;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  TransportListener _listener = const _Detached();
  TransportStatus _status = TransportStatus.idle;
  String _detail = 'NOT CONNECTED';
  String _localAddress = '';
  int _localPort = 0;
  int _txPackets = 0;
  int _rxPackets = 0;
  int _txBytes = 0;
  int _rxBytes = 0;
  int _epoch = 0;
  bool _disposed = false;

  @override
  TransportKind get kind => TransportKind.udp;

  @override
  TransportStatus get status => _status;

  @override
  bool get isReady => _socket != null && _status == TransportStatus.connected;

  @override
  String get describe => 'UDP $robotAddress:$robotPort';

  /// Local address the socket is bound to, for the diagnostics panel.
  String get localAddress => _localAddress;

  /// Local ephemeral port the socket is bound to.
  int get localPort => _localPort;

  @override
  void bind(TransportListener listener) {
    _listener = listener;
  }

  @override
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('UDP transport disposed');
    }
    final int epoch = ++_epoch;
    await _closeSocket();
    _status = TransportStatus.connecting;
    _detail = 'BINDING UDP SOCKET...';
    _emitStatus();

    final InternetAddress bindAddress = await _pickBindAddress();
    if (epoch != _epoch) {
      return;
    }
    try {
      final RawDatagramSocket socket =
          await RawDatagramSocket.bind(bindAddress, 0, reuseAddress: true, reusePort: false);
      if (epoch != _epoch || _disposed) {
        socket.close();
        return;
      }
      _socket = socket;
      _localAddress = bindAddress.address;
      _localPort = socket.port;
      _txPackets = 0;
      _rxPackets = 0;
      _txBytes = 0;
      _rxBytes = 0;
      _status = TransportStatus.connected;
      _detail = 'UDP SOCKET BOUND - AWAITING TELEMETRY';
      _socketSubscription = socket.listen(
        _onSocketEvent,
        onError: (Object error) {
          _status = TransportStatus.error;
          _detail = 'UDP SOCKET ERROR: $error';
          _emitStatus();
        },
        onDone: () {
          _status = TransportStatus.disconnected;
          _detail = 'UDP SOCKET CLOSED';
          _emitStatus();
        },
      );
      _emitStatus();
    } on SocketException catch (error) {
      _status = TransportStatus.error;
      _detail = 'UDP BIND FAILED: ${error.message}';
      _emitStatus();
      rethrow;
    }
  }

  /// Chooses the local IPv4 address to bind.
  ///
  /// Preference order: an address on the robot AP subnet (192.168.4.x), then
  /// any private 192.168.x / 10.x Wi-Fi style address, then loopback, then
  /// any interface. Binding to the Wi-Fi address keeps the datagram off the
  /// cellular interface when the AP has no internet.
  Future<InternetAddress> _pickBindAddress() async {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    InternetAddress? apAddress;
    InternetAddress? privateAddress;
    for (final NetworkInterface nic in interfaces) {
      for (final InternetAddress address in nic.addresses) {
        if (address.type != InternetAddressType.IPv4) {
          continue;
        }
        final String text = address.address;
        if (text.startsWith('192.168.4.')) {
          apAddress ??= address;
        } else if (text.startsWith('192.168.') ||
            text.startsWith('10.') ||
            text.startsWith('172.')) {
          privateAddress ??= address;
        }
      }
    }
    final InternetAddress chosen = apAddress ?? privateAddress ?? InternetAddress.anyIPv4;
    return chosen;
  }

  void _onSocketEvent(RawSocketEvent event) {
    final RawDatagramSocket? socket = _socket;
    if (socket == null) {
      return;
    }
    // Read events are level-triggered: drain every datagram that is already
    // buffered, because a single event can cover several packets at 100 Hz.
    if (event == RawSocketEvent.read) {
      while (true) {
        final Datagram? datagram = socket.receive();
        if (datagram == null) {
          break;
        }
        final Uint8List payload = Uint8List.fromList(datagram.data);
        if (payload.isEmpty) {
          continue;
        }
        _rxPackets++;
        _rxBytes += payload.length;
        _listener.onFrameReceived(payload);
      }
      _emitCounters();
    }
  }

  @override
  Future<void> disconnect() async {
    final int epoch = ++_epoch;
    await _closeSocket();
    if (epoch != _epoch) {
      return;
    }
    _status = TransportStatus.disconnected;
    _detail = 'DISCONNECTED';
    _emitStatus();
  }

  Future<void> _closeSocket() async {
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    _socket?.close();
    _socket = null;
    _localAddress = '';
    _localPort = 0;
  }

  @override
  Future<void> send(Uint8List frame) async {
    final RawDatagramSocket? socket = _socket;
    if (socket == null) {
      return;
    }
    try {
      final InternetAddress target = InternetAddress(robotAddress);
      final int sent = socket.send(frame, target, robotPort);
      if (sent > 0) {
        _txPackets++;
        _txBytes += sent;
        _emitCounters();
      }
    } on SocketException catch (error) {
      _status = TransportStatus.error;
      _detail = 'UDP SEND FAILED: ${error.message}';
      _emitStatus();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    ++_epoch;
    await _closeSocket();
    _listener = const _Detached();
  }

  void _emitStatus() {
    _listener.onTransportStatus(_status, _detail);
  }

  void _emitCounters() {
    _listener.onTransportCounters(_txPackets, _rxPackets, _txBytes, _rxBytes);
  }
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
