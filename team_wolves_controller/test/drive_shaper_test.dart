import 'package:flutter_test/flutter_test.dart';
import 'package:team_wolves_controller/controller/drive_shaper.dart';

const DriveTuning flat = DriveTuning(
  throttleExpo: 0.0,
  steeringExpo: 0.0,
  reverseCap: 1.0,
  highSpeedTurnFactor: 1.0,
  trim: 0.0,
);

void main() {

  DriveCommand shape(
    DriveShaper shaper, {
    double throttle = 0,
    double steering = 0,
    bool pivot = false,
    bool boost = false,
    DriveTuning tuning = flat,
    double speedScale = 1.0,
    double dt = 0.01,
  }) {
    return shaper.shape(
      throttle: throttle,
      steering: steering,
      pivot: pivot,
      boost: boost,
      tuning: tuning,
      speedScale: speedScale,
      dtSeconds: dt,
    );
  }

  group('DriveShaper neutral', () {
    test('zero input produces zero output', () {
      final DriveCommand c = shape(DriveShaper());
      expect(c.throttle, 0);
      expect(c.steering, 0);
    });

    test('tiny stick noise inside the 3% band still maps to near zero', () {
      final DriveCommand c = shape(DriveShaper(), throttle: 0.001);
      expect(c.throttle.abs(), lessThanOrEqualTo(1));
    });
  });

  group('DriveShaper expo', () {
    test('uses (1-e)x + e*x^3', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: 0.5,
        tuning: flat.copyWith(throttleExpo: 0.20),
      );
      // 0.8*0.5 + 0.2*0.125 = 0.425
      expect(c.throttle, 425);
    });

    test('zero expo is linear', () {
      expect(shape(DriveShaper(), throttle: 0.25, tuning: flat).throttle, 250);
      expect(shape(DriveShaper(), throttle: -0.25, tuning: flat).throttle, -250);
    });

    test('input beyond +/-1 is clamped', () {
      final DriveCommand c = shape(DriveShaper(), throttle: 4.0, steering: -4.0);
      expect(c.throttle, 1000);
      expect(c.steering, -1000);
    });
  });

  group('DriveShaper speed mapping', () {
    test('35/65 scale is applied to the shaped throttle', () {
      final DriveCommand c = shape(DriveShaper(), throttle: 1.0, speedScale: 35 / 65);
      expect(c.throttle, 538);
    });

    test('35/45 scale is applied for the torque preset', () {
      final DriveCommand c = shape(DriveShaper(), throttle: 1.0, speedScale: 35 / 45);
      expect(c.throttle, 778);
    });
  });

  group('DriveShaper reverse cap', () {
    test('caps negative throttle outside BOOST', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: -1.0,
        tuning: flat.copyWith(reverseCap: 0.50),
      );
      expect(c.throttle, -500);
    });

    test('does not apply to positive throttle', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: 1.0,
        tuning: flat.copyWith(reverseCap: 0.50),
      );
      expect(c.throttle, 1000);
    });

    test('is bypassed during BOOST', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: -1.0,
        boost: true,
        tuning: flat.copyWith(reverseCap: 0.50),
      );
      expect(c.throttle, -1000);
    });
  });

  group('DriveShaper terrain damping and trim', () {
    test('steering is damped by 1-(1-f)*|throttle|', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: 0.5,
        steering: 0.5,
        tuning: flat.copyWith(highSpeedTurnFactor: 0.72),
      );
      // 0.5 * (1 - 0.28*0.5) = 0.43
      expect(c.steering, 430);
    });

    test('trim adds throttle*trim above the 4% threshold', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: 0.5,
        tuning: flat.copyWith(trim: 0.10),
      );
      expect(c.steering, 50);
    });

    test('trim is ignored below the 4% threshold', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: 0.02,
        tuning: flat.copyWith(trim: 0.10),
      );
      expect(c.steering, 0);
    });

    test('trim is an open-loop bias, never a correction', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: 0.5,
        steering: 0.5,
        tuning: flat.copyWith(trim: 0.10),
      );
      expect(c.steering, 550);
    });
  });

  group('DriveShaper pivot', () {
    test('forces throttle to zero and uses expo 0.15', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: 0.8,
        steering: 0.5,
        pivot: true,
      );
      expect(c.throttle, 0);
      // (0.85*0.5) + (0.15*0.125) = 0.44375 -> 444
      expect(c.steering, 444);
    });

    test('clears the deceleration reference on entry', () {
      final DriveShaper shaper = DriveShaper();
      shape(shaper, throttle: 1.0);
      shape(shaper, pivot: true, steering: 0.2);
      final DriveCommand after = shape(shaper, throttle: 0.0);
      expect(after.throttle, 0);
    });
  });

  group('DriveShaper boost', () {
    test('uses the near-linear 0.05 expo regardless of the tuning slider', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: 1.0,
        boost: true,
        tuning: flat.copyWith(throttleExpo: 0.70),
      );
      expect(c.throttle, 1000);
    });

    test('mid-travel boost is linear-ish, not softened by the slider', () {
      final DriveCommand c = shape(
        DriveShaper(),
        throttle: 0.5,
        boost: true,
        tuning: flat.copyWith(throttleExpo: 0.70),
      );
      // (0.95*0.5) + (0.05*0.125) = 0.48125 -> 481
      expect(c.throttle, 481);
    });
  });

  group('DriveShaper smooth decel', () {
    test('limits only decreases in magnitude', () {
      final DriveShaper shaper = DriveShaper();
      shape(shaper, throttle: 1.0, tuning: flat.copyWith(smoothDecel: true));
      final DriveCommand c = shape(
        shaper,
        throttle: 0.0,
        tuning: flat.copyWith(smoothDecel: true),
      );
      expect(c.throttle, 920);
    });

    test('allows an increase immediately', () {
      final DriveShaper shaper = DriveShaper();
      shape(shaper, throttle: 0.2, tuning: flat.copyWith(smoothDecel: true));
      final DriveCommand c = shape(
        shaper,
        throttle: 0.8,
        tuning: flat.copyWith(smoothDecel: true),
      );
      expect(c.throttle, 800);
    });

    test('scales the step with dt', () {
      final DriveShaper shaper = DriveShaper();
      shape(shaper, throttle: 1.0, tuning: flat.copyWith(smoothDecel: true));
      final DriveCommand c = shape(
        shaper,
        throttle: 0.0,
        tuning: flat.copyWith(smoothDecel: true),
        dt: 0.02,
      );
      expect(c.throttle, 840);
    });

    test('is disabled by default', () {
      final DriveShaper shaper = DriveShaper();
      shape(shaper, throttle: 1.0);
      final DriveCommand c = shape(shaper, throttle: 0.0);
      expect(c.throttle, 0);
    });

    test('reset clears the reference', () {
      final DriveShaper shaper = DriveShaper();
      shape(shaper, throttle: 1.0, tuning: flat.copyWith(smoothDecel: true));
      shaper.reset();
      final DriveCommand c = shape(
        shaper,
        throttle: 0.0,
        tuning: flat.copyWith(smoothDecel: true),
      );
      expect(c.throttle, 0);
    });
  });
}
