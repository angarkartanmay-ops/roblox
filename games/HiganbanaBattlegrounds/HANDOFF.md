<!-- section: 3 -->
# HANDOFF: section 3 of 6 closed (World and visuals)

Game: `D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds`
Written: 2026-11-23T12:02:50+05:30

A cleared session starts from this file alone. Read it in full, then run:

```bash
python ~/.claude/skills/create-roblox-game/scripts/section.py resume --dir "D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds"
```

## Where things are
- Map spec: `design/map.json` (rewritten; backup of the section-2 version in `design/map.section2.json`), written by `tools/fix_map_spec.py` + `tools/scatter_map.py`.
- Prover output: `work/map/report.json`, `work/map/plan.png`, `work/map/terrain/`, `work/map/build.lua` (served builder), `work/map/dressing.json` (mesh placements), `work/map/landing_view.png`. Older copy in `build/map/`.
- Meshes: `assets/meshes/manifest.json` (38 entries), `design/mesh_ids.json` (published model ids of the first 10). In Studio: `ServerStorage.DressingCache.<Name>` (one Model per mesh).
- Map in Studio: `Workspace.FarShore` (parts, Spawns, KillPlane, `Dressing` folder with 169 placed meshes + `Dressing.LilyDrifts` 754 lilies), smooth terrain, Lighting (golden_hour preset + dusk Atmosphere).
- UI: `assets/ui/*.model.json` (exported live trees, re-exported in the polish pass: `WorldOverlay`, `DummyNameplate`, new `DeathRecap`), `assets/ui/mockup.png`, `assets/ui/README.md`.
- Code: `src/shared/FarShore.luau` (spawns y48, lantern 50.5, Elder anchor 53.5), `src/server/Services/MapService.luau` (find() returns the PART, not a same-named folder), `src/server/Services/FighterService.luau` (Humanoid.MaxSlopeAngle = 45), `src/client/Controllers/SelectController.luau` (panel named FighterDetail_<id>; core PlayerList hidden while open).
- Skill change: `roblox/.claude/skills/roblox-map/scripts/checks_terrain.py` T4 honours volume.killPlane and volume.slideSlope.

## Done this section
- Map prove: RESULT WARN (was FAIL on P1, P3, P13, T4). Passing: P1, P3, P13, T2 (levels 24/48/72), T4 (all 7 zones at both tides), T7, T9. WARN only: P2, T6 (coast all cliff), T8 (bare voxel cliff).
- Map installed by build.lua (185 parts) + build_terrain.lua (BuildDone=true). verify_build.lua: errors=0, grey=0, unresolvedRoles=0, 923 mesh parts.
- Playtest on the real map: no fallback shore; player spawns on Spawn3 (1 stud above); 5 dummies stand on terrain on Jizo Beach; lantern ProximityPrompt present after MapService fix; Elder wakes at (0, 67.2, -215) with 2400 HP; MaxSlopeAngle=45 on the character.
- 38 meshes generated in Studio (every name in design/meshes.json, BambooCluster shares the BambooClump mesh); 10 placed as map dressing.
- UI: exported trees list every asset-plan UI name except PhaseNameplate; Phase Select clicked through in a playtest (cards rename the detail panel per fighter).
- Gates: roblox-code check.py all green, 327/327 tests, luau-lsp 0 errors.

## Decisions and why
- The landing is a flagstone quay + walk (parts) because the reachability prover walks parts only; spawns stand on the quay.
- Sea floor -104 below the tide: the mist sea is open water to T4, 34 studs under the kill plane.
- T4 treats ground under the ring-out line as lethal and faces steeper than volume.slideSlope (45) as slides; the game enforces it with Humanoid.MaxSlopeAngle = 45. Without this every cliff skirt counted as a stranding pocket.
- Lily Hill and Pine Bluff raised to flat tops at ~72 with switch trails (LilyTrail, PineTrail, max grade 22) to give the third ground level T2 asks for.
- Dressing boxes in the spec carry a `dressing` kind; Studio swaps each box for the mesh, scaled to the box height, base on the box bottom. Boats/hut/torii keep invisible boxes with collision off; trees, boulders, small stones collide by Hull; torii and hut by PreciseConvexDecomposition; lilies are walk-through.
- Meshes come from Studio generate_mesh because Tier 2 needs an Open Cloud key to upload (unset). generate_mesh publishes the assets itself, so they persist in the place.
- UI stays runtime-built Luau (section 2). Its artifact is the exported live tree, not a separate headless spec, so the mockup cannot drift from what ships.
- Lighting: golden_hour preset, ClockTime 17.6, teal-grey Atmosphere (density 0.32). Lighting.Technology cannot be set from a plugin; default.project.json already sets Future.

