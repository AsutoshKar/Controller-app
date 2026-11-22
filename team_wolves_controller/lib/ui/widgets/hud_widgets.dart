import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared palette. Cyan/teal is primary and speed, amber is torque/boost/
/// warning, green is confirmed armed/live, red is E-STOP and loss. Colour is
/// always paired with text.
abstract final class TacticalColors {
  static const Color background = Color(0xFF070B0D);
  static const Color backgroundDeep = Color(0xFF04070A);
  static const Color surface = Color(0xFF0E161A);
  static const Color surfaceAlt = Color(0xFF121C21);
  static const Color primary = Color(0xFF00E5C7);
  static const Color amber = Color(0xFFFFB020);
  static const Color green = Color(0xFF3DFF88);
  static const Color red = Color(0xFFFF3B30);
  static const Color text = Color(0xFFE6F1F2);
  static const Color muted = Color(0xFF6B8A8F);
  static const Color line = Color(0xFF1E2F35);
}

/// Alpha helper that works across Flutter releases.
///
/// `Color.withValues` only exists from Flutter 3.27, and `Color.withOpacity`
/// is deprecated on newer releases. `withAlpha` is stable everywhere, so every
/// tinted colour in the app goes through this extension.
extension ColorAlphaX on Color {
  Color withA(double opacity) {
    final double clamped = opacity.isNaN
        ? 0.0
        : (opacity < 0.0 ? 0.0 : (opacity > 1.0 ? 1.0 : opacity));
    return withAlpha((clamped * 255.0).round());
  }
}

/// Dark carbon grid with a radial vignette, used behind the splash and the
/// console. Pure `CustomPaint`, no image assets.
class TacticalBackground extends StatelessWidget {
  const TacticalBackground({super.key, this.child, this.gridStep = 26.0});

  final Widget? child;
  final double gridStep;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TacticalBackgroundPainter(gridStep: gridStep),
      child: child,
    );
  }
}

class _TacticalBackgroundPainter extends CustomPainter {
  const _TacticalBackgroundPainter({required this.gridStep});

  final double gridStep;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    final Paint base = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.5, -0.35),
        radius: 1.35,
        colors: const <Color>[Color(0xFF0C181D), Color(0xFF05080A)],
        stops: const <double>[0.0, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    final Paint grid = Paint()
      ..color = const Color(0xFF00E5C7).withA(0.055)
      ..strokeWidth = 1.0;

    final double step = math.max(gridStep, 8.0);
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // A few brighter structural lines for a "tactical" feel.
    final Paint accent = Paint()
      ..color = const Color(0xFF00E5C7).withA(0.10)
      ..strokeWidth = 1.2;
    final double third = size.height / 3.0;
    canvas.drawLine(Offset(0, third), Offset(size.width, third), accent);
    canvas.drawLine(Offset(size.width / 2.0, 0), Offset(size.width / 2.0, size.height), accent);

    final Paint vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.1,
        colors: <Color>[
          Colors.black.withA(0.0),
          Colors.black.withA(0.45),
        ],
        stops: const <double>[0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _TacticalBackgroundPainter oldDelegate) {
    return oldDelegate.gridStep != gridStep;
  }
}

/// Bordered panel with a small uppercase caption.
class PanelFrame extends StatelessWidget {
  const PanelFrame({
    super.key,
    required this.title,
    required this.child,
    this.accent = TacticalColors.line,
    this.padding = const EdgeInsets.fromLTRB(8, 6, 8, 6),
    this.titleColor,
  });

  final String title;
  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: TacticalColors.surface.withA(0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withA(0.85), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: (titleColor ?? TacticalColors.muted).withA(0.95),
              fontSize: 9,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Small monospace-ish readout.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.label,
    required this.value,
    this.color = TacticalColors.text,
    this.align = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final Color color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: TacticalColors.muted.withA(0.9),
            fontSize: 8,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w800,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// The status pill in the top HUD. Tapping it opens the connection dialog.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.text,
    required this.color,
    this.onTap,
    this.icon = Icons.circle,
  });

  final String text;
  final Color color;
  final VoidCallback? onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withA(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withA(0.75), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact segmented selector. Colour carries meaning and the labels carry
/// the actual meaning, so it stays readable in bright sunlight.
class SegmentedButtons<T> extends StatelessWidget {
  const SegmentedButtons({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.accent,
    this.height = 30,
    this.fontSize = 10,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final Color accent;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < options.length; i++) <Widget>[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _Segment(
                label: options[i].$2,
                selected: options[i].$1 == selected,
                accent: accent,
                fontSize: fontSize,
                onTap: () => onChanged(options[i].$1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.accent,
    required this.fontSize,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final double fontSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent.withA(0.30) : TacticalColors.surface.withA(0.4),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? accent : accent.withA(0.35),
              width: 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? TacticalColors.text : accent.withA(0.9),
              fontSize: fontSize,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// A deliberately oversized red control. It acts on pointer-down so there is
/// no animation or confirmation step between the driver and the stop command.
class EmergencyStopButton extends StatelessWidget {
  const EmergencyStopButton({super.key, required this.onPressed, this.latched = false});

  final VoidCallback onPressed;
  final bool latched;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onPressed(),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: TacticalColors.red.withA(latched ? 0.42 : 0.22),
          border: Border.all(color: TacticalColors.red, width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: TacticalColors.red.withA(latched ? 0.55 : 0.28),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.warning_amber_rounded,
                size: 26, color: TacticalColors.red.withA(latched ? 1.0 : 0.9)),
            const SizedBox(height: 2),
            const Text(
              'E-STOP',
              style: TextStyle(
                color: TacticalColors.red,
                fontSize: 17,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              latched ? 'LATCHED' : 'HOLD TO STOP',
              style: TextStyle(
                color: TacticalColors.red.withA(0.85),
                fontSize: 8,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small uppercase section label used inside the settings sheet.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color = TacticalColors.muted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 10,
        letterSpacing: 1.8,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

/// A labelled slider row used in Settings.
class TuningSlider extends StatelessWidget {
  const TuningSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.display,
    this.divisions,
    this.accent = TacticalColors.primary,
    this.onReset,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final Color accent;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 132,
          child: Text(
            label,
            style: TextStyle(
              color: TacticalColors.text.withA(0.9),
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: accent.withA(0.22),
              thumbColor: accent,
              overlayColor: accent.withA(0.18),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              label: display,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (onReset != null)
          IconButton(
            tooltip: 'Reset $label',
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt, size: 16, color: TacticalColors.muted),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
      ],
    );
  }
}

/// A simple on/off switch row.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(
          color: TacticalColors.text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                color: TacticalColors.muted.withA(0.9),
                fontSize: 10,
              ),
            ),
      value: value,
      activeColor: TacticalColors.primary,
      onChanged: onChanged,
    );
  }
}
