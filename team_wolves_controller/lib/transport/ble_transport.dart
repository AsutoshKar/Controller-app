import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocol/protocol.dart';
import 'robot_transport.dart';

/// One advertising BLE device, reduced to the fields the UI needs.
///
/// The UI never touches `flutter_blue_plus` types; it only sees this class and
/// hands the `deviceId` back to the controller.
class BleScanHit {
  const BleScanHit({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.hasControlService,
  });

  final String deviceId;
  final String name;
  final int rssi;
  final bool hasControlService;
}

/// Bluetooth LE fallback transport.
///
/// BLE is *manual only*: the driver switches to it from the connection dialog.
/// Nothing here auto-connects or auto-fails-over.
///
/// Write discipline, because the ESP32 BLE link is slow and write-without-
/// response has no per-packet confirmation:
///   * at most one BLE write is in flight at a time ([_writing]),
///   * DRIVE frames are coalesced into a single slot ([_pendingDrive]) so an
///     obsolete command can never pile up behind newer ones,
///   * E-STOP and ARM=0 jump the queue,
///   * the control queue is capped, and the oldest non-critical frame is
///     dropped rather than letting memory grow.
class BleTransport extends RobotTransport {
  BleTransport();

  static const String controlServiceUuid = '0000abcd-0000-1000-8000-00805f9b34fb';
  static const String controlCharacteristicUuid = '0000ab01-0000-1000-8000-00805f9b34fb';
  static const String telemetryCharacteristicUuid = '0000ab03-0000-1000-8000-00805f9b34fb';
  static const int _maxQueuedControlFrames = 8;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _controlCharacteristic;
  BluetoothCharacteristic? _telemetryCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  TransportListener _listener = const _Detached();
  TransportStatus _status = TransportStatus.idle;
  String _detail = 'NOT CONNECTED';
  bool _ready = false;
  bool _disposed = false;
  int _epoch = 0;

  bool _writing = false;
  final List<Uint8List> _queue = <Uint8List>[];
  Uint8List? _pendingDrive;

  int _txPackets = 0;
  int _rxPackets = 0;
  int _txBytes = 0;
  int _rxBytes = 0;

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  TransportStatus get status => _status;

  @override
  bool get isReady => _ready;

  @override
  String get describe {
    final BluetoothDevice? device = _device;
    final String name = (device?.platformName ?? '').isNotEmpty
        ? device!.platformName
        : 'ROBORACE_ESP32';
    return 'BLE $name';
  }

  @override
  void bind(TransportListener listener) {
    _listener = listener;
  }

  /// Live scan results, mapped to [BleScanHit].
  Stream<List<BleScanHit>> get scanResults {
    return FlutterBluePlus.scanResults.map(_mapScanResults);
  }

  static List<BleScanHit> _mapScanResults(List<ScanResult> results) {
    final List<BleScanHit> hits = <BleScanHit>[];
    for (final ScanResult result in results) {
      final String name = result.device.platformName;
      final bool hasService = result.advertisementData.serviceUuids
          .any((Guid uuid) => uuid.str.toLowerCase() == controlServiceUuid);
      final bool namedLikeRobot = name.toUpperCase().contains('ROBO');
      // Only show peripherals that either advertise the control service or
      // carry the expected name, so the operator is not scrolling through a
      // room full of watches and earbuds.
      if (!hasService && !namedLikeRobot) {
        continue;
      }
      hits.add(BleScanHit(
        deviceId: result.device.remoteId.str,
        name: name.isEmpty ? '(unnamed)' : name,
        rssi: result.rssi,
        hasControlService: hasService,
      ));
    }
    hits.sort((BleScanHit a, BleScanHit b) => b.rssi.compareTo(a.rssi));
    return hits;
  }

