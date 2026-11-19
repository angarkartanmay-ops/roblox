# Third-party skills: sources and licences

Every skill in this folder was copied from a public GitHub repository, reviewed
before install (no hooks, no hidden network calls, API keys only read from
environment variables), and pinned to the commit below. Each skill folder also
carries the upstream licence as `UPSTREAM_LICENSE*`.

| Repository | Licence | Taken |
|---|---|---|
| [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills) | MIT | all 23 (`roblox-ui` renamed to `roblox-ui-layout` here) |
| [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills) | SyphoDev free licence: free use and modification, no resale; free redistribution must link back to the [SyphoDev YouTube channel](https://www.youtube.com/@SyphoDev) | all 11, plus the 7 subagents in `../agents/` |
| [TabooHarmony/roblox-brain](https://github.com/TabooHarmony/roblox-brain) | MIT | 7 |
| [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills) | MIT | 11 |
| [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills) | MIT | 20 of 28 |

Local changes from upstream:

- `~/.claude/skills/...` paths in Markdown were rewritten to
  `$(git rev-parse --show-toplevel)/.claude/skills/...` because the skills are installed
  per project, not per user.
- `roblox-ui-layout` (EL4CTEO) was renamed from `roblox-ui` to avoid clashing
  with SyphoDev's `roblox-ui`; the five cross-references to it were updated.
- `roblox-build-orchestrator`: the "copy agents to ~/.claude/agents" step was
  replaced by a note, since the agents ship in `.claude/agents/`.

To update a skill, re-clone its repository and copy the folder over, then
re-apply the changes above.

## Per-skill source

| Skill | Source | Commit |
|---|---|---|
| `blender-animation` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-animation) | 9e7e04a |
| `blender-asset-qa` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-asset-qa) | 9e7e04a |
| `blender-character-rigging` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-character-rigging) | 9e7e04a |
| `blender-clothing` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-clothing) | 9e7e04a |
| `blender-core` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-core) | 9e7e04a |
| `blender-environment-kits` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-environment-kits) | 9e7e04a |
| `blender-export-pipelines` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-export-pipelines) | 9e7e04a |
| `blender-facial-shapekeys` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-facial-shapekeys) | 9e7e04a |
| `blender-game-optimization` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-game-optimization) | 9e7e04a |
| `blender-geometry-nodes` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-geometry-nodes) | 9e7e04a |
| `blender-hardsurface-modeling` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-hardsurface-modeling) | 9e7e04a |
| `blender-pbr-materials` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-pbr-materials) | 9e7e04a |
| `blender-pipeline-automation` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-pipeline-automation) | 9e7e04a |
| `blender-retopology-uv` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-retopology-uv) | 9e7e04a |
| `blender-scene-setup` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-scene-setup) | 9e7e04a |
| `blender-sculpting` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-sculpting) | 9e7e04a |
| `blender-stylized-npr` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-stylized-npr) | 9e7e04a |
| `blender-texture-baking` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-texture-baking) | 9e7e04a |
| `blender-texturing` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-texturing) | 9e7e04a |
| `blender-workflow-recipes` | [EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills/tree/9e7e04a/skills/blender-workflow-recipes) | 9e7e04a |
| `create-roblox-game` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/create-roblox-game) | 5aad881 |
| `roblox-3d-model` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/roblox-3d-model) | 5aad881 |
| `roblox-admin-tools-observability` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-admin-tools-observability) | a3a7b94 |
| `roblox-analytics-liveops` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-analytics-liveops) | cac3ce0 |
| `roblox-animation-audio-feedback` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-animation-audio-feedback) | a3a7b94 |
| `roblox-animation` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/roblox-animation) | 5aad881 |
| `roblox-architecture` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-architecture) | cac3ce0 |
| `roblox-audio` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-audio) | cac3ce0 |
| `roblox-build-orchestrator` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/roblox-build-orchestrator) | 5aad881 |
| `roblox-camera` | [TabooHarmony/roblox-brain](https://github.com/TabooHarmony/roblox-brain/tree/ceee4aa/skills/gameplay/roblox-camera) | ceee4aa |
| `roblox-characters-animation` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-characters-animation) | cac3ce0 |
| `roblox-code-review` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-code-review) | cac3ce0 |
| `roblox-code` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/roblox-code) | 5aad881 |
| `roblox-combat-systems` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-combat-systems) | a3a7b94 |
| `roblox-creator-store-security-audit` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-creator-store-security-audit) | a3a7b94 |
| `roblox-data-stores` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-data-stores) | cac3ce0 |
| `roblox-economy-balancing` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-economy-balancing) | a3a7b94 |
| `roblox-game-design` | [TabooHarmony/roblox-brain](https://github.com/TabooHarmony/roblox-brain/tree/ceee4aa/skills/design/roblox-game-design) | ceee4aa |
| `roblox-game-ideas` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-game-ideas) | a3a7b94 |
| `roblox-game-systems` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-game-systems) | cac3ce0 |
| `roblox-genre-patterns` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-genre-patterns) | a3a7b94 |
| `roblox-growth-design` | [TabooHarmony/roblox-brain](https://github.com/TabooHarmony/roblox-brain/tree/ceee4aa/skills/design/roblox-growth-design) | ceee4aa |
| `roblox-input` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-input) | cac3ce0 |
| `roblox-lighting` | [TabooHarmony/roblox-brain](https://github.com/TabooHarmony/roblox-brain/tree/ceee4aa/skills/gameplay/roblox-lighting) | ceee4aa |
| `roblox-localization` | [TabooHarmony/roblox-brain](https://github.com/TabooHarmony/roblox-brain/tree/ceee4aa/skills/gameplay/roblox-localization) | ceee4aa |
| `roblox-luau` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-luau) | cac3ce0 |
| `roblox-map` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/roblox-map) | 5aad881 |
| `roblox-monetization` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-monetization) | cac3ce0 |
| `roblox-networking` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-networking) | cac3ce0 |
| `roblox-npc-ai` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-npc-ai) | cac3ce0 |
| `roblox-open-cloud` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-open-cloud) | cac3ce0 |
| `roblox-performance` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-performance) | cac3ce0 |
| `roblox-physics` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-physics) | cac3ce0 |
| `roblox-player-psychology` | [TabooHarmony/roblox-brain](https://github.com/TabooHarmony/roblox-brain/tree/ceee4aa/skills/design/roblox-player-psychology) | ceee4aa |
| `roblox-policy-compliance` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-policy-compliance) | a3a7b94 |
| `roblox-publish-checklist` | [TabooHarmony/roblox-brain](https://github.com/TabooHarmony/roblox-brain/tree/ceee4aa/skills/tools/roblox-publish-checklist) | ceee4aa |
| `roblox-quest-progression-systems` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-quest-progression-systems) | a3a7b94 |
| `roblox-security` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-security) | cac3ce0 |
| `roblox-sfx` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/roblox-sfx) | 5aad881 |
| `roblox-skills-setup` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/roblox-skills-setup) | 5aad881 |
| `roblox-social-systems` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-social-systems) | a3a7b94 |
| `roblox-studio-mcp` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-studio-mcp) | cac3ce0 |
| `roblox-teleport-matchmaking` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-teleport-matchmaking) | cac3ce0 |
| `roblox-testing` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-testing) | cac3ce0 |
| `roblox-text-chat` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-text-chat) | cac3ce0 |
| `roblox-texture-gen` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/roblox-texture-gen) | 5aad881 |
| `roblox-tooling` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-tooling) | cac3ce0 |
| `roblox-ui-layout` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-ui) | cac3ce0 |
| `roblox-ui` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/roblox-ui) | 5aad881 |
| `roblox-vfx` | [SyphoDev-yt/roblox-ai-skills](https://github.com/SyphoDev-yt/roblox-ai-skills/tree/5aad881/skills/roblox-vfx) | 5aad881 |
| `roblox-world-building` | [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills/tree/cac3ce0/skills/roblox-world-building) | cac3ce0 |
| `roblox-world-level-design` | [AshExplained/roblox-skills](https://github.com/AshExplained/roblox-skills/tree/a3a7b94/roblox-world-level-design) | a3a7b94 |
