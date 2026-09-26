import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Liquid-glass surface primitive — a faithful clone of the primitive that
/// ships in a real production app (iterated through ~20 CI builds and daily
/// driver use). Pure Flutter, no dependencies, no platform channels.
///
/// Drop this file into `lib/ui/`. Everything is a parameter because glass
/// taste is subjective: blur on/off, scrim depth, rim brightness, press
/// physics, solid fallback for a settings toggle.
///
/// What it draws (bottom to top):
/// 1. optional `BackdropFilter` blur of everything painted beneath it
///    (`blurSigma > 0`; **`blurSigma == 0` skips the filter layer entirely** —
///    no saveLayer at all; that is the "clear glass" tier the app settled on)
/// 2. a near-transparent theme-aware scrim with a top-left glint
/// 3. your [child]
/// 4. an optional press overlay: spring scale-up + a radial glow that follows
///    the pointer (observe-only — wrapped taps still work)
/// 5. a directional rim light via [GlassRimPainter] (bright top-left edge,
///    dark bottom-right), optionally with chromatic-aberration strokes
///
/// Pitfalls this class exists to avoid (see SKILL.md / pitfalls.md):
/// - directional rims are a CustomPaint stroke, NOT a non-uniform Border on a
///   BoxDecoration (release mode silently paints a rectangle over the radius)
/// - there is deliberately no BackdropFilter in the press overlay: a moving
///   lens ghosts one frame behind its rim and Transform-stretches its sample

/// Values inlined from the shipping app's theme so this file stays
/// self-contained (its `UniMailTokens`): solid fallback surfaces.
const Color kGlassSurfaceCard = Color(0xFFFFFFFF);
const Color kGlassSurfaceCardDark = Color(0xFF101F33);

