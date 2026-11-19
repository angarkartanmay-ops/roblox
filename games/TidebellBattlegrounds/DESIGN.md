# Tidebell Battlegrounds: game design

> When the bell rises, the island rises. The last one standing strikes it.

A free-for-all, anime-style battlegrounds game on a drowned temple-island. Pick one of five
champions, each sworn to one of the Five Great Elements, fight in the Toll Plaza, and survive the
Tide Warden when the island wakes.

## Originality

This game is its own world. It takes its genre (Roblox battlegrounds) and public-domain material:
- the Japanese *godai*, the five great elements Earth, Water, Fire, Wind and Void (as in Miyamoto
  Musashi's *Book of Five Rings*);
- Edo-era temple architecture, *bonshō* temple bells and stone lanterns;
- folk tales of villages drowned by the sea.

No character, name, power, place or plot comes from an existing anime, manga or game.
`tests/originality.spec.luau` fails the test run if names from *Hell's Paradise: Jigokuraku*
appear anywhere in the game's data, so the line stays clear as the roster grows.

## Story

Six hundred years ago a temple-town on the island of **Kanejima** was swallowed by the sea in a
single night. Its great bronze bell, the **Tide Bell**, went down with it, still ringing.

Once every sixty years, when an eclipse lines up with the spring tide, the bell rises and the
island rises with it. Folk say that whoever strikes the Tide Bell while the eclipse holds may call
back **one thing the sea has taken**.

Five martial schools, each sworn to one Great Element, send a champion. Only the last fighter
standing may ring the bell. But the island remembers its oath: when the fighting grows too loud,
the bell's guardian, the **Tide Warden**, a colossus of barnacled bronze, climbs out of the deep.

Planned acts (live updates):
1. **The Rising** (this build): the island surfaces; champions arrive; the Warden wakes.
2. **The Drowned Abbots**: lesser guardians haunt the grove and the bell tower.
3. **The Eclipse Toll**: a timed server-wide finale where the winner rings the bell.

## The five champions

| Champion | Element | Role | Difficulty | What the sea took |
|---|---|---|---|---|
| **Stonebreaker**, Abbot Kozan of the Sunken Quarry | Earth | Bruiser | ★ | His quarry-temple and forty brothers |
| **Tide Dancer**, Sayo of the Pearl Reefs | Water | Controller | ★★ | Her twin sister, lost diving the reef |
| **Lantern Fox**, Kiyo of the Lantern Troupe | Fire | Zoner | ★★ | The troupe's ship; she wears its last mask |
| **Gale Courier**, Shun of the High Passes | Wind | Assassin | ★★★ | His mother's last, undelivered letter |
| **Bell Monk**, Brother Joen | Void | Disruptor | ★★★ | His voice, given up ringing the flood warning |

Every champion keeps the player's own avatar and adds a school sash, a weapon and an element tint.

### Stonebreaker (Earth) and the stone maul
- **M1**: slow, heavy four-hit chain; the fourth hit sends the target flying.
- **1 Quake Stomp**: stomp that stuns everyone around him and **breaks guard**.
- **2 Boulder Heave**: hurls a boulder that knocks back the first target.
- **3 Granite Hide**: four seconds of stone skin: half damage taken, cannot be stunned.
- **4 Rockline Rush**: shoulder charge that drags enemies along the line.
- **G Mountainfall** (ultimate): leaps skyward and lands in a guard-breaking crater.

### Tide Dancer (Water) and the naginata
- **M1**: long-reach polearm chain.
- **1 Crescent Wave**: a piercing water crescent.
- **2 Undertow**: drags enemies in front of her toward her.
- **3 Mist Step**: dashes away, leaving a mist that slows pursuers.
- **4 Whirlpool Spin**: three spinning sweeps; the last throws enemies outward.
- **G Drowning Tide** (ultimate): a giant piercing wave that slows everyone it hits.

### Lantern Fox (Fire) and the iron war fans
- **M1**: fast fan strikes.
- **1 Foxfire**: three homing fox-flames.
- **2 Fan Blaze**: a three-tick cone of flame that sets enemies burning.
- **3 Ember Hop**: backflip escape that bursts into fire where she stood.
- **4 Lantern Snare**: a lantern that explodes on contact, launching and burning.
- **G Hundred Lanterns** (ultimate): lanterns rain over an area, then the night explodes.

### Gale Courier (Wind) and the chain sickles
- **M1**: very fast sickle chain.
- **1 Cyclone Kick**: launcher kick that juggles the target upward.
- **2 Sickle Boomerang**: a sickle that flies out and returns, cutting both ways.
- **3 Updraft**: launches himself skyward, tossing nearby enemies up.
- **4 Slipstream**: dashes through enemies, cutting everyone on the path.
- **G Thousand Gusts** (ultimate): blinks around a target six times, then blows them away.

### Bell Monk (Void) and the ringed staff
- **M1**: staff chain.
- **1 Echo Strike**: a palm strike whose echo hits the same target again a moment later.
- **2 Hush**: a silent pulse that **silences** abilities around him.
- **3 Null Step**: vanishes and reappears behind the nearest enemy, striking.
- **4 Resonant Ward**: a short counter stance; melee hits are reflected into a counterattack.
- **G Toll of the Deep** (ultimate): a spectral bell drops on an area, then its toll silences.

## Combat rules

| Rule | Value |
|---|---|
| M1 chain | 4 hits; resets after 1.1 s; the 4th hit knocks back and locks M1 for 1 s |
| Block (hold) | Front-facing. Blocks M1 fully, abilities take 40 %; drains the 100-point guard |
| Guard break | Guard at 0, or a guard-breaking move: stunned for 1.6 s |
| Parry | Raise block within 0.22 s of an M1 landing: attacker is stunned for 1.25 s |
| Dash | 1.8 s cooldown |
| Resonance | Fills from damage dealt (×1.2) and taken (×0.6); at 100 the ultimate (G) unlocks |
| Statuses | Stun, Slow, Silence (no abilities), Burn (damage over time), Stone Skin (armor) |

### The element wheel

Every pair of different elements has a winner. Each element beats two and loses to two:

| Element | Beats | Because |
|---|---|---|
| Water | Fire, Earth | douses fire, erodes stone |
| Fire | Wind, Void | devours the air, lights the dark |
| Wind | Earth, Water | scours stone, scatters the sea |
| Earth | Void, Fire | anchors the void, smothers flame |
| Void | Water, Wind | swallows the tide, stills the wind |

An advantaged hit deals **+15 %** damage and **+50 %** guard damage; a disadvantaged one deals
**−10 %**. Mirror matches are neutral.

## The Tide Warden (world boss)

Wakes 2.5 minutes after the server starts, then 6 minutes after each defeat. Health scales with
the server: 1,800 + 350 per player. Water element; cannot be stunned or knocked back.

| Attack | Tell | Effect |
|---|---|---|
| Bell Slam | Red ring under a player for 1.2 s | Heavy area hit, launches |
| Undertow Sweep | Red cone in front for 0.9 s | Cone hit that drags players in |
| Tide Toll | Warden raises its arms for 2 s | An expanding shock ring: **jump over it** |

Below 40 % health it enrages: faster attacks and movement. Everyone who dealt at least 4 % of its
health earns 30 Bell Shards and **Tide-Blessed** (+10 % damage for 90 s).

## Kanejima (the map)

- **Toll Plaza** (centre): the stone arena, with the Five Seals (one short pillar per element)
  and broken pillars for cover.
- **Bell Tower** (north): the ruined tower holding the Tide Bell; the Warden climbs out in front of it.
- **Shrine of Arrival** (south): the spawn pier and safe zone (no damage); fighter-select altar.
- **Training Grounds** (west): three dummies (a striker, a blocking guard dummy, a heavy dummy)
  showing their element so players can practise the wheel.
- **Drowned Grove** (east): dead trees and tide pools.
- Mood: eclipse dusk, warm sun against teal fog, Future lighting with bloom and sun rays.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| M1 (hold to chain) | Left click | R2 | ATTACK |
| Block (hold) | F | L2 | BLOCK |
| Dash | Q | B | DASH |
| Abilities 1-4 | 1, 2, 3, 4 | X, Y, L1, R1 | ability buttons |
| Ultimate | G | D-pad up | ULT button |
| Choose fighter | T, or the altar at spawn | D-pad down | FIGHTERS button |

Attacks turn the character toward the camera, so shift lock is optional.

## Progression and economy (this build)

Session stats: **Kills**, kill **Streak** (announced at 3, 5 and 10) and **Bell Shards**
(+5 per kill, +2 per streak step above 2, +30 per Warden defeat). Shards persist only for the session.
Next: saving (ProfileStore), a cosmetics shop for sashes, trails and aura colours, and daily quests.

## Build notes

- No uploaded assets are required: animation is procedural (Motor6D/AnimationConstraint transforms
  driven on every client), VFX are built from neon parts, trails and built-in particle textures,
  and weapons are assembled from parts at spawn.
- The server owns cooldowns, hit detection, damage, statuses and the boss; clients send intents and
  render.
- Sounds use built-in `rbxasset://` sounds as placeholders; swap them for Creator Store sounds with
  the `roblox-sfx` skill once Studio is connected.
