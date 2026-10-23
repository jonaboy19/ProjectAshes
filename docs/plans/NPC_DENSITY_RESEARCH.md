# NPC density research: fewer agents, living world

Scope: how shipped games keep towns alive with few fully simulated NPCs, then a mapping to Rising Ashes (Godot 4.6).
Evidence grading: **[P]** primary (dev talk/abstract/official), **[S]** secondary press/community, **[N]** not found / unverified.
Honest caveat: many GDC Vault pages and the KCD GDC slides returned 403/maintenance, so most hard ms numbers are NOT public in what I could reach. Numbers marked [N] must not be treated as facts.

## 1. What the AAA games do (sourced)

| Game | Known facts | Grade |
|---|---|---|
| **Assassin's Creed Unity** | GDC 2015 "Massive Crowd: AI Recycling": budget of **40 real AIs and 120 high-res models** supports **10,000 crowd NPCs** on screen. A pooling system swaps low-res NPCs for high-res ones unnoticed (AI LOD, "recycling"). Separate talk covers systemic crowd events (fistfights, pickpockets) marshalling hundreds of NPCs. ms/frame: [N]. | [P] abstract |
| **Kingdom Come: Deliverance 1/2** | KCD1 had ~600 simultaneously active NPCs (2018 Smrcek slides, via search snippet); KCD2 quadruples NPCs on the map to **nearly 2,400, about half in one city (Kuttenberg)**. New AI LOD was needed to hold frame time and memory, and the scripting interface was kept **oblivious to the LOD** (scripts do not know which tier an NPC is in). Talk topics: thread use, moving standardised logic into code, "knowing what can be stripped away". Community reports say Kuttenberg was optimised with simplified NPC routines and line-of-sight blockers such as market stalls (unverified); NPC density is the biggest FPS lever there. Tier names/frame budgets: [N]. | [P] GDC abstract / [S] |
| **Witcher 3** | Schedules use **pools of spots, not fixed paths**; Novigrad harbour had 200 possible locations for 50 sailors. Mostly hand-authored routines and weather shelter. Fear/flee system caused dropped-baby bugs. No public LOD numbers. | [S] Edge/PC Gamer/GameStar interviews |
| **Oblivion / Skyrim (Radiant AI)** | Engine has **4 AI process levels** (High 0, Middle-high 1, Middle-low 2, Low 3): update frequency falls with distance; High = actors in the player's cell/loaded area. Scripts for Middle ~ every 18 s real time, Low ~ every 2 min once the cell unloads. Fallout 3 GECK lists High = every frame, Low ~ every 120 s. Oblivion has 1000+ NPCs with 24 h schedules; schedules for unloaded actors are resolved by position-update on a coarse clock (Skyrim limitation: a loaded NPC can only be advanced about one hour; fast-travel destinations may not update). Lesson: schedule = a **function of time evaluated lazily**, not a continuous sim. | [S] UESP/CK wiki (partly bot-written, unverified) |
| **Red Dead Redemption 2** | Press: daily routines are scripted and run in a bubble around the player (critics note they switch off outside it); townsfolk remember encounters. No published LOD/count figures found; Digital Foundry coverage found was pre-release trailer only. | [S] |
| **Cyberpunk 2077** | No GDC/Digital Dragons crowd talk found. Observed (community): crowd NPCs are two kinds (just walking vs interacting with a prop/point), they despawn/respawn when you look away (random set), models drawn from a library (visible repeats), crowd density is the single biggest FPS setting; CDPR job ads for the sequel target the "most realistic and reactive crowd system". | [S] weak |
| **Dragon's Dogma 2** | Capcom said frame-rate problems were largely caused by NPC "thinking" in towns; Digital Foundry: heavily CPU bound by NPCs/enemies in dense towns; NPC draw distance cut on consoles so townsfolk pop in near the player. Title Update 3.2 (2026-09-02) added "NPC thinning" and a CPU power-saving mode; PCGH measured **no gain** (CPU load unchanged, up to 4.9% fps loss). Lesson: thinning only the drawn NPCs while leaving their AI running does not help; cut the thinking. | [S] Automaton, PCGH |
| **Mount & Blade II: Bannerlord** | Engine agent cap ~2040 (mounts count as agents; modder claim). Dev goal 800 characters at 60 fps; CPU bound by individual AI, formation AI, IK. No tier numbers. | [S] |
| **Manor Lords** | Update 7 reworked pathfinding (island rejection), locomotion/collision refactor; a 3000-resident + 2000-sheep save went from 2-5 to 30-40 fps after optimisation (Jan 2026). Lesson: pathfinding and collision among many agents dominate, not rendering. | [S] |
| **Mafia / GTA / Medieval Dynasty** | No technical sources found. GTA-style ambient population is commonly described as spawn-around-player with per-hour density curves and scenario points (benches, chatting) (mod-level source only). Do not cite as developer fact. | [N]/[S] |
| **VAT / GPU crowds** | GPU Gems 3 (NVIDIA): animation baked in textures, ~10,000 independently animated characters at 30 fps on old hardware. A 2020s VAT write-up: 6,000+ spectators at ~17.5 ms GPU with 276 draw calls, needs 16-bit float textures to avoid jitter. | [P] GPU Gems / [S] 80.lv |