class GlassSurface extends StatefulWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 18,
    this.blurSigma = 18,
    this.pressScale = 1.03,
    this.vibrancy,
    this.tint,
    this.borderColor,
    this.boxShadow,
    this.enabled = true,
  });

  final Widget child;

  /// Resting blur strength. `0` = no filter layer AT ALL (clear glass tier).
  final double blurSigma;

  /// Press bulge multiplier target; `1.0` disables the press interaction.
  final double pressScale;
  final double borderRadius;

  /// Glass scrim override. Default: white glass in light mode, near-invisible
  /// dark navy in dark mode (real users push transparency to the floor).
  final Color? tint;

  /// Backdrop luminance signal in 0..1 (bright content behind -> higher).
  /// null = unknown, treated as neutral 0.5. Drives scrim depth, blur and rim
  /// brightness so the glass reads near-invisible over dark content and picks
  /// up contrast over bright content.
  final double? vibrancy;
  final Color? borderColor;
  final BoxShadow? boxShadow;

  /// false = solid themed surface fallback (for a settings toggle or
  /// reduce-transparency accessibility mode).
  final bool enabled;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 1,
  );

  /// Under-damped: springs up fast with a little overshoot, like Apple's.
  static final SpringDescription _spring =
      SpringDescription.withDampingRatio(
    mass: 1,
    ratio: 0.55,
    stiffness: 320,
  );

  Offset _touch = Offset.zero;

  void _animatePressTo(double target) {
    _press.animateWith(
      SpringSimulation(_spring, _press.value, target, 0),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(widget.borderRadius);

    // vibrancy is already a 0 (dark) .. 1 (bright) signal.
    final t = (widget.vibrancy ?? 0.5).clamp(0.0, 1.0);
    // Brighter backdrop -> deeper blur (floats 12..24dp for the default 18)
    // so colours melt together instead of fighting the labels.
    final effectiveBlur = lerpDouble(
      widget.blurSigma - 4,
      widget.blurSigma + 6,
      t,
    )!;

    Widget surface = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: widget.enabled
            ? null
            : (dark ? kGlassSurfaceCardDark : kGlassSurfaceCard),
        boxShadow: widget.boxShadow == null ? null : [widget.boxShadow!],
      ),
      child: widget.enabled
          ? AnimatedBuilder(
              animation: _press,
              builder: (context, _) {
                final press = _press.value;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    Widget glass = DecoratedBox(
                        // One gradient, two jobs: top-left glint + scrim.
                        // Dark-mode glint is smaller (too bright looks dirty
                        // on navy).
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _glassColors(dark, widget.tint, t),
                            stops: const [0, 0.3],
                          ),
                        ),
                        child: Stack(
                          children: [
                            widget.child,
                            if (press > 0)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        center: _touchAlignment(
                                          constraints.biggest,
                                        ),
                                        radius: 1.1,
                                        colors: [
                                          Colors.white
                                              .withValues(alpha: 0.2 * press),
                                          Colors.transparent,
                                        ],
                                      ),
                                      backgroundBlendMode: BlendMode.plus,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    );
                    if (widget.blurSigma > 0) {
                      // blurSigma 0 = skip the filter layer ENTIRELY (not a
                      // sigma-0 filter) — saves a saveLayer.
                      glass = BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: effectiveBlur + 6 * press,
                          sigmaY: effectiveBlur + 6 * press,
                        ),
                        child: glass,
                      );
                    }
                    return glass;
                  },
                );
              },
            )
          : widget.child,
    );

    // Directional rim via CustomPaint stroke. A non-uniform Border on a
    // BoxDecoration with a borderRadius asserts in debug and silently paints
    // an axis-aligned rectangle in release — never do that.
    surface = CustomPaint(
      foregroundPainter: GlassRimPainter(
        borderRadius: widget.borderRadius,
        borderColor: widget.borderColor,
        vibrancy: t,
      ),
      child: surface,
    );

    if (widget.enabled && widget.pressScale > 1) {
      surface = Listener(
        // Observe-only: never consumes events, so wrapped taps keep working.
        onPointerDown: (event) {
          setState(() => _touch = event.localPosition);
          _animatePressTo(1);
        },
        onPointerMove: (event) {
          if (_press.value > 0 || _press.isAnimating) {
            setState(() => _touch = event.localPosition);
          }
        },
        onPointerUp: (_) => _animatePressTo(0),
        onPointerCancel: (_) => _animatePressTo(0),
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) => Transform.scale(
            scale: 1 + (widget.pressScale - 1) * _press.value,
            child: child,
          ),
          child: surface,
        ),
      );
    }
    return surface;
  }

  Alignment _touchAlignment(Size size) {
    if (size.isEmpty) return Alignment.center;
    return Alignment(
      (_touch.dx / size.width).clamp(0.0, 1.0) * 2 - 1,
      (_touch.dy / size.height).clamp(0.0, 1.0) * 2 - 1,
    );
  }

  /// [0] = top-left glint, [1] = main scrim. Near-transparent by design:
  /// every real user pushes transparency further than you expect. Vibrancy
  /// curve: dark mode rests at ~8% navy and deepens to 18% over bright
  /// content; light mode deepens the white scrim the brighter the backdrop.
  static List<Color> _glassColors(bool dark, Color? tint, double t) {
    if (tint != null) return [tint, tint];
    return dark
        ? [
            Colors.white.withValues(alpha: lerpDouble(0.02, 0.06, t)!),
            const Color(0xFF101F33)
                .withValues(alpha: lerpDouble(0.08, 0.18, t)!),
          ]
        : [
            Colors.white.withValues(alpha: lerpDouble(0.12, 0.32, t)!),
            Colors.white.withValues(alpha: lerpDouble(0.1, 0.28, t)!),
          ];
  }
}

/// Directional rim light: one stroked round-rect whose colour is a gradient
/// from bright top-left to dark bottom-right, optionally with two faint
/// magenta/cyan strokes for a chromatic-aberration hint (small lenses only).
/// The brighter the backdrop (vibrancy), the brighter the whole rim.
class GlassRimPainter extends CustomPainter {
  GlassRimPainter({
    required this.borderRadius,
    required this.vibrancy,
    this.borderColor,
    this.chromatic = false,
  });

  final double borderRadius;
  final double vibrancy;
  final Color? borderColor;
  final bool chromatic;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(borderRadius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (chromatic) {
      // Chromatic aberration: magenta outer, cyan inner, very faint — only
      // visible under strong light.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(-0.4), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x28FF8AE2),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1.2), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x2880E4FF),
      );
    }
    if (borderColor != null) {
      paint.color = borderColor!;
    } else {
      paint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: lerpDouble(0.45, 0.7, vibrancy)!),
          Colors.white.withValues(alpha: lerpDouble(0.25, 0.4, vibrancy)!),
          Colors.white.withValues(alpha: lerpDouble(0.08, 0.18, vibrancy)!),
        ],
        stops: const [0, 0.5, 1],
      ).createShader(rect);
    }
    canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(0.5), radius), paint);
  }

  @override
  bool shouldRepaint(GlassRimPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.vibrancy != vibrancy ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.chromatic != chromatic;
}
