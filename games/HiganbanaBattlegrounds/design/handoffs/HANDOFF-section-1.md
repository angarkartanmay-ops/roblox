<!-- section: 1 -->
# HANDOFF: section 1 of 6 closed (Research and design)

Game: `D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds`
Written: 2026-11-20T11:09:35+05:30

A cleared session starts from this file alone. Read it in full, then run:

```bash
python ~/.claude/skills/create-roblox-game/scripts/section.py resume --dir "D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds"
```

(On this machine the skills live in the repo, not `~/.claude`: use
`d:\Antigravity\Roblx\roblox\.claude\skills\create-roblox-game\scripts\section.py`, and set
`$env:ROBLOX_GAMES_HOME = "d:\Antigravity\Roblx\roblox\games"` first. See `LOCAL.md` in that skill.)

## Where things are
- `design/game.json`: the contract. Pitch, core loop, win/lose, the Five Phases rules (`phases`), the five fighters with every move (`roster`), the Thirsting Elder (`elder`), 16 systems with what each owns, 68 config tunables, the 23-section plan, and the asset plan (50 entities).
- `design/research.md`: research findings, the originality line, public-domain sources, market read, numbered source list.
- `design/map.json`: the Far Shore in roblox-map format (terrain landforms, pads, paths, zones, greybox parts, spawns, `open_edges`, `references`, `dressing_plan`).
- `design/meshes.json`: 35 meshes (name, studs, tris, use, attach, paint, prompt) plus the palette.
- `design/animations.json`: 61 clips (R15 and the Elder's Motor6D rig), markers at contact frames, a weapon `_intent` sentence for every weapon clip.
- `design/vfx.json`: 80 effects (kind, attach, colour, seconds, look, library search words).
- `design/sfx.json`: 72 sound roles in roblox-sfx format (query, kind, length band, volume, looped).
- `design/ui.json`: the UI theme, phase glyphs, 49-icon manifest, 4 screens and 4 billboard templates with every instance name the asset plan checks for.
- `build-runs/higanbana-battlegrounds/`: the ledger (`meta.json`, `events.jsonl`, `counter.txt`).
- `src/`, `tests/`, `lune/`, `default.project.json` and the other root files are the Knit template `new_game.py` laid down. They are NOT the game's code: section 2 replaces them with the Tidebell fork.
- `d:\Antigravity\Roblx\roblox\.claude\skills\create-roblox-game\LOCAL.md`: this machine's paths, tools and missing keys.
- Studio: nothing was created or changed in Studio for this game.

## Done this section
- Preflight: Rokit toolchain present (Rojo 7.7.1, Lune 0.11.1, Selene 0.31.0, StyLua 2.6.0, luau-lsp 1.70.1, Wally 0.3.2, darklua 0.19.0); Studio MCP `roblox-studio` connected; Blender absent; `ROBLOX_API_KEY` and `HF_TOKEN` unset.
- Research written to `design/research.md` from 5 opened pages (5 publishers) and 4 search excerpts.
- Contract: `validate.py --dir <game>` passes: "contract valid", 21 plan sections answered, 2 declined (data_saving, monetisation), 0 unaddressed.
- Asset plan against the stage specs, checked by script: meshes 35/35, animation 61/61, vfx 80/80, sfx 72/72, ui 25/25 plan names present in the specs; no duplicates, no unplanned extras.
- Map spec dry run: `roblox-map/scripts/terrain.py design/map.json` generated a 160x160-column heightfield. Measured: landing 44.0, bed floor 22.2 to 23.6 under every boat and cairn, Jizo Beach 26.0, grove 52.0, Lily Hill 54.3, Pine Bluff 56.6, pier end over a 39.1 bank. Bank profile at x=0 rises 22 to 44 between z=0 and z=±80.

## Decisions and why
- Genre: battlegrounds (named by the brief). The request was a "Hell's Paradise mimic", so the game takes the genre and mood only and none of the anime's names, characters, designs, powers, places or plot. Reason: the user's LOCAL.md preference is original games only, and the IP is someone else's. Enforced in code from section 2 by the originality spec.
- World from public-domain sources: Wuxing Five Phases, higanbana and the Sanzu far shore, Sai no Kawara and Jizo, Edo archetypes for the fighters.
- The blood-drinking tree "jubokko" was dropped (likely Shigeru Mizuki's invention) in favour of an original boss, the Thirsting Elder; "jubokko" joins the banned list.
- No blood: hits spill crimson Ki motes. Reason: 9+ audience, mild violence.
- Five fighters, one per phase, so every phase has an identical matchup profile (balanced by construction): Tsuta (Wood, wagasa), Hibiki (Fire, taiko bachi), Iwao (Earth, sumo), Kanemori (Metal, jitte), Rokumon (Water, ferry oar).
- PvP feeds PvE: total damage between players fills the Thirst; the Elder wakes and only the phase that overcomes its cycling heart wounds it. Reason: the market gap in research.md (leaders have no matchup layer and no PvP-fed event).
- Session-only stats, no shop, no datastore (scope law); monetisation and data_saving declined with reasons in the plan.
- Engine: fork Tidebell Battlegrounds (server services, client controllers, Remotes in default.project.json, no Knit). Reason: the repo rule to follow the framework the game already uses, and Tidebell already proves the combat core (166 Lune specs passing).
- Map: a plateau over a sea of mist; the edges are the ring-out boundary (`open_edges`), no barrier walls. The tide is set below the sea floor so the river is dry. The greybox parts carry no mesh, because T9 judges a dressed map as a whole; `dressing_plan` lists the swaps for section 3.
- The Elder is a rigid Motor6D rig of five MeshParts (no skinning), so it can be animated without Blender skinning.
- Idles pose the upper body only at Idle priority, so the default walk keeps driving the legs.
- UI: dark lacquer theme with bone-white text (art direction); phase badges are the Five Phases' own characters drawn as text, not generated icons.

## Unproven
- The map prover has not run. Bank slopes at x=0 measure about 22 to 26 degrees in places; if the prover's walk limit (24) fails them, widen the SanzuBed profile.
- No mesh, icon or concept prompt has been run through a generator.
- No SFX query has been searched in the Creator Store.
- No weapon `_intent` has been checked against reference photographs yet (required before authoring each clip).
- The market figures come from one aggregator page with no snapshot date (research.md source 5) plus one dated article (source 6).
- The Tidebell fork has not been copied or built in this folder.
- The Five Phases balance claim (identical profile per phase) is reasoning, not yet a Lune spec.

## Debts
- Ledger: 0 interventions, 0 fallbacks, 0 stalls (`run_log.py debts`: clean).
- The design-spec ledger stage ran 2h02m against a 45m budget (+77m). Over budget, nothing skipped.
- Blockers waiting for later sections (not fallbacks yet; each becomes a declared external debt only if its stage cannot run):
  - Blender not installed: blocks the roblox-3d-model and roblox-animation routes (sections 3, 4). Pre-authorised fallbacks are written into `meshes.json` and `animations.json` `routes`.
  - `HF_TOKEN` unset (mesh concept and image-to-3D).
  - `CF_ACCOUNT_ID` and `CF_API_TOKEN` unset (icon generation, section 3).
  - `ROBLOX_API_KEY` unset (uploads and publish, sections 3 to 6).
  - The roblox-vfx library is empty: section 4 starts by harvesting a pack.
  - The Tidebell engine carries 51 unique strict-mode luau-lsp errors; the fork inherits them and section 2 fixes them.
- This environment has no screen-access request tool, so rule 6 cannot be followed literally; Studio is reached through the `roblox-studio` MCP (`execute_luau`, `screen_capture`).

## Ledger

Initialised once in section 1. Never run `init` again.

```bash
python ~/.claude/skills/roblox-build-orchestrator/scripts/run_log.py counter --dir "D:\Antigravity\Roblx\roblox\games\HiganbanaBattlegrounds\build-runs" --run "higanbana-battlegrounds"
```

## Place
No place exists for this game yet, and no universe or place id is minted (`publish` ids are null in game.json). Nothing for this game was put in Studio, so there was nothing to save. Section 2 creates the place: `rojo build -o build/HiganbanaBattlegrounds.rbxl`, opened in Studio and saved to disk before any Studio work.

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
Section 2: Code and the playable loop (3 code, 4 map BLOCKOUT only, then play the loop on placeholder art).

First action, in PowerShell with the Rokit tools on PATH (`$env:Path = "$env:USERPROFILE\.rokit\bin;$env:Path"`):

1. `python d:\Antigravity\Roblx\roblox\.claude\skills\create-roblox-game\scripts\section.py resume --game "higanbana" --expect 2`
2. Replace the Knit template with the Tidebell fork: delete this game's `src/`, `tests/`, `lune/` and `default.project.json`, then copy those four from `d:\Antigravity\Roblx\roblox\games\TidebellBattlegrounds`. Keep `design/`, `HANDOFF.md` and `build-runs/`.
3. In `tests/originality.spec.luau` add `"jubokko"` to BANNED, then run `lune run test` before changing any game code, so the fork starts green.
4. Then rename and rebuild the content from `design/game.json`: Elements to Phases (generating and overcoming tables, the four relations), the five fighters and moves, Ki and Mend, ThirstService and ElderService, config from `config`.