### Cross-game pattern (synthesis, not a quote)

1. **Three populations, not one**: a tiny set of real thinking agents (AC Unity: 40), a bigger set of cheap animated bodies (120 high-res), and a huge set of dumb or no-AI visuals (10,000). Rising Ashes already has this shape; the budgets are just large.
2. **Simulation is a function of time + position, evaluated lazily** (Oblivion low-process, KCD LOD hiding LOD from scripts). Off-screen NPCs hold `(job, schedule slot, home/work/point)`; when you arrive, snap them to where the schedule says they are.
3. **Few agents, many places**: Witcher 3 gives each NPC a pool of spots; busy towns come from every spot being plausible and some being occupied, not from many agents.
4. **Cut thinking before cutting drawing** (DD2 lesson). AI/pathing/collision are the CPU cost; VAT/impostors are nearly free by comparison.
5. **Hide the pop**: respawn/swap outside the camera frustum, behind buildings, or at spawn doors/alleys (Cyberpunk, AC Unity, DD2 complaints show what happens when you do not).

## 2. Rising Ashes current state (read only)

Source: `kingdom/scripts/core/quality.gd`, `population/population_lod.gd`, `living_world/crowd_anim_lod.gd`, `docs/world/VALENCIOUS_WORLD.md`.

- World: 30 settlements, total residents about **10,170** (Kingsreach 1600; 5 towns 640-720; 4 frontier towns 360-380; villages 200-210, small villages 90). Radii 42-175 m.
- PopulationLOD: FULL_RANGE 45 m, SPRITE_RANGE 220 m, NEAR_ALWAYS 9 m, **NEAR_HARD_CAP 12**, **MAX_FULL 24**, **MAX_SPRITES 140**, VAT_RANGE 120 m, SPRITE_MIN_DIST 20 m. Tier values `npc_full`/`npc_sprites` are clamped by MAX_*.
- PC tiers (`npc_full / rig_budget / npc_sprites / crowd near_max`): LOW(PC_LOW) 16/6/60/8; MED 20/8/90/10; HIGH 28/12/140/14; ULTRA 36/16/200/18. Note PC_ULTRA `npc_full` 36 and `npc_sprites` 200 exceed MAX_FULL 24 / MAX_SPRITES 140, so those rows are **dead values** (clamped), plus NEAR_HARD_CAP 12 caps bodies in the 9 m zone. Mobile LOW is 5/0/10; mobile tiers 8/14/16 full and 22/32/45 sprites; ram8 cap 10/40.
- CrowdAnimLOD BUDGETS (near_max/near_dist/mid/far): idx0 3/10/26/110, idx1 5/12/32/130, idx2 8/14/40/150, idx3 12/18/50/180; PC tiers carry their own crowd rows (near full-rate 8-18, stepped MID, steps [1..4]); OFFSCREEN_STEP 8.

Observation: the full-body tier is already 16-36 on PC, i.e. 5-10x what AC Unity used as its true-AI budget. Anything above ~12 "thinking" bodies near the player is cost that the eye cannot distinguish from a well-staged 8.

## 3. Recommended numbers (PC)

