# Handoff: Antigravity (animation)

Written 2026-10-21 by the cloud Claude session. **Antigravity owns all animation and everything revolving around it** (replaces the earlier "Codex does animation" arrangement). Read `docs/PROJECT_BIBLE.md` first for the project map. Paths are relative to the repo root; the Godot project is `kingdom/`.

## Rules

1. **Do not change simulation code.** That is `kingdom/scripts/realm/*`, `scripts/sim/*`, `autoload/*`, the rules in `scripts/population/presence.gd`, `perception.gd`, `utility_brain.gd`, `schedule.gd`, and `reaction_request.gd` (the frozen contract).
2. **Need a hook, signal, field or new reaction kind? Ask the cloud session in this file**, under "Open animation requests" (add a dated line: who, what you need, why, which clip/layer it feeds). The cloud session answers in the same line and documents the API.
3. You may freely change: clip choice, blend times, AnimationTree layers, LookAt, root-motion handling, retargeting, clip libraries, `reaction_adapter.gd` (the mapping side), `character_animator.gd`, `procedural_rig.gd`, `bending_library.gd`, `hero_face_driver.gd`, `ragdoll.gd`, `impact_pause.gd`, `scripts/living_world/*` (life clips, smart objects, VAT crowds), `assets/incoming/animations/*`, `docs/anim/*`, `tools/qa/anim_qa/`.
4. Shared files (`villager.gd`, `player.gd`, `follower_body.gd`, `monster.gd`, `wolf.gd`): the AI code in them is cloud-owned; the clip calls inside are yours. Keep edits to the animation lines, put a dated note in `docs/LOCAL_SESSION_HANDOFF.md` before editing, and keep `player.gd` CRLF.
5. Commit only your own paths, merge before push (skill `ashes-collab`). Prove animation changes with captures (skill `ashes-video-review`, `tools/qa/feel_sheets.sh`), not just code.

## 1. The reaction contract (frozen)

The AI side asks for an **abstract reaction**; the animation side maps it to clips. No clip names or blend values live in the AI code.

**Files**
- `kingdom/scripts/population/reaction_request.gd` (`ReactionRequest`): the request queue. Per body slot: one current request per layer plus a ring of 6 pending requests; no allocation.
- `kingdom/scripts/population/reaction_adapter.gd`: the **only place that turns a reaction into "what the body should do"**. Today a stub: `describe(kind)` returns `{clip_hint, look, additive|displace|speak, layer, priority, keeps_activity}`; `consume(queue, slot, sink)` drains pending requests to a Callable; `look_target(queue, slot, now)` returns the id the head/eyes should follow. **Your job: replace the `clip_hint` strings (`react_glance`, `react_bow`, `react_flee`...) with real AnimationTree layers/clips.** AI code never changes.
- `kingdom/scripts/population/presence.gd`: decides when to ask (see section 3).
- `kingdom/scripts/population/presence_live.gd` (`PresenceLive`): live wiring, owned by `PopulationLOD`, runs at 10 Hz, only FULL-tier bodies are observers; calls `body.presence_react(kind, target_id, info)` after `adapter.consume`.
- `kingdom/scripts/population/villager.gd`, `presence_react(kind, target, info)` (around line 2393): the current implementation on the villager. It already uses `Life_Social_Wave_Greet`, `Life_Social_Nod`, `Life_Social_Bow`, `Idle_Hurt`, `Hit_Light` via `_begin_oneshot`, `_begin_sidestep` for step back/aside, `_react_look_until` / `_react_away_until` for head look, `_say()` for confront/warn barks. Replace these with adapter-driven layers when your mapping exists. `last_reaction` holds `"<name>@<ms>"` for debugging.
- Tests: `kingdom/tests/test_mw_presence.gd`, `test_presence_live.gd`.

**Kinds** (enum `ReactionRequest.Kind`, values 0 to 12), with layer, priority, duration, keeps_activity:

