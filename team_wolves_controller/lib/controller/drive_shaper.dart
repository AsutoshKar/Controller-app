import 'dart:math' as math;

/// Driver-facing drive profile. "Torque" is a profile name, not a measured
/// quantity: the app has no current sensor.
enum DriveProfile { torque, speed }

/// Approved UI presets. There is deliberately no 45% preset.
enum PowerPreset { p35, p65, p100 }

/// Driver-selected terrain profiles. These change the app's default expo and
/// steering damping; they are not surface detection or traction control.
enum TerrainProfile { normal, sandPebbles, plySlick, fireSprint }

extension DriveProfileX on DriveProfile {
  String get label => this == DriveProfile.torque ? 'TORQUE' : 'SPEED';
}

extension PowerPresetX on PowerPreset {
  String get label => switch (this) {
        PowerPreset.p35 => '35%',
        PowerPreset.p65 => '65%',
        PowerPreset.p100 => '100%',
      };

  int get percent => switch (this) {
        PowerPreset.p35 => 35,
        PowerPreset.p65 => 65,
        PowerPreset.p100 => 100,
      };
}

extension TerrainProfileX on TerrainProfile {
  String get label => switch (this) {
        TerrainProfile.normal => 'NORMAL',
        TerrainProfile.sandPebbles => 'SAND / PEBBLES',
        TerrainProfile.plySlick => 'PLY / SLICK',
        TerrainProfile.fireSprint => 'FIRE SPRINT',
      };

  double get throttleExpo => switch (this) {
        TerrainProfile.normal => 0.20,
        TerrainProfile.sandPebbles => 0.45,
        TerrainProfile.plySlick => 0.35,
        TerrainProfile.fireSprint => 0.05,
      };

  double get steeringExpo => switch (this) {
        TerrainProfile.normal => 0.30,
        TerrainProfile.sandPebbles => 0.35,
        TerrainProfile.plySlick => 0.55,
        TerrainProfile.fireSprint => 0.15,
      };

  double get highSpeedTurnFactor => switch (this) {
        TerrainProfile.normal => 0.90,
        TerrainProfile.sandPebbles => 0.72,
        TerrainProfile.plySlick => 0.65,
        TerrainProfile.fireSprint => 1.00,
      };

  String get hint => switch (this) {
        TerrainProfile.normal => 'Balanced',
        TerrainProfile.sandPebbles => 'Soft throttle',
        TerrainProfile.plySlick => 'Calm steering',
        TerrainProfile.fireSprint => 'Linear, fast',
      };

  TerrainProfile get next => switch (this) {
        TerrainProfile.normal => TerrainProfile.sandPebbles,
        TerrainProfile.sandPebbles => TerrainProfile.plySlick,
        TerrainProfile.plySlick => TerrainProfile.fireSprint,
        TerrainProfile.fireSprint => TerrainProfile.normal,
      };
}

/// Session-only tuning. Nothing here is persisted.
class DriveTuning {
  const DriveTuning({
    this.trim = 0.0,
    this.throttleExpo = 0.20,
    this.steeringExpo = 0.30,
    this.reverseCap = 0.60,
    this.smoothDecel = false,
    this.floatingSticks = false,
    this.haptics = true,
    this.highSpeedTurnFactor = 0.90,
  });

  /// Straight-line steering bias, -0.15..0.15.
  final double trim;

  /// Throttle expo, 0.00..0.70.
  final double throttleExpo;

  /// Steering expo, 0.00..0.70.
  final double steeringExpo;

  /// Reverse throttle cap, 0.30..1.00.
  final double reverseCap;

  /// Optional throttle-only deceleration ramp. Default OFF.
  final bool smoothDecel;

  /// Fixed-origin (default) or floating-origin sticks.
  final bool floatingSticks;

  /// Optional haptics. Default ON.
  final bool haptics;

  /// Steering damping factor, 0.65..1.00 depending on terrain.
  final double highSpeedTurnFactor;

  DriveTuning copyWith({
    double? trim,
    double? throttleExpo,
    double? steeringExpo,
    double? reverseCap,
    bool? smoothDecel,
    bool? floatingSticks,
    bool? haptics,
    double? highSpeedTurnFactor,
  }) {
    return DriveTuning(
      trim: trim ?? this.trim,
      throttleExpo: throttleExpo ?? this.throttleExpo,
      steeringExpo: steeringExpo ?? this.steeringExpo,
      reverseCap: reverseCap ?? this.reverseCap,
      smoothDecel: smoothDecel ?? this.smoothDecel,
      floatingSticks: floatingSticks ?? this.floatingSticks,
      haptics: haptics ?? this.haptics,
      highSpeedTurnFactor: highSpeedTurnFactor ?? this.highSpeedTurnFactor,
    );
  }
}

