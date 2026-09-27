# Pitfalls — every one of these actually broke in a shipping app

Ordered by how expensive they were to find. #1–#3 only manifest in release
builds or while a gesture is in flight, so `flutter analyze` and debug builds
will all tell you everything is fine.

## 1. A moving `BackdropFilter` ghosts (double vision while dragging)

If the glass bubble/lens is its own `BackdropFilter` and you slide it (a
draggable selection bubble, a reordering chip), the blurred backdrop sample
lags **one frame behind** the painted rim. Result: while dragging you see two
offset pills — the crisp rim in the new position and the stale blur region in
the old one. It looks like motion blur but it is not; it does not go away with
faster rebuilds.

Fix: keep the travelling element to fill + rim only. Blur belongs to the
*static* bar underneath, not to the moving lens.

## 2. `Transform` around a `BackdropFilter` distorts the sampled backdrop

The backdrop sample is taken in the *transformed* space, so scaling a lens
while pressed/dragging stretches the content seen **through** it — text behind
the lens visibly squashes. iOS gets away with this because its lens is a
fragment shader with real refraction parameters; Flutter's BackdropFilter has
none. There is no workaround in pure Flutter — don't transform a
BackdropFilter, and never promise "magnifying" behaviour.

## 3. Non-uniform `Border` + `borderRadius` = silent square frame in release

```dart
// DON'T: debug asserts, release paints an axis-aligned RECTANGLE over your capsule
BoxDecoration(
  borderRadius: BorderRadius.circular(100),
  border: Border(top: side(0.4), left: side(0.25), ...), // directional rim
)
```

`BoxDecoration` only supports borders uniform on all four sides together with a
borderRadius. Debug mode asserts; release mode strips the assert and paints the
border as an axis-aligned rectangle — you ship a square frame over a glass
capsule. The fix is the `GlassRimPainter` in glass_surface.dart: one stroked
`RRect` with a gradient shader.

## 4. `FractionallySizedBox` without `heightFactor` = invisible bubble

A selection bubble positioned with `Align(alignment: Alignment(x, 0))` +
`FractionallySizedBox(widthFactor: 1/n)` has **zero height** (no child of its
own to size from loose constraints). The widget exists, hit-testing works,
nothing renders. Always pass `heightFactor: 1` (or give it a child with
intrinsic height).

## 5. FABs and snackbars don't know about your floating bar

With `extendBody: true`:
- `FloatingActionButton` (nested Scaffold) positions off **`viewPadding`**, so
  changing `MediaQuery.padding` does nothing — it sits on top of your glass
  bar. Fix: a custom `FloatingActionButtonLocation` that offsets
  `endFloat` by the bar height:

```dart
class AboveGlassBarFabLocation extends FloatingActionButtonLocation {
  const AboveGlassBarFabLocation();
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final base = FloatingActionButtonLocation.endFloat.getOffset(geometry);
    return Offset(base.dx, base.dy - 76); // bar height + margins
  }
}
```

- Floating `SnackBar`s read `MediaQuery`, so wrapping the body in
  `MediaQuery(data: mq.copyWith(padding: mq.padding.copyWith(bottom: mq.padding.bottom + 76)))`
  lifts them — and conveniently gives lists the extra bottom inset they need
  to scroll their last item clear of the bar.

## 6. `RepaintBoundary.toImage()` hangs widget tests forever

Under `flutter_test`'s fake async, the raster callback that completes the
`toImage` future never runs — the test times out after 10 minutes with no
error message. Wrap the capture in `tester.runAsync(() async { ... })`. Also:
`pixelRatio` below 1 is legal and the cheap way to sample (`pixelRatio: 24 /
width` gives you a 24 px-wide thumbnail), and prefer `ImageByteFormat.rawRgba`.

For the luminance signal itself: average the whole thumbnail AND the pixels
brighter than ~0.35, then average those two numbers. Pure averages stay pinned
near zero in dark themes and the glass never reacts; the bright-region term is
what makes a patch of light content move the bar.

## 7. Transparency is a direction, not a destination

Shipping sequence from the real app this skill was extracted from: solid bar →
60% scrim ("too solid") → 45% ("more transparent!") → 38% → 28% → 16% → 8% →
"why is there blur at all?" → zero scrim, zero blur, rim-only. Users who ask
for liquid glass mean *clear*, not frosted. Make every alpha and the blur
itself a parameter from day one, expect the feedback loop, and keep the solid
fallback (`enabled: false`) for accessibility / low-end devices.

## 8. Scale effects compound

