# Higanbana Battlegrounds: research findings (section 1, 2026-11-20)

## The brief and the line it does not cross

The user asked for a Roblox game that "mimics" *Hell's Paradise: Jigokuraku*, built from the
Tidebell Battlegrounds engine. The genre is therefore fixed: **Roblox battlegrounds** (anime-style
free-for-all PvP brawler), the genre Tidebell already is.

What this game does **not** take from that anime: its name, characters, character designs,
named powers, places, factions, plot, logo, music or look. That is a hard line, not a style
choice, and it is enforced in code: section 2 ports Tidebell's `tests/originality.spec.luau`
into this game (its banned-name list, plus `jubokko`, see below), so the build fails if any of
those names appear in source or data.

What it **does** take is the genre and the mood the user is after (dark, beautiful-and-deadly
Japanese fantasy; life-force martial arts with elemental affinities; immortal things that only
the right element can wound), built from public-domain sources:

| Source (public domain) | What the game uses it for |
|---|---|
| *Wuxing*, the Chinese Five Phases: Wood, Fire, Earth, Metal, Water, with a generating cycle (Wood → Fire → Earth → Metal → Water → Wood) and an overcoming cycle (Wood → Earth → Water → Fire → Metal → Wood) [1] | The combat relation system: every pair of fighters is Overcome, Resisted, Feeding or Drawing. Phase colours follow the traditional ones [1] |
| *Higanbana* (Lycoris radiata), "the flower of the higan", the other shore; tied to the autumn equinox, graves and the far bank of the Sanzu River, "a heavy connotation to death and afterlife"; poisonous [2] | Title, setting and palette: a field of red spider lilies on the far shore of the river of the dead |
| *Sai no Kawara*, the riverbank where the souls of children stack stones that demons knock down, and Jizo shelters them in his robe [3] | The training ground: a pebble beach of stone cairns and red-bibbed Jizo statues |
| Edo-period archetypes: taiko war drummer, sumo wrestler, *jitte*-carrying constable, shrine keeper with a *wagasa*, river ferryman paid six coins | The five fighters. None of them matches a character from the anime (no fire shinobi, no woman executioner with a katana, no thread-using kunoichi, no giant-sword samurai, no bandit) |

**One name dropped on research:** the blood-drinking battlefield tree *jubokko* has no earlier
folklore record, and researchers suspect it was invented by Shigeru Mizuki (*GeGeGe no Kitarō*) [4].
It may be someone's creation, so the boss is an original tree, **the Thirsting Elder**, and
`jubokko` joins the banned-name list.

**Content maturity:** the anime is gory; this game has no blood. Hits spill *Ki* (glowing
crimson motes), and the Elder drinks Ki and sap, not blood. That keeps the experience inside
Roblox's mild-violence band for a 9+ audience (checked again at publish by `roblox-policy-compliance`).

## Market read

| Game | Figures (source, date) | Read |
|---|---|---|
| Jujutsu Shenanigans | 84K concurrent, 8B visits, 86.3% rating [5]; ~178,000 playing, "riding the 2026 fighting-game wave" (June 2026) [6] | The genre leader. A homage to one anime; its players arrive with that show's seasons |
| The Strongest Battlegrounds | 42.5K concurrent, 19.7B visits [5]; formerly "Saitama Battlegrounds", released 2 Aug 2022 [7*] | The genre's biggest lifetime title, now second. Also an anime homage |
| Long tail: Anime Ability Arena 5.4K, Legends Battlegrounds 4.7K, Jujutsu Beatdown 4.3K, Heroes Battlegrounds 3.7K (1.8B visits) [5] | | Saturated with anime-IP homages; large lifetime visits show the audience is durable |
| Ragdoll MMA titles | -15% to -20% in 24h [5] | A single-day reading; weak signal |
| The sub-genre | "Battlegrounds & Fighting": 657.2K players [5] | Big, healthy, growing in 2026 [6] |

**Where the gap is (my reading, not a source's claim):** nearly every battlegrounds hit is a
re-skin of someone else's anime. That gives instant recognition but no ownership: no
coherent world of its own, takedown risk, and traffic that rises and falls with another
company's release calendar. The sources give player numbers, not design analysis, so the
design bets below are judgement:

1. **An original world with a strong look.** Dark ukiyo-e afterlife (spider lilies, river of
   the dead, Jizo, ferry lanterns) stands apart from the bright shonen look of the leaders.
2. **A readable matchup layer.** The Five Phases make every fight a counter-pick question that
   a player can learn in one minute (red arrow = you overcome them; green leaf = you are
   feeding them). Neither leader has a system like it.
3. **PvP that feeds a PvE event.** Every hit spills Ki into the soil; when the server has spilled
   enough, the Thirsting Elder wakes, and only the phase that overcomes its current phase can
   wound it. The brawl turns into a raid without a timer.

## Decisions taken in this section

- Genre: battlegrounds (fixed by the brief). Theme: the far shore of the river of the dead.
- Build from the Tidebell engine (server-authoritative services, client controllers, Remotes in
  `default.project.json`), forked into this folder in section 2. The Knit scaffold that
  `new_game.py` laid down is replaced, per the repo rule to follow the framework the game
  already uses.
- Five fighters, one per phase; one world boss; one map; session-only stats.
- Out of scope this build: saving, shop and Robux, quests, teams and parties, trading, more
  fighters, a second map.

## Sources

Opened and read:

1. Wikipedia, "Wuxing (Chinese philosophy)": https://en.wikipedia.org/wiki/Wuxing_(Chinese_philosophy)
2. Wikipedia, "Lycoris radiata": https://en.wikipedia.org/wiki/Lycoris_radiata
3. Japan Tourism Agency multilingual guide (MLIT), "Audio Guide: Sai no Kawara": https://www.mlit.go.jp/tagengo-db/en/R1-02817.html
5. Bloxodes, "Top Trending Roblox Battlegrounds & Fighting Games" (2026 stats table, no snapshot date): https://bloxodes.com/lists/top-trending-roblox-battlegrounds-fighting-games
6. RoWatcher, "The Most Popular Roblox Games Right Now, Ranked by Live Players" (June 2026): https://rowatcher.com/news/the-most-popular-roblox-games-right-now-ranked-by-live-players

Search excerpts only (marked * where cited; the page itself was not read):

4. Wikipedia, "Jubokko" (origin doubtful; suspected Mizuki invention): https://en.wikipedia.org/wiki/Jubokko
7. Sportskeeda, "The Strongest Battlegrounds: how to play": https://www.sportskeeda.com/roblox-news/roblox-the-strongest-battlegrounds-how-play-gamepasses
8. esports.gg, "Best Roblox games" (claims The Strongest Battlegrounds' fall and Jujutsu Shenanigans' lead; the fetch failed with a certificate error): https://esports.gg/news/best-roblox-games
9. ExitLag, "Roblox game genres and popularity" (HTTP 403): https://www.exitlag.com/blog/roblox-game-genres-and-popularity/

Origins counted: five pages opened from five different publishers; four more seen only as
search excerpts.

## References for later sections (download before building, never build from imagination)

- Map: Osorezan's Sai no Kawara (Aomori; barren stone fields, cairns, pinwheels), Kinchakuda
  spider-lily fields (Saitama), dry gravel riverbeds with beached wooden boats, a Japanese
  stone arch bridge (Meganebashi, Nagasaki).
- Animation: taiko drummers' ready stance, sumo *shiko* and *tachiai*, jitte kata photographs,
  sculling-oar ferrymen, wagasa carry.
