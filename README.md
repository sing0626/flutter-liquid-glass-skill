# flutter-liquid-glass-skill

A [code-agent skill](skills/flutter-liquid-glass/SKILL.md) that teaches
**ZCode / Claude Code / Codex** how to build iOS-26-style **liquid glass UI in
Flutter** — with pure Flutter (`BackdropFilter`, `CustomPaint`, spring physics,
backdrop luminance sampling). No native code, no shader packages.

The pattern was reverse-engineered from
[SimpMusic](https://github.com/maxrave-dev/SimpMusic) (Kyant0's Compose
`backdrop` library) and re-expressed in Flutter, then hardened through ~20
real CI builds — including the release-mode-only breakage that static analysis
cannot catch ([pitfalls.md](skills/flutter-liquid-glass/reference/pitfalls.md)).

## What the skill gives your agent

- **Capability map first**: what pure Flutter can and cannot do (true lens
  refraction needs a shader — the skill says so instead of faking it)
- A **drop-in `GlassSurface`** primitive: blur tiers (frosted / clear / off),
  near-transparent theme-aware scrim, directional rim light, optional
  chromatic-aberration edge, observe-only press interaction (spring bulge +
  pointer-following glow), luminance-driven vibrancy, solid-surface fallback
- A complete **glass capsule nav bar with a draggable selection bubble**
  (tap-slide / drag / fling-snap) with the backdrop sampler wired in
- **Nine pitfalls** with fixes — the moving-`BackdropFilter` ghost, the
  release-mode square frame from non-uniform borders, the zero-height bubble,
  FABs sitting on top of the bar, the widget-test `toImage()` hang, and more

## Install

### ZCode

```bash
# personal (all projects)
mkdir -p ~/.zcode/skills && cp -r skills/flutter-liquid-glass ~/.zcode/skills/

# or project-level
mkdir -p .zcode/skills && cp -r skills/flutter-liquid-glass .zcode/skills/
```

### Claude Code

```bash
# personal (all projects)
mkdir -p ~/.claude/skills && cp -r skills/flutter-liquid-glass ~/.claude/skills/

# or project-level
mkdir -p .claude/skills && cp -r skills/flutter-liquid-glass .claude/skills/
```

Both agents pick the skill up automatically from the `SKILL.md` frontmatter;
invoke it by saying something like *"add liquid glass to my Flutter bottom
bar"*.

### Codex CLI

Codex has no skill loader — teach it the path from your `AGENTS.md`:

```markdown
## Skills
- When adding glass / liquid-glass / glassmorphism effects to Flutter UI, read
  `skills/flutter-liquid-glass/SKILL.md` first and follow it (including
  reference/pitfalls.md). Reference implementations live in that folder.
```

(Adjust the relative path to wherever you clone this repo into the workspace.)

### One-liner

```bash
git clone https://github.com/sing0626/flutter-liquid-glass-skill.git
flutter-liquid-glass-skill/install.sh           # detects ~/.zcode and ~/.claude
```

## Repo layout

```
skills/flutter-liquid-glass/
├── SKILL.md                      # the skill (frontmatter + guidance)
└── reference/
    ├── glass_surface.dart        # GlassSurface + GlassRimPainter (compiles standalone)
    ├── pitfalls.md               # 9 release-mode war stories, with fixes
    └── examples/
        └── glass_nav_bar.dart    # capsule bar + draggable bubble + vibrancy sampler
```

Both `.dart` files compile standalone (`flutter analyze` clean on a fresh
`flutter create --empty` project).

## Licence

MIT — see [LICENSE](LICENSE).
