# CPU, memory and save pass (2026-10-06, cloud lane)

**Scope and rule.** CPU time, memory and save size only, in game scripts, invisible to the player. Nothing here touches models, LODs,
textures, materials, shaders, lights, shadows, render resolution, draw distances, foliage density, crowd counts or animation
quality: rendering and GPU performance stay with the local session (`docs/qa/RELEASE_READINESS.md`, "Perf pass 1-3"). Two edits
are next to rendering inputs and are value-for-value identical to what they replaced: the grass interactor slots are not re-sent
to the renderer when unchanged, and the weather system builds its "<id>:<property>" bookkeeping keys once (same writes, same values).

Why: the S22 sat at 26-29 fps on LOW with severe heat and 3.2 GB PSS. The game is CPU bound, so script and simulation time feeds
both heat and fps (about 5 ms on the phone per ms measured here).

## How it was measured (tools in `kingdom/tools_qa/cpu_mem/`)

| tool | what it does |
|---|---|
| `cpu_profile.gd` | `--qa=` driver. Walks the player through Ashford's plaza ring, Thornfield's plaza ring and 550 m of the forest outside Thornfield (30 s each, 10 s settle). Takes every node's `_process` / `_physics_process` over (`set_process(false)`, then calls them itself between two `Time.get_ticks_usec()` reads) so each script's cost is exact. Prints ms per rendered frame (mean and p95), frame time, MEMORY_STATIC, object and node counts. `--census` adds `mem_census.gd`. `--raw` leaves the callbacks with the engine (the instrumentation costs about 3 %). |
| `sim_save_probe.gd` | No 3D world. Ticks `WorldSim.hour_changed` hour by hour (each connected handler timed alone, the realm hub queue drained job by job), and at checkpoint days measures the size of every save section, JSON / zstd bytes, snapshot, stringify, write, read and restore times. `-s` script: `-- days=730 tag=x checkpoints=1,30,365,730 [dump=1]`. |
| `mem_census.gd` | Bytes held by the autoloads' members and by every `static var` (var_to_bytes length: a proxy that counts shared references twice). |
| `ab_overlay.sh <ref> <dir>` | Throw-away project with `scripts/` and `autoload/` from a git ref and everything else from the working tree (assets and import cache symlinked), for a before / after run without a second 11 GB checkout. |
| `scripts/core/perf_probe.gd` | Section timer used inside the hot paths (`Probe.t()` / `Probe.add("name", t0)`). Off by default: a static call and a bool test. |

Caveats that cost time to find, so the next person does not repeat them:
- **A headless window never has focus, so the main loop sleeps `OS.low_processor_usage_mode_sleep_usec` (6.9 ms) per frame**, a hidden 144 fps floor whatever `Engine.max_fps` says. `cpu_profile.gd` sets it to 0; with the default every frame reads 6.9 ms and ablation medians come out identical.
- `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` are the **maximum over the last second**, not a mean: they cannot be averaged per tick (the first runs of this pass did, and chased a phantom 14 ms physics tick). They are printed as `*_max1s`.
- The container has 4 cores shared with other agents (load average 2-6 during these runs). Every number below is best-of or the mean of alternating before / after runs (B A B A), not a single run.
- This is the PC/headless dummy renderer: `Performance` draw counters read 0 and the static memory counts CPU-side texture copies the real renderer would drop. Scripted time is what transfers; multiply by 4-6 for the S22.

## 1. CPU profile

### Frame time (best of 2 to 4 runs per side; headless, LOW quality, uncapped)

| | before ms (mean / p95 / p99) | after ms (mean / p95 / p99) | script time in callbacks, per frame |
|---|---|---|---|
| Ashford plaza | 6.90 / 14.4 / 23.0 | **4.84 / 11.5 / 20.5** (-30 %) | 3.87 -> 1.90 ms |
| Thornfield plaza | 7.25 / 15.9 / 27.9 | **5.28 / 13.0 / 23.6** (-27 %) | 4.17 -> 2.30 ms |
| wilds (550 m of forest) | 4.59 / 8.3 / 10.8 | **3.21 / 6.8 / 9.5** (-30 %) | 2.88 -> 1.35 ms |

