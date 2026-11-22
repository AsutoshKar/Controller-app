import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../controller/drive_shaper.dart';
import 'hud_widgets.dart';

/// A single-axis raw stick.
///
/// Uses a raw [Listener] with pointer IDs, so two sticks and the hold paddles
/// can all be driven at the same time. Each stick owns exactly one pointer:
/// a second finger landing on an already-held stick is ignored, which prevents
/// a stray palm from yanking the axis.
///
/// * Fixed origin (default): the knob springs back to the centre on release.
/// * Floating origin: a touchdown anchors the stick wherever the finger
///   landed, starting from neutral.
///
/// The widget reports a value in `-1..1`; it never clamps to a deadband and
/// never talks to the transport.
class ProJoystick extends StatefulWidget {
  const ProJoystick({
    super.key,
    required this.axis,
    required this.label,
    required this.accent,
    required this.onChanged,
    required this.value,
    this.onReleased,
    this.floating = false,
    this.sublabel = '',
  });

  final Axis axis;
  final String label;
  final String sublabel;
  final Color accent;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReleased;
  final bool floating;

  /// Externally owned value, used when no pointer is active so the knob snaps
  /// back immediately when the controller clears input.
  final double value;

  @override
  State<ProJoystick> createState() => _ProJoystickState();
}

class _ProJoystickState extends State<ProJoystick> {
  final GlobalKey _key = GlobalKey();

  int? _pointerId;
  Offset _origin = Offset.zero;
  double _localValue = 0.0;

  double get _displayValue => _pointerId == null ? widget.value : _localValue;

  RenderBox? _box() {
    final RenderObject? object = _key.currentContext?.findRenderObject();
    return object is RenderBox ? object : null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final double knob = math.min(width, height) * 0.40;
        final bool vertical = widget.axis == Axis.vertical;
        final double extent = (vertical ? height : width) - knob;
        final double half = math.max(extent / 2.0, 1.0);

        final double shown = _displayValue.clamp(-1.0, 1.0).toDouble();
        final double dx = vertical ? 0.0 : half * shown;
        final double dy = vertical ? -half * shown : 0.0;

        return Listener(
          key: _key,
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // Track.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(knob * 0.45),
                    color: TacticalColors.surface.withA(0.55),
                    border: Border.all(
                      color: TacticalColors.line.withA(0.9),
                      width: 1,
                    ),
                  ),
                ),
              ),
              // Centre reference line.
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      width: vertical ? knob * 1.15 : 1,
                      height: vertical ? 1 : knob * 1.15,
                      color: TacticalColors.muted.withA(0.45),
                    ),
                  ),
                ),
              ),
              // Knob.
              Positioned(
                left: width / 2 + dx - knob / 2,
                top: height / 2 + dy - knob / 2,
                child: IgnorePointer(
                  child: Container(
                    width: knob,
                    height: knob,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: <Color>[
                          widget.accent.withA(0.85),
                          widget.accent.withA(0.18),
                        ],
                        stops: const <double>[0.25, 1.0],
                      ),
                      border: Border.all(
                        color: widget.accent.withA(0.9),
                        width: 1.5,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: widget.accent.withA(0.35),
                          blurRadius: knob * 0.5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: knob * 0.30,
                      height: knob * 0.30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.accent.withA(0.75),
                      ),
                    ),
                  ),
                ),
              ),
              // Caption.
              Positioned(
                left: 0,
                right: 0,
                bottom: 4,
                child: IgnorePointer(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: widget.accent.withA(0.85),
                      fontSize: 10,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointerId != null) {
      return;
    }
    final RenderBox? box = _box();
    if (box == null) {
      return;
    }
    _pointerId = event.pointer;
    final Offset local = box.globalToLocal(event.position);
    if (widget.floating) {
      _origin = local;
      // A floating touchdown starts at neutral, so the first reported value is
      // zero until the finger actually moves.
      _localValue = 0.0;
      widget.onChanged(0.0);
    } else {
      _origin = box.size.center(Offset.zero);
      _applyLocal(local);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointerId) {
      return;
    }
    final RenderBox? box = _box();
    if (box == null) {
      return;
    }
    _applyLocal(box.globalToLocal(event.position));
  }

  void _applyLocal(Offset local) {
    final RenderBox? box = _box();
    if (box == null) {
      return;
    }
    final double width = box.size.width;
    final double height = box.size.height;
    final double knob = math.min(width, height) * 0.40;
    final bool vertical = widget.axis == Axis.vertical;
    final double extent = (vertical ? height : width) - knob;
    final double half = math.max(extent / 2.0, 1.0);

    final double raw;
    if (vertical) {
      // Dragging up is forward.
      raw = -(local.dy - _origin.dy) / half;
    } else {
      raw = (local.dx - _origin.dx) / half;
    }
    final double next = raw.isNaN ? 0.0 : raw.clamp(-1.0, 1.0).toDouble();
    _localValue = next;
    widget.onChanged(next);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointerId) {
      return;
    }
    _release();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointerId) {
      return;
    }
    _release();
  }

  void _release() {
    _pointerId = null;
    _localValue = 0.0;
    widget.onChanged(0.0);
    widget.onReleased?.call();
  }
}

