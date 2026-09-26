#!/usr/bin/env bash
# Installs the flutter-liquid-glass skill into whichever agent home exists.
set -euo pipefail
cd "$(dirname "$0")"
SRC="skills/flutter-liquid-glass"

installed=0
for dest in "$HOME/.zcode/skills" "$HOME/.claude/skills"; do
  if [ -d "${dest%/*}" ]; then
    mkdir -p "$dest"
    rm -rf "$dest/flutter-liquid-glass"
    cp -r "$SRC" "$dest/"
    echo "installed -> $dest/flutter-liquid-glass"
    installed=1
  fi
done

if [ "$installed" -eq 0 ]; then
  echo "No ~/.zcode or ~/.claude found."
  echo "For Codex CLI: clone this repo into your workspace and reference"
  echo "skills/flutter-liquid-glass/SKILL.md from your AGENTS.md (see README)."
fi