The p95 / p99 are the frames that carry a physics tick (LOW runs 30 Hz): scripted work inside those ticks is `villager.gd`,
`player.gd`, `critter.gd`, `soldier.gd`, `wolf.gd` (3.5 ms per tick before and after) plus the engine's own physics step; those
are the next target and were not changed (gameplay feel and animation).

### Top 15 scripts by ms per rendered frame (mean over the three route phases; `phys` = `_physics_process`)

| rank | script | before avg | before p95 | after avg | after p95 | what changed |
|--:|---|--:|--:|--:|--:|---|
| 1 | `region1/tutorial_game_bridge.gd` | 0.935 | 1.336 | **0.067** | 0.073 | context built at 6.7 Hz, idle when nothing is left to teach |
| 2 | `autoload/world_sim.gd` | 0.599 | 0.667 | **0.172** | 0.330 | far loop paced by time, near ring capped at 6 Hz |
| 3 | `phys actors/player.gd` | 0.213 | 1.112 | 0.147 | 1.076 | not touched (per-frame figure falls with the frame time) |
| 4 | `ui/hud.gd` | 0.202 | 0.516 | 0.162 | 0.430 | settled buttons are not rewritten every frame |
| 5 | `phys population/villager.gd` | 0.196 | 1.250 | 0.134 | 0.895 | not touched |
| 6 | `population/population_lod.gd` | 0.174 | 0.005 | 0.125 | 0.004 | not touched (a 0.25 s refresh: about 0.8 to 2 ms per call, a spawn is 3.7 to 6 ms) |
| 7 | `world/weather.gd` | 0.141 | 0.249 | 0.128 | 0.217 | bookkeeping keys built once |
| 8 | `phys actors/critter.gd` | 0.120 | 0.608 | 0.082 | 0.575 | not touched |
| 9 | `population/micro_actor.gd` | 0.105 | 0.171 | 0.093 | 0.161 | not touched |
| 10 | `phys army/soldier.gd` | 0.092 | 0.488 | 0.064 | 0.470 | not touched |
| 11 | `world/street_routines.gd` | 0.085 | 0.115 | **0.023** | 0.027 | murmur placed once, volume only while it fades |
| 12 | `world/exploration_director.gd` | 0.073 | 0.155 | **0.015** | 0.035 | light shafts and rifts at 5 Hz, rift list cached |
| 13 | `audio/audio_director.gd` | 0.050 | 0.096 | 0.041 | 0.076 | already throttled (0.5 s / 0.15 s polls) |
| 14 | `phys actors/wolf.gd` | 0.048 | 0.261 | 0.033 | 0.261 | not touched |
| 15 | `region1/tutorial_prompt_view.gd` | 0.047 | 0.076 | 0.028 | 0.045 | asleep while no prompt is shown |

The `phys` rows are per rendered frame, and the frame got shorter, so they fall without a change: they run per physics tick
(3.5 ms of script per tick before and after). Everything else in the top 40 is below 0.05 ms per frame (checked: quest pump,
town-kit hubs, crime watch, interaction controller and work widget are throttled or asleep already; `Life._process` fell from
0.03 to 0.02).

### Not per-frame, so not in that table (sim probe, `sim_save_probe.gd`, 30 game days, same harness before / after)

| event | before | after |
|---|---|---|
| `Life._on_hour` (once per game hour = 30 s of play; 17 520 calls over 730 days) | mean **25.9 ms**, p95 35.3, max 81.6 | mean **1.5 ms**, p95 4.2, max 13.8 (730 days: 2.0 / 4.7 / 21.5) |
| economy hourly tick (30 markets, 8 282 goods rows) | one 17 to 25 ms block inside that handler | 15 queued jobs of about 0.8 ms (two markets each), run by the realm hub pump (600 us budget per frame) |
| 06:00 import wagons and surplus trade | 22 ms (worst 37) | 4.6 ms + six jobs of about 1.5 ms |
| realm hub jobs (`campaign`, `construction`, `society`, `city_life` ... `tick_hour`) | 0.01 to 0.12 ms each | 0.01 to 0.09 ms each (noise) |
| `Life.road_risk` refresh | 0.65 ms per hour | unchanged (cheap enough) |

The total economy work per game hour is about the same in a 2-year game (about 17 ms of market ticking); what changed is that
it no longer lands in one frame (85 ms on the S22 every 30 s) and the idle goods and unchanged price modifiers are skipped.
`WorldSim.hour_changed` handlers other than Life's cost 0.01 to 0.13 ms.