/// A hold paddle (BOOST, ZERO PIVOT).
///
/// Also a raw [Listener]: onPointerDown engages, onPointerUp/onPointerCancel
/// releases. It never toggles, so a lost pointer can never leave an override
/// stuck on.
class HoldPaddle extends StatefulWidget {
  const HoldPaddle({
    super.key,
    required this.label,
    required this.accent,
    required this.onPressed,
    required this.onReleased,
    this.active = false,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final Color accent;
  final VoidCallback onPressed;
  final VoidCallback onReleased;
  final bool active;

  @override
  State<HoldPaddle> createState() => _HoldPaddleState();
}

class _HoldPaddleState extends State<HoldPaddle> {
  int? _pointerId;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent event) {
        if (_pointerId != null) {
          return;
        }
        _pointerId = event.pointer;
        widget.onPressed();
      },
      onPointerUp: (PointerUpEvent event) {
        if (event.pointer != _pointerId) {
          return;
        }
        _pointerId = null;
        widget.onReleased();
      },
      onPointerCancel: (PointerCancelEvent event) {
        if (event.pointer != _pointerId) {
          return;
        }
        _pointerId = null;
        widget.onReleased();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        // This control is only 34 px tall on the landscape console. Keep its
        // vertical padding small enough for the label and subtitle to fit.
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: widget.active
              ? widget.accent.withA(0.28)
              : TacticalColors.surface.withA(0.55),
          border: Border.all(
            color: widget.active
                ? widget.accent
                : widget.accent.withA(0.45),
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.active ? TacticalColors.text : widget.accent,
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: TacticalColors.muted,
                  fontSize: 8.5,
                  letterSpacing: 1.0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Converts a `-1..1` axis value to a short label such as `+45%`.
String axisLabel(double value) {
  final int percent = (value.abs() * 100).round();
  if (percent == 0) {
    return '0%';
  }
  final String sign = value > 0 ? '+' : '-';
  return '$sign$percent%';
}

/// Converts a signed thousandths command to a compact display value.
String countsLabel(int value) {
  final int percent = (value.abs() / 10).round();
  if (percent == 0) {
    return '0%';
  }
  return '${value > 0 ? '+' : '-'}$percent%';
}

/// Terrain badge helper shared by the console and settings sheet.
String terrainShortLabel(TerrainProfile terrain) {
  switch (terrain) {
    case TerrainProfile.normal:
      return 'NORMAL';
    case TerrainProfile.sandPebbles:
      return 'SAND';
    case TerrainProfile.plySlick:
      return 'PLY';
    case TerrainProfile.fireSprint:
      return 'FIRE';
  }
}
