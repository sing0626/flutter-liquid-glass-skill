---
name: flutter-liquid-glass
description: Build iOS-26-style liquid glass UI in Flutter (Android/desktop included) with pure Flutter — no native code, no shader packages. Use when asked to add liquid glass, glassmorphism, frosted/transparent glass bars, glass buttons, or "make it look like iOS 26 / SimpMusic" glass effects to a Flutter app. Covers a battle-tested GlassSurface primitive, a glass capsule nav bar with a draggable selection bubble, adaptive vibrancy (backdrop luminance sampling), and the release-mode pitfalls that silently break glass UI.
---

# Flutter Liquid Glass

Battle-tested pattern distilled from a real app that iterated through ~20 CI builds
chasing the iOS-26 look. Pure Flutter only: `BackdropFilter`, `CustomPaint`,
`Listener` + spring physics, and `RenderRepaintBoundary.toImage()` luminance
sampling. No `liquid_glass_renderer`, no Kyant0 backdrop (that one is
Compose/AGSL-only), no platform channels.

**Read [reference/pitfalls.md](reference/pitfalls.md) before writing any code.**
Most of it is release-mode-only breakage that analyze cannot catch.

**Paste the two reference files VERBATIM and wire like the demo.** Do not
adapt the bar's internals — every "small improvement" to the Stack/clip/layer
order has already broken in a real app (pitfalls #12/#13: pill escaping the
capsule, vanishing pill, desynced page cross-fades). For the integration,
copy [`reference/examples/demo_app.dart`](reference/examples/demo_app.dart)
whole: a runnable app with the exact Scaffold wiring (`extendBody`,
MediaQuery +76 padding, `RepaintBoundary` backdrop key, `IndexedStack` pages).

## The honest capability map (set expectations first)

| Effect | Pure Flutter can? | How |
| --- | --- | --- |
| Frosted blur behind a shape | ✅ | `BackdropFilter` + `ClipRRect` |
| Transparent "clear glass" (no blur, no tint) | ✅ | Skip the filter layer entirely, keep the rim |
| Directional rim light (bright top edge) | ✅ | `CustomPaint` stroke with gradient shader |
| Chromatic-aberration edge (rainbow rim) | ✅ (approx) | Two faint offset strokes (magenta/cyan) |
| Press bulge + glow following the finger | ✅ | Observe-only `Listener` + spring + `BlendMode.plus` radial |
| Adaptive vibrancy (glass reacts to content behind) | ✅ | Sample the backdrop via `RepaintBoundary.toImage` |
| **True lens refraction / magnification** | ❌ | Needs a fragment shader sampling the backdrop (`liquid_glass_renderer`) |
| Moving glass lens that refracts while travelling | ❌ | A moving `BackdropFilter` ghosts one frame behind its rim |

Ask the user which tier they want: **clear** (no blur, rim only — the endgame of
"make it transparent"), **frosted** (blur + near-transparent scrim), or
**lens** (needs a shader package; warn about maturity). Do not quietly stack
blur + tint + effects; real users almost always push transparency further than
you think.

## Quick start

Copy [`reference/glass_surface.dart`](reference/glass_surface.dart) into
`lib/ui/`. It is self-contained (only Flutter SDK imports) and themable.

```dart
// Frosted capsule (default)
GlassSurface(
  borderRadius: 100, // >= half height -> stadium
  child: yourContent,
)

// Clear glass (no filter layer at all, rim light only)
GlassSurface(borderRadius: 100, blurSigma: 0, child: yourContent)

// Disabled -> falls back to a solid themed surface (settings toggle)
GlassSurface(borderRadius: 100, enabled: false, child: yourContent)
```

`GlassSurface` gives you: blur, theme-aware near-transparent scrim, directional
rim light, optional chromatic rim (`GlassRimPainter(chromatic: true)`), an
observe-only press interaction (spring scale-up, blur deepen, radial glow that
follows the pointer — taps inside still work), and a solid-surface fallback.

### Adaptive vibrancy (glass reacts to what's behind)

Wrap your body in a `RepaintBoundary`, sample its average luminance on a timer,
and feed the smoothed signal into `vibrancy:` — brighter content behind drives a
deeper scrim, stronger blur and a brighter rim. Full working sampler + bar in
[`reference/examples/glass_nav_bar.dart`](reference/examples/glass_nav_bar.dart).
250–500 ms cadence is plenty; sample a 24 px-wide image, not the full frame.

### Glass capsule nav bar with a draggable selection bubble