## Unproven
- PhaseNameplate: needs a second player; validate --stage-gate reports it missing until the two-player test exports it (section 5).
- Mesh proportions: Wagasa, NoboriBanner, BridgeParapet, FerryPier, FerryOar, WeightedChain, ElderBranchTube, DohyoRing, CoinString, Sugegasa and Jingasa came out with squashed bounds (manifest marks them). They are not placed yet; check or regenerate them before integration.
- Kit/Elder meshes (weapons, hats, Elder trunk/crown/heart/roots, DohyoRing, PhantomBoat, SapSprout, LilyCrown) are generated but not wired: Weapons.luau and ElderService still build parts. That wiring is section 5 integration.
- Trees and boulders as Hull colliders: walk-into tested only by verify_build, not by walking.
- Map look: dusk lighting tuned in the polish pass (see below); terrain still renders textureless on this network.
- Phase Select layout on phone sizes: not run in the Device Simulator.

## Debts
- FALLBACK (logged, 3d-meshes): Studio generate_mesh instead of the roblox-3d-model pipeline. Not healed. It needs ROBLOX_API_KEY to upload, which is an external blocker.
- The section-2 map fallback (flat FallbackShore) is HEALED: the proven map is installed and the game no longer builds the fallback.
- generate_mesh hit "Rate limit exceeded" on 13 of 27 parallel jobs. They were retried 3 at a time and all succeeded.
- Studio closed between sessions. It was reopened on the saved place and nothing was lost.
- Interventions: none. The user said "continue using studio", which is not an intervention.

## Polish pass after section 3 (2026-11-23)

The user asked, after the section 3 close, to run the game, fix all bugs, improve the UI and gameplay, and fix the many visual bugs. That names THAT, not WHAT, so it is not an intervention (ledger note, stage playtest).

**Root cause of most of the visual bugs: the network, not the game.** This machine's network runs Sophos HTTPS inspection, which re-signs roblox.com and rbxcdn.com. Studio's CDN fetches fail with `TlsVerificationFail`, so avatar meshes, default animations, sounds, prop textures, terrain material textures and the Fabric/Grass part materials never load. The user's fix is IT-side: trust the org CA, exempt `*.roblox.com` and `*.rbxcdn.com` from inspection, or use another network. Never install the certificate from here.

Measured engine behaviour under it, which the code now works around:
- A BillboardGui with `AlwaysOnTop = true` does not render. World text that must show through bodies goes on the `WorldOverlay` ScreenGui, projected with `Camera:WorldToViewportPoint` each frame.
- MeshParts inside a Model that has a Humanoid do not draw when their mesh fetch fails, while the same parts under Workspace do. So the Elder's tree stays outside its combat model, linked by an ObjectValue `Body`.
- Clearing a failed TextureID renders the prop black. A Highlight per prop kind (FallbackController, at most 16 groups) tints it instead.
- Fabric, Grass, Granite, Ground and LeafyGrass render near-black or dull. Plastic, SmoothPlastic, Neon, Wood, WoodPlanks, Slate, Metal, Glass and Limestone are fine. Kit cloth and VFX leaves and straw now use SmoothPlastic.

Fixes, each checked in a playtest:
- FallbackController: stand-in bodies with a natural skin tone; failed-texture props tinted by kind (the torii is red, the pines green, the lanterns cream).
- NameplateController: damage numbers and the relation indicator moved to the projected overlay. Numbers pop to one side of the body and rise a little, instead of running through the nameplate.
- HudController: the M1 slot's icon, name and combo pips no longer overlap; cooldowns dim the slot; the HUD hides under Phase Select and the Death Recap.
- SelectController: the button reads CROSS on first pick and CROSS AGAIN after; the Death Recap is a compact card.
- ElderService: the tree draws, shudders awake, sinks on defeat and regrows in the grove. The boss bar is filled during the 3 s wake.
- VfxController: the Thousand-Root Bloom trunk stands ahead of Tsuta, so it no longer blocks the camera. Festival of a Thousand Drums ghosts the drums next to each viewer's camera. The Elder's tree flashes when hit.
- CombatService: The River Returns hitboxes are 26 studs tall. The wave carries victims 40+ studs up the shore, and the drain was missing them.
- Lighting: dusk values in `default.project.json`. The terrain Rock material is recoloured to (112, 106, 88) in the place. `work/map/dress_landmarks.lua` dresses the lantern and the dormant Elder and colours the props.
- Kit test: all 5 fighters cast Ability1 to 4 and their Ultimate at a dummy. There were no non-network errors in the server or client logs.
- Gates: check.py all green (328 tests), luau-lsp 0 errors.

Still open:
- Sounds cannot play on this network, and no code fix exists for that.
- PhaseNameplate still needs a second player.

## The Wilds: NPC enemies, wardens and open world (2026-11-24)

The user asked for NPC enemies and bosses, creative characters built in Studio in the same dark-fantasy mood, and a full battleground with open-world elements. They named the request, not what was wrong, so it is logged as an intervention (a scope addition). Every character comes from public-domain folklore: Sanzu river, the ox-headed hell jailer, the kasha cat, the fox wedding procession and the datsue-ba robe-taker. None comes from any anime.