## 2. Changes (all behaviour-preserving; tests listed in section 5)

| file | change |
|---|---|
| `scripts/region1/tutorial_game_bridge.gd` | The director's context (interaction picker, group scans, providers) is built every `CTX_RATE` = 0.15 s with the summed delta instead of every frame; real actions (walk, look, buttons) are still polled per frame; nothing is built at all once every prompt is done, skipped or switched off. `Life` lookup cached. |
| `scripts/region1/tutorial_prompt_view.gd` | `set_process(false)` and no `queue_redraw()` while no prompt is shown (it redrew every frame); `show_prompt` / `hide_prompt` wake it. |
| `autoload/world_sim.gd` | The far loop used to run until `BUDGET_US` was gone every frame. It now steps `n * delta / FAR_PERIOD` (5 s) residents, the near ring `m * delta * NEAR_HZ` (6 Hz) with fractional credit; both still obey the 0.5 ms budget. Every step integrates the person's own elapsed time, so positions, wages and treasury flows are the same; the near ring is 320 m + 2 settlement radii around the player, sprites only sample `WorldSim.pos` at 4 Hz, and the old count grew with the frame rate. |
| `autoload/life.gd` | Hunger, mana, shift attendance and starvation integrate at 10 Hz with the summed game hours (the realm pump still runs every frame). The hourly economy tick goes through `realm.queue_jobs(economy.queue_hour_jobs(...))`. `snapshot()` settles pending economy jobs first. |
| `scripts/sim/economy.gd` | `tick_hour` is split into jobs (`_hour_plan`): market chunks of 2, the daily wagons, the daily surplus trade in 6 slices, caravans. `tick_hour` (synchronous, same results) is kept for tests and catch-up; `queue_hour_jobs`, `settle_hour_jobs`, `flush_hour_jobs` for the spread-out form; `serialize()` finishes pending jobs so a save never misses a tick. Population / capital lookups come from a table instead of scanning 30 settlements per market. The surplus trade only walks goods some market makes (`RAMarket.producers()`), in the same order. Modifiers are recomputed only when their inputs changed. |
| `scripts/sim/market.gd` | Goods with no stock and no production are skipped in `tick_hours` (the step is the identity there); `producers()` cache; `mods_sig` / `goods_rev()` for the modifier cache; `serialize()` leaves out zero carries (a missing entry loads as 0). |
| `scripts/realm/realm_hub.gd` | `queue_jobs(callables)`: other systems can queue pump jobs. |
| `scripts/world/street_routines.gd`, `exploration_director.gd`, `grass_interactors.gd`, `weather.gd`, `ui/hud.gd` | see the top-15 table; `hud.gd` also skips same-value position writes on the hotbar and pill. |
| `scripts/sim/save_manager.gd` | schema 3 (section 4). |
| `scripts/population/population_lod.gd`, `scripts/ui/hud.gd`, `autoload/*.gd`, `economy.gd` | `Probe` sections (zero cost while off): `pop.*`, `hud.*`, `life.hour.*`, `economy.hour_*`, `worldsim.*`. |

Looked at and left alone (and why): `weather._apply_environment` runs every frame on purpose (other systems write the base values
every frame and the weather multiplies on top, a skipped frame would flicker); `population_lod.refresh` (allocation per resident
is about 0.3 ms per call; the cost is the spawn, which is the model); `RoadTraffic`, `micro_actor`, villager / critter / soldier
physics ticks (movement and animation); the audio director, quest pump, town hubs, crime watch, interaction picker and work widget
(already on 0.15 to 22 s timers or asleep).

## 3. Memory (non-render)

| | value |
|---|---|
| engine, empty project (headless) | 20.6 MB MEMORY_STATIC |
| autoloads loaded, no world (`sim_save_probe`) | 225 MB static, 4 588 objects (realm warm-up adds nothing: already built at load) |
| the same after 2 game years | 238 MB (+13 MB: markets, society, history), 4 591 objects |
| in the world (headless dummy renderer: Ashford / Thornfield / wilds) | 1.45 / 1.56 / 1.57 GB static, 28.5k / 31k / 32k objects, 10.2k / 11.6k / 11.3k nodes, 4.4-4.6k resources. **Unchanged by this pass** (run-to-run spread is +-15 MB) |
| one economy (30 markets x 276 goods, 5 dictionaries each) | **3.0 MB** |
| WorldSim people arrays (10 170 residents, 12 km world) | about 0.73 MB (`npc_need_values` 203 KB, `npc_need_hours` 81 KB, `pos` / `target` / `external_position_owner` 81 KB each, 12 more arrays 10 to 41 KB) |

