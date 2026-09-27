import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import '../glass_surface.dart';

/// A glass capsule bottom bar — a faithful clone of the bar that ships in the
/// production app this skill was extracted from (the clear glass capsule
/// with the in-place 1.08× swell selection bubble), wrapped in a reusable widget API.
/// Pure Flutter; pairs with glass_surface.dart.
///
/// Behaviour (all learned the hard way — see reference/pitfalls.md):
/// - one bubble slides behind the tabs: tap = 260ms ease-out slide, drag =
///   follows the finger exactly (zero animation while dragging), release =
///   snaps to the nearest tab taking fling velocity into account
/// - bubble drag alignment is clamped to [-1.0, 1.0] (the first and last tab
///   centers), so it never slides out into the capsule's rounded stadium ends
/// - press-and-hold anywhere swells the bubble in place by 1.08× with spring physics;
///   release springs it back onto the selected tab
/// - the bar samples its backdrop's luminance every 1000ms (1s is smooth without
///   causing periodic raster jank) and feeds it to GlassSurface.vibrancy
/// - the parent's `currentIndex` is the source of truth for WHAT is
///   selected: external page changes (deep links, back button) move the
///   bubble and highlight too via didUpdateWidget (pitfalls.md #10)
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
  late int _currentIndex;

  /// Spring progress of the press swell (0 rest .. 1 fully swelled).
  late final AnimationController _bubblePress = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 1,
  );
  late final Animation<double> _bubbleScale = Tween(begin: 1.0, end: 1.08).animate(
    CurvedAnimation(
      parent: _bubblePress,
      curve: Curves.easeOutCubic,
    ),
  );
  static final SpringDescription _spring =
      SpringDescription.withDampingRatio(mass: 1, ratio: 0.55, stiffness: 320);

  void _bubblePressTo(double target) {
    _bubblePress.animateWith(
      SpringSimulation(_spring, _bubblePress.value, target, 0),
    );
  }

  /// Horizontal drag displacement in px while dragging; null = not dragging.
  double? _dragPx;

  /// Backdrop vibrancy signal (0 dark .. 1 bright), 0.5 = unknown.
  double _vibrancy = 0.5;
  Timer? _luminanceTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
    // SimpMusic-style backdrop sampling: shrink the backdrop to a 24px-wide
    // thumbnail every 1000ms and average its relative luminance.
    // 1s is smooth without raster readback jank.
    _luminanceTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sampleLuminance());
    });
  }

  @override
  void didUpdateWidget(covariant GlassNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent's index is the source of truth for WHAT is selected: page
    // switches that didn't come from this bar (deep links, back button,
    // state restore) must move the bubble and highlight too. Without this
    // the bar silently keeps its own stale index forever (pitfalls.md #10).
    if (widget.currentIndex != oldWidget.currentIndex &&
        widget.currentIndex != _currentIndex) {
      setState(() {
        _currentIndex = widget.currentIndex;
        _dragPx = null;
      });
    }
  }

  Future<void> _sampleLuminance() async {
    final boundary = widget.backdropKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.attached) return;
    try {
      final width = boundary.size.width;
      if (width <= 0) return;
      final image = await boundary.toImage(pixelRatio: 24 / width);
      final ByteData? data = await image.toByteData(
        format: ImageByteFormat.rawRgba,
      );
      image.dispose();
      if (data == null || !mounted) return;
      final stats = rgbaLuminanceStats(data.buffer.asUint8List());
      final signal = vibrancySignal(stats.avg, stats.bright);
      if (!mounted) return;
      setState(() => _vibrancy += (signal - _vibrancy) * 0.5);
    } catch (_) {
      // Not painted yet / app backgrounded: skip this round.
    }
  }

  @override
  void dispose() {
    _luminanceTimer?.cancel();
    _bubblePress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: GlassSurface(
        // Capsule: a radius larger than the height degrades to a stadium.
        borderRadius: 100,
        // Clear-glass tier: blurSigma 0 skips the BackdropFilter layer
        // entirely (no saveLayer). Use 18 for the frosted tier.
        blurSigma: 0,
        vibrancy: _vibrancy,
        boxShadow: BoxShadow(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0x40000000)
              : const Color(0x0F16283A),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final n = widget.tabs.length;
              final tabWidth = constraints.maxWidth / n;
              final dark = Theme.of(context).brightness == Brightness.dark;
              // One bubble slides behind all tabs: tapping slides it over,
              // dragging makes it follow the finger exactly, releasing snaps
              // it to the nearest tab.
              return Listener(
                // Observe-only: while pressed the bubble spring-swells,
                // and the tabs' taps + horizontal drag keep working.
                onPointerDown: (_) => _bubblePressTo(1),
                onPointerUp: (_) => _bubblePressTo(0),
                onPointerCancel: (_) => _bubblePressTo(0),
                child: GestureDetector(
                  onHorizontalDragStart: (_) =>
                      setState(() => _dragPx = 0),
                  onHorizontalDragUpdate: (details) =>
                      setState(() => _dragPx = (_dragPx ?? 0) + details.delta.dx),
                  onHorizontalDragCancel: () =>
                      setState(() => _dragPx = null),
                  onHorizontalDragEnd: (details) {
                    final units =
                        (_dragPx ?? 0) / tabWidth +
                            details.velocity.pixelsPerSecond.dx /
                                tabWidth *
                                0.15;
                    setState(() {
                      _currentIndex =
                          (_currentIndex + units.round()).clamp(0, n - 1);
                      _dragPx = null;
                    });
                    widget.onChanged?.call(_currentIndex);
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedAlign(
                          key: const ValueKey('glass-bubble-align'),
                          // While dragging: zero duration so it tracks the
                          // finger exactly; released: 260ms ease-out slide.
                          duration: _dragPx == null
                              ? const Duration(milliseconds: 260)
                              : Duration.zero,
                          curve: Curves.easeOutCubic,
                          // Clamp to [-1.0, 1.0] (first & last tab centers) so
                          // dragging never pokes the bubble past the stadium edge.
                          alignment: Alignment(
                            ((_currentIndex + (_dragPx ?? 0) / tabWidth) /
                                    (n - 1) *
                                    2 -
                                1)
                                .clamp(-1.0, 1.0),
                            0,
                          ),
                          child: FractionallySizedBox(
                            // heightFactor must be set or the pill collapses to 0 height.
                            heightFactor: 1,
                            widthFactor: 1 / n,
                            child: ScaleTransition(
                              key: const ValueKey('glass-bubble-scale'),
                              // Press-and-hold swells the bubble in place by 1.08x.
                              scale: _bubbleScale,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: dark
                                        ? Colors.white.withValues(alpha: 0.14)
                                        : const Color(0xFFD9EAF8)
                                            .withValues(alpha: 0.85),
                                    borderRadius:
                                        BorderRadius.circular(100),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: dark ? 0.4 : 0.9,
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
                                },
                                child: _NavTabContent(
                                  icon: tab.$1,
                                  activeIcon: tab.$2,
                                  label: tab.$3,
                                  selected: _currentIndex == index,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One tab's content (icon + label). The selection pill is drawn by the
/// sliding bubble behind the tabs; this only switches colours, with a small
/// scale-in on the active icon.
class _NavTabContent extends StatelessWidget {
  const _NavTabContent({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              selected ? activeIcon : icon,
              key: ValueKey(selected),
              size: 23,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Luminance stats from a raw RGBA buffer: [avg] = overall average relative
/// luminance, [bright] = average of pixels above 0.35 (falls back to [avg]
/// when there are none).
({double avg, double bright}) rgbaLuminanceStats(Uint8List pixels) {
  var sum = 0.0, count = 0, brightSum = 0.0, brightCount = 0;
  for (var i = 0; i + 3 < pixels.length; i += 4) {
    final l =
        0.2126 * pixels[i] + 0.7152 * pixels[i + 1] + 0.0722 * pixels[i + 2];
    sum += l;
    count++;
    if (l > 90) {
      brightSum += l;
      brightCount++;
    }
  }
  if (count == 0) return (avg: 0.0, bright: 0.0);
  final avg = sum / count / 255;
  final bright = brightCount > 0 ? brightSum / brightCount / 255 : avg;
  return (avg: avg, bright: bright);
}

/// Maps luminance stats to a 0..1 vibrancy signal (a 0.18..0.6 band, clamped
/// at both ends) so even a patch of bright content inside a dark theme can
/// move the bar.
double vibrancySignal(double avg, double bright) {
  return (((avg + bright) / 2) - 0.18) / 0.42;
}
