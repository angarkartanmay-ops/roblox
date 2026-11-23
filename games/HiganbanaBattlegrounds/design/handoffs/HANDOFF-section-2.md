<!-- section: 2 -->
# HANDOFF: section 2 of 6 closed (Code and the playable loop)

Game: `D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds`
Written: 2026-11-22T14:23:32+05:30

A cleared session starts from this file alone. Read it in full, then run:

```bash
python ~/.claude/skills/create-roblox-game/scripts/section.py resume --dir "D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds"
```

## Where things are
- Server: `src/server/Services/*` (KiService gained `isUltimateHit`), `src/server/init.server.luau`, Debug BindableFunction at `ServerScriptService.Server.Debug` (commands: entities, entity, cast, ki, cooldowns, teleport, wake, thirst).
- Shared: `src/shared/*` (Fighters, Constants.FLAG, Poses, VfxCatalog).
- Client: `src/client/init.client.luau`; `src/client/Lib/Remotes.luau`, `src/client/Lib/UiKit.luau`; `src/client/Controllers/` AnimationController, InputController, VfxController (~2050 lines, all 25 moves), SelectController (PhaseSelect + DeathRecap), HudController (full HUD + TouchControls), NameplateController (new), Rig, SoundController, CameraController.
- Place: `places/HiganbanaBattlegrounds.rbxl` (working copy, open in its own Studio window).
- Map attempt output: `build/map/` (report.json, plan.png, terrain) - prove FAILED, not installed.

## Done this section
- Full server combat (6 fighters, 25 moves, Five Phases generate/overcome relations, Ki, guard, mend, thirst, Elder world boss) and the full client (input, HUD, select wheel, death recap, nameplates, VFX handlers, procedural upper-body idles).
- Gates: roblox-code `check.py` green (rojo build, lune 325/325 tests, selene, stylua); luau-lsp strict 0 errors.
- Studio playtest on the fallback blockout: boot with no errors; 5 dummies take M1 + ability damage; Ki gain; Ultimate casts; Elder wakes, attacks and killed the player, times out at 240 s, re-wakes; Wound (Fire vs Metal heart) pauses regen (2400 -> 2368, wounded=true); SelectFighter remote switches fighter; HUD texts read live state.
- Bug fixed: Ultimate hits refilled Ki (5 dummies -> 100). After fix measured Ki stays 0 for 4 s after an Ultimate that hit a dummy (dummy 272 HP).

## Decisions and why
- Code synced into Studio by a localhost HTTP server (`python -m http.server 8766 --directory src`) + `ScriptEditorService:UpdateSourceAsync`, because the Studio place is a separate working copy and `rojo build` to `build/` must not clobber it.
- Playtest probes go through the server `Debug` BindableFunction: execute_luau `require` gets a separate module cache, so requiring Registry from a probe sees empty state.
- Ultimate damage grants no Ki to its caster, so an Ultimate cannot chain into another Ultimate.
- Fighter idles animate the upper body only, so they never fight the default walk/run legs.
- Core Health GUI disabled; the HUD owns health display.

## Unproven
- Two-player PvP (relation damage, ring-outs, kill feed between players): UNTESTED.
- Elder solo balance: regen 36 HP/s out-heals one neutral M1 player; needs tuning in section 5.
- Status chips show no seconds left (server publishes booleans only).
- VfxCatalog.PHASES lacks Miss, Shout, Charge, Fall, Explode entries (client falls back to GENERIC_PHASES).
- Touch controls built but not tested on Device Simulator.
- VFX/animation visuals are placeholder-procedural; not reviewed visually.

## Debts
- FALLBACK (logged): `design/map.json` fails `build_map.py` prove (P1 grounding: 17 parts 'float inf', likely not counting terrain; P13 dressing; P3 intent; T4 tides). Loop played on MapService's flat fallback (FallbackShore, SelectLantern, ElderTrunkBlock, Spawns). NOT healed - section 3 must fix map.json and install the proven map.
- No interventions. The fighter switching to Hibiki mid-probe was probably the user clicking a card in Studio; it changed nothing that was built.
- User asked for a whole-game run ("I approve section 1. Start it and build everything."): sections 2-6 run back to back, still closing each with `section.py close N`.