`mem_census.gd` (after the route, proxy bytes; shared references are counted more than once, so these are upper bounds): the
crafting recipe tables (`Life.crafting.recipes` 319 KB, `_by_id` 336 KB: the same dictionaries), `Crafting._item_db` 769 KB,
`ItemsDB._new_entries` 694 KB and `_extras` 511 KB (the item set exists as raw entries, resolved copies and the GLoot protoset), the
Region 1 terrain stamps 1.8 MB, the town documents (`town_data._docs`, 30 files, 876 KB), `region_sites` / `region_pois` placement grids
(references into `WorldGen.sites`, almost no real memory), `WorldGen.settlements` / `sites` 0.6 / 0.7 MB, the named-resident table 731 KB.
**All the scripted data together is a few MB of 1.5 GB**, so no scripted cache is worth a risky change; the heap is nodes and
resources. Findings for the local session instead:

- 829 stray nodes at the end of the route are the **idle bodies of the creature pools**: 113 `critter.gd` bodies, each with a Skeleton3D,
  PhysicalBoneSimulator3D, AnimationPlayer and mesh instances (`CreaturePool.CRITTER_CAP` = 96 per spawner and kind, 24 for wolves and
  monsters). They never shrink: `NodePool.trim_all(keep)` exists but is only called after teleports. Trimming idle bodies to a few per
  pool after a minute is invisible and frees them; not done here because it re-creates bodies (a few ms each) when you walk back.
- The 205 MB between the 20 MB engine baseline and "autoloads only" (225 MB) is compiled scripts plus what they preload (audio
  streams, item data, shaders); a per-system split needs the S22's `meminfo` more than this headless build.

## 4. Save size and time

`Life.snapshot()` is about 1.2 MB of JSON on day 1 and grows to 2.0 MB at two years (the 1.42 MB in the brief is about day 5 to 8:
realm 487 KB, world 448 KB, economy 132 KB growing to 468 KB as markets get their first tick). Measured with `sim_save_probe.gd`:

| game day | JSON text before | file before (plain JSON) | JSON text after | **file after** | reduction |
|--:|--:|--:|--:|--:|--:|
| 1 | 1 168 657 | 1 168 774 | 1 168 661 | **175 358** | -85 % |
| 30 | 1 671 529 | 1 671 646 | 1 671 328 | **287 462** | -83 % |
| 120 | 1 811 814 | 1 811 931 | 1 807 867 | **328 350** | -82 % |
| 365 | 1 943 493 | 1 943 610 | 1 932 332 | **356 922** | -82 % |
| 730 (two years) | 2 017 230 | 2 017 347 | 2 008 346 | **360 926** | -82 % |

(The plain file is the JSON text plus 117 bytes of envelope.) Target was 1 MB: met by a factor of 2.8 at two years. By section at day 60 (raw / zstd alone): realm 657 KB / 98 KB, economy 482 / 65,
world 448 / 17, life_courses 85 / 6, frontier 53 / 7. The raw text does not shrink much by pruning (zero carries are 11 of 8 282
entries; rounding the carries would save 92 KB raw and 12 KB compressed, so it was not done: it is the one lossy option).

What changed (`scripts/sim/save_manager.gd`, **schema 3**):
- A data text of `COMPRESS_MIN` (64 KB) or more is stored as `{"schema":3,"meta":{...},"checksum":md5(base64 text),"enc":"zstd","raw":N,"data":"<base64>"}`;
  smaller saves (and every test fixture) stay plain JSON, so the file is still readable JSON with the same `meta`, `.meta.json` cache, thumbnail,
  atomic tmp / verify / `.bak` write and fallback chain.
- `_read_valid` checks the checksum, decodes `enc`, parses, then runs the migration table; `MIGRATIONS[2] = _migrate_2_to_3` is the identity
  on `data`. **Old saves load**: schema 1 (bare snapshot) and schema 2 (plain envelope) are covered by tests that write the old layout by hand,
  including a full `Life.snapshot()` through `Life.restore`. A newer schema (> 3) is refused as before; a damaged or truncated compressed file
  falls back to the backup with the readable error.
