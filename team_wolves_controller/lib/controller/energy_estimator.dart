/// Duty-based pack usage estimate.
///
/// Integrates `((|L| + |R|) / 2 + 3) * dtSeconds` over **valid** telemetry and
/// compares it against a fixed budget of 60,000 %-seconds.
///
/// This is an estimate of how hard the pack has been worked. It is *not*
/// measured state of charge, not a voltage reading, and not a low-voltage
/// cutoff. The app has no battery sensor.
class EnergyEstimator {
  EnergyEstimator({this.budgetPercentSeconds = defaultBudget});

  /// Tunable pack budget in percent-seconds.
  static const double defaultBudget = 60000.0;

  final double budgetPercentSeconds;

  double _used = 0.0;
  double _elapsed = 0.0;

  /// Integrated duty usage, 0.0..1.0.
  double get fraction {
    if (budgetPercentSeconds <= 0.0) {
      return 0.0;
    }
    final double value = _used / budgetPercentSeconds;
    if (value < 0.0) {
      return 0.0;
    }
    if (value > 1.0) {
      return 1.0;
    }
    return value;
  }

  /// Whole-percent estimate for the HUD.
  int get percent => (fraction * 100.0).round();

  /// Wall-clock seconds integrated since the last reset.
  double get elapsedSeconds => _elapsed;

  /// Elapsed time as `MM:SS`.
  String get elapsedLabel {
    final int total = _elapsed.floor();
    final int minutes = total ~/ 60;
    final int seconds = total % 60;
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  /// Adds one telemetry sample.
  ///
  /// [dtSeconds] is clamped to 0.5 s so a long gap in telemetry is never
  /// integrated as if the robot had been driving the whole time.
  void addSample({
    required int leftPercent,
    required int rightPercent,
    required double dtSeconds,
  }) {
    double dt = dtSeconds;
    if (dt.isNaN || dt < 0.0) {
      dt = 0.0;
    } else if (dt > 0.5) {
      dt = 0.5;
    }
    final double left = leftPercent.abs().toDouble();
    final double right = rightPercent.abs().toDouble();
    _used += ((left + right) / 2.0 + 3.0) * dt;
    _elapsed += dt;
  }

  /// Resets both the estimate and the pack timer (NEW PACK).
  void reset() {
    _used = 0.0;
    _elapsed = 0.0;
  }
}