## Ledger

Initialised once in section 1. Never run `init` again.

```bash
python ~/.claude/skills/roblox-build-orchestrator/scripts/run_log.py counter --dir "D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds\build-runs" --run "higanbana-battlegrounds"
```

## Place
- `D:/Antigravity/Roblx/roblox/games/HiganbanaBattlegrounds/places/HiganbanaBattlegrounds.rbxl`, saved 2026-11-22 at section 2 close via save_place.
- Studio window studio_id at time of writing: `d2720900-eb16-4271-875a-4df26becea66` (re-list on a new session).
- No universe/place minted. ROBLOX_API_KEY is unset - publish (section 6) is blocked on both.
- Do not overwrite the Tidebell place.

## Loop playtest
Played in Studio on the fallback blockout: spawn -> select fighter -> fight dummies (damage + Ki measured) -> Ultimate -> wake Elder -> Elder kills player -> DeathRecap -> respawn -> Elder timeout at 240 s -> re-wake -> Wound pauses regen (2400 -> 2368). Loop closes end to end, solo.

## Rules

1. ONE SECTION PER SESSION. Finish this section's whole scope, then stop. Inside a section the skill's 'the run does not stop' rule applies in full; `section.py close N` passing is the only place you stop. Never start the next section's work, even with budget left.
2. STAY INSIDE CLAUDE CODE AND ROBLOX STUDIO. Work through the skills, MCPs and CLIs. No browser-driving tools (browser pane, Chrome), no web-GUI generators. WebSearch and WebFetch inside Claude Code are fine. Screen access is for Roblox Studio only.
3. NOTHING IN STUDIO BY THE USER'S HAND. Never ask the user to place, type, edit or configure anything in Studio, and never ask them to leave Claude Code or Studio. You may ask for: pressing Play or Stop, clicking Publish, approving a tool call, restarting a stuck MCP, or something purely mechanical no API or screen action of yours can reach.
4. LOG INTERVENTIONS AS THEY HAPPEN (run_log.py event --kind intervention): the user writes or edits code, makes a design or art decision (a genre named in the section 1 prompt is the brief, not an intervention), chooses between options, tells you WHAT is wrong rather than THAT something is wrong, or does something in Studio by hand. So never offer options: decide, and say why.
5. TIER 2 FIRST, fallback pre-authorised: take it without asking and log it as a fallback. 30-minute stall rule: one problem eats 30 minutes, fall back, log it, keep moving.
6. EVERY SESSION: ask for Roblox Studio screen access first (a grant does not survive a cleared session). 'Continue with the development of the <genre> game' means `section.py resume --game "<genre>"`: it finds the game and says which section is next.
7. THE LEDGER IS INITIALISED ONCE, in section 1. Every later call passes the --dir and --run recorded in HANDOFF.md. Bracket each ledger stage with start/end.
8. BEFORE CLOSING: save the place, write HANDOFF.md with `section.py handoff N`, replace every placeholder, run `section.py close N`. Then stop and ask the user to approve. Approval is free. If the user asks for changes, make them, log an intervention if they named what was wrong, update HANDOFF.md and close again. When the user approves ("approved", "yes that's all good"), run `section.py approve N` and say it is safe to clear the chat. Do not start the next section.

## Next section: first step
Section 3: World and visuals (4 map (full), 5 meshes + colour + materials, 6 ui).
Fix `design/map.json` so prove passes: `python <roblox-map>/scripts/build_map.py design/map.json --out build/map` and read `build/map/report.json` (start with P1 grounding - check whether terrain counts as ground). Then `--serve --port 8765` and install into the Studio place, then meshes and UI.

## Earlier handoffs

- `D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds\design\handoffs\HANDOFF-section-1.md`
