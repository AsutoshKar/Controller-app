import 'package:material_ui/material_ui.dart';

import '../controller/drive_controller.dart';
import '../controller/drive_shaper.dart';
import '../protocol/protocol.dart';
import '../transport/robot_transport.dart';
import 'connection_popup.dart';
import 'settings_sheet.dart';
import 'widgets/hud_widgets.dart';
import 'widgets/pro_joystick.dart';
import 'widgets/wolve_watermark.dart';

/// Main race console.
///
/// Two-handed landscape layout: ~34% left (throttle + BOOST), ~32% centre
/// (presets, profile, terrain, ARM, E-STOP), ~34% right (steering + pivot).
/// Nothing needs scrolling to drive or to stop.
class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key, required this.controller});

  final DriveController controller;

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Anything except a full resume zeroes the drive. This includes inactive,
    // which fires when a system dialog or the notification shade appears.
    if (state == AppLifecycleState.resumed) {
      widget.controller.handleLifecycleResumed();
    } else {
      widget.controller.handleLifecycleStopped();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        return Scaffold(
          backgroundColor: TacticalColors.background,
          body: Stack(
            children: <Widget>[
              const Positioned.fill(child: TacticalBackground()),
              const Positioned.fill(child: WolveWatermark(opacity: 0.12)),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    _HudBar(controller: widget.controller),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Expanded(
                              flex: 34,
                              child: _LeftPanel(controller: widget.controller),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 32,
                              child: _CenterPanel(controller: widget.controller),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 34,
                              child: _RightPanel(controller: widget.controller),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _NoticeBar(controller: widget.controller),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

class _HudBar extends StatelessWidget {
  const _HudBar({required this.controller});

  final DriveController controller;

  String _statusText(DriveController c) {
    if (c.transportKind == null) {
      return 'OFFLINE';
    }
    if (c.transportStatus == TransportStatus.connecting) {
      return 'CONNECTING';
    }
    if (c.isLinkLive) {
      return c.transportKind == TransportKind.udp ? 'WIFI LIVE' : 'BLE LIVE';
    }
    if (c.transportStatus == TransportStatus.error) {
      return 'LINK ERROR';
    }
    if (c.transportStatus == TransportStatus.connected) {
      return 'NO TELEMETRY';
    }
    return 'DISCONNECTED';
  }

  Color _statusColor(DriveController c) {
    if (c.isLinkLive) {
      return TacticalColors.green;
    }
    if (c.transportStatus == TransportStatus.error) {
      return TacticalColors.red;
    }
    if (c.transportStatus == TransportStatus.connected) {
      return TacticalColors.amber;
    }
    return TacticalColors.muted;
  }

  @override
  Widget build(BuildContext context) {
    final DriveController c = controller;
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: <Widget>[
            StatusPill(
              text: _statusText(c),
              color: _statusColor(c),
              icon: c.transportKind == TransportKind.ble
                  ? Icons.bluetooth
                  : Icons.wifi,
              onTap: () => ConnectionPopup.show(context, c),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HudStat(
                'ESP32',
                c.telemetryStateLabel,
                c.telemetryState == RobotState.armed
                    ? TacticalColors.green
                    : (c.telemetryState >= RobotState.failsafe
                        ? TacticalColors.red
                        : TacticalColors.text),
              ),
            ),
            Expanded(
              child: _HudStat('L', '${c.leftPercent}%', TacticalColors.amber),
            ),
            Expanded(
              child: _HudStat('R', '${c.rightPercent}%', TacticalColors.amber),
            ),
            Expanded(
              child: _HudStat('MODE', c.confirmedModeLabel, TacticalColors.primary),
            ),
            Expanded(
              child: _HudStat(
                'RTT',
                c.rttMs == null ? '--' : '${c.rttMs}ms',
                TacticalColors.text,
              ),
            ),
            Expanded(
              child: _HudStat('DROPS', '${c.firmwareDrops}', TacticalColors.text),
            ),
            Expanded(
              child: _HudStat('PACK', '${c.packPercent}%', TacticalColors.amber),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => SettingsSheet.show(context, c),
              icon: const Icon(Icons.settings, size: 20, color: TacticalColors.muted),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _HudStat extends StatelessWidget {
  const _HudStat(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: TacticalColors.muted.withA(0.85),
              fontSize: 7,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 11,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w800,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left / right panels
// ---------------------------------------------------------------------------

class _LeftPanel extends StatelessWidget {
  const _LeftPanel({required this.controller});

  final DriveController controller;

  @override
  Widget build(BuildContext context) {
    final DriveController c = controller;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 34,
          child: HoldPaddle(
            label: 'BOOST 100%',
            subtitle: 'HOLD · M3',
            accent: TacticalColors.amber,
            active: c.boostHeld,
            onPressed: () => c.setBoostHeld(true),
            onReleased: () => c.setBoostHeld(false),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: PanelFrame(
            title: 'THROTTLE  ${axisLabel(c.throttle)}',
            accent: TacticalColors.amber,
            child: ProJoystick(
              axis: Axis.vertical,
              label: 'FWD / REV',
              accent: TacticalColors.amber,
              value: c.throttle,
              floating: c.tuning.floatingSticks,
              onChanged: c.setThrottle,
            ),
          ),
        ),
      ],
    );
  }
}

class _RightPanel extends StatelessWidget {
  const _RightPanel({required this.controller});

  final DriveController controller;

  @override
  Widget build(BuildContext context) {
    final DriveController c = controller;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 34,
          child: HoldPaddle(
            label: 'ZERO PIVOT',
            subtitle: 'HOLD · ZERO THROTTLE',
            accent: TacticalColors.primary,
            active: c.pivotHeld,
            onPressed: () => c.setPivotHeld(true),
            onReleased: () => c.setPivotHeld(false),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: PanelFrame(
            title: 'STEERING  ${axisLabel(c.steering)}',
            accent: TacticalColors.primary,
            child: ProJoystick(
              axis: Axis.horizontal,
              label: 'LEFT / RIGHT',
              accent: TacticalColors.primary,
              value: c.steering,
              floating: c.tuning.floatingSticks,
              onChanged: c.setSteering,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Centre panel
// ---------------------------------------------------------------------------

class _CenterPanel extends StatelessWidget {
  const _CenterPanel({required this.controller});

  final DriveController controller;

  @override
  Widget build(BuildContext context) {
    final DriveController c = controller;
    return Column(
      children: <Widget>[
        SegmentedButtons<PowerPreset>(
          options: const <(PowerPreset, String)>[
            (PowerPreset.p35, '35%'),
            (PowerPreset.p65, '65%'),
            (PowerPreset.p100, '100%'),
          ],
          selected: c.preset,
          onChanged: c.setPreset,
          accent: TacticalColors.amber,
        ),
        const SizedBox(height: 4),
        SegmentedButtons<DriveProfile>(
          options: const <(DriveProfile, String)>[
            (DriveProfile.torque, 'TORQUE'),
            (DriveProfile.speed, 'SPEED'),
          ],
          selected: c.profile,
          onChanged: c.setProfile,
          accent: TacticalColors.primary,
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 12,
          child: Align(
            alignment: Alignment.centerLeft,
            child: c.torqueLimited
                ? const Text(
                    'TORQUE LIMITED',
                    style: TextStyle(
                      color: TacticalColors.amber,
                      fontSize: 8,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : Text(
                    'SCALE ${(c.throttleScale * 100).round()}%',
                    style: TextStyle(
                      color: TacticalColors.muted.withA(0.8),
                      fontSize: 8,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 3),
        _TerrainRow(controller: c),
        const SizedBox(height: 4),
        _ArmSwitch(controller: c),
        const SizedBox(height: 4),
        Expanded(
          child: EmergencyStopButton(
            onPressed: c.triggerEStop,
            latched: c.estopLatched,
          ),
        ),
      ],
    );
  }
}

class _TerrainRow extends StatelessWidget {
  const _TerrainRow({required this.controller});

  final DriveController controller;

  @override
  Widget build(BuildContext context) {
    final DriveController c = controller;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: c.cycleTerrain,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: TacticalColors.surface.withA(0.6),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: TacticalColors.line),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.terrain, size: 12, color: TacticalColors.primary),
              const SizedBox(width: 5),
              const Text(
                'TERRAIN',
                style: TextStyle(
                  color: TacticalColors.muted,
                  fontSize: 8,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                c.terrain.label,
                style: const TextStyle(
                  color: TacticalColors.primary,
                  fontSize: 9,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                c.terrain.hint,
                style: TextStyle(
                  color: TacticalColors.muted.withA(0.8),
                  fontSize: 8,
                ),
              ),
              const Icon(Icons.swap_horiz, size: 12, color: TacticalColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArmSwitch extends StatelessWidget {
  const _ArmSwitch({required this.controller});

  final DriveController controller;

  @override
  Widget build(BuildContext context) {
    final DriveController c = controller;
    final bool confirmed = c.armedConfirmed;
    final bool requested = c.armRequested;
    final Color color = confirmed
        ? TacticalColors.green
        : (requested ? TacticalColors.amber : TacticalColors.muted);
    final String label = confirmed ? 'ON (ARMED)' : (requested ? 'ARMING...' : 'OFF');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (c.armRequested) {
            c.requestDisarm();
          } else {
            c.requestArm();
          }
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withA(0.16),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color, width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                confirmed ? Icons.check_circle_outline : Icons.power_settings_new,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.controller});

  final DriveController controller;

  @override
  Widget build(BuildContext context) {
    final DriveController c = controller;
    final Color color = c.estopLatched
        ? TacticalColors.red
        : (c.isLinkLive ? TacticalColors.green : TacticalColors.amber);
    return Container(
      height: 15,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: TacticalColors.backgroundDeep.withA(0.6),
      child: Text(
        c.notice,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color.withA(0.95),
          fontSize: 8.5,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