  /// Whether the platform reports a usable Bluetooth adapter right now.
  Future<bool> isAdapterReady() async {
    try {
      final bool supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        return false;
      }
      final BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  /// Starts a scan. The caller listens on [scanResults].
  Future<void> startScan({Duration timeout = const Duration(seconds: 6)}) async {
    if (_disposed) {
      return;
    }
    await stopScan();
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await FlutterBluePlus.stopScan();
  }

  /// Keeps a subscription alive for a dialog; cancelled by [stopScan].
  void keepScanSubscription(StreamSubscription<List<ScanResult>> subscription) {
    _scanSubscription = subscription;
  }

  /// Selects a device by the id surfaced in [BleScanHit] and opens the link.
  ///
  /// Replaces any previously selected device. The caller is responsible for
  /// closing the old transport first (the controller does this).
  Future<void> connectToDevice(String deviceId) async {
    await disconnect();
    _device = BluetoothDevice.fromId(deviceId);
    await connect();
  }

  /// Connects to a device previously surfaced by [scanResults].
  @override
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('BLE transport disposed');
    }
    final BluetoothDevice? device = _device;
    if (device == null) {
      throw StateError('No BLE device selected');
    }
    final int epoch = ++_epoch;
    _ready = false;
    _status = TransportStatus.connecting;
    _detail = 'CONNECTING TO BLE...';
    _emitStatus();

