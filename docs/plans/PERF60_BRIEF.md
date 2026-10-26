# Execution brief: Kingsreach gate market to 60 fps, PC_HIGH 1440p (Opus plan 2026-10-23, one Sonnet executor)

Finding: residents are already mostly records (WorldSim packed arrays by row; recruitment by row). The 41–45 ms frames come from what surrounds the records: lookups walking every resident, a sprite pass rebuilt from scratch, one script callback per node per physics tick, and scans of the whole "villager" group. Targets below are to be measured.

## Ground rules
- Start from `origin/claude/focused-curie-m09hbd` (≥ f3994fd7). One Godot at a time; PC rows only; commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Don't touch `actors/follower_manager.gd`, `follower_body.gd`, `follower_brain.gd` (cloud PR `claude/v1-companions`); only call `FollowerManager.attach`. `population/villager.gd`: hooks only; new logic in new files.
- Gate before each commit: tests in §6 + a perf run.

## 0. Today
- `kingdom/autoload/world_sim.gd`: packed arrays by row (`home, job, pos, target, money, health, phase`, needs, `external_position_owner`); `ranges[sid]` contiguous rows per settlement. `serialize()` (372–378) writes day, time, treasury, money, needs, dead list; positions regenerated on load.
- `people_near()` (271) checks every row of every settlement in range; caller grows radius to 220 m → ~500 residents per refresh.
- `PopulationLOD.refresh()` (`population_lod.gd:223`) at 4 Hz: `people_near` → sort → want_full/physics pick → `_sprite_job_begin`. `_sprite_job_step` (405) walks the whole list; per resident `_sprite_route_graph`, `_advance_sprite_route` (`clear_line`/`push_out`), `_sprite_heading`, cache check, VAT `want()`; 4 ms slices → runs most frames.
- Villagers: `CharacterBody3D` with `_physics_process` (villager.gd:557); `lod_tier >= 1` non-contact skip every other tick; 4 (`MAX_PHYSICS_CONTACT`) `move_and_slide`, other in-contact `move_and_collide`, rest write `global_position`; still a dispatch ~2.6×/frame + `WorldGen.height`.
- Critters (`actors/critter.gd:248`): Node3D with `_physics_process`; distance LOD (1/3/6 ticks) runs after the dispatch and a player lookup → ~228 critters ≈ 600 dispatches/frame. `ambient_life.gd` wakes groups via CellStreamer "ambient" (load 110 m, hyst 60 m); 30 % of houses get a 4–6 chicken group; no area cap.
- Group scans of "villager": `player.gd:1620, :2160`, `talk_target.gd:86, :117`, `grass_interactors.gd:171`, `alert_glyphs.gd:130`, `village_services.gd:1394, :1484`, `npc_world.gd:482, :948, :1037`, `crime_watch.gd:96, :195`.
- Physics: Jolt, interpolation on, 60 Hz.

## 1. Residents as records (finish, don't rebuild)
- **`ResidentIndex`** new `kingdom/scripts/population/resident_index.gd` (owned by WorldSim): 16 m cell grid per settlement; per-cell `PackedInt32Array` rows; `cell_of: PackedInt32Array`. Rows change cells only in `WorldSim._step(i)` and `set_external_position_owner()`, only when the cell changes. `people_near()` scans cells in range in ring order. Add `people_in_ring(p, r0, r1, max_n)` nearest-first without a full sort (visit cells by ring, stop at `max_n`).
- **`BodyRegistry`** new `kingdom/scripts/population/body_registry.gd`: row↔node maps + 8 m body grid updated at 10 Hz. Replaces all group scans above with `BodyRegistry.near(p, r)` / `body_of(row)`. PopulationLOD fills it in `_drain_spawns`, `evict_person`, wherever `_full` is erased; one-line hook in `Villager._ready`/`_exit_tree` for bodies made elsewhere (MicroScene).
- **Tiers** `tier: PackedByteArray` in PopulationLOD: 0 full, 1 VAT, 2 sprite, 3 record. No gameplay code reads it.
- **Rules (keep numbers):** full within `NEAR_ALWAYS` 9 m or nearest `min(MAX_FULL, Quality.npc_full)` within `_full_range` 45 m (`KEEP_BIAS` 0.75, `CONTACT_KEEP` 3 s); VAT 9–120 m; sprite 120–220 m with budget `min(MAX_SPRITES, Quality.npc_sprites)`; record beyond 220 m. Despawn after leaving want_full > `CONTACT_KEEP`. Never despawn: in conversation, active quest target, KO'd/dead (Takedown), `_held`.
- **Pooling:** `VillagerPool` keyed by look (`LOOK_MODEL`), ≤ `npc_full + 4` nodes; recycle via new hook `Villager.reset_for(row)` (reset brain, needs, anim state, re-read WorldSim needs, `_ready`-equivalent setup without rebuilding the model) — removes 3.7–6 ms per spawn. Named residents (`TownRoster`, quest- or follower-referenced rows) never pooled; free them on return to record.
- **Coarse placement:** beyond VAT range keep WorldSim FAR_PERIOD (5 s) straight-line mover, no street graph. Only nearest 120 sprites/VATs use `_advance_sprite_route`. On record→body, snap to `Schedule` + `phase` activity spot or nearest street-graph point via `push_out`.
- **Finding people at any tier:** by row (`WorldSim.person_name(row)`, `.pos[row]`, `.home[row]`, `recruitment.profile(row)`); add `WorldSim.locate(row) -> Vector2` (body pos if present else `pos[row]`); `PopulationLOD.ensure_body(row)` pins full while a quest step/dialogue needs it, `unpin(row)`. Shops (`village_services.gd`, `shop_hours.gd`) open by the shopkeeper row's `phase` + hours, not node proximity; node lookup only for the talk prompt via BodyRegistry.