Principle: **think-count small, body-count medium, visual-count large.** Tiers for the three populations:
- **A "thinking" (full AI, pathing, reactive, name tags, collision)**: hard cap, mostly named/role NPCs + anyone the player is interacting with.
- **B "simplified bodies"**: real skeleton at reduced animation rate, steering only along street graph/spline (no navmesh queries, no physics collider unless within 3 m), no per-NPC reactive presence.
- **C "VAT crowd"**: MultiMesh VAT instances on pre-baked loops along paths/POIs; zero nodes.
- **D "sprites/impostors"**: far billboards, no animation beyond 1-2 frame loops.

| Tier | A thinking (npc_full cap) | B simplified (CrowdAnimLOD near+mid body) | C VAT residents | D sprites | FULL_RANGE | VAT_RANGE | SPRITE_RANGE |
|---|---|---|---|---|---|---|---|
| PC_LOW | **8** (was 16) | 10 more (stepped 1/3, near_max 4) | 40 | 30 (was 60) | 32 m | 70 m | 140 m |
| PC_MED | **10** (was 20) | 14 | 70 | 50 (was 90) | 38 m | 90 m | 170 m |
| PC_HIGH | **14** (was 28) | 20 | 110 | 80 (was 140) | 45 m | 110 m | 200 m |
| PC_ULTRA | **18** (was 36 but clamped to 24) | 28 | 160 | 120 (was 200, clamped 140) | 50 m | 130 m | 240 m |

Constants: `MAX_FULL` 24 -> 18, `NEAR_HARD_CAP` 12 -> 8, `MAX_SPRITES` 140 -> 120; make `NEAR_HARD_CAP = min(8, npc_full)` so LOW is not forced above its budget. `rig_budget` (skeleton rigs animated at full rate): LOW 3, MED 5, HIGH 7, ULTRA 10 (roughly 1/2 of the thinking count; KCD/AC logic is that animation cost is the second wall). CrowdAnimLOD `near_max`: LOW 4 / MED 6 / HIGH 8 / ULTRA 10 with `steps` MID [2,3,4] on LOW/MED, [2,3,3] HIGH, [1,2,3] ULTRA; keep OFFSCREEN_STEP 8.

Target totals visible in a busy town centre (Kingsreach market, tier HIGH): 14 thinking + 20 simplified + about 110 VAT + background sprites = **~140-150 bodies on screen**, but only **14 doing AI work** and **~34 with real skeletons** (this is the AC Unity 40/120 shape). Today: up to 28+ thinking, 140 sprites.

Budgets to enforce with the existing `perf_probe.gd` (my targets, not published numbers): population AI total <= **1.0 ms** (LOW 1.5 ms) on HIGH tier at 60 fps; animation (all skeletons) <= **1.5 ms**; VAT/sprite update <= 0.3 ms; spawn/despawn <= 1 body per frame (already MAX_SPAWNS_PER_FRAME 1). If population exceeds budget, shrink `A` first (DD2 lesson), then `B`, never the VAT layer.

Memory/ram8 cap: keep at 10 thinking / 40 sprites; LOW 8 / 30 supersedes it.

## 4. What to cut or abstract

