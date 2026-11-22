import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../protocol/protocol.dart';
import '../transport/ble_transport.dart';
import '../transport/robot_transport.dart';
import '../transport/udp_transport.dart';
import 'drive_shaper.dart';
import 'energy_estimator.dart';

/// Haptic strengths used by the controller.
enum HapticPulse { light, medium, heavy }

/// Owns input, drive timing, link/arm state, diagnostics and tuning.
///
/// Layering: `ui/` calls the setters and reads the getters; nothing in `ui/`
/// writes a packet. `protocol/` is pure Dart; `transport/` owns sockets and
/// BLE. This class is the only place that turns driver intent into frames.
///
/// Timing model
/// ------------
/// A single `Timer.periodic` drives transmission: 100 Hz on UDP, ~45 Hz on BLE.
/// Stick input only updates the latest value; it never queues. Because the
/// timer runs independently of widget rebuilds, a slow frame can never delay a
/// command.
///
/// Safety model
/// ------------
/// The ESP32 owns the real safety chain (250 ms DRIVE watchdog, E-STOP latch,
/// arming interlock, motor clamping). The controller mirrors that state for
/// the UI and never auto-rearms. App-side actions are commands, not guarantees.
class DriveController extends ChangeNotifier implements TransportListener {
  DriveController({
    DriveShaper? shaper,
    EnergyEstimator? energy,
    int Function()? clockMicros,
  })  : _shaper = shaper ?? DriveShaper(),
        _energy = energy ?? EnergyEstimator(),
        _clockMicros = clockMicros {
    _stopwatch.start();
  }

  /// Nominal UDP tick: 100 Hz.
  static const Duration udpPeriod = Duration(milliseconds: 10);

  /// Nominal BLE tick: ~45 Hz.
  static const Duration blePeriod = Duration(milliseconds: 22);

  /// Diagnostics / UI refresh tick. Deliberately slower than TX so the console
  /// never rebuilds at 100 Hz.
  static const Duration uiPeriod = Duration(milliseconds: 50);

  /// App-side telemetry freshness threshold. Independent of the ESP32's
  /// 250 ms DRIVE watchdog.
  static const int staleLinkMicros = 650000;

  /// Joystick centring tolerance required before arming.
  static const double centerTolerance = 0.05;

  static const int _maxRttSamples = 24;
  static const int _maxRttPending = 256;
  static const int _modeResendDelayMicros = 300000;
  static const int _modeMaxRetries = 4;

  final DriveShaper _shaper;
  final EnergyEstimator _energy;
  final Stopwatch _stopwatch = Stopwatch();
  final int Function()? _clockMicros;
  final Map<int, int> _rttPending = <int, int>{};
  final List<int> _rttSamples = <int>[];

  RobotTransport? _transport;
  BleTransport? _scanTransport;
  TransportKind? _transportKind;
  TransportStatus _transportStatus = TransportStatus.idle;
  String _transportDetail = 'NOT CONNECTED';

  int _epoch = 0;
  bool _disposed = false;
  bool _foreground = true;

  double _throttle = 0.0;
  double _steering = 0.0;
  int _commandThrottle = 0;
  int _commandSteering = 0;
  bool _boostHeld = false;
  bool _pivotHeld = false;
  bool _armRequested = false;
  bool _estopLatched = false;
  bool _recoveringFromEstop = false;
  int _lastThrottleBucket = 0;

  DriveProfile _profile = DriveProfile.speed;
  PowerPreset _preset = PowerPreset.p65;
  TerrainProfile _terrain = TerrainProfile.normal;
  DriveTuning _tuning = const DriveTuning();

  int _telemetryState = RobotState.boot;
  int _leftPercent = 0;
  int _rightPercent = 0;
  int _confirmedMode = 0;
  int _firmwareDrops = 0;
  int _telemetrySequence = -1;
  bool _telemetrySeen = false;
  int _lastTelemetryMicros = 0;
  bool _wasLive = false;
  bool _energyActive = false;

