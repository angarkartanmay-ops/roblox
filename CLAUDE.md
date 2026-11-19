# Roblox game development workspace

This repo builds Roblox games from scratch with Rojo (files on disk are the source of truth,
synced into Studio). 72 skills are installed in `.claude/skills/` and 7 subagents in
`.claude/agents/`; sources and licences are in `.claude/skills/THIRD_PARTY.md`.

## Where things go

- Each game lives in `games/<GameName>/` as its own Rojo project. When a skill script asks for
  a folder (`--dir`), pass `games/<GameName>`. Do not use the skills' default
  `~/Projects/Roblox-Games`: it is outside the repo and is lost with the container.
- Skill scripts live at `$(git rev-parse --show-toplevel)/.claude/skills/<skill>/scripts/`.
- API keys only in environment variables (`ROBLOX_API_KEY`, `HF_TOKEN`, ...), never in files.
  `LOCAL.md` files written by `roblox-skills-setup` are machine-specific and gitignored.

## Which skill for what

Start a whole game with **`create-roblox-game`** (one section per session, with a
`HANDOFF.md` between sessions), or **`roblox-build-orchestrator`** to fan asset work out to
the subagents. For single tasks:

| Area | Skills |
|---|---|
| Idea and design | `roblox-game-ideas`, `roblox-genre-patterns`, `roblox-game-design`, `roblox-player-psychology`, `roblox-economy-balancing`, `roblox-world-level-design` |
| Luau and architecture | `roblox-luau`, `roblox-architecture`, `roblox-code` (scaffold and gates) |
| Backend and game logic | `roblox-game-systems`, `roblox-combat-systems`, `roblox-quest-progression-systems`, `roblox-social-systems`, `roblox-npc-ai`, `roblox-physics` |
| Networking and security | `roblox-networking`, `roblox-security`, `roblox-code-review`, `roblox-creator-store-security-audit` |
| Data and servers | `roblox-data-stores`, `roblox-teleport-matchmaking`, `roblox-open-cloud`, `roblox-admin-tools-observability` |
| Frontend / UI | `roblox-ui` (headless builder: spec to PNG mockup, `.model.json` and Luau), `roblox-ui-layout` (responsive layout rules, StyleSheets), `roblox-input`, `roblox-camera`, `roblox-text-chat`, `roblox-localization` |
| World, maps, 3D | `roblox-map`, `roblox-world-building`, `roblox-3d-model`, `roblox-texture-gen` |
| Look ("shaders") | `roblox-lighting`, `roblox-world-building`, `blender-pbr-materials`, `blender-texture-baking`, `blender-stylized-npr` |
| Characters and animation | `roblox-characters-animation`, `roblox-animation`, `blender-character-rigging`, `blender-clothing`, `blender-facial-shapekeys`, `blender-animation` |
| VFX, audio, feel | `roblox-vfx`, `roblox-sfx`, `roblox-audio`, `roblox-animation-audio-feedback` |
| Blender modelling | `blender-core` first, then `blender-hardsurface-modeling`, `blender-sculpting`, `blender-retopology-uv`, `blender-texturing`, `blender-geometry-nodes`, `blender-environment-kits`, `blender-game-optimization`, `blender-export-pipelines`, `blender-asset-qa` |
| Testing and performance | `roblox-testing`, `roblox-performance` |
| Money, launch, growth | `roblox-monetization`, `roblox-analytics-liveops`, `roblox-policy-compliance`, `roblox-publish-checklist`, `roblox-growth-design` |
| Tooling and Studio | `roblox-tooling`, `roblox-studio-mcp`, `roblox-skills-setup` |

Roblox has no custom shader language. The look comes from `Lighting` (Technology = Future),
`Atmosphere`, post-processing (Bloom, ColorCorrection, DepthOfField, SunRays), `SurfaceAppearance`
PBR maps, `MaterialVariant`, `Highlight`, and particle/beam flipbooks. Use the "Look" skills above.

When skills disagree on an engine API, trust the EL4CTEO core skills (`roblox-luau`,
`roblox-architecture`, `roblox-networking`, `roblox-data-stores`, ...): their Luau examples are
type-checked in CI against the current Roblox API. Inside an existing game, follow the
framework that game already uses (e.g. Knit from `roblox-code`) rather than mixing in another.

## Verify without Studio

Every change must pass these before it reaches Studio. `roblox-code/scripts/check.py` runs the
first four; run the type check as well. Run them from the game's folder:

```bash
mkdir -p build && rojo build -o build/game.rbxl   # parses and assembles (Rojo needs the folder to exist)
lune run test                                   # pure-logic specs, no engine
selene src                                      # lint against the Roblox std
stylua --check src                              # format
rojo sourcemap -o sourcemap.json && luau-lsp analyze --sourcemap=sourcemap.json \
  --definitions=$HOME/.cache/luau-lsp/globalTypes.d.luau src   # strict types vs the Roblox API
```

## What this cloud container can and cannot do

Installed by `tools/setup-cloud-toolchain.sh`: Rojo, StyLua (Luau), darklua, Lune, Wally (built
from crates.io), Selene (patched to trust the proxy's CA so it can fetch the Roblox API dump),
luau-lsp (built from source with Roblox type definitions), Blender 4.0 (headless), and Python 3
with Pillow, NumPy, SciPy, OpenCV, requests, gradio_client and huggingface_hub. If a tool is
missing, the container is new: run that script (about 20 minutes, mostly compiling).

- **Roblox Studio does not run here** (Windows/macOS only), so there is no Studio MCP, playtest
  or screenshot here. Code, maps, UI, VFX specs and Blender assets can be built and checked
  here; playtesting needs the user's machine with Studio open and the Studio MCP connected.
- **Blocked by the network policy** (ask the user to allow the host if a task needs it):
  `huggingface.co` (3D model generation), `apis.roblox.com` (Open Cloud uploads and
  publishing), GitHub release downloads (Rokit installs). `wally install`, crates.io, PyPI,
  npm, apt and `raw.githubusercontent.com` work.
- Never use Kaggle for the 3D/UI scripts: its terms ban this use (see `roblox-skills-setup`).

## Reinstalling the toolchain

- Cloud container: `bash tools/setup-cloud-toolchain.sh` (idempotent; `SKIP_BLENDER=1` and
  `SKIP_LUAU_LSP=1` skip the slow parts).
- Local machine: install [Rokit](https://github.com/rojo-rbx/rokit) and run `rokit install` in
  the repo root (`rokit.toml` pins the same versions), plus Blender 4.x and Roblox Studio with
  its MCP server enabled.