## 2. Sprite pass rewrite (`population_lod.gd`)
1. `refresh()` uses `ResidentIndex.people_in_ring(focus, 0, _sprite_range, want_n)` (replaces `people_near` + sort; drop adaptive `_query_r`). Re-rank only after player moved > 4 m or 1 s; otherwise transform-only update.
2. `SPRITE_SLICE_US := 1000`, hard cap 48 instances/frame; cursor through the visible set; update a MultiMesh slot only if the row moved > 0.05 m (`_sprite_cache`).
3. Stable slots: row→slot per look with a free list; enter/leave = one swap-remove.
4. Cache: `_sprite_route_graph` only on settlement change (`PackedInt32Array route_sid`); `push_out` + `WorldGen.height` skipped beyond 90 m; `_advance_sprite_route` only for nearest 40 sprites.
5. VAT: `_vat.want()` only on tier change or move; persistent instances in `vat_residents.gd`.
6. Keep probes `pop.sprites_slice`, `sprj.*`; add `pop.rank`.
7. Target `pop.sprites_slice + pop.rank` ≤ 0.6 ms avg, ≤ 2 ms worst.

## 3. Critters
- `ambient_life.gd`: `CRITTERS_TOWN_MAX := 40` within 110 m inside a settlement radius, `CRITTERS_WILD_MAX := 24`, `SMALL_FLOCK` ≤ 2 per group in towns (Quality-scaled); wake nearest groups until budget spent, 1 Hz in `_process`; group→settlement-cell index built once in `_ready`.
- New `scripts/world/critter_director.gd` (child of AmbientLife) ticks all critters from one `_physics_process`: `set_physics_process(false)` on spawn; hook in `critter.gd` `func director_tick(delta, player_pos)` wrapping the old body minus the LOD prelude; near < 30 m every tick, 30–70 m 20 Hz, far 10 Hz, off-screen > 40 m 5 Hz; player pos fetched once per tick; riders (`rider_owned`) and hunt groups keep the per-tick path. Note: `critter.gd` is a locally owned hot file — hook only.
- Target ≤ 40 critter bodies in the market; `ambient.*` + director ≤ 0.8 ms/frame.

## 4. Physics
| Tier | Body | Collision | Motion | Rate |
|---|---|---|---|---|
| Contact (≤ 4) | CharacterBody3D `move_and_slide` | on | physics | 60 Hz |
| Other in-contact ≤ 8 m | `move_and_collide` | on | physics | 30 Hz |
| Mid full 8–45 m | kinematic | shape disabled (`collision_layer=0`, `CollisionShape3D.disabled=true`) | `global_position` from anim/steering | 15 Hz, interpolated |
| VAT/sprite/record | no node | none | data | 4 Hz / FAR_PERIOD |
| Critters | no physics body | none | terrain follow | §3 |
- Keep 60 Hz physics; player, combat, projectiles, contact villagers on `_physics_process`. New `scripts/population/npc_ticker.gd` (child of PopulationLOD): non-contact Villagers `set_physics_process(false)` (hook in `Villager._set_contact` and the `physics_active` setter); round-robin with fixed budget — ~1/2 of non-contact bodies at 30 Hz within 20 m, 1/4 beyond — calling `v._tick_body(accumulated_delta)`. villager.gd hooks: `_physics_process` returns early when `ticker_owned`; `_tick_body` callable externally; remove the odd/even skip.
- Death spiral: `Engine.max_physics_steps_per_frame` — check current (PC cap is 3 via `PC_MAX_PHYSICS_STEPS`); keep ≤ 4.
- Target villager physics scripts ≤ 2.5 ms/frame.

