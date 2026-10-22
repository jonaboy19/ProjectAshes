# Rising Ashes: Project Bible

Written 2026-10-21 for the three AI teams and the owner. Read this first, then your team's handoff:
`docs/HANDOFF_ANTIGRAVITY.md` (animation), `docs/HANDOFF_CODEX_WORLD.md` (world), `docs/LOCAL_SESSION_HANDOFF.md` (running coordination log, newest first).

All code paths below are relative to the repo root. The Godot project is `kingdom/`, so "scripts/realm/x.gd" means `kingdom/scripts/realm/x.gd`. Godot 4.6.2 in CI and on the cloud; the PC uses 4.6.3.

Contents: 1 Vision, 2 World, 3 Systems, 4 Realm hub / tick / save, 5 Testing, 6 Performance rules, 7 Design-doc index, 8 Ownership, 9 How to start (per team).

---

## 1. Vision

- **An NPC-centred, living medieval fantasy world.** Everyone the player meets is a real record with a job, a home, needs, relationships, memories and secrets. The world keeps running whether or not the player is looking (markets, wars, migration, crime, weather).
- **Become anything.** Farmer, scribe, soldier, merchant, lord, adventurer, cultivator, priest, outlaw. Careers have real vacancies and ladders; there is no class menu. Archetypes emerge from what the character actually does (`scripts/sim/archetypes.gd`).
- **Freedom first.** Quests are optional, show no markers unless pinned, and are offered by people in the world, not by cutscenes.
- **PC first, mobile later.** The shipping target is PC (Windows, Forward+). The phone build (Android, Mobile/Compatibility renderer, LOW tier) is kept alive by budgets but is not the current priority. Terrain3D and ProtonScatter are PC-only until the phone build returns.
- **Memory presets.** Quality tiers LOW / MEDIUM / HIGH / ULTRA (phone) plus PC_LOW / PC_MED / PC_HIGH / PC_ULTRA live in `scripts/core/quality.gd`. The **ram8 preset** (8 GB RAM PCs) is opt-in with `-- --ram8` or `Quality.ram8 = true` before the world builds; it caps view radius 3, full NPC bodies 10, sprite NPCs 40, scatter 0.7, shadow distance 90 m, and turns off SDFGI and SSIL (`RAM8_CAP`, `RAM8_FLOOR`, `RAM8_OFF`).
- **One look: Style G** (Kingsreach gate market, "target 03"). See the `ashes-style-g*` skills in `.claude/skills/`.

The foundation freeze (owner decision 2026-10-05, `docs/design/FOUNDATION_PLAN.md`) still stands for large simulation features: 13 kingdoms politics, dynamic wars, settlement founding pressure, advanced personalities, monster civilizations, Soulbeast evolution and the economy sim get bug fixes only until the Thornfield vertical slice is fun. New work on those needs the owner's word.

## 2. World

- **Thirteen kingdoms** are the design target (`docs/WORLD_LORE.md`, `docs/KINGDOM_DESIGN.md`, `docs/design/LIVING_WORLD_SANDBOX.md`). The data file `kingdom/data/world/nations.json` currently carries 8 nations (Valencious/`caldrenn`, Isles of Seirune, Ongur Khanate, Aurelis Patriarchate/`solmarch`, Urrokai Clanlands, Shenlu Peaks Covenant, Veylwood Concord, Hollowdeep Holds); the rest are lore only and are frozen.
- **Valencios (Valencious, internal id `caldrenn`) is secular.** Church power 0.25: secular law, small runestone keepers in 14 towns, a Dawn mission chapel only in the capital, independent schools. **The three eastern church kingdoms** have church power 0.6 to 0.85, closed borders and a 6 to 10 percent tithe, and need not honour Valencios nobility (legitimacy is per observer culture, MW-6). Early story stays in Valencios. See `scripts/realm/faith.gd` and `docs/design/LIVING_WORLD_SANDBOX.md` section 14.
- **The map** is 12 x 12 km (`WorldGen.WORLD_HALF = 6144`), about 30 settlements and roughly 10,000 people (budget 25,000). Everything is a pure function of the seed (`scripts/world/world_gen.gd`).
- **Region 1** is the first playable region around Ashford and Thornfield: 20 settlements (`kingdom/data/region1/towns/*.json`, `data/region1/world/settlements.json`), landmarks, wardlines, caves, towers and 56 exploration POIs. Plan: `docs/regions/REGION_1_PLAN.md`; guide: `kingdom/data/region1/README.md`. The runestone wards define "inside" and "outside the walls" (`scripts/world/outer_identity.gd`).
- **Thornfield** is the vertical-slice village (`scripts/world/thornfield/`), plus one town (`scripts/world/town_kit/`), one Rift and one outpost.