  int _txPackets = 0;
  int _rxPackets = 0;
  int _txBytes = 0;
  int _rxBytes = 0;
  int _malformedFrames = 0;

  int? _requestedModeSent;
  int _modeSentMicros = 0;
  int _modeRetries = 0;

  Timer? _txTimer;
  Timer? _uiTimer;
  Duration _txPeriod = udpPeriod;

  String _notice = 'DISARMED - CONNECT AND ARM TO DRIVE';

  int _nowMicros() => _clockMicros?.call() ?? _stopwatch.elapsedMicroseconds;

  // ---------------------------------------------------------------------
  // Session and transport
  // ---------------------------------------------------------------------

  TransportKind? get transportKind => _transportKind;

  TransportStatus get transportStatus => _transportStatus;

  String get transportDetail => _transportDetail;

  bool get hasTransport => _transport != null;

  bool get isTransportReady => _transport?.isReady ?? false;

  String get transportDescription => _transport?.describe ?? 'NO TRANSPORT';

  /// True while a CRC-valid telemetry frame is younger than [staleLinkMicros].
  /// A bound socket or a connected BLE peripheral is *not* enough.
  bool get isLinkLive {
    if (!_telemetrySeen) {
      return false;
    }
    return _nowMicros() - _lastTelemetryMicros <= staleLinkMicros;
  }

  int? get telemetryAgeMs {
    if (!_telemetrySeen) {
      return null;
    }
    return ((_nowMicros() - _lastTelemetryMicros) / 1000.0).round();
  }

  /// Opens the primary Wi-Fi UDP link, replacing any existing transport.
  Future<void> connectUdp() {
    return attachTransport(UdpTransport());
  }

  /// Opens the manual BLE fallback link to [deviceId].
  Future<void> connectBle(String deviceId) {
    return attachTransport(
      BleTransport(),
      prepare: (RobotTransport transport) async {
        (transport as BleTransport).selectDevice(deviceId);
      },
    );
  }

  /// Attaches a transport, closing the previous link first.
  ///
  /// The old transport is detached *before* it is disconnected so a late
  /// callback can never mutate the new session. [prepare] runs before
  /// [RobotTransport.connect] so a BLE transport can be pointed at a device.
  Future<void> attachTransport(
    RobotTransport transport, {
    Future<void> Function(RobotTransport transport)? prepare,
  }) async {
    if (_disposed) {
      throw StateError('DriveController disposed');
    }
    final RobotTransport? previous = _transport;
    final int epoch = ++_epoch;
    _stopTimers();

    if (previous != null) {
      previous.detach();
      try {
        await previous.disconnect();
      } catch (_) {
        // Best effort: the new link is what matters now.
      }
      try {
        await previous.dispose();
      } catch (_) {
        // Best effort.
      }
    }

    _resetSessionState();
    _transport = transport;
    _transportKind = transport.kind;
    transport.bind(this);
    _notice = transport.kind == TransportKind.udp
        ? 'OPENING UDP LINK...'
        : 'OPENING BLE LINK...';
    notifyListeners();

    try {
      if (prepare != null) {
        await prepare(transport);
      }
      await transport.connect();
    } catch (error) {
      if (epoch != _epoch || _disposed) {
        return;
      }
      _transportStatus = TransportStatus.error;
      _notice = 'CONNECT FAILED: $error';
      notifyListeners();
      rethrow;
    }

    if (epoch != _epoch || _disposed) {
      return;
    }

    _txPeriod = transport.kind == TransportKind.ble ? blePeriod : udpPeriod;
    _requestedModeSent = null;
    _modeRetries = 0;
    _syncMode();
    _startTimers();
    _notice = transport.isReady
        ? (transport.kind == TransportKind.udp
            ? 'UDP SOCKET BOUND - JOIN WOLVE BOT AP, THEN AWAIT TELEMETRY'
            : 'BLE LINK UP - AWAITING TELEMETRY')
        : 'LINK NOT READY';
    notifyListeners();
  }

