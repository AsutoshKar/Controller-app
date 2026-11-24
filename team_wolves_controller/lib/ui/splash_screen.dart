import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'widgets/hud_widgets.dart';
import 'widgets/wolve_watermark.dart';

/// Startup splash.
///
/// Cosmetic only: the progress bar is an animation, not a radio check. Nothing
/// connects, arms or sends a packet here. The status line is deliberately
/// labelled so it cannot be mistaken for a live link.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  /// Progress bar animation duration.
  static const Duration barDuration = Duration(milliseconds: 2200);

  /// Automatic entry into the console.
  static const Duration autoAdvance = Duration(milliseconds: 2400);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: SplashScreen.barDuration,
    )..forward();
    Future<void>.delayed(SplashScreen.autoAdvance, _finish);
  }

  void _finish() {
    if (_finished) {
      return;
    }
    _finished = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TacticalColors.backgroundDeep,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: TacticalBackground()),
            const Positioned.fill(
              child: WolveWatermark(opacity: 0.09),
            ),
            SafeArea(
              child: Center(
                child: AnimatedBuilder(
                  animation: _progress,
                  builder: (BuildContext context, Widget? child) {
                    final double t = _progress.value;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Image.asset(
                          'assets/images/team_wolves_logo.png',
                          width: 180,
                          height: 180,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'ROBO RACE',
                          style: TextStyle(
                            color: TacticalColors.primary,
                            fontSize: 13,
                            letterSpacing: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 26),
                        const Text(
                          'STARTING WOLVE BOT',
                          style: TextStyle(
                            color: TacticalColors.amber,
                            fontSize: 11,
                            letterSpacing: 3.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 260,
                          height: 6,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: Stack(
                              children: <Widget>[
                                Container(
                                  color: TacticalColors.line.withA(0.9),
                                ),
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: t,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: <Color>[
                                          TacticalColors.primary,
                                          TacticalColors.green,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                          color: TacticalColors.primary.withA(0.6),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          t < 0.45
                              ? 'INITIALIZING 100HZ TACTICAL LINK...'
                              : 'LOADING PRO CONSOLE...',
                          style: TextStyle(
                            color: TacticalColors.muted.withA(0.9),
                            fontSize: 9,
                            letterSpacing: 2.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'TAP TO SKIP',
                          style: TextStyle(
                            color: TacticalColors.muted.withA(0.6),
                            fontSize: 8,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