| Kind | Layer | Prio | ms | Keeps activity | Meaning |
|---|---|---|---|---|---|
| GLANCE | HEAD | 1 | 1200 | yes | quick look at target (additive, look) |
| LOOK_AWAY | HEAD | 1 | 1500 | yes | avoid eye contact (additive) |
| STEP_BACK | LOCO | 3 | 900 | yes | short backwards displacement, look at target |
| STEP_ASIDE | LOCO | 3 | 1100 | yes | short sideways displacement, look at target |
| BOW | UPPER | 2 | 1400 | yes | respectful bow (additive, look) |
| FLINCH | UPPER | 4 | 600 | yes | startle (additive) |
| CONFRONT | BODY | 5 | 3000 | no | stops activity, faces target, speaks |
| WAVE | UPPER | 2 | 1500 | yes | friendly greeting (additive, look) |
| WARN | BODY | 5 | 2500 | no | warning stance, speaks |
| CALL_GUARD | BODY | 6 | 3500 | no | shout/gesture for the guards, speaks |
| FLEE | LOCO | 7 | 6000 | no | run away; **exclusive** (see rules) |
| RETURN_TO_WORK | LOCO | 1 | 800 | yes | resume the paused activity (ends BODY layer) |

Layers: `HEAD, UPPER, LOCO, BODY`.

**Rules (`can_preempt`)**: layers coexist; on the same layer only a strictly higher priority preempts, equal or lower waits for expiry; FLEE is exclusive (while it runs only higher than 7, none today, preempts on any layer); `keeps_activity == true` means the animation layer works OVER the current activity (additive or short displacement) and the activity resumes by itself; `false` pauses the activity until RETURN_TO_WORK. `pausing_activity(slot, now)` tells you when to hold the schedule/brain action.

**Subjects and stimuli** (what triggers requests, `presence.gd` `Stim`): STARE, FOLLOW, BLOCK_DOOR, BUMP, RUN_CROWD, DRAWN_WEAPON, TRESPASS, TAKE_OBJECT, EAVESDROP, PUBLIC_MAGIC, KINDNESS, INSIGNIA, INJURED, REPEAT_VISIT. Stages per observer: NOTICE, CHECK, TEST, DECIDE. Debug: set `PresenceLive.debug = true` to print every reaction plus the watching stage/reason.

**Body duck-type** (`presence_live.gd` header): `presence_sample() -> {id, pos, facing, vel, flags, busy, guard, opts}` and `presence_react(kind, target_id, info)`. Any new body type (follower, creature) that should react implements the same two methods.

## 2. Other bodies and their clip entry points

- **Villagers**: `scripts/population/villager.gd` (clips by job via `Assets.character` and `LifeLibrary`; `scripts/living_world/life_library.gd`, `life_actor.gd`, `smart_objects.gd` for work spots, data `kingdom/data/living_world/smart_objects.json`, `life_props.json`, `face_offsets.json`). Talk pose: `scripts/population/talk_pose.gd`. Faces: `scripts/living_world/face_state.gd`, `npc_face_card.gd`, `docs/art/FACES.md`.
- **Far/crowd animation**: `scripts/living_world/crowd_anim_lod.gd`, `vat_asset.gd`, `vat_crowd.gd`, `vat_residents.gd` (vertex-animation-texture crowds; bake data `data/living_world/vat_bake.json`).
- **Follower bodies (recruits)**: `kingdom/scripts/actors/follower_body.gd`. It wears the villager's model, tint and clips (`Walking_A` / `Running_A`, smart-object work clips), takes orders from `follower_brain.gd` (follow / fight / wait / home / work), thinks at `THINK_HZ = 4`. Fighters use `scripts/combat/npc_fighter.gd`; when hurt they are **knocked out for a while, never killed**. Manager and budget: `follower_manager.gd`. Squad bodies: `squad_soldier.gd`, `squad_manager.gd`. Soulbeast (wolf companion): `soulbeast.gd` + `soulbeast_brain.gd`. Followers do not yet implement `presence_react`; see requests.
- **Player**: `scripts/actors/player.gd`, `player_arms.gd` (attack tap = light combo, hold past `hold_time` = charged heavy, bow draw/release), `traversal.gd`, `technique_caster.gd` + `bending_library.gd`, `mount_controller.gd`, `character_animator.gd` (the AnimationTree built in code, OneShot slots `play_upper` / `play_full`).
- **Creatures**: `monster.gd` (humanoid monsters; **yield = kneel when beaten**), `wolf.gd` (wolf, boar, bear, blight rat, fungal brute), `critter.gd`, `creature_models.gd` (model table: GLB, scale, walk/run speed per clip, when the attack clip connects), `creature_attack_tokens.gd`.
- **Hero**: `hero_tier_a.gd`, `hero_outfit.gd` (skinned garments follow every clip), `hero_face_driver.gd` (blink, moods, brows, secondary motion), skill `ashes-hero-character`.