  /// Closes the active link and clears every session value.
  Future<void> disconnectTransport() async {
    if (_disposed) {
      return;
    }
    final RobotTransport? transport = _transport;
    ++_epoch;
    _stopTimers();
    _transport = null;
    _transportKind = null;
    _resetSessionState();
    _transportStatus = TransportStatus.disconnected;
    _transportDetail = 'DISCONNECTED';
    _notice = 'DISCONNECTED';
    notifyListeners();

    if (transport != null) {
      transport.detach();
      try {
        await transport.disconnect();
      } catch (_) {
        // Best effort.
      }
      try {
        await transport.dispose();
      } catch (_) {
        // Best effort.
      }
    }
  }

  void _resetSessionState() {
    _throttle = 0.0;
    _steering = 0.0;
    _commandThrottle = 0;
    _commandSteering = 0;
    _boostHeld = false;
    _pivotHeld = false;
    _armRequested = false;
    _estopLatched = false;
    _recoveringFromEstop = false;
    _lastThrottleBucket = 0;
    _shaper.reset();
    _telemetryState = RobotState.boot;
    _leftPercent = 0;
    _rightPercent = 0;
    _confirmedMode = 0;
    _firmwareDrops = 0;
    _telemetrySequence = -1;
    _telemetrySeen = false;
    _lastTelemetryMicros = 0;
    _wasLive = false;
    _rttPending.clear();
    _rttSamples.clear();
    _txPackets = 0;
    _rxPackets = 0;
    _txBytes = 0;
    _rxBytes = 0;
    _malformedFrames = 0;
    _requestedModeSent = null;
    _modeRetries = 0;
  }

  // ---------------------------------------------------------------------
  // BLE scanning (transport owns the scan; UI only sees BleScanHit)
  // ---------------------------------------------------------------------

  /// Live scan results from the dedicated scanner transport.
  Stream<List<BleScanHit>> get bleScanResults {
    return (_scanTransport ??= BleTransport()).scanResults;
  }

  Future<void> startBleScan() async {
    await (_scanTransport ??= BleTransport()).startScan();
  }

  Future<void> stopBleScan() async {
    await _scanTransport?.stopScan();
  }

  Future<bool> get isBleAdapterReady async {
    return (_scanTransport ??= BleTransport()).isAdapterReady();
  }

  // ---------------------------------------------------------------------
  // Driver input
  // ---------------------------------------------------------------------

  /// Raw throttle, -1..1. Positive is forward.
  double get throttle => _throttle;

  /// Raw steering, -1..1. Positive is right.
  double get steering => _steering;

  /// Last shaped throttle command in thousandths.
  int get commandThrottle => _commandThrottle;

  /// Last shaped steering command in thousandths.
  int get commandSteering => _commandSteering;

  bool get boostHeld => _boostHeld;

  bool get pivotHeld => _pivotHeld;

  bool get sticksCentered =>
      _throttle.abs() <= centerTolerance && _steering.abs() <= centerTolerance;

  void setThrottle(double value) {
    if (_disposed) {
      return;
    }
    final double next = _clampAxis(value);
    if ((next - _throttle).abs() < 0.0001) {
      return;
    }
    _throttle = next;
    _maybeThrottleHaptic(next.abs());
  }

  void setSteering(double value) {
    if (_disposed) {
      return;
    }
    _steering = _clampAxis(value);
  }

  void setBoostHeld(bool held) {
    if (_disposed || _boostHeld == held) {
      return;
    }
    _boostHeld = held;
    if (held) {
      _haptic(HapticPulse.heavy);
      _notice = 'BOOST - M3 REQUESTED';
    } else {
      _notice = 'BOOST RELEASED - PROFILE RESTORED';
    }
    notifyListeners();
  }

