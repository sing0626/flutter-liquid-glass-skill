import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import '../glass_surface.dart';

/// A glass capsule bottom bar with a draggable selection bubble and
/// backdrop-luminance vibrancy. Pure Flutter; pairs with glass_surface.dart.
///
/// Behaviour (all learned the hard way — see reference/pitfalls.md):
/// - one bubble slides behind the tabs: tap = ~300ms spring slide, drag =
///   follows the finger exactly, release = snaps to the nearest tab taking
///   fling velocity into account
/// - pressing anywhere swells the bubble 1.05x (observe-only Listener — the
///   tab taps underneath are untouched)
/// - the bar samples its backdrop's luminance every 250ms and feeds it to
///   GlassSurface.vibrancy: near-invisible over dark content, picks up scrim
///   + blur + rim brightness over bright content
///
/// Scaffold setup this expects:
///   Scaffold(
///     extendBody: true,                       // content scrolls under the bar
///     body: MediaQuery(data: mq.copyWith(     // FABs/snackbars clear the bar
///            padding: mq.padding.copyWith(bottom: mq.padding.bottom + 76)),
///       child: RepaintBoundary(key: _backdropKey, child: yourPages),
///     ),
///     bottomNavigationBar: GlassNavBar(backdropKey: _backdropKey, ...),
///   )

class GlassNavBar extends StatefulWidget {
  const GlassNavBar({
    super.key,
    required this.backdropKey,
    required this.tabs,
    required this.currentIndex,
    this.onChanged,
  });