## 5. Budget (PC_HIGH 1440p, steady, Kingsreach market)
| System | Probe | Today | Avg | p95 |
|---|---|---|---|---|
| PopulationLOD + sprites | `pop.*`, `sprj.*`, `prof_lod_usec` | ~3–4 | 0.8 | 2.0 |
| Villager `_tick_body` | `NpcWorld.prof_usec`, `villager.anim` | ~10 | 2.5 | 3.5 |
| CrowdAnimLOD | row | ? | 0.5 | 1.0 |
| Presence (`_tick_presence`) | `presence_live.gd` | ? | 0.4 | 0.8 |
| Critters + AmbientLife | `critter.gd`, `ambient.*` | ~4–5 | 0.8 | 1.2 |
| WorldSim `_simulate_slice` | `dbg_slice_usec` | ≤ 0.5 | 0.5 | 0.6 |
| Group-scan users | per script | ~2 | 0.5 | 0.8 |
| Everything else | remainder | ~8 | 3.0 | 4.0 |
| **Scripts** | | ~31 | ≤ 9 | ≤ 12 |
| Engine | frame − scripts | ~11 | ≤ 8 | ≤ 9 |
| **Frame** | `--hitchcsv` | 41–45 | ≤ 16.7 | ≤ 20 |
- Measure: edit `ROOT` in `kingdom/tools_qa/perf/run_hitch.sh` (hard-coded to PA_wt_audit) for your worktree; `bash kingdom/tools_qa/perf/run_hitch.sh A_stand_1440 2560x1440 150 --stand --prof --after=75 <PC_HIGH flag, check quality.gd e.g. --profile=pc --quality=high>`; walking `B_walk_1440 ... --walkk --after=21`; A/B vs `--perf-legacy` alternating, 2 runs each; `python docs/qa/perf/analyze.py` reads `raw/m_<scenario>_<legacy|fixed>_r<N>.csv`; copy `--prof` per-system rows into a new section of `docs/qa/perf/HITCH_RESULTS.md` after each step; `--census=20,40,65` for counts. Record power state (AC/battery) and other Godot processes for every run.
- Accept: A_stand_1440 and B_walk_1440 median ≥ 60 fps, p95 ≤ 20 ms, p99 ≤ 28 ms, 0 frames > 50 ms/min in steady window; scripts p95 ≤ 12 ms; on screen ≥ 18 full bodies and ≥ 100 VAT/sprite figures in the market (check census; town must not look emptier — one gate-market screenshot before/after, READ them).
- Commit order (measure after each): 1 ResidentIndex + `people_in_ring` + parity test; 2 sprite pass; 3 BodyRegistry + group-scan replacement; 4 critter budget + CritterDirector; 5 NpcTicker + mid-tier collision off; 6 VillagerPool + `ensure_body`/pin; 7 results doc.

## 6. Tests (gdUnit4, `kingdom/tests/`)
- `test_resident_index.gd`: `people_in_ring` == old `people_near` for 200 random points/radii, before and after 10 simulated hours; cell membership consistent after `kill_person` and external ownership.
- `test_body_registry.gd`: `body_of(row)` == old group scan; `near()` == brute force; entries gone on despawn and recycle.
- `test_resident_tiers.gd` (headless, `queue_spawns=false`) for a shopkeeper, a TownRoster NPC, a generic recruitable row, a quest giver: reachable via `WorldSim.locate`, `person_name`, `recruitment.profile` at tiers 3/2/0; `ensure_body(row)` → body at the scheduled spot within 2 frames; recruitment `engage(row, …)` identical with/without a body; recycled pooled body has no leftover needs/name.
- Save round-trip: extend `test_save_manager.gd`, `test_save_compress.gd` (bodies present vs none → identical; no new save keys).
- Must stay green: `test_recruitment.gd`, `test_follower_bodies.gd`, `test_realm_followers.gd`, `test_mw_followers.gd`, `test_wardwright_recruiter.gd`, `test_villager_torso.gd`, `tools_qa/living_world/vat_test.gd`, plus `test_scripts_parse`, `test_quality_pc`, `test_hitch_pass`, boot test.
- Critters: seeded town count within 110 m ≤ budget; director-driven critter flees within ±0.2 s of the old path.

## 7. Risks
- `claude/v1-companions` conflict: keep `FollowerManager.attach(self)`; followers out of pool and ticker; rebase before final commit.
- villager.gd / critter.gd hot files: hooks only.
- Kinematic mid-tier with collision off may pass through the player at 8–10 m: promote before overlap (9 m NEAR_ALWAYS + hysteresis).
- 30/15 Hz ticking: feed `_resolved_speed` the accumulated delta or feet slide.
- Pool state leaks (`_talk`, `_so` claims, `external_position_owner`, CrowdAnimLOD registration, Presence observers) — `reset_for` undoes each; tests check.
- Shop/quest code relying on a node existing — audit every §0 group-scan site.
- Crime witnesses: `crime_watch`, `npc_world:948` see only embodied NPCs — keep, via BodyRegistry.
- Measurement noise: AC power, close other Godot, alternate A/B.
- If scripts hit target but frames > 20 ms: check skinned-mesh/AnimationTree counts; lower PC_HIGH `npc_full` before looking elsewhere.