  void setPivotHeld(bool held) {
    if (_disposed || _pivotHeld == held) {
      return;
    }
    _pivotHeld = held;
    // Pivot entry must never inherit a deceleration reference.
    _shaper.reset();
    if (held) {
      _haptic(HapticPulse.medium);
      _notice = 'ZERO PIVOT - COUNTER-ROTATION';
    } else {
      _notice = 'PIVOT RELEASED';
    }
    notifyListeners();
  }

  void _clearIntent() {
    _throttle = 0.0;
    _steering = 0.0;
    _commandThrottle = 0;
    _commandSteering = 0;
    _boostHeld = false;
    _pivotHeld = false;
    _lastThrottleBucket = 0;
  }

  static double _clampAxis(double value) {
    if (value.isNaN) {
      return 0.0;
    }
    if (value < -1.0) {
      return -1.0;
    }
    if (value > 1.0) {
      return 1.0;
    }
    return value;
  }

  static int _bucketFor(double magnitude) {
    if (magnitude < 0.03) {
      return 0;
    }
    if (magnitude < 0.45) {
      return 1;
    }
    if (magnitude < 0.90) {
      return 2;
    }
    return 3;
  }

  /// Fires once per upward threshold crossing, never repeatedly while a driver
  /// holds a stick near a boundary.
  void _maybeThrottleHaptic(double magnitude) {
    if (!_tuning.haptics) {
      return;
    }
    final int bucket = _bucketFor(magnitude);
    if (bucket > _lastThrottleBucket) {
      if (bucket == 1) {
        _haptic(HapticPulse.light);
      } else if (bucket == 2) {
        _haptic(HapticPulse.light);
      } else {
        _haptic(HapticPulse.medium);
      }
    }
    _lastThrottleBucket = bucket;
  }

  // ---------------------------------------------------------------------
  // Profile / preset / terrain
  // ---------------------------------------------------------------------

  DriveProfile get profile => _profile;

  PowerPreset get preset => _preset;

  TerrainProfile get terrain => _terrain;

  /// True when Torque is selected at 65% or 100%: the firmware still caps at
  /// M1, so the number on the screen must not imply that output.
  bool get torqueLimited =>
      _profile == DriveProfile.torque && _preset != PowerPreset.p35;

  int get requestedMode {
    if (_boostHeld) {
      return 3;
    }
    if (_profile == DriveProfile.torque) {
      return 1;
    }
    if (_preset == PowerPreset.p100) {
      return 3;
    }
    return 2;
  }

  double get throttleScale {
    if (_boostHeld) {
      return 1.0;
    }
    if (_profile == DriveProfile.torque) {
      return _preset == PowerPreset.p35 ? 35.0 / 45.0 : 1.0;
    }
    return _preset == PowerPreset.p35 ? 35.0 / 65.0 : 1.0;
  }

  void setProfile(DriveProfile profile) {
    if (_disposed || _profile == profile) {
      return;
    }
    _profile = profile;
    _haptic(HapticPulse.light);
    _notice = '${profile.label} PROFILE - M$requestMode';
    notifyListeners();
  }

  void setPreset(PowerPreset preset) {
    if (_disposed || _preset == preset) {
      return;
    }
    _preset = preset;
    _haptic(HapticPulse.light);
    _notice = '${profile.label} ${preset.label} - M$requestMode';
    notifyListeners();
  }

  /// Selecting a terrain replaces the default expo and damping values. The
  /// Settings sliders then adjust from that baseline.
  void setTerrain(TerrainProfile terrain) {
    if (_disposed) {
      return;
    }
    _terrain = terrain;
    _tuning = _tuning.copyWith(
      throttleExpo: terrain.throttleExpo,
      steeringExpo: terrain.steeringExpo,
      highSpeedTurnFactor: terrain.highSpeedTurnFactor,
    );
    _haptic(HapticPulse.light);
    _notice = 'TERRAIN ${terrain.label}';
    notifyListeners();
  }