Press-swell on the bar × press-swell on the bubble × squash-and-stretch on the
bubble add up — 1.03 × 1.08 × 1.25 pokes the bubble past the capsule's rounded
ends. Cap combined scale under ~1.12, and inset the bubble from the cell edge
so the stadium corners never clip it.

## 9. Static BackdropFilter placement rules

- The glass surface must be painted *after* (siblings below) the content it
  blurs. In a Scaffold: `extendBody: true` + bar in `bottomNavigationBar`
  works; nesting the glass inside the scroll content it samples is a feedback
  loop (in Compose's Kyant0 backdrop this literally crashes the shader; in
  Flutter it just blurs itself).
- One or two `BackdropFilter`s per screen. Each is a saveLayer; a glass FAB +
  glass bar is fine, a glass card per list row is a jank factory.
- Skip the layer entirely for `blurSigma == 0` (check the flag, don't build a
  sigma-0 filter — that still costs a saveLayer).

## 10. A spring with no listener repaints nothing (bubble strands / desyncs)

`AnimationController.animateWith(...)` drives *values*, not *frames*. If your
build method reads `controller.value` directly (e.g. `Align(alignment:
Alignment(_bubbleX.value, 0))`) with no `AnimatedBuilder`/`ListenableBuilder`
in between, the widget repaints **only when some unrelated `setState`
happens** — a drag update, the 250ms vibrancy tick, any parent rebuild.

Symptoms seen in a shipping app: the tab highlight switches instantly (its
`setState` is right there in `onTap`) while the bubble lags behind, teleports
in 250ms steps, or — worst case, when nothing else rebuilds (static page, a
dialog opening that steals the pointer) — **freezes mid-way between two tabs
for seconds or forever** after a drag is released or cancelled. It looks like
render ghosting; it is just a widget that never rebuilds.

Fix: everything reading a controller value goes inside
`AnimatedBuilder(animation: Listenable.merge([_bubbleX, _press]), ...)`.
Then a cancelled drag's spring home *actually animates*, and the bubble can
never strand. Related hardening, same failure family:

- the parent's `currentIndex` is the source of truth for what is selected —
  implement `didUpdateWidget` to follow external index changes (deep links,
  back button), or the bar keeps a stale private index forever;
- drag state must end on EVERY exit path: `onHorizontalDragEnd` **and**
  `onHorizontalDragCancel` (dialogs, system gestures steal the pointer).

## 11. Two controllers ≠ `SingleTickerProviderStateMixin`

The nav bar State owns two `AnimationController`s (bubble + press). With
`SingleTickerProviderStateMixin` the second `createTicker` asserts — **debug
builds crash on the first frame**; release strips the assert and runs on, so
your only clue is that debug/profile never boots while release "works".
Use `TickerProviderStateMixin` whenever a State owns more than one controller.

## 12. Rewriting the bubble layer = the pill escapes the capsule or vanishes

Real integration failures, both impossible with the verbatim example:

- **Pill paints OVER the rim and off the bar's edge** (worst at the last
  tab). In the verbatim code the rim is the `CustomPaint` **foregroundPainter**
  — always painted on top of everything inside the surface — and the pill is
  `Positioned.fill` child #0 of the Stack INSIDE GlassSurface, whose
  `Clip.antiAlias` contains the swallow bulge. If your copy can draw the pill
  past the rim, the bubble layer was moved outside GlassSurface or reordered.
- **Pill invisible at rest.** Note first: while pressed, the verbatim pill
  swells to the FULL bar width and its border hugs the inner rim — that is
  the swallow look, not a missing pill; release and it springs back onto the
  selected tab. If no pill ever comes back, your bubble was deleted, covered
  by an opaque sibling, or given a zero/negative width factor.

Rules: paste `glass_nav_bar.dart` verbatim; the bubble stays child #0 and the
tabs Row child #1 of that Stack; never `Clip.none`, never an opaque sibling
between them, never a per-tab pill next to the sliding one (two indicators);
wire the Scaffold exactly like `reference/examples/demo_app.dart`.

## 13. The bar resolves instantly — pages must switch instantly too

`onChanged` fires the moment a tap/drag resolves and the bubble settles in
~260ms. If pages cross-fade through a `PageRoute` or a long
`AnimatedSwitcher`, the page is still half-faded under an already-settled
bubble and the whole thing reads as desynced. unimail uses
`IndexedStack(index: currentIndex)` — instant, and it preserves each page's
scroll position and state for free. Want animated page transitions? Keep them
short and let the bar remain the source of truth for the index.
