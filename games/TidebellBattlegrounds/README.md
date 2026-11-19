# Tidebell Battlegrounds

An original anime-style battlegrounds game for Roblox: five elemental champions fight on a drowned
temple-island while a bronze colossus climbs out of the sea. Design, story and roster:
[DESIGN.md](DESIGN.md).

## Play it in Roblox Studio

1. Build the place (or use the `TidebellBattlegrounds.rbxl` shared with you):

   ```bash
   mkdir -p build && rojo build -o build/game.rbxl
   ```

2. Open `build/game.rbxl` in Roblox Studio and press **Play** (or **Start** with 2+ players under
   Test → Clients and Servers to try PvP).
3. Pick a champion, walk west to the Training Grounds to try every move on the dummies, then fight
   in the Toll Plaza. In Studio the Tide Warden rises after 25 seconds (2.5 minutes in live servers).

For live editing, run `rojo serve` and connect the Rojo plugin in Studio; files on disk stay the
source of truth.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| M1 (hold to chain) | Left click | R2 | ATTACK |
| Block / parry | F (hold) | L2 | BLOCK |
| Dash | Q | B | DASH |
| Abilities | 1, 2, 3, 4 | X, Y, L1, R1 | ability buttons |
| Ultimate | G (needs full Resonance) | D-pad up | ULT button |
| Champions | T, the badge, or the altar at spawn | D-pad down | badge |

## How it is built

```text
src/shared/   pure data and rules (no Roblox globals, all covered by tests)
  Fighters    the five champions: stats, M1 chains, 25 moves
  Elements    the five-way element wheel
  CombatMath  damage, guard, parry, resonance, hit geometry, movement
  Poses       procedural animation poses and timed sequences
  VfxCatalog  every effect / projectile / special id the client must implement
src/server/   server-authoritative game (one Script, services as modules)
  CombatService      intents -> M1 chains, move timelines, specials, hits, block/parry, statuses
  ProjectileService  homing, boomerang and exploding projectiles
  StatusService      stun / slow / silence / armor -> movement; guard regen; safe zone
  FighterService     champion choice, stats, weapons (Lib/Weapons builds them from parts)
  MapService         Kanejima, generated from code (terrain + parts)
  DummyService       training dummies (striker, always-blocking guard dummy, heavy)
  BossService        the Tide Warden: telegraphed slam, sweep, jump-over toll ring, enrage, rewards
  StatsService       leaderboard, streaks, kill feed, announcements
src/client/   rendering and input (one LocalScript, controllers as modules)
  InputController      keyboard/mouse, gamepad, touch; local prediction with rollback
  AnimationController  procedural Motor6D/AnimationConstraint poses on every rig (R15 and R6)
  VfxController        all move, hit, projectile and boss effects (asset-free)
  HudController        meters, cooldowns, statuses, feed, boss bar, combo, damage numbers, touch UI
  SelectController     champion select screen
```

The client sends only intents (`Action(slot, aim)`, `SetBlock`, `Dash`, `SelectFighter`); every remote
is type-checked and rate-limited, and the server decides cooldowns, hits, damage and rewards.
Remotes are declared in `default.project.json`, so they exist before any script runs.

No uploaded assets are needed: weapons are welded parts, animation is procedural, effects use neon
parts, trails and built-in particle textures. Sounds are built-in placeholders (`SoundController`).

## Verify

Run from this folder. All five pass on this build:

```bash
mkdir -p build && rojo build -o build/game.rbxl
lune run test        # 166 specs: rules, roster data, poses, originality scan, built-place structure
selene src tests .lune
stylua --check src tests .lune
rojo sourcemap -o sourcemap.json && luau-lsp analyze --sourcemap=sourcemap.json --definitions=$HOME/.cache/luau-lsp/globalTypes.d.luau src
```

## Not yet verified (needs Roblox Studio)

These were built and type-checked but have not been run in the engine yet; check them on the first
playtest:

- the feel of the procedural poses (angles are hand-authored) and the knockback strengths;
- the built-in placeholder sounds (any that fail to load are skipped silently);
- `CreateHumanoidModelFromDescriptionAsync` rigs for the dummies and the boss (a block-rig
  fallback exists for the dummies);
- mobile layout in the Device Simulator.

## Next steps

- Replace placeholder sounds with Creator Store audio (`roblox-sfx` skill, needs Studio).
- Save Kills and Bell Shards with ProfileStore (`roblox-data-stores`), then a cosmetics shop.
- Act II content: Drowned Abbot mini-bosses in the grove and the bell tower.