  void cycleTerrain() => setTerrain(_terrain.next);

  // ---------------------------------------------------------------------
  // Arm / disarm / E-STOP
  // ---------------------------------------------------------------------

  bool get armRequested => _armRequested;

  /// True only when the ESP32 has confirmed ARMED *and* we asked for it.
  /// Local arm intent alone is never reported as armed.
  bool get armedConfirmed =>
      _armRequested && _telemetryState == RobotState.armed;

  bool get estopLatched => _estopLatched;

  bool get canArm =>
      isLinkLive &&
      sticksCentered &&
      !_estopLatched &&
      _telemetryState != RobotState.estop;

  /// Requests ARM=1. Returns true only if the request was actually sent.
  bool requestArm() {
    if (_disposed) {
      return false;
    }
    if (_estopLatched) {
      _notice = 'E-STOP LATCHED - TURN OFF TO RESET';
      notifyListeners();
      return false;
    }
    if (_telemetryState == RobotState.estop) {
      _notice = 'ESP32 ESTOP LATCHED - TURN OFF, THEN ON';
      notifyListeners();
      return false;
    }
    if (!isLinkLive) {
      _notice = 'NO LIVE LINK - CANNOT ARM';
      notifyListeners();
      return false;
    }
    if (!sticksCentered) {
      _notice = 'Center both joysticks (\u00B15%) before turning ON.';
      notifyListeners();
      return false;
    }
    if (_armRequested) {
      return true;
    }
    _armRequested = true;
    _energyActive = true;
    _haptic(HapticPulse.medium);
    _sendControl(Protocol.arm(sequence: Protocol.nextSequence(), arm: true));
    _notice = 'ARM REQUESTED - AWAITING ESP32 ARMED';
    notifyListeners();
    return true;
  }

  /// Requests ARM=0, clears drive intent, and clears the local E-STOP latch so
  /// the deliberate OFF -> ON recovery path is available.
  void requestDisarm() {
    if (_disposed) {
      return;
    }
    final bool wasEstop = _estopLatched || _telemetryState == RobotState.estop;
    _armRequested = false;
    _estopLatched = false;
    if (wasEstop) {
      _recoveringFromEstop = true;
    }
    _clearIntent();
    _shaper.reset();
    _sendControl(Protocol.arm(sequence: Protocol.nextSequence(), arm: false));
    _notice = wasEstop ? 'OFF SENT - WAIT FOR ESP32 DISARMED' : 'ARM=0 SENT - DISARMING';
    _haptic(HapticPulse.light);
    notifyListeners();
  }