1. **Settlement residents ~10,170 become records, not agents**. Only the nearest settlement (or two) materialises; each resident is `(id, name?, job, home, work, schedule_seed)`. Everything beyond FULL/VAT range runs a coarse schedule clock (Oblivion low-process): re-evaluate once per game-hour (or every 30-60 s real time) and on arrival, place the NPC at the slot the schedule says (teleport-by-schedule, no walking). Existing SKIP_HOURS 0.5 is the right hook.
2. **Named vs generic split**: authored/named NPCs (quest givers, merchants, guards by name, recruitables, ~5-12 per village, 20-40 per town, 60 in Kingsreach) are the only ones that persist individual state. Generic residents are interchangeable from a pool of ~12-20 looks per region (AC Unity recycling): they may be re-rolled when off-screen without the player noticing; they should not carry unique memory/relationship state.
3. **Recruitable/settlement-founding NPCs** (the game's core) need persistent identity, so keep them as named records; make the generic crowd the abstract layer.
4. **Cut per-NPC systems from tiers B, C, D**: Reactive Presence (PresenceLive ~10 Hz) only for tier A and only the nearest 6; no physics contact bodies beyond 6 m (MAX_PHYSICS_CONTACT 8 -> 4); micro-events (`micro_events.gd`) become town-level events that pick 2-4 tier-B actors on demand rather than a polling sim per NPC; alert glyphs and name tags only for A within 25 m.
5. **Pathfinding**: B uses street graph/splines only, A uses navmesh with time-sliced requests (Manor Lords/Bannerlord lesson: pathing and collision dominate). Share path results per POI route (many agents, one precomputed path).
6. **Collision**: tier B/C/D agents ignore each other (soft avoidance via lane offsets and speed jitter), only collide with the player and weapons within 3 m.
7. **Scripting interface oblivious to LOD (KCD2)**: expose `npc.do(job)`, `npc.get_state()` from a record; whether it is a node, VAT instance or nothing is hidden from quest/recruit code. This removes the need for per-tier special cases in gameplay code.

## 5. Keeping towns lively with fewer agents

- **Points of interest first**: 8-15 POIs per town (well, market stalls, smithy, tavern door, shrine, notice board, gate, bench groups). Each has a capacity of 1-4 and an idle loop (WORK, TALK, SIT, SWEEP, HAWK). Assign A/B agents to POIs by schedule instead of random wandering (Witcher 3 pool-of-spots: 200 spots for 50 sailors).
- **Stage the camera zone**: fill the 8-30 m ring around the player first (that is what is seen); the rest of the town can be 30-50% sparser. Crowd density rises toward market squares and the road from the gate to the centre.
- **VAT "set dressing" crowd**: static-position VAT actors at POIs (a smith hammering, two people talking, a farmer hoeing) cost one instance each and make a street read as busy; they upgrade to a B/A body when the player is within about 8 m.
- **Time-of-day curves**: density per hour (dawn farmers, noon market peak, dusk tavern, night near-empty with guards and a few lit windows) like the GTA density curves. Peaks concentrate the same headcount in fewer places; nights need fewer actors.
- **Ambient props and sound**: smoke, chimney, laundry, carts that move on rails, chickens/dogs (cheap animals as VAT), a 5-10 s positional audio layer (hammer, market chatter, children) rooted at the POI, not at agents. Sound sells population: a muffled crowd murmur bed whose volume scales with the *virtual* population of the district, even when only 15 bodies exist.
- **Edges**: spawn/despawn in doorways, alleys, behind carts, outside the frustum (Cyberpunk/DD2 pop-in is the failure case). Keep the existing 20 m near-sprite ban plus a frustum test for swaps.
- **Persistence illusion**: when the player returns, teleport NPCs to the correct schedule slot, and let a small number "arrive" by walking in from the gate. Remember the last position of anyone the player talked to.
- **Variety via cheap permutations**: hats/colours/tints on VAT bodies, not new meshes; 12-20 base bodies is enough.
- **Population scaling by settlement kind** (concurrent bodies materialised, HIGH tier): small village 8-12 total (A 4 / B 4 / VAT 4), village 12-20, frontier town 20-35, town 35-60, Kingsreach 60-90, regardless of the 90-1600 record counts. Records exist for sims (taxes, recruits, events), bodies exist for show.

## 6. Order of work (suggested)

1. Lower constants and per-tier rows as in section 3 (cheap, measurable with perf_probe).
2. Remove dead tier values / align `quality.gd` and `population_lod.gd` clamps (single source of truth).
3. Time-slice or cut PresenceLive/micro_events for non-A tiers.
4. Add POI capacity + schedule-driven placement and the off-screen "snap to schedule" path.
5. Add VAT set-dressing at POIs and density-by-hour curves.
6. Add ambience audio per district and the virtual-population mix.

## 7. Sources

- AC Unity, GDC 2015 "Massive Crowd on Assassin's Creed Unity: AI Recycling": https://gdcvault.com/play/1022141/Massive-Crowd-on-Assassin-s ; abstract (40 real AIs, 120 high-res models, 10,000 crowd): https://www.gamedeveloper.com/programming/get-coding-advice-from-insomniac-riot-and-ubisoft-at-gdc-2015 ; https://gdconf.com/article/learn-about-assassin-s-creed-unity-s-dynamic-crowds-at-gdc-2015/
- AC Unity crowd events postmortem: https://gdcvault.com/play/1022211/Postmortem-Developing-Systemic-Crowd-Events
- KCD1/KCD2 GDC 2026 "Supporting Thousands of NPCs": https://schedule.gdconf.com/session/supporting-thousands-of-npcs-in-kingdom-come-deliverance-kingdom-come-deliverance-ii/915120 ; recap https://gamedev.net/news/5526-supporting-thousands-of-npcs-in-kingdom-come-deliverance-kingdom-come/
- KCD Smrcek slides (2018, ~600 active NPCs, "NPC LOD" section; not fully read): https://www.karlin.mff.cuni.cz/mffseminar/prezentace_smrcek.pdf
- Kuttenberg design constraints: https://gamedev.net/news/4891-designing-kuttenberg-city-around-design-constraints-kcd-2/
- Witcher 3 NPC schedules: https://www.pcgamer.com/games/the-witcher/witcher-3-designer-says-it-wasnt-easy-to-convince-players-its-npc-simulation-wasnt-just-fakery-people-nowadays-are-interested-in-those-kinds-of-details-and-it-really-came-to-haunt-us/ ; https://www.gamestar.de/artikel/witcher-3-npc-komplexe-tagesablaeufe,3433467.html ; https://mein-mmo.de/en/the-witcher-3-wanted-realistic-npcs-but-that-caused-mothers-to-abandon-their-babies,1582612/
- Oblivion/Skyrim process levels: https://cs.uesp.net/wiki/GetProcessLevel ; https://cs.uesp.net/wiki/GetMiddleHighActors ; https://en.uesp.net/wiki/Oblivion:Radiant ; https://geck.uesp.net/wiki/GetActorProcessingLevel ; https://ck.uesp.net/wiki/GetActorsInHigh ; https://www.nexusmods.com/skyrimspecialedition/articles/2467
- RDR2 NPC routines: https://www.tweaktown.com/news/63303/red-dead-redemption-2-npc-system-explained-rockstar-devs/index.html ; https://mein-mmo.de/en/3-npcs-red-dead-redemption-2-einen-tag,286499
- Cyberpunk 2077 crowd (community / job ad only): https://80.lv/articles/cdpr-wants-cyberpunk-2077-sequel-to-have-most-realistic-crowd-system-ever ; https://www.nexusmods.com/cyberpunk2077/mods/526
- Dragon's Dogma 2: https://automaton-media.com/en/?p=38585 ; https://www.pcgameshardware.de/Dragons-Dogma-2-Spiel-73773/News/CPU-Performance-Leistung-Fps-1552848/ ; https://www.pushsquare.com/news/2024/03/capcom-simply-must-improve-dragons-dogma-2-ps5-performance-concludes-digital-foundry ; https://hothardware.com/news/dogma-2-benchmarked
- Bannerlord: https://www.pcgamesn.com/mount-and-blade-2-bannerlord/ ; https://mynewsdesk.com/uk/bastion-uk/pressreleases/taleworlds-entertainment-announce-mount-and-blade-ii-bannerlord-benchmark-tool-3141932 ; https://www.benchmark.pl/mount-blade-ii-bannerlord-cel-800-wojaków-w-60-fps-7263521627517505a
- Manor Lords: https://www.pcgamesn.com/manor-lords/update-7 ; https://ixbt.games/en/news/2026/01/12/sozdatel-manor-lords-v-20-raz-povysil-fps-optimizaciiu-smogli-ulucsit-blagodaria-kosmarnomu-soxraneniiu-ot-fanaty-igry.html
- GPU crowds / VAT: https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch02.html ; https://80.lv/articles/6-000-agents-on-one-game-thread-novel-high-performance-framework-for-gpu-driven-crowd-systems
- GTA V density mod (curves per hour, only mod-level): https://www.gta5-mods.com/scripts/dynamic-population-density
- Not found: Mafia/Medieval Dynasty/Cyberpunk developer tech talks, Digital Foundry RDR2/Cyberpunk population analysis, any published ms-per-frame AI budgets. Treat the ms targets in section 3 as proposals.