    _adapterSubscription ??= FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      if (_disposed) {
        return;
      }
      if (state != BluetoothAdapterState.on && state != BluetoothAdapterState.turningOn) {
        _status = TransportStatus.error;
        _detail = 'BLUETOOTH ${_adapterLabel(state)}';
        _emitStatus();
      }
    });

    try {
      await device.connect(timeout: const Duration(seconds: 10));
      if (epoch != _epoch || _disposed) {
        await device.disconnect(queue: false);
        return;
      }
      _connectionSubscription = device.connectionState.listen(
        (BluetoothConnectionState state) {
          if (state == BluetoothConnectionState.disconnected) {
            _ready = false;
            _status = TransportStatus.disconnected;
            _detail = 'BLE DISCONNECTED';
            _emitStatus();
          }
        },
        onError: (Object error) {
          _ready = false;
          _status = TransportStatus.error;
          _detail = 'BLE LINK ERROR: $error';
          _emitStatus();
        },
      );

      final List<BluetoothService> services = await device.discoverServices();
      if (epoch != _epoch || _disposed) {
        return;
      }
      BluetoothService? service;
      for (final BluetoothService candidate in services) {
        if (candidate.uuid.str.toLowerCase() == controlServiceUuid) {
          service = candidate;
          break;
        }
      }
      if (service == null) {
        throw const BleTransportException(
            'Control service $controlServiceUuid not found on the peripheral.');
      }
      for (final BluetoothCharacteristic characteristic in service.characteristics) {
        final String uuid = characteristic.uuid.str.toLowerCase();
        if (uuid == controlCharacteristicUuid) {
          _controlCharacteristic = characteristic;
        } else if (uuid == telemetryCharacteristicUuid) {
          _telemetryCharacteristic = characteristic;
        }
      }
      if (_controlCharacteristic == null || _telemetryCharacteristic == null) {
        throw const BleTransportException(
          'Required characteristics not found (control and telemetry are both mandatory).',
        );
      }

      await _telemetryCharacteristic!.setNotifyValue(true);
      if (epoch != _epoch || _disposed) {
        return;
      }
      _notifySubscription = _telemetryCharacteristic!.lastValueStream.listen(
        (List<int>? value) {
          if (value == null || value.isEmpty || _disposed) {
            return;
          }
          _rxPackets++;
          _rxBytes += value.length;
          _listener.onFrameReceived(Uint8List.fromList(value));
          _emitCounters();
        },
        onError: (Object error) {
          _status = TransportStatus.error;
          _detail = 'BLE NOTIFY ERROR: $error';
          _emitStatus();
        },
      );

      _ready = true;
      _status = TransportStatus.connected;
      _detail = 'BLE LINK UP - AWAITING TELEMETRY';
      _txPackets = 0;
      _rxPackets = 0;
      _txBytes = 0;
      _rxBytes = 0;
      _emitStatus();
    } catch (error) {
      _ready = false;
      _status = TransportStatus.error;
      _detail = _describeError(error);
      _emitStatus();
      rethrow;
    }
  }

  static String _adapterLabel(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.off:
        return 'OFF';
      case BluetoothAdapterState.turningOff:
        return 'TURNING OFF';
      case BluetoothAdapterState.unauthorized:
        return 'PERMISSION DENIED';
      case BluetoothAdapterState.unavailable:
        return 'UNAVAILABLE';
      case BluetoothAdapterState.unsupported:
        return 'UNSUPPORTED';
      case BluetoothAdapterState.turningOn:
      case BluetoothAdapterState.on:
      case BluetoothAdapterState.unknown:
        return state.name.toUpperCase();
    }
  }

  static String _describeError(Object error) {
    final String text = error.toString();
    if (text.contains('permission') || text.contains('Permission') || text.contains('unauthorized')) {
      return 'BLE PERMISSION DENIED - ALLOW BLUETOOTH IN SETTINGS';
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return 'BLE CONNECTION TIMED OUT - IS THE ROBOT POWERED?';
    }
    return 'BLE ERROR: $text';
  }

  @override
  Future<void> disconnect() async {
    final int epoch = ++_epoch;
    _ready = false;
    await _teardownLink();
    if (epoch != _epoch) {
      return;
    }
    _status = TransportStatus.disconnected;
    _detail = 'DISCONNECTED';
    _emitStatus();
  }

  Future<void> _teardownLink() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _controlCharacteristic = null;
    _telemetryCharacteristic = null;
    _queue.clear();
    _pendingDrive = null;
    final BluetoothDevice? device = _device;
    if (device != null) {
      try {
        await device.disconnect(queue: false);
      } catch (_) {
        // The link may already be gone; that is the desired end state.
      }
    }
  }

  @override
  Future<void> send(Uint8List frame) async {
    if (!_ready || _controlCharacteristic == null || frame.isEmpty) {
      return;
    }
    final int type = frame[1];
    if (type == FrameType.drive) {
      // Coalesce: only the newest DRIVE command matters.
      _pendingDrive = Uint8List.fromList(frame);
    } else if (type == FrameType.eStop ||
        (type == FrameType.arm && frame.length > 4 && frame[4] == 0)) {
      // Stop and disarm outrank everything already queued.
      _queue.insert(0, Uint8List.fromList(frame));
    } else {
      _queue.add(Uint8List.fromList(frame));
    }
    while (_queue.length > _maxQueuedControlFrames) {
      _queue.removeAt(0);
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_writing) {
      return;
    }
    _writing = true;
    try {
      while (!_disposed) {
        final Uint8List? frame;
        if (_queue.isNotEmpty) {
          frame = _queue.removeAt(0);
        } else if (_pendingDrive != null) {
          frame = _pendingDrive;
          _pendingDrive = null;
        } else {
          break;
        }
        final BluetoothCharacteristic? characteristic = _controlCharacteristic;
        if (frame == null || characteristic == null) {
          break;
        }
        final int epoch = _epoch;
        try {
          final bool withoutResponse = characteristic.properties.writeWithoutResponse;
          // The frame is copied before being handed to an async write, so the
          // caller's buffer can never be mutated underneath the platform.
          await characteristic.write(
            Uint8List.fromList(frame),
            withoutResponse: withoutResponse,
            allowLongWrite: false,
          );
          _txPackets++;
          _txBytes += frame.length;
          _emitCounters();
        } catch (error) {
          _status = TransportStatus.error;
          _detail = 'BLE WRITE FAILED: $error';
          _emitStatus();
          return;
        }
        if (epoch != _epoch) {
          return;
        }
      }
    } finally {
      _writing = false;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    ++_epoch;
    _ready = false;
    await stopScan();
    await _adapterSubscription?.cancel();
    _adapterSubscription = null;
    await _teardownLink();
    _listener = const _Detached();
  }

  void _emitStatus() {
    _listener.onTransportStatus(_status, _detail);
  }

  void _emitCounters() {
    _listener.onTransportCounters(_txPackets, _rxPackets, _txBytes, _rxBytes);
  }
}

/// Thrown when the peripheral does not expose the Wolve Bot GATT layout.
class BleTransportException implements Exception {
  const BleTransportException(this.message);

  final String message;

  @override
  String toString() => message;
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