  /// Emergency stop. Called on pointer-down with no animation or confirmation.
  ///
  /// Sends `0x06` immediately, clears every input and shaping reference, and
  /// keeps the E-STOP flag on subsequent DRIVE frames while locally latched.
  /// This is a command, not a guarantee of zero-latency stopping.
  void triggerEStop() {
    if (_disposed) {
      return;
    }
    final bool alreadyLatched = _estopLatched;
    _estopLatched = true;
    _recoveringFromEstop = false;
    _armRequested = false;
    _clearIntent();
    _shaper.reset();
    _haptic(HapticPulse.heavy);

    final RobotTransport? transport = _transport;
    if (transport == null || !transport.isReady) {
      _notice = 'E-STOP: NO LINK - COMMAND NOT DELIVERED';
    } else {
      _sendControl(Protocol.eStop(sequence: Protocol.nextSequence()));
      _notice = alreadyLatched
          ? 'E-STOP LATCHED - AWAITING ESP32 ESTOP'
          : 'E-STOP SENT - AWAITING ESP32 ESTOP STATE';
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Telemetry
  // ---------------------------------------------------------------------

  int get telemetryState => _telemetryState;

  String get telemetryStateLabel => RobotState.label(_telemetryState);

  bool get telemetrySeen => _telemetrySeen;

  int get leftPercent => _leftPercent;

  int get rightPercent => _rightPercent;

  int get confirmedMode => _confirmedMode;

  String get confirmedModeLabel => _confirmedMode == 0 ? 'M-' : 'M$_confirmedMode';

  int get firmwareDrops => _firmwareDrops;

  int get telemetrySequence => _telemetrySequence;

  int get malformedFrames => _malformedFrames;

  /// Coarse echo round-trip estimate in milliseconds, or null with no sample.
  /// This is phone -> ESP32 -> phone, not input-to-wheel latency.
  int? get rttMs {
    final int? micros = rttMicros;
    if (micros == null) {
      return null;
    }
    return (micros / 1000.0).round();
  }

  int? get rttMicros {
    if (_rttSamples.isEmpty) {
      return null;
    }
    int total = 0;
    for (final int sample in _rttSamples) {
      total += sample;
    }
    return total ~/ _rttSamples.length;
  }

  int get txPackets => _txPackets;

  int get rxPackets => _rxPackets;

  int get txBytes => _txBytes;

  int get rxBytes => _rxBytes;

  String get notice => _notice;

  int get packPercent => _energy.percent;

  String get packElapsed => _energy.elapsedLabel;

  @override
  void onFrameReceived(Uint8List frame) {
    if (_disposed) {
      return;
    }
    final TelemetryFrame? telemetry = Protocol.parseTelemetry(frame);
    if (telemetry == null) {
      _malformedFrames++;
      return;
    }

    final int now = _nowMicros();
    final double dt =
        _telemetrySeen ? (now - _lastTelemetryMicros) / 1000000.0 : 0.0;
    _telemetrySeen = true;
    _lastTelemetryMicros = now;
    _telemetrySequence = telemetry.sequence;
    _telemetryState = telemetry.state;
    _leftPercent = telemetry.leftPercent;
    _rightPercent = telemetry.rightPercent;
    _confirmedMode = telemetry.mode;
    _firmwareDrops = telemetry.dropped;

    if (_energyActive) {
      _energy.addSample(
        leftPercent: telemetry.leftPercent,
        rightPercent: telemetry.rightPercent,
        dtSeconds: dt,
      );
    }

    final int? sentAt = _rttPending.remove(telemetry.sequence);
    if (sentAt != null) {
      _recordRtt(now - sentAt);
    }

    if (telemetry.state == RobotState.estop) {
      if (!_recoveringFromEstop) {
        _estopLatched = true;
        _armRequested = false;
        _notice = 'ESP32 ESTOP CONFIRMED - TURN OFF, THEN ON TO RESET';
      }
    } else {
      if (_recoveringFromEstop) {
        _recoveringFromEstop = false;
        _notice = 'ESP32 ESTOP CLEARED';
      }
      if (telemetry.state == RobotState.failsafe && _armRequested) {
        _armRequested = false;
        _notice = 'ESP32 FAILSAFE - LINK OR WATCHDOG TRIPPED';
      }
    }
  }

  void _recordRtt(int micros) {
    if (micros < 0 || micros > 5000000) {
      return;
    }
    _rttSamples.add(micros);
    if (_rttSamples.length > _maxRttSamples) {
      _rttSamples.removeAt(0);
    }
  }

  @override
  void onTransportStatus(TransportStatus status, String detail) {
    if (_disposed) {
      return;
    }
    _transportStatus = status;
    _transportDetail = detail;
    if (status == TransportStatus.disconnected || status == TransportStatus.error) {
      _telemetrySeen = false;
      _wasLive = false;
      _armRequested = false;
    }
    if (status == TransportStatus.error) {
      _notice = detail;
    }
    notifyListeners();
  }

  @override
  void onTransportCounters(int txPackets, int rxPackets, int txBytes, int rxBytes) {
    if (_disposed) {
      return;
    }
    _txPackets = txPackets;
    _rxPackets = rxPackets;
    _txBytes = txBytes;
    _rxBytes = rxBytes;
  }

  // ---------------------------------------------------------------------
  // TX scheduler
  // ---------------------------------------------------------------------

  void _startTimers() {
    _stopTimers();
    _txTimer = Timer.periodic(_txPeriod, (_) => _tick());
    _uiTimer = Timer.periodic(uiPeriod, (_) => pumpDiagnostics());
  }

  void _stopTimers() {
    _txTimer?.cancel();
    _txTimer = null;
    _uiTimer?.cancel();
    _uiTimer = null;
  }

  void _tick() {
    if (_disposed || !_foreground) {
      return;
    }
    final RobotTransport? transport = _transport;
    if (transport == null || !transport.isReady) {
      return;
    }

    final DriveCommand command;
    if (_estopLatched) {
      _shaper.reset();
      command = DriveCommand.zero;
    } else {
      command = _shaper.shape(
        throttle: _throttle,
        steering: _steering,
        pivot: _pivotHeld,
        boost: _boostHeld,
        tuning: _tuning,
        speedScale: throttleScale,
        dtSeconds: _txPeriod.inMicroseconds / 1000000.0,
      );
    }
    _commandThrottle = command.throttle;
    _commandSteering = command.steering;

    final int sequence = Protocol.nextSequence();
    _rttPending[sequence] = _nowMicros();
    if (_rttPending.length > _maxRttPending) {
      _rttPending.remove(_rttPending.keys.first);
    }

    final Uint8List frame = Protocol.drive(
      sequence: sequence,
      armed: _armRequested,
      eStop: _estopLatched,
      throttle: command.throttle,
      steering: command.steering,
    );
    unawaited(transport.send(frame));
  }

  void _sendControl(Uint8List frame) {
    final RobotTransport? transport = _transport;
    if (transport == null || !transport.isReady) {
      return;
    }
    unawaited(transport.send(frame));
  }

  /// Sends SET_MODE when the requested mode changes, and retries a few times if
  /// the ESP32 never confirms it. Never sent on every DRIVE tick.
  void _syncMode() {
    final int wanted = requestedMode;
    final int now = _nowMicros();

    if (_requestedModeSent != wanted) {
      _requestedModeSent = wanted;
      _modeSentMicros = now;
      _modeRetries = 0;
      _sendControl(Protocol.setMode(sequence: Protocol.nextSequence(), mode: wanted));
      return;
    }
    if (_confirmedMode == wanted) {
      _modeRetries = 0;
      return;
    }
    if (_modeRetries < _modeMaxRetries &&
        now - _modeSentMicros > _modeResendDelayMicros) {
      _modeRetries++;
      _modeSentMicros = now;
      _sendControl(Protocol.setMode(sequence: Protocol.nextSequence(), mode: wanted));
      if (_modeRetries >= _modeMaxRetries) {
        _notice = 'MODE NOT CONFIRMED - CHECK LINK';
      }
    }
  }

  /// Runs one TX tick immediately. Test seam: production code only ever reaches
  /// [_tick] from the periodic timer.
  @visibleForTesting
  void debugTick() => _tick();

  /// Diagnostics tick. Public so tests can advance state without real time.
  void pumpDiagnostics() {    if (_disposed) {
      return;
    }
    _syncMode();

    final bool live = isLinkLive;
    if (!live && _wasLive) {
      _wasLive = false;
      if (_armRequested) {
        _armRequested = false;
      }
      _notice = 'LINK LOST - ESP32 WATCHDOG OWNS THE STOP';
      _haptic(HapticPulse.heavy);
    } else if (live && !_wasLive) {
      _wasLive = true;
      if (_armRequested) {
        _notice = 'LINK LIVE';
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  /// Background / inactive / detached: zero everything and stop the DRIVE timer.
  void handleLifecycleStopped() {
    if (_disposed) {
      return;
    }
    _foreground = false;
    _stopTimers();
    _clearIntent();
    _armRequested = false;
    _shaper.reset();
    _notice = 'APP BACKGROUND - DRIVE TIMER STOPPED';
    notifyListeners();
  }

  /// Resume restarts only an *unarmed* session, and only if the transport is
  /// still usable. An async connect that finished in the background cannot
  /// restart driving because the timer is only created here.
  void handleLifecycleResumed() {
    if (_disposed) {
      return;
    }
    _foreground = true;
    final RobotTransport? transport = _transport;
    if (transport != null && transport.isReady) {
      _requestedModeSent = null;
      _syncMode();
      _startTimers();
      _notice = 'RESUMED - DISARMED, LINK PRESERVED';
    } else {
      _notice = 'RESUMED - NO LINK';
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Tuning
  // ---------------------------------------------------------------------

  DriveTuning get tuning => _tuning;

  void setTrim(double value) {
    if (_disposed) {
      return;
    }
    _tuning = _tuning.copyWith(trim: _clampDouble(value, -0.15, 0.15));
    notifyListeners();
  }

  void resetTrim() => setTrim(0.0);

  void setThrottleExpo(double value) {
    if (_disposed) {
      return;
    }
    _tuning = _tuning.copyWith(throttleExpo: _clampDouble(value, 0.0, 0.70));
    notifyListeners();
  }

  void setSteeringExpo(double value) {
    if (_disposed) {
      return;
    }
    _tuning = _tuning.copyWith(steeringExpo: _clampDouble(value, 0.0, 0.70));
    notifyListeners();
  }

  void setReverseCap(double value) {
    if (_disposed) {
      return;
    }
    _tuning = _tuning.copyWith(reverseCap: _clampDouble(value, 0.30, 1.00));
    notifyListeners();
  }

  void setSmoothDecel(bool enabled) {
    if (_disposed) {
      return;
    }
    _tuning = _tuning.copyWith(smoothDecel: enabled);
    if (!enabled) {
      _shaper.reset();
    }
    notifyListeners();
  }

  void setFloatingSticks(bool enabled) {
    if (_disposed) {
      return;
    }
    _tuning = _tuning.copyWith(floatingSticks: enabled);
    notifyListeners();
  }

  void setHaptics(bool enabled) {
    if (_disposed) {
      return;
    }
    _tuning = _tuning.copyWith(haptics: enabled);
    notifyListeners();
  }

  /// NEW PACK: resets the duty estimate and the pack timer.
  void resetPack() {
    if (_disposed) {
      return;
    }
    _energy.reset();
    _energyActive = false;
    _notice = 'NEW PACK - ESTIMATE RESET';
    notifyListeners();
  }

  static double _clampDouble(double value, double low, double high) {
    if (value.isNaN) {
      return low;
    }
    if (value < low) {
      return low;
    }
    if (value > high) {
      return high;
    }
    return value;
  }

  // ---------------------------------------------------------------------
  // Haptics
  // ---------------------------------------------------------------------

  void _haptic(HapticPulse pulse) {
    if (!_tuning.haptics) {
      return;
    }
    switch (pulse) {
      case HapticPulse.light:
        unawaited(HapticFeedback.selectionClick());
        break;
      case HapticPulse.medium:
        unawaited(HapticFeedback.mediumImpact());
        break;
      case HapticPulse.heavy:
        unawaited(HapticFeedback.heavyImpact());
        break;
    }
  }

  // ---------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    ++_epoch;
    _stopTimers();
    final RobotTransport? transport = _transport;
    _transport = null;
    if (transport != null) {
      transport.detach();
      unawaited(transport.dispose());
    }
    final BleTransport? scanner = _scanTransport;
    _scanTransport = null;
    if (scanner != null) {
      unawaited(scanner.dispose());
    }
    super.dispose();
  }
}
