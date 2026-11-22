import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:team_wolves_controller/controller/drive_controller.dart';
import 'package:team_wolves_controller/controller/drive_shaper.dart';
import 'package:team_wolves_controller/protocol/protocol.dart';
import 'package:team_wolves_controller/transport/robot_transport.dart';

import 'support/fake_transport.dart';

void main() {
  late FakeTransport transport;
  late DriveController controller;
  late int nowMicros;

  setUp(() {
    nowMicros = 0;
    Protocol.resetSequenceForTest(0);
    transport = FakeTransport();
    controller = DriveController(clockMicros: () => nowMicros);
  });

  tearDown(() async {
    await controller.disconnectTransport();
    controller.dispose();
  });

  Future<void> attach({FakeTransport? withTransport}) async {
    await controller.attachTransport(withTransport ?? transport);
  }

  group('mode mapping', () {
    test('Torque + 35% maps to M1 with a 35/45 scale', () {
      controller.setProfile(DriveProfile.torque);
      controller.setPreset(PowerPreset.p35);
      expect(controller.requestedMode, 1);
      expect(controller.throttleScale, closeTo(35 / 45, 1e-9));
      expect(controller.torqueLimited, isFalse);
    });

    test('Torque + 65% maps to M1 unscaled and flags torque limited', () {
      controller.setProfile(DriveProfile.torque);
      controller.setPreset(PowerPreset.p65);
      expect(controller.requestedMode, 1);
      expect(controller.throttleScale, 1.0);
      expect(controller.torqueLimited, isTrue);
    });

    test('Torque + 100% maps to M1 unscaled and flags torque limited', () {
      controller.setProfile(DriveProfile.torque);
      controller.setPreset(PowerPreset.p100);
      expect(controller.requestedMode, 1);
      expect(controller.throttleScale, 1.0);
      expect(controller.torqueLimited, isTrue);
    });

    test('Speed + 35% maps to M2 with a 35/65 scale', () {
      controller.setProfile(DriveProfile.speed);
      controller.setPreset(PowerPreset.p35);
      expect(controller.requestedMode, 2);
      expect(controller.throttleScale, closeTo(35 / 65, 1e-9));
      expect(controller.torqueLimited, isFalse);
    });

    test('Speed + 65% is the M2 default and unscaled', () {
      expect(controller.profile, DriveProfile.speed);
      expect(controller.preset, PowerPreset.p65);
      expect(controller.requestedMode, 2);
      expect(controller.throttleScale, 1.0);
    });

    test('Speed + 100% maps to M3 unscaled', () {
      controller.setPreset(PowerPreset.p100);
      expect(controller.requestedMode, 3);
      expect(controller.throttleScale, 1.0);
    });

    test('BOOST forces M3 and removes the scale', () {
      controller.setPreset(PowerPreset.p35);
      controller.setBoostHeld(true);
      expect(controller.requestedMode, 3);
      expect(controller.throttleScale, 1.0);
      controller.setBoostHeld(false);
      expect(controller.requestedMode, 2);
      expect(controller.throttleScale, closeTo(35 / 65, 1e-9));
    });
  });

  group('terrain', () {
    test('selecting a terrain replaces the default expo and damping', () {
      controller.setTerrain(TerrainProfile.sandPebbles);
      expect(controller.terrain, TerrainProfile.sandPebbles);
      expect(controller.tuning.throttleExpo, 0.45);
      expect(controller.tuning.steeringExpo, 0.35);
      expect(controller.tuning.highSpeedTurnFactor, 0.72);
    });

    test('quick cycle visits every preset and wraps', () {
      expect(controller.terrain, TerrainProfile.normal);
      controller.cycleTerrain();
      expect(controller.terrain, TerrainProfile.sandPebbles);
      controller.cycleTerrain();
      expect(controller.terrain, TerrainProfile.plySlick);
      controller.cycleTerrain();
      expect(controller.terrain, TerrainProfile.fireSprint);
      controller.cycleTerrain();
      expect(controller.terrain, TerrainProfile.normal);
    });
  });

  group('arming', () {
    test('is rejected with no live link and sends nothing', () async {
      await attach();
      expect(controller.isLinkLive, isFalse);
      expect(controller.requestArm(), isFalse);
      expect(controller.notice, contains('NO LIVE LINK'));
      expect(transport.ofType(FrameType.arm), isEmpty);
    });

    test('is rejected when the sticks are off centre', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.disarmed));
      controller.setThrottle(0.40);
      expect(controller.requestArm(), isFalse);
      expect(controller.notice, contains('Center both joysticks'));
      expect(transport.ofType(FrameType.arm), isEmpty);
    });

    test('sends ARM=1 and shows ARMED only after ESP32 confirmation', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.disarmed));
      expect(controller.requestArm(), isTrue);
      expect(controller.armRequested, isTrue);
      expect(controller.armedConfirmed, isFalse);

      final List<Uint8List> armFrames = transport.ofType(FrameType.arm);
      expect(armFrames, hasLength(1));
      expect(armFrames.single[4], 1);

      transport.emit(telemetryFrame(state: RobotState.armed));
      expect(controller.armedConfirmed, isTrue);
    });

    test('OFF sends ARM=0 and clears drive intent', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.disarmed));
      controller.requestArm();
      controller.setThrottle(0.7);
      controller.requestDisarm();

      expect(controller.armRequested, isFalse);
      expect(controller.throttle, 0);
      final List<Uint8List> armFrames = transport.ofType(FrameType.arm);
      expect(armFrames.last[4], 0);
    });

    test('clears arm intent when the ESP32 reports FAILSAFE', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.disarmed));
      controller.requestArm();
      transport.emit(telemetryFrame(state: RobotState.failsafe));
      expect(controller.armRequested, isFalse);
      expect(controller.armedConfirmed, isFalse);
    });
  });

  group('E-STOP', () {
    test('acts immediately, clears every input and sends 0x06', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.disarmed));
      controller.requestArm();
      controller.setThrottle(0.9);
      controller.setSteering(-0.6);
      controller.setBoostHeld(true);
      controller.debugTick();
      final int before = transport.sent.length;

      controller.triggerEStop();

      expect(controller.estopLatched, isTrue);
      expect(controller.armRequested, isFalse);
      expect(controller.throttle, 0);
      expect(controller.steering, 0);
      expect(controller.boostHeld, isFalse);
      expect(transport.ofType(FrameType.eStop), hasLength(1));
      expect(transport.sent.length, greaterThan(before));
    });

    test('keeps the E-STOP flag on subsequent DRIVE frames', () async {
      await attach();
      controller.triggerEStop();
      controller.debugTick();
      final Uint8List drive = transport.ofType(FrameType.drive).last;
      expect(drive[4] & 0x02, 0x02);
      expect(readInt16LE(drive, 5), 0);
      expect(readInt16LE(drive, 7), 0);
    });

    test('outranks an arm request made afterwards', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.disarmed));
      controller.triggerEStop();
      expect(controller.requestArm(), isFalse);
      expect(controller.notice, contains('E-STOP LATCHED'));
      expect(transport.ofType(FrameType.arm), isEmpty);
    });

    test('reports a missing link instead of claiming a stop was delivered', () async {
      controller.triggerEStop();
      expect(controller.estopLatched, isTrue);
      expect(controller.notice, contains('NO LINK'));
    });

    test('deliberate OFF clears the local latch and re-enables arming', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.disarmed));
      controller.triggerEStop();
      expect(controller.estopLatched, isTrue);
      controller.requestDisarm();
      expect(controller.estopLatched, isFalse);
    });
  });

  group('link freshness', () {
    test('treats telemetry older than 650 ms as stale', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.disarmed));
      expect(controller.isLinkLive, isTrue);

      nowMicros += 700000;
      controller.pumpDiagnostics();

      expect(controller.isLinkLive, isFalse);
      expect(controller.telemetryAgeMs, 700);
    });

    test('a recovered link does not auto re-arm', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.disarmed));
      controller.requestArm();
      transport.emit(telemetryFrame(state: RobotState.armed));
      expect(controller.armedConfirmed, isTrue);

      nowMicros += 700000;
      controller.pumpDiagnostics();
      expect(controller.armRequested, isFalse);

      nowMicros += 1000;
      transport.emit(telemetryFrame(state: RobotState.armed));
      expect(controller.isLinkLive, isTrue);
      expect(controller.armRequested, isFalse);
      expect(controller.armedConfirmed, isFalse);
    });

    test('reports no RTT before a valid echo and a value afterwards', () async {
      await attach();
      expect(controller.rttMs, isNull);

      controller.debugTick();
      final Uint8List drive = transport.ofType(FrameType.drive).last;
      final int seq = drive[2];
      nowMicros += 4000;
      transport.emit(telemetryFrame(sequence: seq, state: RobotState.disarmed));
      expect(controller.rttMs, 4);
    });

    test('ignores an echo whose sequence was never sent', () async {
      await attach();
      transport.emit(telemetryFrame(sequence: 200, state: RobotState.disarmed));
      expect(controller.rttMs, isNull);
      expect(controller.telemetrySeen, isTrue);
    });
  });

  group('transport switching', () {
    test('clears input, arm state and diagnostics', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.armed));
      controller.requestArm();
      controller.setThrottle(0.8);
      controller.setProfile(DriveProfile.torque);

      final FakeTransport second = FakeTransport(kind: TransportKind.ble);
      await attach(withTransport: second);

      expect(controller.transportKind, TransportKind.ble);
      expect(controller.throttle, 0);
      expect(controller.armRequested, isFalse);
      expect(controller.isLinkLive, isFalse);
      expect(controller.rttMs, isNull);
      expect(transport.ready, isFalse);
      expect(transport.disposeCalls, greaterThanOrEqualTo(1));
    });

    test('sends SET_MODE on attach and again when BOOST is pressed', () async {
      await attach();
      final List<Uint8List> initial = transport.ofType(FrameType.setMode);
      expect(initial, isNotEmpty);
      expect(initial.last[4], 2);

      controller.setBoostHeld(true);
      controller.pumpDiagnostics();
      final List<Uint8List> after = transport.ofType(FrameType.setMode);
      expect(after.last[4], 3);

      controller.setBoostHeld(false);
      controller.pumpDiagnostics();
      expect(transport.ofType(FrameType.setMode).last[4], 2);
    });

    test('never sends SET_MODE on every DRIVE tick', () async {
      await attach();
      final int before = transport.ofType(FrameType.setMode).length;
      for (int i = 0; i < 20; i++) {
        controller.debugTick();
      }
      expect(transport.ofType(FrameType.setMode).length, before);
    });
  });

  group('lifecycle', () {
    test('backgrounding zeroes inputs, disarms and stops the DRIVE timer', () async {
      await attach();
      transport.emit(telemetryFrame(state: RobotState.disarmed));
      controller.requestArm();
      controller.setThrottle(0.9);
      controller.setBoostHeld(true);
      controller.debugTick();
      final int before = transport.sent.length;

      controller.handleLifecycleStopped();

      expect(controller.throttle, 0);
      expect(controller.boostHeld, isFalse);
      expect(controller.armRequested, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(transport.sent.length, before);
    });

    test('resume restarts an unarmed session only', () async {
      await attach();
      controller.handleLifecycleStopped();
      controller.handleLifecycleResumed();

      expect(controller.armRequested, isFalse);
      controller.debugTick();
      expect(transport.ofType(FrameType.drive), isNotEmpty);
      final Uint8List drive = transport.ofType(FrameType.drive).last;
      expect(drive[4] & 0x01, 0); // not armed
    });
  });

  group('diagnostics counters', () {
    test('counts malformed frames without treating them as live', () async {
      await attach();
      final Uint8List bad = Uint8List.fromList(telemetryFrame());
      bad[bad.length - 1] ^= 0xFF;
      transport.emit(bad);
      expect(controller.malformedFrames, 1);
      expect(controller.isLinkLive, isFalse);
    });

    test('stores transport counters', () async {
      await attach();
      controller.debugTick();
      expect(controller.txPackets, greaterThan(0));
      expect(controller.txBytes, greaterThan(0));
    });
  });
}