## 3. What requests which reaction today and what is planned

Implemented requests come from `presence.gd` decisions (staged, hash-deterministic, with de-escalation). Check `presence.gd` around the `K.` mappings (line ~713 maps names to kinds) for exact thresholds.

| Situation | System | Reaction today |
|---|---|---|
| Player stares / follows / blocks a door / bumps | `presence.gd` stimuli | GLANCE, LOOK_AWAY, STEP_ASIDE/STEP_BACK, FLINCH (bump) |
| Player draws a weapon, runs through a crowd, casts publicly | Presence + `social_perception.gd` (status-dependent) | STEP_BACK, WARN, CONFRONT, CALL_GUARD, FLEE depending on persona courage and status |
| Trespass / entering a `private_home` door | `interior_door.gd` reports `Stim.TRESPASS` | CONFRONT/WARN, CALL_GUARD |
| Kindness, insignia, repeat visits | positive stimuli | WAVE, BOW, GLANCE |
| Guards | `guard` flag in `presence_sample`; guard-near radius `GUARD_NEAR_M` 15 m | CALL_GUARD is answered through `villager.witness(...)`, guards then run `perception.gd` alert states |
| Crime witnessed | `scripts/population/witness.gd`, `alert_net.gd`, `search.gd` | alert classes (SUSPICIOUS, ALARMED) via `Perception.set_class_at_least`; searchers check claimed hiding spots |
| Player crouched in a hiding spot | `search.gd` (`HIDE_R`) | vision treats the player as nearly invisible; **hiding pose for the player is yours** |
| Beaten humanoid monster | `monster.gd` | yield (kneel) loop; named subordinates later |

**Planned behaviours that will need clips (cloud will emit them through the same contract; the exact new kinds are in `docs/design/AURA_RELEASE.md` once written, which is being drafted now):**
- **Aura / presence release**: high-aura characters make nearby NPCs bow, kneel, step back, tremble, shield their eyes, or **faint** in extreme cases. Expect new kinds such as KNEEL, TREMBLE, FAINT, SHIELD_EYES (names not final until the doc lands).
- **Fleeing with children**: parents/guardians carrying or pulling children while FLEE runs (carry pose, hand-hold run, child following at an offset).
- **Kneeling / begging / surrendering**: yielded monsters, bound captives, petitioners at audiences (`scripts/realm/audiences.gd`).
- **Hiding**: villagers ducking behind carts or indoors during a raid or fight; closing shutters (the world side belongs to Codex).
- **Guards**: alarm shout, drawing weapons, arrest escort, lantern-carrying patrol (`guard_lantern.gd`), `Style_Guard_March_Loop`.
- **Fainting**: fall, lie, wake-up (see `Lie_Down` / `Stand_From_Floor` / `Fall_Forward_Knockdown` in the feel list).

Until those land, build the mapping so that an unknown `kind` falls back to the nearest existing one and never leaves the body in T-pose.

## 4. Combat and traversal clips and data

- `kingdom/data/movement/traversal.json`: bands, probe, auto_vault, vault, mantle_low, mantle_high, ledge, ladder, step; every clip name and timing. `scripts/actors/traversal.gd` moves the capsule along scripted curves; **clip root motion is not used** (root track disabled in `UAL_Authored_Traversal.glb`). Handoff: `docs/anim/traversal_v2_HANDOFF.md`.
- `kingdom/data/combat/player_weapons.json`: `heavy`, `style_of_type`, `ammo_of_type`, `bow`, `pool`, `knockdown`. `kingdom/data/combat/archetypes.json`: NPC fighter archetypes. Per-clip combat markers (frames at 30 fps, rate 1.0): `kingdom/assets/incoming/animations/combat/combat_markers.json`, loaded by `scripts/actors/combat_markers.gd`. Code: `scripts/combat/*` (`combat_moves.gd`, `hit_resolver.gd`, `knockdown_state.gd`, `combat_feel.gd`, `telegraph.gd`, `takedown.gd`), `scripts/actors/impact_pause.gd` (local hit-pause).
- Docs: `docs/anim/COMBAT_AUDIT.md`, `FEEL_AUDIT.md`, `CODEX_LOCOMOTION_JUMP.md` (nine-step jump/land/run-stop/pivot validation), `CODEX_INTEGRATION_REVIEW.md`.