[`reference/examples/glass_nav_bar.dart`](reference/examples/glass_nav_bar.dart)
is a complete drop-in and a **faithful clone of the bar that ships in the app
this skill was extracted from** — the exact code users have validated on real
devices: one bubble slides behind the tabs (tap = 260ms ease-out slide, drag =
follows the finger with zero animation, release = snaps to the nearest tab with
fling velocity), **press-and-hold anywhere swells the bubble from its cell to
the FULL bar width** ("swallow the bar"), it bulges vertically against the
capsule's rounded ends, and the bar samples backdrop luminance every 250ms for
adaptive vibrancy. The parent's `currentIndex` is followed via
`didUpdateWidget`. `AnimatedAlign` + `Alignment(-1..1)` is all the "physics" a
sliding bubble needs — **do not** build the bubble as its own moving
`BackdropFilter` (see pitfalls #1/#2) and **do not** read a raw
`AnimationController.value` outside an `AnimatedBuilder` (pitfalls #10/#11).

## API cheat sheet

```dart
GlassSurface(
  borderRadius: 100,          // radius; large value = capsule
  blurSigma: 18,              // 0 = no filter layer AT ALL (no saveLayer)
  pressScale: 1.05,           // 1.0 disables the press interaction
  vibrancy: 0.0..1.0,         // backdrop luminance signal (null = neutral)
  tint: null,                 // override scrim (default: theme-aware)
  borderColor: null,          // override rim (default: gradient rim)
  boxShadow: BoxShadow(...),  // optional lift
  enabled: true,              // false = solid themed fallback
)
```

## The pitfalls (release mode will eat you — full list in pitfalls.md)

1. **Never put a `BackdropFilter` inside something that moves.** It samples its
   backdrop a frame behind the painted rim → double-vision ghosting while
   dragging; and a `Transform` wrapping it stretches the *sampled backdrop*,
   visibly distorting text seen through the lens. Move a rim + fill, not a lens.
2. **Never combine a non-uniform `Border` with `borderRadius` in one
   `BoxDecoration`.** Debug asserts; release silently paints an axis-aligned
   rectangle over your capsule. Directional rims = `CustomPaint` stroke with a
   gradient shader.
3. **`FractionallySizedBox` without `heightFactor` collapses to zero height** —
   your selection bubble will exist but be invisible.
4. **FABs in nested Scaffolds position off `viewPadding`, not `padding`** —
   `MediaQuery` padding tweaks will not lift them over your floating bar. Use a
   custom `FloatingActionButtonLocation` offset by the bar height, and add the
   bar height to the body's bottom `MediaQuery.padding` for floating snackbars.
5. **`RenderRepaintBoundary.toImage()` futures never complete under widget-test
   fake async** — wrap in `tester.runAsync(...)` or the test times out.
6. With `extendBody: true`, remember `MediaQuery` bottom padding for list
   scroll-outs, FABs and snackbars (see pitfalls.md §5).
7. Transparency is a direction, not a setting: every scrim alpha in this skill
   is a parameter because real feedback is always "more transparent". Ship the
   knob (`enabled`, `blurSigma`, `vibrancy`) — do not hardcode taste.
8. A raw `AnimationController` spring repaints nothing by itself. If the build
   reads `controller.value` without an `AnimatedBuilder`, the bubble lags the
   tab highlight, teleports on vibrancy ticks, or strands mid-bar after a
   cancelled drag (dialog steals the pointer). Every controller reader goes in
   `AnimatedBuilder(animation: Listenable.merge([...]))`; follow external
   `currentIndex` changes in `didUpdateWidget`; and a State with two
   controllers needs `TickerProviderStateMixin` (see pitfalls.md #10/#11).

## Platform notes

- Android: everything above works; Impeller is fine for a *static* backdrop
  filter. Desktop (macOS/Windows): same code, GPUs laugh at one blur.
- Want the *window* blurred (behind the app, not app content)? That is
  `NSVisualEffectView` (macos_ui) / Fluent Acrylic (fluent_ui) — native only,
  outside this skill's scope.
- iOS-26 true lens refraction: point the user at `liquid_glass_renderer`
  (whynotmake.it) and its maturity caveats; keep this skill's primitives for the
  bar/bubble so motion stays ghost-free.

## Where the pattern comes from

Reverse-engineered from SimpMusic (Kyant0 `backdrop` Compose library:
`layerBackdrop` source layer + `drawBackdrop` effect stack — vibrancy,
colorControls, blur, lens; observe-only press; per-second luminance sampling)
and re-expressed in pure Flutter, then hardened through user testing
(transparency → no blur at all; ghosting; square frames; invisible bubbles).