- Economy market `carry` omits zero entries; hour jobs pending at save time are finished first (`economy.settle_hour_jobs`), because the home market
  is saved twice (`market` and `economy.markets.0`).

Times (ms, this container, load 1-3; the phone is 4-6x slower):

| | snapshot | stringify | write (incl. zstd, base64, md5, atomic rename) | read (incl. unpack, parse) | `Life.restore` |
|---|--:|--:|--:|--:|--:|
| before, day 30 (plain JSON) | 41 | 66 | 95 | 60 | 109 |
| after, day 30 | 42 | 65 | 98 | 59 | 116 |
| after, day 365 | 55 | 79 | 113 | 69 | 133 |
| after, day 730 | 72 | 83 | 119 | 69 | 154 |

Compression is free in time (the smaller file write pays for it) and cuts the autosave file from 2.0 MB to 0.36 MB.

## 5. Tests

New: `tests/test_economy_hour_jobs.gd` (the synchronous tick, the queued jobs and a save halfway through an hour all equal a reference copy of
the old algorithm over 4-5 game days, including price modifiers after road risk, civilisation, Scar and new-good changes),
`tests/test_save_compress.gd` (compressed round trip, plain small saves, schema 2 and schema 1 style files, newer schema refused, damaged and
truncated compressed files, the real `Life.snapshot()` through the compressed and the plain schema-2 file, every section equal afterwards),
`tests/test_cpu_pass.gd` (bridge rate, idle and per-frame action counting, prompt view sleep and wake, WorldSim pacing and coverage, probe is a no-op).
Existing suites for every system touched pass; the full batched run is recorded below.

Full batched run, `GODOT=$GODOT tools/qa/run_tests.sh 20` (9 batches, working tree of 2026-10-06 with the other agents' uncommitted changes):

```
batch 1 (exit 101): 344 test cases | 0 failures | 349 orphans      batch 6 (exit 101): 243 test cases | 0 failures | 886 orphans
batch 2 (exit 0):   228 test cases | 0 failures                    batch 7 (exit 101): 298 test cases | 0 failures | 663 orphans
batch 3 (exit 101): 288 test cases | 0 failures | 4 orphans        batch 8 (exit 101): 330 test cases | 0 failures | 869 orphans
batch 4 (exit 101): 309 test cases | 0 failures | 3 orphans        batch 9 (exit 0):    29 test cases | 0 failures
batch 5 (exit 0):   293 test cases | 0 failures
TOTAL: 2362 test cases, 0 failures, bad batches: none
```
(Exit 101 is orphan warnings only.)

## 6. Reproduce

```
GODOT=/tmp/claude-0/godot/Godot_v4.6.2-stable_linux.x86_64
cd kingdom
$GODOT --headless --path . -- --adult --quality=low --qa=res://tools_qa/cpu_mem/cpu_profile.gd --seconds=30 --census --out=/tmp/after.json
$GODOT --headless --path . -s res://tools_qa/cpu_mem/sim_save_probe.gd -- days=730 tag=x checkpoints=1,30,120,365,730
tools_qa/cpu_mem/ab_overlay.sh <git-ref-before-this-pass> /tmp/kbase       # then the same profile with --path /tmp/kbase
```

## 7. Next (not done: either gameplay-visible, or the local session's lane)

1. The physics tick (3.5 ms of script per tick at 30 Hz, p95 and p99 frames): `villager.gd` and `critter.gd` bodies near the player, `soldier.gd` guards, `player.gd`.
   A per-body rate by distance (animation and move at 15 Hz beyond 20 m) changes motion, so it needs a visual check on the phone.
2. `PopulationLOD.refresh` spawns (3.7 to 6 ms each, one per refresh at most): pre-build the next body one frame earlier, or pool bodies per look.
3. Idle creature-pool bodies (section 3).
4. On the S22: run `cpu_profile.gd` through `tools/qa/phone/route.sh` (not forwarded on the phone: bake `--qa=res://tools_qa/cpu_mem/cpu_profile.gd` in a QA APK) to confirm the 4-6x factor and look at thermal status.