## 5. Rigs and clip libraries (UAL)

- **Skeleton**: the Universal Animation Library (UAL) 65-bone rig. Everything retargets onto it (skill `ashes-animation-pipeline`: free mocap sourcing, licence rules, Blender retarget, GLB AnimationLibrary export, preview strips).
- **Loaded at start** through `Assets.UAL_FILES` in `kingdom/scripts/world/assets.gd` (first match wins): `UAL_Loco_Transitions.glb`, `UAL_Authored_Traversal.glb`, `UAL1_Standard.glb`, `UAL2_Standard.glb`, then 119 extra CC0 retargeted clips and more. Libraries under `kingdom/assets/incoming/animations/`: `combat/UAL_Combat.glb`, `life/UAL_Life_{Mocap,Social,Town,Work}.glb` (+ `.life.json` sidecars), `cmu_mocap/UAL_CMU_Mocap.glb`, `souls_cat/UAL_Souls_Cat.glb`; `kingdom/assets/incoming/mocap/cmu/clips/UAL_CMU_Bending.glb` (36 bending clips, installed on demand as library `"bending"`); `kingdom/assets/incoming/characters/_library/UAL_Extra_100STYLE.glb` (14 styled locomotion clips: WalkBack, Strafe, Rushed_Sprint, Walk_Start/Stop, Turn_InPlace, Guard_March, Old_Walk, Wounded_Walk, Sneak, Shielded_Walk, Unarmed_Punch_Idle; CC BY 4.0; **not yet in `UAL_FILES`**).
- **Not in `UAL_FILES` yet**: `UAL_Free_Reactions` (Fall_Forward_Knockdown, GetUp_*), the 100STYLE set. Both are what reactions (flee gait, faint, knockdown get-up) need.
- Sidecars: `*.clips.json` per GLB list clips; `*.life.json` list prop/work metadata.
- Verification tools: `tools/qa/anim_qa/run.sh` (catalogue QA, reports in `docs/qa/anim_qa_report*.md`), `tools/qa/bench/check_clips.gd`, `kingdom/tools_qa/anim_tech`, `kingdom/tools/anim/*` (preview, foot-slide, measure_events), `tools/qa/feel_sheets.sh`.

## 6. Feel lists (carried over from `docs/LOCAL_SESSION_HANDOFF.md`)

**Locomotion / foundation (2026-10-05)**: (1) run the nine-step validation of jump, land, run-stop and pivot in `docs/anim/CODEX_LOCOMOTION_JUMP.md` and fix failures; (2) wire walk/run starts, walk stop, sprint skid, idle turn; (3) sword-stance armed locomotion (idle/walk/run with weapon drawn) and additive hit reactions; (4) tune timing of the traversal clips (`Ledge_*`, `Mantle_*`, `Vault_*`).

**Traversal check list**: foot slide after the vault handover; the 0.12 s shuffle before a standing mantle; `Vault_Low` / `_B` side mapping; ledge top landing 10 cm off; `Ledge_Hang_Idle` loop blending into the climb; step-up floating at run speed.

**Combat check list**: `Lie_Down` at 3x into `Stand_From_Floor` will pop; `UAL_Free_Reactions` has `Fall_Forward_Knockdown` / `GetUp_*` but is not in `UAL_FILES`; staff light attacks borrow `Sword_Regular_*`; the `Bow_Hold` loop is a re-fired one-shot and may seam; no charge/draw meter yet (the `charge_changed` signal exists).

**Bending polish (open)**: clips are trimmed mid-motion so the OneShot fade-in (0.06 to 0.08 s) pops: add a lead-in or a longer fade; `upper` mode leaves legs jogging during strikes while running: consider a brief move lock for planted-leg clips (`Fire_Box_*`, `Earth_Lunge_*`); `Lightning_*` are placeholders; fingers are fixed fist/relaxed poses; blending notes in `docs/LOCAL_SESSION_HANDOFF.md` section "WIRED (cloud, 2026-10-05)". Test: `tests/test_technique_anims.gd`.

**Other open items from older notes**: locomotion library gaps filled by 100STYLE (suggested blend 0.15 to 0.2 s loops, 0.1 s transitions); rider seat height on the `HorseRig` town horse not checked in a ride; hero close-up faces and dialogue presentation (`docs/art/FACES.md`, `docs/art/AAA_PRESENTATION_REVIEW.md`).