  /// The RepaintBoundary that wraps your page content — the sampler reads it.
  final GlobalKey backdropKey;
  final List<(IconData icon, IconData activeIcon, String label)> tabs;
  final int currentIndex;
  final ValueChanged<int>? onChanged;

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar>
    with TickerProviderStateMixin {
  // TickerProviderStateMixin, NOT the single-ticker variant: this State owns
  // two AnimationControllers (_bubbleX and _press), and
  // SingleTickerProviderStateMixin asserts on the second one (debug builds
  // crash on first frame; release silently runs on).
  late int _currentIndex = widget.currentIndex;

  /// True between onHorizontalDragStart and its end/cancel. Gates
  /// didUpdateWidget so a parent-driven index change can't yank the bubble
  /// out from under the user's finger mid-drag.
  bool _dragActive = false;

  /// Bubble position in alignment units: -1 = first tab, +1 = last tab.
  /// Managed by hand (not AnimatedAlign) so a drag can write the value
  /// directly and a release can hand the drag velocity to a spring.
  late final AnimationController _bubbleX = AnimationController(
    vsync: this,
    lowerBound: -1.2,
    upperBound: 1.2,
    value: -1,
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 1,
  );

  double _vibrancy = 0.5;
  Timer? _sampleTimer;

  static final SpringDescription _spring =
      SpringDescription.withDampingRatio(mass: 1, ratio: 0.55, stiffness: 320);

  double _targetOf(int index, int n) => (index / (n - 1)) * 2 - 1;

  void _springTo(double target, {double velocity = 0}) {
    _bubbleX.animateWith(
      SpringSimulation(_spring, _bubbleX.value, target, velocity),
    );
  }

  @override
  void initState() {
    super.initState();
    // SimpMusic-style backdrop sampling: shrink the backdrop to a 24px-wide
    // thumbnail every 250ms and average its relative luminance. Cheap; do NOT
    // sample per-frame.
    _sampleTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sample());
    });
  }

  @override
  void didUpdateWidget(covariant GlassNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent's index is the source of truth for WHAT is selected: page
    // switches that didn't come from this bar (deep links, back button,
    // state restore) must move the bubble and highlight too. Without this
    // the bar silently keeps its own stale index forever.
    if (widget.currentIndex != oldWidget.currentIndex &&
        widget.currentIndex != _currentIndex &&
        !_dragActive) {
      _currentIndex = widget.currentIndex;
      _springTo(_targetOf(_currentIndex, widget.tabs.length));
    }
  }

  Future<void> _sample() async {
    final boundary = widget.backdropKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.attached) return;
    try {
      final width = boundary.size.width;
      if (width <= 0) return;
      final image = await boundary.toImage(pixelRatio: 24 / width);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (data == null || !mounted) return;
      setState(() => _vibrancy += (_luminance(data.buffer.asUint8List()) - _vibrancy) * 0.5);
    } catch (_) {
      // Not painted yet / app backgrounded: skip this round.
    }
  }

  /// Mix overall average luminance with the average of bright pixels (>0.35).
  /// Pure averages stay pinned near 0 in dark themes; the bright-region term
  /// is what lets a patch of light content move the glass.
  static double _luminance(Uint8List pixels) {
    var sum = 0.0, count = 0, brightSum = 0.0, brightCount = 0;
    for (var i = 0; i + 3 < pixels.length; i += 4) {
      final l = 0.2126 * pixels[i] +
          0.7152 * pixels[i + 1] +
          0.0722 * pixels[i + 2];
      sum += l;
      count++;
      if (l > 90) {
        brightSum += l;
        brightCount++;
      }
    }
    if (count == 0) return 0.5;
    final avg = sum / count / 255;
    final bright = brightCount > 0 ? brightSum / brightCount / 255 : avg;
    return ((((avg + bright) / 2) - 0.18) / 0.42).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    _bubbleX.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.tabs.length;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: GlassSurface(
        borderRadius: 100, // >= half height -> capsule
        vibrancy: _vibrancy,
        blurSigma: 0, // clear-glass tier; use 18 for frosted
        boxShadow: BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Listener(
            // Observe-only press swell; tabs below still receive their taps.
            onPointerDown: (_) => _press.animateWith(
              SpringSimulation(_spring, _press.value, 1, 0),
            ),
            onPointerUp: (_) => _press.animateWith(
              SpringSimulation(_spring, _press.value, 0, 0),
            ),
            onPointerCancel: (_) => _press.animateWith(
              SpringSimulation(_spring, _press.value, 0, 0),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final unitsPerPx = 2 / constraints.maxWidth;
                return GestureDetector(
                  onHorizontalDragStart: (_) {
                    _dragActive = true;
                    _bubbleX.stop();
                  },
                  onHorizontalDragUpdate: (details) =>
                      _bubbleX.value = (_bubbleX.value +
                              details.delta.dx * unitsPerPx)
                          .clamp(-1.0, 1.0),
                  onHorizontalDragCancel: () {
                    _dragActive = false;
                    // Whatever stole the pointer (dialog, system gesture),
                    // the bubble must go home — see pitfalls.md #10.
                    _springTo(_targetOf(_currentIndex, n));
                  },
                  onHorizontalDragEnd: (details) {
                    _dragActive = false;
                    final velocity =
                        details.velocity.pixelsPerSecond.dx * unitsPerPx;
                    // Fling projection: aim slightly past the release point.
                    final projected = _bubbleX.value + velocity * 0.12;
                    final target =
                        ((projected + 1) / 2 * (n - 1)).round().clamp(0, n - 1);
                    setState(() => _currentIndex = target);
                    widget.onChanged?.call(target);
                    _springTo(_targetOf(target, n), velocity: velocity);
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        // REGRESSION GUARD (pitfalls.md #10): the bubble is
                        // driven by raw AnimationControllers, which repaint
                        // NOTHING on their own. Everything reading a
                        // controller value must sit inside this
                        // AnimatedBuilder, or the bubble only moves when some
                        // unrelated setState happens — it lags the highlight,
                        // teleports on vibrancy ticks, and strands mid-bar
                        // after a cancelled drag.
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_bubbleX, _press]),
                          builder: (context, _) => Align(
                            key: const ValueKey('glass-bubble-align'),
                            alignment: Alignment(
                              _bubbleX.value.clamp(-1.0, 1.0),
                              0,
                            ),
                            child: FractionallySizedBox(
                              // heightFactor is mandatory: without it the
                              // bubble collapses to zero height and
                              // "disappears".
                              heightFactor: 1,
                              widthFactor: 1 / n,
                              child: Transform.scale(
                                scale: 1 + 0.05 * _press.value,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                              .withValues(alpha: 0.08)
                                          : Colors.black
                                              .withValues(alpha: 0.06),
                                      borderRadius:
                                          BorderRadius.circular(100),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha:
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? 0.35
                                                  : 0.85,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (final (index, tab) in widget.tabs.indexed)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  setState(() => _currentIndex = index);
                                  widget.onChanged?.call(index);
                                  _springTo(_targetOf(index, n));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 7,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _currentIndex == index
                                            ? tab.$2
                                            : tab.$1,
                                        size: 23,
                                        color: _currentIndex == index
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        tab.$3,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: _currentIndex == index
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: _currentIndex == index
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
