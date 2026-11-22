import 'package:flutter_test/flutter_test.dart';
import 'package:team_wolves_controller/controller/energy_estimator.dart';

void main() {
  group('EnergyEstimator', () {
    test('integrates ((|L|+|R|)/2 + 3) * dt', () {
      final EnergyEstimator e = EnergyEstimator();
      for (int i = 0; i < 10; i++) {
        e.addSample(leftPercent: 100, rightPercent: 100, dtSeconds: 1.0);
      }
      // (100 + 3) * 10 = 1030 %-s out of a 60000 budget
      expect(e.elapsedSeconds, closeTo(10.0, 1e-9));
      expect(e.fraction, closeTo(1030.0 / 60000.0, 1e-9));
    });

    test('averages both motors', () {
      final EnergyEstimator e = EnergyEstimator();
      e.addSample(leftPercent: 100, rightPercent: 0, dtSeconds: 1.0);
      // (100/2 + 3) * 1 = 53
      expect(e.fraction, closeTo(53.0 / 60000.0, 1e-9));
    });

    test('uses the absolute value of signed percentages', () {
      final EnergyEstimator e = EnergyEstimator();
      e.addSample(leftPercent: -100, rightPercent: -100, dtSeconds: 1.0);
      expect(e.fraction, closeTo(103.0 / 60000.0, 1e-9));
    });

    test('clamps a stale gap so it is never integrated as measured', () {
      final EnergyEstimator e = EnergyEstimator();
      e.addSample(leftPercent: 100, rightPercent: 100, dtSeconds: 10.0);
      expect(e.elapsedSeconds, 0.5);
      expect(e.fraction, closeTo(103.0 * 0.5 / 60000.0, 1e-9));
    });

    test('ignores negative and NaN dt', () {
      final EnergyEstimator e = EnergyEstimator();
      e.addSample(leftPercent: 100, rightPercent: 100, dtSeconds: -3.0);
      e.addSample(leftPercent: 100, rightPercent: 100, dtSeconds: double.nan);
      expect(e.elapsedSeconds, 0.0);
      expect(e.fraction, 0.0);
    });

    test('clamps the estimate at 100%', () {
      final EnergyEstimator e = EnergyEstimator();
      for (int i = 0; i < 1000; i++) {
        e.addSample(leftPercent: 100, rightPercent: 100, dtSeconds: 1.0);
      }
      expect(e.fraction, 1.0);
      expect(e.percent, 100);
    });

    test('reset clears both the estimate and the pack timer', () {
      final EnergyEstimator e = EnergyEstimator();
      e.addSample(leftPercent: 100, rightPercent: 100, dtSeconds: 10.0);
      e.reset();
      expect(e.fraction, 0.0);
      expect(e.elapsedSeconds, 0.0);
      expect(e.percent, 0);
    });

    test('formats elapsed time as MM:SS', () {
      final EnergyEstimator e = EnergyEstimator();
      e.addSample(leftPercent: 0, rightPercent: 0, dtSeconds: 65.0);
      expect(e.elapsedLabel, '01:05');
    });

    test('zero dt contributes nothing', () {
      final EnergyEstimator e = EnergyEstimator();
      e.addSample(leftPercent: 100, rightPercent: 100, dtSeconds: 0.0);
      expect(e.fraction, 0.0);
    });
  });
}
