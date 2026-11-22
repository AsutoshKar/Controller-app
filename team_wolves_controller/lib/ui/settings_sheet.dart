import 'package:flutter/material.dart';

import '../controller/drive_controller.dart';
import '../controller/drive_shaper.dart';
import 'widgets/hud_widgets.dart';

/// Settings drawer.
///
/// Everything here is in memory for the prototype: no persistence, no
/// accounts, no cloud sync. The telemetry inspector is included so the owner
/// can verify what the app actually received rather than what it hoped for.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.controller});

  final DriveController controller;

  static Future<void> show(BuildContext context, DriveController controller) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TacticalColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (BuildContext context) => SettingsSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final DriveController c = controller;
        final DriveTuning tuning = c.tuning;

        return FractionallySizedBox(
          heightFactor: 0.92,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.tune, size: 16, color: TacticalColors.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'SETTINGS',
                      style: TextStyle(
                        color: TacticalColors.text,
                        fontSize: 13,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'IN-MEMORY · NOT SAVED',
                      style: TextStyle(
                        color: TacticalColors.muted.withA(0.8),
                        fontSize: 8,
                        letterSpacing: 1.2,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close, size: 18, color: TacticalColors.muted),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const Divider(color: TacticalColors.line, height: 10),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      const SectionLabel('STRAIGHT LINE'),
                      const SizedBox(height: 2),
                      TuningSlider(
                        label: 'L/R trim',
                        value: tuning.trim,
                        min: -0.15,
                        max: 0.15,
                        divisions: 30,
                        display: tuning.trim.toStringAsFixed(3),
                        onChanged: c.setTrim,
                        onReset: c.resetTrim,
                      ),
                      const SizedBox(height: 6),
                      const SectionLabel('INPUT SHAPING'),
                      const SizedBox(height: 2),
                      TuningSlider(
                        label: 'Throttle expo',
                        value: tuning.throttleExpo,
                        min: 0.0,
                        max: 0.70,
                        divisions: 70,
                        display: tuning.throttleExpo.toStringAsFixed(2),
                        onChanged: c.setThrottleExpo,
                      ),
                      TuningSlider(
                        label: 'Steering expo',
                        value: tuning.steeringExpo,
                        min: 0.0,
                        max: 0.70,
                        divisions: 70,
                        display: tuning.steeringExpo.toStringAsFixed(2),
                        onChanged: c.setSteeringExpo,
                      ),
                      TuningSlider(
                        label: 'Reverse cap',
                        value: tuning.reverseCap,
                        min: 0.30,
                        max: 1.00,
                        divisions: 70,
                        display: '${(tuning.reverseCap * 100).round()}%',
                        onChanged: c.setReverseCap,
                      ),
                      const SizedBox(height: 4),
                      ToggleRow(
                        label: 'Smooth decel',
                        subtitle: 'Limits drops in throttle magnitude. Not a brake.',
                        value: tuning.smoothDecel,
                        onChanged: c.setSmoothDecel,
                      ),
                      const SizedBox(height: 4),
                      const SectionLabel('CONTROLS'),
                      const SizedBox(height: 2),
                      ToggleRow(
                        label: 'Floating sticks',
                        subtitle: 'Touchdown anchors the stick at neutral.',
                        value: tuning.floatingSticks,
                        onChanged: c.setFloatingSticks,
                      ),
                      ToggleRow(
                        label: 'Haptics',
                        subtitle: 'Deadband exit, 50%, 95%+, mode changes, link loss.',
                        value: tuning.haptics,
                        onChanged: c.setHaptics,
                      ),
                      const SizedBox(height: 8),
                      const SectionLabel('PACK'),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Duty-based estimate',
                                  style: TextStyle(
                                    color: TacticalColors.text.withA(0.9),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Not measured charge or voltage. Never a cutoff.',
                                  style: TextStyle(
                                    color: TacticalColors.muted.withA(0.85),
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatChip(label: 'USED', value: '${c.packPercent}%'),
                          const SizedBox(width: 10),
                          StatChip(label: 'PACK TIME', value: c.packElapsed),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: c.resetPack,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: TacticalColors.amber.withA(0.18),
                              foregroundColor: TacticalColors.amber,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              minimumSize: const Size(0, 30),
                            ),
                            child: const Text(
                              'NEW PACK',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const SectionLabel('TELEMETRY INSPECTOR'),
                      const SizedBox(height: 4),
                      _InspectorTile('STATE', c.telemetryStateLabel),
                      _InspectorTile('MODE', '${c.confirmedModeLabel} (requested M${c.requestedMode})'),
                      _InspectorTile('L / R OUTPUT', '${c.leftPercent}% / ${c.rightPercent}%'),
                      _InspectorTile('DROPS', '${c.firmwareDrops}'),
                      _InspectorTile(
                        'RTT',
                        c.rttMs == null ? '-- (no sample)' : '${c.rttMs} ms echo',
                      ),
                      _InspectorTile(
                        'TELEMETRY AGE',
                        c.telemetryAgeMs == null
                            ? '--'
                            : '${c.telemetryAgeMs} ms'
                                '${c.isLinkLive ? '' : '  (STALE)'}',
                      ),
                      _InspectorTile('LAST SEQ', '${c.telemetrySequence}'),
                      _InspectorTile('MALFORMED RX', '${c.malformedFrames}'),
                      _InspectorTile('TX / RX BYTES', '${c.txBytes} / ${c.rxBytes}'),
                      const SizedBox(height: 10),
                      Text(
                        'Tuning here changes app-side command shaping only. '
                        'Firmware deadband, expo, slew, breakaway floor and '
                        'skid-steer mixing still apply, so a 35% selection is '
                        'not a guaranteed wheel-duty percentage.',
                        style: TextStyle(
                          color: TacticalColors.muted.withA(0.8),
                          fontSize: 9,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InspectorTile extends StatelessWidget {
  const _InspectorTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                color: TacticalColors.muted.withA(0.9),
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: TacticalColors.text,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