## 7. Open animation requests (add yours here)

Format: `YYYY-MM-DD who: request -> status/answer`.

- 2026-10-21 cloud: build the real mapping behind `ReactionAdapter.describe()` for all 12 kinds (layers HEAD/UPPER/LOCO/BODY), keep the unknown-kind fallback. -> open (Antigravity).
- 2026-10-21 cloud: add `presence_react` to `follower_body.gd` and creatures if wanted; cloud will add `presence_sample` hooks on request. -> open, tell cloud which bodies.
- 2026-10-21 cloud: new reaction kinds for aura (kneel, tremble, faint, shield eyes), carrying/leading children while fleeing, hiding, surrender. Cloud adds the kinds to `reaction_request.gd` (contract change, additive only) once `docs/design/AURA_RELEASE.md` is final. -> waiting on design doc; list the clips you need here.
- 2026-10-21 cloud: put `UAL_Free_Reactions` and `UAL_Extra_100STYLE` into `Assets.UAL_FILES` (animation owner decides order; first match wins). -> open.
- 2026-10-21 cloud: confirm timing of `Lie_Down` to `Stand_From_Floor` and knockdown get-up (feel list). -> open.
- 2026-10-21 cloud: **Aura reaction kinds are in** (`docs/design/AURA_RELEASE.md`, "Implemented (cloud)"). `ReactionRequest.Kind` now has KNEEL=13 (BODY, prio 4, 5000 ms, pauses activity: knees give / devotee kneels), FAINT=14 (BODY, prio 8, 12000 ms, outranks the exclusive flee: fall, lie, later get up), HIDE=15 (LOCO, prio 6, 6000 ms: duck into a doorway or behind cover), FLEE_WITH_CHILD=16 (LOCO, prio 7, 6000 ms, exclusive like FLEE; the request target is the child's body id when known: carry pose or hand-hold run, child follows at an offset). Add real mappings in `reaction_adapter.gd` `INFO` (entries exist with `clip_hint` react_kneel / react_faint / react_hide / react_flee_with_child and a `fallback` kind); until then `villager.presence_react` plays the fallback (bow, flinch, step back, flee) so nothing T-poses. Tier-to-kind mix, so you know what to author: T1 glance/look away; T2 step back, flinch, hide (parents), kneel (pious, holy read), warn/call guard; T3 flee, flee_with_child (parents), kneel (elders), hide, call guard; T4 kneel, faint (frail); T5 faint. Also wanted: tremble/shield-eyes overlays (not requested by cloud), rival-mage counter-pulse, child stare walk-up, officer parley stances (the ladder exposes `ladder(subject, sid)` with `id` patrol / officer_parley / captain_mages ...). Player aura state for VFX/anim: player meta `aura_view` (`state`, `aura_emit`, `reach_m`, `signature`, `cone`). -> open (Antigravity).
- 2026-10-21 cloud: **Monster naming and status clips** (`design/MONSTER_NAMING_AND_STATUS.md`, "Implemented (cloud)"). The data is in `kingdom/data/world/species_tracks.json`; each species lists the AnimationLibrary names it needs under `clips`. Needed per species where listed: `name_evolve` (morph, 3 day dormancy is a data state: `monster_bonds.is_dormant(bond_id)`), `dormant` (cocoon/fever/sleep pose, vulnerable), speech sets by Speech track (`speak_pidgin` track 2, `speak_fluent` 3, `speak_eloquent` 4 for orc/lizardfolk; wolf `speak_bark_short`; spider `web_sign`), `oath_swear` + `salute` (orc), `petition` + `disguise_robe` (lizardfolk), `disguise_hood` (goblin), work loops `work_hammer`, `work_ledger`, `work_mine`, `work_haul`, `hold_chokepoint`, `winter_sleep` (bear), `gate_wait` (wolf/ogre waiting at the gate camp), `mourn` (death of a bonded companion). Gate reactions for guards (verdict strings from `entry_law.gd`: `admit`, `admit_with_terms`, `turn_back`, `bar`): wave through, wave off, spit, salute; plus a crowd protest loop and a `leave_town` carry-bundle walk for households that emigrate (reason "monsters"). Track values to key the visuals: `form`, `mind`, `speech`, `ability` 0..4 on each bond (`Life.realm.mod("monster_bonds").bond(id)`). -> open (Antigravity).