## 3. Systems (description and files)

### 3.1 Realm simulation (`scripts/realm/*`, pure data, no nodes)
Every module extends `scripts/realm/realm_module.gd` and is registered in `realm_hub.gd`. Roughly 85 files; the groups:

- **Identity and records.** `registry.gd` gives persistent ids (`"<prefix>:<n>"`, never reused) and a legacy alias map. `events.gd` is an append-only ring of the 2,000 newest EventRecords that news, rumour, memory, chronicle and justice read. `persona.gd` packs a person into 24 bytes (traits). `save_codec.gd` writes columns instead of dictionaries.
- **Minds and society.** `minds.gd` (decision layers for at most 1,000 registry-upgraded Characters), `psyche.gd` (emotional memory and mood), `bonds.gd` over `sim/npc_social_graph.gd` (bounded ties, eight signed axes), `secrets.gd`, `rumours.gd`, `social_perception.gd` (what an observer reads off a subject; pure), `reputation.gd` (nine axes per subject), `society.gd` (crime, law, daily social life), `notables.gd` (about 60 named agents who rise and fall), `governance.gd`, `dynasties.gd`, `succession.gd`.
- **Economy and work.** `city_life.gd` (inns, rent, jobs, quest boards, guilds, districts), `work.gd` + `work_jobs.gd` (what a shift is), `businesses.gd` (account books, staff), `enterprise*.gd` (Bannerlord-style trade, fiefs, clans), `farming*.gd` (fields, herds, climate), `ledger.gd` (one scheduled realm ledger), `settlements.gd` (identity drift, emergencies, supply chains), `career_trades.gd`, `scribe.gd`, `soldier.gd`, `callups.gd`, `education.gd`, `household.gd`, `homes.gd`.
- **Politics and law.** `territory.gd` (ten independent 300 m layers: sovereignty, ownership, policing...), `land.gd`, `land_law.gd`, `land_claim.gd`, `stewardship.gd`, `audiences.gd`, `diplomacy.gd`, `courts.gd`, `factions.gd`, `faith.gd`, `organizations*.gd` (one generic entity for guilds, companies, orders, academies).
- **War.** `armies.gd` + `armies_data.gd` (entity, command, logistics, settlement defence, `battlefield_snapshot(sid, at_hour)`), `campaign.gd`, `war_units.gd`, `tactical.gd` + `tactical_ai.gd` (battle grid, 10 s steps), `siege.gd`, `strongholds.gd`, `war_advisors.gd`, `war_intel.gd`, `war_influence.gd`, `sighting_report.gd`.
- **Civilization and ecology.** `civilization.gd` (settlements grow and die from pressure), `migration.gd`, `camps.gd`, `founding.gd` (player and NPC founders use one loop), `ecology*.gd` (per-zone populations, monster clans), `emergence.gd` (event director), `news.gd`, `exploration.gd`, `towers.gd`.
- **Building.** `build_kit.gd` (Palworld-style snapping grid, at most 3 player grids), `construction*.gd` (survival construction, builders' routes).
- **People you lead and become.** `followers.gd`, `recruitment.gd`, `follower_will.gd`, `power_paths.gd`, `cultivation.gd`.
- **Districts.** `district_values.gd`: hidden per-quarter values (prosperity, safety, corruption, tension and seven more) that relax toward causes. Read API in `docs/HANDOFF_CODEX_WORLD.md`.
- **Gap closure (2026-10).** `PD.kingdom_of(sid | Vector2)` resolves the real kingdom (settlement `kingdom` field, else position: inside the +-6144 m first region is `caldrenn`, beyond it the border exit's neighbour). `Life._realm_ctx()` feeds the live weather node (or a seasonal roll) into `ctx.weather`, which armies and campaign read hourly. `Theft.steal` reports `Stim.TAKE_OBJECT` to `PresenceLive`. `migration` consumes `monster_society.take_departures()` as refugee waves (cause "monsters"); `homes.rent_den()` lets a monster den (rent scales with prejudice) and opens a `monster` quarter in `district_values` (`open_monster_quarter`). `social_perception.read` adds aura awe (pious observers, up to +0.25) and dread (timid, up to -0.15) to legitimacy. `barks_status.json` has 131 lines. Recruitment, armies, homes and faith payers still only `ledger.note()`; the 180-day integration test confirms gold is conserved. Tests: `tests/test_gap_closure.gd`.

### 3.2 Player-life simulation (`scripts/sim/*`)
The player's own life and shared rules: `save_manager.gd` + `save_containers.gd` (saves), `progression.gd` (level 1 to 500), `skills.gd`, `mastery.gd`, `soul.gd`, `naming.gd`, `magicules.gd`, `equipment.gd`, `items_db.gd` (1,200 items, see skill `ashes-items`), `crafting.gd`, `economy.gd` + `market.gd`, `careers.gd` + `career_ladders.gd` (real vacancies), `life_path.gd` + `life_courses.gd` + `childhood_events.gd` + `awakening.gd` + `tendencies.gd` (birth to adulthood), `family.gd`, `lordship.gd`, `property.gd`, `homestead.gd`, crime (`theft.gd`, `pickpocket.gd`, `arrest.gd`, `ownership.gd`), `injuries.gd`, `needs.gd`, `seasons.gd` (4 x 28 days), `radiant_quests.gd`, `dialogue_runner.gd`, `utility_core.gd` (shared utility scorer), `trace.gd` (decision inspector data), `threat_map.gd`, `runestone_network.gd`, `monster_ecology.gd`, `war_sim.gd`, `world_lore.gd`.

### 3.3 Autoloads (`kingdom/autoload/*`, plus `scripts/core/*` ones)
`Quality` (scripts/core/quality.gd), `PerfOverlay`, `Game` (gold, rank, messages, input map), `WorldSim` (autoload/world_sim.gd: every person is a row in packed arrays, no node), `Audio` (scripts/audio/audio_director.gd), `Frontier` (runestones, ecology, threat map, advanced once per in-game day), `Life` (autoload/life.gd: the player's life, owns the hub as `Life.realm`), `App` (scripts/core/app_services.gd), plus addons (QuestWeaver, PhantomCamera, DebugMenu).

### 3.4 Population: people with bodies (`scripts/population/*`)
- **Tiering.** `population_lod.gd` gives WorldSim rows a body near the player: FULL (animated, nametag, max 24 to 48), then sprite/far tiers, nothing beyond. `micro_actor.gd`, `micro_events.gd`, `micro_catalog.gd`, `micro_scene.gd` run the street-scene director (carts, funerals, gate closing).
- **Brain.** `villager.gd` is the embodied person; `utility_brain.gd` scores actions a few times a second; `schedule.gd` + `daily_rhythm.gd` give one timetable at every LOD; `street_graph.gd` is the walkable network; `town_mood.gd` is the settlement mood as numbers.
- **Perception and crime.** `perception.gd` (alert scalar, cone x distance x light x stance, hearing), `npc_world.gd` (shared awareness), `alert_net.gd`, `search.gd`, `witness.gd`, `evidence.gd`, `crime_watch.gd`, `trespass.gd`, `guard_lantern*.gd`. Skill `ashes-perception-ai`.
- **Reactive Presence (animation contract).** `presence.gd`, `presence_live.gd`, `reaction_request.gd`, `reaction_adapter.gd`. See the Antigravity handoff.
- **Talk.** `talk_bark.gd`, `talk_pose.gd`.

### 3.5 Actors (`scripts/actors/*`)
`player.gd` (four-scale camera, controls), `chase_camera.gd`, `camera_occluders.gd`, `traversal.gd` (vault, mantle, ledge, ladder), `player_arms.gd` (attack input, bow draw), `technique_caster.gd`, `bending_library.gd`, `monster.gd`, `wolf.gd`, `critter.gd`, `creature_models.gd`, `creature_attack_tokens.gd`, `mount_controller.gd`, recruits (`follower_body.gd`, `follower_brain.gd`, `follower_manager.gd`), squad (`squad_manager.gd`, `squad_soldier.gd`), Soulbeast (`soulbeast*.gd`), hero look (`hero_outfit.gd`, `hero_tier_a.gd`, `hero_face_driver.gd`), `ragdoll.gd`, `procedural_rig.gd`, `character_animator.gd`, `equipment_visuals.gd`, `impact_pause.gd`. Combat rules are in `scripts/combat/*` (`hit_resolver.gd`, `npc_fighter.gd`, `knockdown_state.gd`, `combat_feel.gd`, `weapon_rules.gd`).

### 3.6 World (`scripts/world/*`, `scripts/region1/`, `scripts/interiors/`)
Terrain and vegetation (`world_gen.gd`, `terrain_streamer.gd`, `terrain_backend.gd`, `terrain3d_bridge.gd`, `scatter_*.gd`, `grass_field.gd`, `water_streamer.gd`, `weather.gd`), settlements (`city_planner.gd`, `settlement_builder.gd`, `town_kit/*`, `town_identity*.gd`, `districts.gd`, `district_props.gd`, `house_details.gd`, `g_dressing.gd`, `town_decals.gd`, `lamp_*.gd`), region content (`region_sites.gd`, `region_dressing.gd`, `region1_*.gd`, `region_caves*.gd`, `region_pois.gd`, `hidden_valley.gd`, `vale_look.gd`, `towers/*`, `thornfield/*`), gatherables and work spots (`deposits.gd`, `forage_nodes.gd`, `work_spots.gd`, `farm_work_spot.gd`), realm made visible (`realm_presence.gd`, `realm_encounters.gd`, `monster_camps.gd`, `road_traffic.gd`, `frontier_presence.gd`), persistence (`world_state.gd`: interactive object deltas keyed by stable ids), budgets (`low_budget.gd`, `static_merge.gd`, `surface_collapse.gd`, `baked_vao.gd`, `town_atlas.gd`). Interiors and doors: `scripts/interiors/` (`interior_door.gd`).

### 3.7 Interaction (`scripts/interaction/*`)
One entry point for the interact button: `interactable.gd` (component attached to any Node3D), `interaction.gd` (gathers candidates), `interaction_picker.gd` (pure scoring, unit-tested), `interaction_controller.gd` (child of Player; tap or hold). Subfolder `kinds/`. Skill `ashes-world-interaction`.

### 3.8 Quests (`scripts/quests/*`)
A library of data-driven objectives (`objective.gd`, `quest_objectives.gd`, JSON under `data/quests/`) run by `quest_runner.gd` over a shared `quest_bus.gd`; `quest_hub.gd` is the single runner and save hook; `quest_pump.gd` feeds the bus from the running game; `quest_rewards.gd` pays through game APIs; `radiant_adapter.gd` and `story_lib_adapter.gd` bridge older systems.

### 3.9 Other folders
`scripts/ui/` (HUD, menus, war map), `scripts/vfx/`, `scripts/audio/`, `scripts/build/` (build mode), `scripts/living_world/` (life clips, smart objects, VAT crowds), `scripts/horses/`, `scripts/abilities/`, `scripts/army/`, `scripts/cinematic/`, `scripts/boot/`, `scripts/style_lab/`, `scripts/style_g.gd`.

### 3.10 Affairs panels (`scripts/ui/affairs/*`, `scripts/ui/gamemenu/tab_affairs.gd`)
PC panels that drive the Living World money, will, justice, war-intel and aura systems through their **public APIs only** (no realm logic in UI; they read getters, call the player's own actions, never tick). Functional and themed with `ashes_frame` + `gm_kit`; visual polish is owed by the local PC session. Test: `tests/test_ui_new_panels.gd`.

| Panel | Keys / entry | File | Module API |
|---|---|---|---|
| Treasury (weekly lines, scheduled payments, warnings, steward budget/limit, audit) | **F6** `menu_treasury` | `treasury_panel.gd` | `ledger.summary / delegate / relieve / audit / cancel` |
| Followers (will): motives in words, requests with answers, orders with a hint, reward / promote / dismiss / forgive / imprison / investigate / audit | **F7** `menu_followers` | `followers_will_panel.gd` | `follower_will.*` |
| Court (cases, evidence reliability, file, press, appeal, persuade / intimidate / blackmail / patronage) | **F8** `menu_court` | `court_panel.gd` | `courts.*` |
| Letters (weekly digest + steward report + urgent word, unread badge, envoys at the door) | **F10** `menu_letters` | `letters_panel.gd` | `war_intel.inbox / envoys` |
| Envoy audience (nine responses) | Letters panel, or `hud.show_envoy_dialog()` | `envoy_dialog.gd` | `war_intel.envoys / respond` |
| Officer parley (suppress, talk, intimidate, bribe, surrender, flee, fight) | opens by itself when the aura ladder reaches an arrived officer (step 2+); `hud.show_aura_parley(subject, sid)` | `aura_parley_dialog.gd` | `aura_fallout.ladder / resolve` |
| Gate prompt (permit, bribe, sponsor, disguise, argue, rite, leave the monster outside) | world calls `hud.show_gate_prompt(party, town, extra)` | `gate_prompt.gd` | `monster_society.gate / take_option` (over `entry_law`) |
| Status breakdown in the Character sheet ("Standing") | Character tab | `status_view.gd` | `monster_society.status_of` |

The four desks live in one Pack-menu tab, **Affairs** (`tab_affairs.gd`, shows "Affairs (n)" with unread letters); `TabAffairs.open_view(hud, "court")` opens one. Keys are `Game.KEYS` defaults, listed in the rebind screen (`settings_store.gd` ACTIONS). `affairs_hooks.gd` is one 2 s timer owned by the HUD: tells `war_intel` who reads (`set_viewer`), counts unread letters / waiting envoys, one toast per game day, and opens the parley. Read-letter ids persist in `Life.life_path.flags["letters_read"]`. Shared base classes: `affairs_base.gd` (panels), `affairs_modal.gd` (dialogs). Rule kept: numbers become words (`AffairsBase.fuzzy`), hidden state (agendas, forged evidence, envoy intent) is never shown unless the module reports it as known.

## 4. How the realm hub, tick and save work

- **Hub.** `Life.realm` is one `RealmHub` (`scripts/realm/realm_hub.gd`) that owns every module in its `MODULES` dictionary (`registry`, `events`, `followers`, ... one preload each). Skill `ashes-realm-module` is the recipe for adding one.
- **Tick tiers** (`docs/design/SIM_HIERARCHY.md`). Life calls `on_hour(hour, ctx)`; the hub queues each module's `tick_hour`, `tick_day` at 06:00 and `tick_week` when `day % 7 == 0`. `pump()` runs queued jobs every frame inside `PUMP_BUDGET_USEC` (600 microseconds). A module that must spread work implements `tick_day_chunks()` and returns Callables. `catch_up(days, ctx)` runs after long sleeps and loads. Messages come back from `pump()` for Life to show via `Game.say()`.
- **Rules for modules.** Pure data (no nodes, no scene access), deterministic (own RNG streams; time passed in), JSON-safe state, nothing that scales with world size per frame.
- **Save.** Each module implements `serialize()` / `deserialize()`; `Life.realm.serialize()` carries all of them. `scripts/sim/save_containers.gd` keeps dirty flags per container, so a snapshot serialises only what changed and a focus-loss autosave is skipped when nothing is dirty. `scripts/sim/save_manager.gd` writes JSON to `user://saves/` (3 manual slots, 3 rotating autosaves, a quicksave; portable, no device-bound encryption). Use `save_codec.gd` column helpers for big tables. Soulbeast state rides in the followers module (`soulbeast_save.gd`).

## 5. Testing

- **Unit tests:** gdUnit4 suites in `kingdom/tests/test_*.gd` (about 416 files). Run all: `GODOT=/path/to/godot tools/qa/run_tests.sh [batch_size]` (batches of 20 suites, one Godot process per batch; exit code 101 means orphan warnings only). Single suite: see skill `ashes-cloud-testing` (gdUnit command, class-cache errors, the shared-memory OOM trap).
- **CI:** `.github/workflows/tests.yml` runs on every push to `main` and `claude/**` and on PRs: secret scan, file-size guard, gdlint, and the full gdUnit run on Godot 4.6.2. Read results through GitHub (skill `ashes-ci`) instead of running everything locally.
- **Lint:** `bash tools/qa/lint.sh` (gdtoolkit + `tools/qa/gd_extra_lint.py`); rationale in `docs/qa/LINT.md`.
- **World lint (no rendering):** `kingdom/tools_qa/lint_world/world_lint.gd`, skill `ashes-world-lint`, test `tests/test_world_lint.gd`.
- **Harnesses (need a GPU or a display):** `kingdom/tools_qa/*` (playtest_bot, movement_qa, look_capture, feel_capture, perf), `tools/qa/anim_qa/` (animation catalogue QA), `tools/qa/bench/`, `tools/qa/perf_visual/`, `tools/qa/feel_sheets.sh`, `tools/qa/video_to_sheets.sh` (contact sheets, skill `ashes-video-review`).
- **Rule:** if you change behaviour, add or update a suite in `kingdom/tests/`. Never claim "tests pass" without a CI run or a logged local run.

## 6. Performance rules (full detail in skill `ashes-performance`)

1. Nothing scales with world size per frame. Far tiers cost nothing; only FULL-tier bodies (24 to 48) are observers or animated.
2. Frame budget at 60 fps: near-NPC AI and animation at most 2.0 ms, WorldSim slice 1.0 ms, hub `pump()` 0.6 ms, everything else in script 1.5 ms.
3. No per-frame allocation in hot paths; decisions run at a few Hz (`THINK_HZ`, presence at 10 Hz with stagger).
4. Streaming builds at most one chunk or region per frame; heavy maths goes to `WorkerThreadPool`.
5. Draw calls: MultiMesh batching, `static_merge.gd`, `surface_collapse.gd`, `character_merge.gd`, baked AO, LOD stages (LOD0 to impostor). LOW has hard budgets in `scripts/world/low_budget.gd`.
6. Every new feature states its cost for LOW and for the ram8 preset. Measure on a GPU before declaring a visual or perf change done (the cloud box cannot render reliably).
7. Textures: `tools/qa/texture_vram.py` and `tools/qa/asset_audit.py` check VRAM and unreferenced assets. Never commit files over 90 MB.

## 7. Design-doc index

**Top level (`docs/`):** `GDD.md` (original game design), `RISING_ASHES_LIFE_SIM_DESIGN.md` (life sim pillars), `RISING_ASHES_OPEN_WORLD.md`, `WORLD_LORE.md`, `KINGDOM_DESIGN.md`, `SYSTEMS_MASTERPLAN.md`, `SYSTEMS_CLAUDE_HANDOFF.md`, `SYSTEMS_CONTINUATION.md`, `LOCAL_SESSION_HANDOFF.md` (coordination log), `STATUS_LOCAL.md`, `CLOUD_SUMMARY_FOR_LOCAL.md`, `LOCAL_SUMMARY_FOR_CLOUD.md`, `LOCAL_PC_TASKS.md`, `RELEASE.md`, `TOOLCHAIN_AUDIT.md`, `TOOLCHAIN_PLAN.md`, `OPEN_SOURCE_AUDIT.md`, `OPEN_SOURCE_REFERENCES.md`, `DOWNLOAD_LIST.md`, `controls.md`.

**`docs/design/` (every file):**
- `FOUNDATION_PLAN.md` the freeze and the first milestone (read first). `VERTICAL_SLICE.md` Thornfield slice, districts, micro-events.
- `SIM_HIERARCHY.md` tick tiers and frame budgets. `REALM_PLAN.md` freedom and exploration, travel and world size. `REALM_WAR_SETTLEMENT.md` camps, construction, factions, war.
- `LIVING_WORLD.md`, `LIVING_WORLD_SANDBOX.md` (Parts A to E, stages 1 to 8), `LIVING_WORLD_MASTER_PLAN.md` (MW-* work items and status table), `NPC_INTELLIGENCE_MAP.md` (NI-* packages).
- `CIVILIZATION.md` settlement lifecycle, governance, information, ecology. `RETINUE_SETTLEMENT_ASCENSION.md` recruits, claiming, build kit.
- `WAR_COMMAND_RULEBOOK.md` war map, tactical battles, sieges. `DUNGEON_TOWERS.md`. `ITEMS_R1.md`.
- `ACADEMY_PLAN.md`, `CHILDHOOD_ACADEMIES.md` education, power paths, everyone learns to fight.
- `AAA_POLISH_PLAN.md`, `STYLE_LAB.md` look and polish.
- **Being written now (2026-10-21), may not exist yet when you read this; check the folder:**
  - `docs/design/AURA_RELEASE.md` aura and presence release: what characters radiate and how towns react (empty markets, shuttered windows, fear).
  - `docs/design/MONSTER_NAMING_AND_STATUS.md` how naming binds monsters, evolution and status.
  - `docs/design/ENDLESS_PLAY_AND_PROFESSIONS.md` endless play and the profession ladders.

**Other doc folders:** `docs/regions/` (Region 1 plan, look, cast, story, balance, audio, hooks), `docs/anim/` (animation audits, handoffs, traversal v2, feel), `docs/art/` (Style G, faces, hero, VFX plans, water, build kit), `docs/qa/` (lint, perf, asset audit, pooling, release readiness), `docs/perf/`, `docs/research/` (mining reference games), `docs/ui/`, `docs/concepts/`.

**Skills (`.claude/skills/`):** one per recurring job; see the descriptions in the folder. Most important: `ashes-collab`, `ashes-handoff`, `ashes-realm-module`, `ashes-work-package`, `ashes-style-g`, `ashes-world-lint`, `ashes-ci`, `ashes-cloud-testing`, `ashes-animation-pipeline`.

## 8. Ownership (updated 2026-10-21)

| Team | Owns | Does not touch |
|---|---|---|
| **Cloud Claude session** | Systems, simulation, saves, tests: `scripts/realm/*`, `scripts/sim/*`, `scripts/population/*` (except the animation mapping side), `autoload/*`, `scripts/quests/*`, `scripts/interaction/*`, `scripts/combat/*` rules, `data/` tables, `kingdom/tests/*`, `tools/qa/run_tests.sh`, CI. Adds the hooks other teams request. | Animation clip choice and blending; world look and dressing. |
| **Antigravity** | All animation and everything revolving around it: clips, AnimationTree layers, locomotion feel, combat and traversal timing, reaction clips and LookAt, follower and creature animation, facial and hero animation, ragdoll feel, mocap retargeting, VAT crowds, anim QA. Files: `scripts/actors/character_animator.gd`, `procedural_rig.gd`, `bending_library.gd`, `hero_face_driver.gd`, `ragdoll.gd`, `impact_pause.gd`, `scripts/population/reaction_adapter.gd` (the mapping), `scripts/living_world/*`, `assets/incoming/animations/*`, `docs/anim/*`, `tools/qa/anim_qa/`. Replaces the earlier "Codex animation" ownership. | Simulation code (realm, sim, presence rules, reaction_request.gd contract). Request hooks from cloud in `docs/HANDOFF_ANTIGRAVITY.md`. |
| **Codex** | The world: terrain, towns, dressing, environment, world VFX. Files: `scripts/world/*`, `scripts/region1/*`, `scripts/interiors/*` visuals, `scripts/vfx/*` (world VFX), `shaders/*` for ground and world, `data/region1/*`, `data/world/*` layout data, `assets/terrain3d/*`, `docs/regions/*`, `docs/art/*`, `tools_qa/lint_world`, `tools_qa/environment`, `tools_qa/terrain3d`. | Simulation rules and saves; animation. Request hooks from cloud in `docs/HANDOFF_CODEX_WORLD.md`. |
| **Local PC Claude session** | GPU checks, performance on a real GPU, Blender GUI and Meshy, release and store, phone tooling (`docs/LOCAL_SESSION_HANDOFF.md`). Judges the Terrain3D backend before it becomes default. | Feature code owned by the others. |

Rules of thumb: the owner's word decides ownership. Shared files need a dated line in `docs/LOCAL_SESSION_HANDOFF.md` before you edit them. Commit only your own paths; never `git add -A`; merge before push (skill `ashes-collab`). Branch for the cloud/local sessions: `claude/focused-curie-m09hbd`.

## 9. How to start working

### Cloud Claude (systems)
1. Merge the shared branch, read `docs/LOCAL_SESSION_HANDOFF.md` (requests from Antigravity and Codex arrive there and in the two handoff files).
2. Pick a work package (skill `ashes-work-package`), design under `docs/design/` first (skill `ashes-game-design`).
3. New simulation = a realm module (skill `ashes-realm-module`): pure data, deterministic, chunked, serialised, with a gdUnit suite. Check CI with skill `ashes-ci`.
4. Answer hook requests: add the data or signal, document it in the requesting team's handoff file, and never reach into their files.

### Antigravity (animation)
1. Read `docs/HANDOFF_ANTIGRAVITY.md` fully, then `docs/anim/` audits and skill `ashes-animation-pipeline`.
2. Start from the reaction contract: implement `ReactionAdapter.describe()` clip mapping and the `presence_react` clip choices. Run `tools/qa/anim_qa/run.sh` and the feel sheets to prove it.
3. Do not edit simulation code. File a request under "Open animation requests" in your handoff doc.

### Codex (world)
1. Read `docs/HANDOFF_CODEX_WORLD.md`, skills `ashes-style-g`, `ashes-style-g-assets`, `ashes-style-g-qa`, `ashes-environment-look`, `ashes-region-content`, `ashes-world-lint`.
2. Run the world linter after every placement change; keep LOW and ram8 budgets green.
3. Read simulation state only through the APIs listed in your handoff file (for example `district_values.gd`). File requests there.

### Local PC session
GPU captures and approvals, release, phone checks. Record results in `docs/LOCAL_SESSION_HANDOFF.md`.