**World.** Three floating islands, each joined to the Far Shore by a plank bridge, with a Ferry Lantern fast-travel network that unlocks once you have visited an island. They are no-PvP zones.
- Gatewaste (Earth, west): the Hell Gate, cages and braziers. Warden: **Ox-Head Jailer**.
- Lantern Road (Fire, east): a torii tunnel, a fox shrine, a paper market and maples. Warden: **The Lantern Bride**.
- Robe Shallows (Water, south): the Robe Tree, a moat, pools, reeds and grave stupas. Warden: **The Robe-Taker**.
- The island builder is `work/map/build_wilds.lua`. It writes terrain and props under `Workspace.FarShore.Wilds`, and they live only in the saved place.

**Creatures.** All are R6 Motor6D rigs built from parts, defined in `src/server/Lib/Creatures.luau`.
- Ordinary creatures: Blossom Husk, Lantern Kasha, Stone Acolyte, Nail Ronin and Drowned Ferryhand.
- Wardens: three bosses at 2.6–3× scale, with 3–4 attacks each and an enraged move below 50% HP.
- Every attack is telegraphed on the ground: circle, cone, lane, donut, charge, projectile or blink.
- There are 9 camps, 31 creatures in all.

**Rewards.**
- Lily Petals for a kill.
- 60 Petals to everyone who dealt 5% or more of a warden's HP.
- An announce in the kill feed, and Thirst build-up.
- Camps respawn after 30–35 s and wardens after 180 s, with an announce.

**HUD.**
- Zone banner.
- Field-boss bar, with an ENRAGED state.
- Minimap.
- World map on M or Select.

**Code.**
- Data: `src/shared/Wilds.luau`.
- AI, spawning and travel: `src/server/Services/WildsService.luau`.
- Telegraphs, HUD and maps: `src/client/Controllers/WildsController.luau`.
- Remote: `WildsFx`.
- Spec: `tests/wilds.spec.luau`.
- Debug: `Debug:Invoke("wilds")`.

**Bug found while balancing.** The Roblox default character `Health` script healed 1% of MaxHealth every second. That undid creature chip damage, and it bypassed Mend and Purify. `src/character/Health.server.luau` (in StarterCharacterScripts) replaces it with an empty script. Measured: 0 HP regenerated in 4 s.

**Balance, measured with a bot that never blocks or dodges.**
- Iwao at 120 HP cleared a pack of 3 Kasha in 29 s and finished at 43 HP.
- Packs take turns: MAX_ATTACKERS = 1, with a 0.35 s gap between swings.
- Creature HP: 70–95 for ordinary creatures, 160 for the Acolyte, 650–750 for wardens.
- A warden kills a standing-still solo player in about 30 s, so wardens are built as group fights.

**Verified in play.** Spawns, aggro, every attack kind, damage, the boss kill and its 60-Petal share, ferry travel both ways, the HUD and both maps. No script errors were recorded by a ScriptContext.Error collector.

**Studio.**
- studio_id this session: `f189e845-168b-43b3-8071-bdeb334e80dd`.
- Backup taken before the Wilds were built: `places/HiganbanaBattlegrounds.pre-wilds.rbxl`.
- Screenshots: `assets/wilds/`.

**Unproven.**
- The 180 s warden respawn announce was not waited out.
- No second player was available.
- Sounds still cannot play on this network.

## Ledger

Initialised once in section 1. Never run `init` again.

```bash
python ~/.claude/skills/roblox-build-orchestrator/scripts/run_log.py counter --dir "D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds\build-runs" --run "higanbana-battlegrounds"
```

## Place
- `D:/Antigravity/Roblx/roblox/games/HiganbanaBattlegrounds/places/HiganbanaBattlegrounds.rbxl`, saved 2026-11-23 at the section 3 close. It is the ONLY copy of the installed map and meshes: `rojo build` does not contain them.
- The Studio window's studio_id in the polish pass was `4802d8b8-e05e-4d95-b8e7-fb167b879802`. Re-list it in a new session.
- Re-saved 2026-11-23 after the polish pass (all `src/` changes synced in).
- No universe/place minted; ROBLOX_API_KEY unset.

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
Section 4: Motion and sound (7 animation, 8 vfx, 9 sfx).
Restart the local servers if they are down: `python -m http.server 8766 --bind 127.0.0.1 --directory src` from the game folder. Use `python3` for the map/skill scripts, because `python` no longer has numpy. Then open `design/animations.json` and run the roblox-animation skill for the clips it lists, writing `assets/animations/manifest.json`. Do vfx (`design/vfx.json`) and sfx (`design/sfx.json`) after that.

## Earlier handoffs

- `D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds\design\handoffs\HANDOFF-section-1.md`
- `D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds\design\handoffs\HANDOFF-section-2.md`