/// A shaped drive command in signed thousandths.
class DriveCommand {
  const DriveCommand(this.throttle, this.steering);

  final int throttle;
  final int steering;

  static const DriveCommand zero = DriveCommand(0, 0);

  @override
  String toString() => 'DriveCommand(t: $throttle, s: $steering)';
}

/// Turns raw stick position into the signed command sent to the ESP32.
///
/// Pipeline outside ZERO PIVOT, in the approved order:
///   1. clamp both axes to [-1, 1]
///   2. throttle and steering expo
///   3. speed mapping (app-side throttle scale)
///   4. reverse cap (skipped during BOOST)
///   5. optional smooth deceleration
///   6. terrain steering damping, then straight-line trim
///
/// The result is converted to signed thousandths and clamped to
/// [-1000, 1000]. There is no `math.pow` in the transmit path.
class DriveShaper {
  double _lastThrottle = 0.0;

  /// Last throttled command magnitude, for diagnostics and tests.
  double get lastThrottle => _lastThrottle;

  /// Clears the deceleration reference. Must be called on every safety or
  /// lifecycle transition so a stale command can never be carried forward.
  void reset() {
    _lastThrottle = 0.0;
  }

  DriveCommand shape({
    required double throttle,
    required double steering,
    required bool pivot,
    required bool boost,
    required DriveTuning tuning,
    required double speedScale,
    double dtSeconds = 0.01,
  }) {
    double t = _clamp(throttle, -1.0, 1.0);
    double s = _clamp(steering, -1.0, 1.0);

    if (pivot) {
      // ZERO PIVOT: throttle is forced to zero and only steering reaches the
      // motors, with the approved near-linear expo for counter-rotation.
      _lastThrottle = 0.0;
      return DriveCommand(0, _toCounts(_expo(s, 0.15)));
    }

    final double throttleExpo = boost
        ? 0.05
        : _clamp(tuning.throttleExpo, 0.0, 0.70);
    final double steeringExpo = _clamp(tuning.steeringExpo, 0.0, 0.70);

    t = _expo(t, throttleExpo);
    t = _clamp(t * _clamp(speedScale, 0.0, 1.0), -1.0, 1.0);

    if (!boost && t < 0.0) {
      final double cap = _clamp(tuning.reverseCap, 0.30, 1.0);
      if (-t > cap) {
        t = -cap;
      }
    }

    if (tuning.smoothDecel && !boost) {
      t = _applySmoothDecel(t, dtSeconds);
    }
    _lastThrottle = t;

    s = _expo(s, steeringExpo);
    final double factor = _clamp(tuning.highSpeedTurnFactor, 0.0, 1.0);
    s *= 1.0 - (1.0 - factor) * t.abs();
    if (t.abs() > 0.04) {
      s += t * _clamp(tuning.trim, -0.15, 0.15);
    }
    s = _clamp(s, -1.0, 1.0);

    return DriveCommand(_toCounts(t), _toCounts(s));
  }

  double _applySmoothDecel(double value, double dtSeconds) {
    const double referenceStep = 0.08;
    const double referenceTick = 0.01;
    final double last = _lastThrottle;
    if (last == 0.0 || value == 0.0 || (last > 0.0) != (value > 0.0)) {
      // A direction change passes straight through: the ESP32's own slew
      // limiter handles the reversal, and the driver expects an immediate
      // response when flipping the stick.
      return value;
    }
    final double magnitude = value.abs();
    final double lastMagnitude = last.abs();
    if (magnitude >= lastMagnitude) {
      return value;
    }
    final double maxStep = referenceStep * math.max(dtSeconds, 0.0) / referenceTick;
    final double floor = math.max(0.0, lastMagnitude - maxStep);
    if (magnitude < floor) {
      return (value > 0.0 ? 1.0 : -1.0) * floor;
    }
    return value;
  }

  static double _expo(double x, double e) => (1.0 - e) * x + e * x * x * x;

  static double _clamp(double value, double low, double high) {
    if (value < low) {
      return low;
    }
    if (value > high) {
      return high;
    }
    return value;
  }

  static int _toCounts(double value) {
    final int counts = (value * 1000.0).round();
    if (counts < -1000) {
      return -1000;
    }
    if (counts > 1000) {
      return 1000;
    }
    return counts;
  }
}
