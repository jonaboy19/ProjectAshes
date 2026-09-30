# Living world: handoff (clips, crowd tech, smart objects)

Local session, 2026-09-30. Goal: villages that feel lived in (Red Dead, Kingdom Come), running at 60 fps HIGH /
30 fps LOW on mid-range phones with 40+ visible villagers.
All new code is standalone. The hot files (villager.gd, population_lod.gd, world_sim.gd, assets.gd) are
untouched in the commits; the integration is in the P13 patches.

- Demo + proof: `kingdom/tools_qa/living_world/living_world_demo.tscn`
- Frames and captures: `docs/anim/living_world/`
- Perf: section 5 below

## 1. What exists

| piece | file | what it does |
|---|---|---|
| Life clip library | `assets/incoming/animations/life/UAL_Life_{Work,Town,Social,Mocap}.glb` + `.life.json` | 188 clips on the UAL skeleton. The sidecar gives, per clip: category, loop, layer (full/upper), enter/exit clips, blend times, props (id + hand), smart-object anchor, events (contact frames), pair partner and distance, walk `speed_mps`, tags (rain, morning, elder ...) |
| LifeLibrary | `scripts/living_world/life_library.gd` | `install(anim)` adds all life clips to a rig's shared library (once per skeleton path). `info(clip)`, `clips_in("work/smith")`, `clips_tagged("rain")`, `composite(anim, "Walk", "Life_Carry_Bucket_Upper")` = legs of one clip + spine/arms of another in ONE AnimationPlayer clip (carry and rain layers with no AnimationTree) |
| Props | `assets/generated/life_props/*.glb` (37 hand props + 11 scene props, one shared atlas material), `data/living_world/life_props.json`, `scripts/living_world/life_props.gd` | Grip contract shared by Blender and Godot: the fist frame comes from the rest bones (fingers, thumb side, palm), and each prop's origin is the grip. `LifeProps.Holder.new(skeleton).show_for_clip(clip)` shows the clip's props and hides the rest; attachments are reused |
| Smart objects | `data/living_world/smart_objects.json`, `scripts/living_world/smart_objects.gd` | 32 activity types: anvil, bellows, field rows, well (with a queue), wash tub, market stall (vendor and customer roles), bar counter, tavern table, bench, chapel pews, guard post, hopscotch, play area, conversation circle, and more. Per slot: stand point (or "auto" from the clip's anchor), facing, approach distance, enter/loop/between/exit clips, duration, job/act/hour/kid filters. Placement rules per building asset. `find` → `claim` → `session` (approach → align → enter → loop/between → exit → release), `interrupt()`, `target_for()` for WorldSim |
| Ambience | `scripts/living_world/life_ambience.gd`, `living_events.gd` | Stable personality per person: walk speed, playback rate, height, gesture, curiosity, restlessness, mood → walk style (happy/sad/brisk/elder/cane). Idle fidgets by time of day and weather (morning stretch, evening yawn, shade eyes in the sun, rub arms in the cold). Glances at events (`LivingEvents.emit("clang", pos, r)`) and at the player, with cooldowns. Rain hunch layer and hurried pace. Talk/listen clip choice for conversation groups |
| VAT crowd | `tools_qa/living_world/vat_bake.tscn`, `scripts/living_world/vat_asset.gd`, `vat_crowd.gd`, `shaders/living_world/vat_crowd.gdshader`, bakes in `assets/generated/vat/` | Bakes the game's own MakeHuman villagers (lod1 → meshoptimizer LOD ~1300 tris; vertex colours = albedo × atlas) with their clips into position (RGBA half) and normal (RGBA8) textures, 6 rows/s, interpolated in the shader. One MultiMesh per look. Per instance: clip row/frames/loop, phase, speed and clothing tint in INSTANCE_CUSTOM, so there is no lockstep. A global `vat_time` lets the skeleton → VAT hand-off keep the exact pose |
| VatResidents | `scripts/living_world/vat_residents.gd` | The FAR tier for WorldSim rows (no nodes). Picks look and clip from job/phase/walking, moves walkers smoothly between PopulationLOD's 4 Hz refreshes, caps per tier (LOW 40 / MED 80 / HIGH 140) and loads 4 looks on LOW |
| CrowdAnimLOD | `scripts/living_world/crowd_anim_lod.gd` | NEAR: full rate, look-at, shadows. MID: manual AnimationPlayer stepped every 2–4 frames (bucketed, exact phase), skeleton modifiers off, 8-frame steps off screen. FAR: model hidden, VAT twin at the same clip time. OUT: sprites (PopulationLOD). Hysteresis, per-tier budgets, `lod_tier` fed back to the body |
| LifeActor | `scripts/living_world/life_actor.gd` | Reference body that ties it all together: routines, sessions, carrying, fidgets, glances, chat groups, props, behaviour LOD (runs every 3–8 physics ticks when not near). The worked example for villager.gd |
| QA | `tools_qa/living_world/clip_gallery.tscn` (clips + props + anchors in engine), `vat_test.tscn` (skeleton vs VAT twin), `living_world_demo.tscn` (`--mode=showcase|stress|bench`), `tests/test_living_world.gd` (9 gdUnit tests) | |

## 2. Hooking the clips and smart objects into villager.gd (Codex)

Step by step in **`docs/anim/patches/P13_villager_life_clips.md`**. Each step can be applied on its own:
1. `LifeLibrary.install(_anim)`: one line.
2. New `ACT_CLIPS` / `JOB_CLIPS` / `TALK_CLIPS` tables with the life clips first (fallbacks kept) and a per-person pick.
3. `LifeProps.Holder`: three lines.
4. Enter/exit transitions from the sidecar.
5. Smart-object sessions in `_apply_plan()` / at arrival, with release on every exit path.
6. `LifeAmbience` for walk style, rate, height, fidgets, glances, rain hunch (`LifeLibrary.composite`) and carry layers.
7. Hand animation LOD to CrowdAnimLOD: delete the villager's own `_anim_lod` stepping.

Blend times: use the sidecar `blend_in` / `blend_out` (0.2–0.35 s). Root motion: none. All life clips play in place
(`root` track disabled under `animations/`). Walks carry `speed_mps` for speed matching:
`speed_scale = body_speed / speed_mps`. Events are 30 fps frame numbers (`contact`, `sip`, `strum`, `page_turn`,
`step_l/r` ...); map `contact` to work sounds in place of `WORK_SOUNDS` fractions.

## 3. Hooking VAT crowds into population_lod.gd (cloud)

**`docs/anim/patches/P13_population_lod_vat.md`** (explained), with the exact tested diff in
**`P13_population_lod_vat.diff`** (41 lines in population_lod.gd, 2 in villager.gd). It was applied and run in the
real game (village bench) on this machine; see section 5.
- `setup()`: create `VatResidents` and `CrowdAnimLOD`.
- `refresh()`: residents inside `VAT_RANGE` without a full model go to `_vat.want(...)` before the sprite code. This
  also fixes close residents that were INVISIBLE when the full-model budget ran out, since they are now VAT.
- `_spawn()` / demotion: `register` / `unregister` with CrowdAnimLOD.

World sim: **`P13_world_sim_smart_objects.md`**: `WorldSim.smart = SmartObjects.new()`, spots populated per settlement
on first use, and `_spot()` asks `smart.target_for()` for work and market targets, so the data tier and the embodied
villager agree on who stands at the anvil.
Assets: **`P13_assets_life_libs.md`** (optional): 4 lines in `UAL_FILES`, to give the player the clips too.

## 4. Clip catalogue (188)

Sources:
- 132 clips are hand-authored in Blender. They use the IK key-pose framework from the combat pass, with the prop grip
  contract (`tools/anim/life/`).
- 56 are CMU everyday mocap retargeted with `retarget_bvh.py` (CMU: free for commercial use, credited in CREDITS.md).
  The take table is in `UAL_Life_Mocap.glb.life.json` (`notes`).
- 14 loops have dedicated `_Enter` / `_Exit` transitions (kneel, sit, lie down, hoe, anvil, saw, nail, chop,
  laundry, mourn, stool). The others blend in over 0.2–0.35 s from neutral.
- Paired clips (`pair`: hug, handshake, converse, quarrel, comfort) carry their partner distance and facing.

| category | count | clips (L loop, U upper-body layer, P props) |
|---|---:|---|
| work | 63 | Carp_Nail_Enter`P`, Carp_Nail_Exit`P`, Carp_Nail`LP`, Carp_Saw_Enter`P`, Carp_Saw_Exit`P`, Carp_Saw`LP`, Chore_Hang_Washing`LP`, Chore_Laundry_Scrub_Enter`P`, Chore_Laundry_Scrub_Exit`P`, Chore_Laundry_Scrub`LP`, Chore_Laundry_Wring`P`, Chore_Sweep`LP`, Chore_Well_Crank`L`, Chore_Well_Lift_Bucket`P`, Cook_Chop`LP`, Cook_Stir`LP`, Farm_Feed_Chickens`LP`, Farm_Harvest_Enter`P`, Farm_Harvest_Exit`P`, Farm_Harvest`LP`, Farm_Hoe_Enter`P`, Farm_Hoe_Exit`P`, Farm_Hoe`LP`, Farm_Milk_Cow_Enter, Farm_Milk_Cow_Exit, Farm_Milk_Cow`L`, Farm_Sow`LP`, Fish_Cast`P`, Fish_Idle_Rod`LP`, Fish_Reel`LP`, Guard_Attention`LP`, Guard_Lean_Spear`LP`, Guard_Look_Out`P`, Market_Arrange`LP`, Market_Call_Out`L`, Market_Hand_Over`P`, Mocap_Buy, Mocap_Carry_Heavy`L`, Mocap_Chop_Wood, Mocap_Dig, Mocap_Fish, Mocap_Hammer_Nail`L`, Mocap_Move_Box, Mocap_Pay, Mocap_Pick_Place, Mocap_Plant, Mocap_Rake, Mocap_Saw`L`, Mocap_Slice, Mocap_Stir`L`, Mocap_Sweep, Shop_Counter_Lean`L`, Shop_Tally`LP`, Shop_Wipe`L`, Smith_Bellows`LP`, Smith_Hammer_Enter`P`, Smith_Hammer_Exit`P`, Smith_Hammer`LP`, Smith_Quench`P`, Wood_Chop_Enter`P`, Wood_Chop_Exit`P`, Wood_Chop`LP`, Wood_Place_Log |
| social | 50 | Market_Browse`LP`, Mocap_Comfort_A, Mocap_Comfort_B, Mocap_Converse_A`L`, Mocap_Converse_B`L`, Mocap_Cry, Mocap_Direct_Wave, Mocap_Directions, Mocap_Handshake_A, Mocap_Handshake_B, Mocap_Happy, Mocap_Laugh, Mocap_Quarrel_A`L`, Mocap_Quarrel_B`L`, Mocap_Sad, Mocap_Teach, Mocap_Wave_Hello, Music_Flute`LP`, Music_Lute_Sit`LP`, Music_Lute`LP`, Social_Argue_A`L`, Social_Argue_B`L`, Social_Bow, Social_Handshake_A, Social_Handshake_B, Social_Hug_A, Social_Hug_B, Social_Laugh, Social_Laugh_Slap, Social_Mourn_Kneel_Enter, Social_Mourn_Kneel_Exit, Social_Mourn_Kneel`L`, Social_Mourn_Stand`L`, Social_Nod, Social_Point_Directions, Social_Shake_Head, Social_Shrug, Social_Wave_Far, Social_Wave_Greet, Talk_Casual`L`, Talk_Emphatic`L`, Talk_Explain`L`, Talk_Gossip`L`, Talk_Listen_Hips`L`, Talk_Listen_Nod`L`, Tavern_Cheer`LP`, Tavern_Drink`P`, Tavern_Lean_Bar`LP`, Tavern_Sit_Drink`LP`, Tavern_Toast`P` |
| ambient | 21 | Ambient_Check_Sky, Ambient_Glance_L, Ambient_Glance_R, Ambient_Look_Around, Ambient_Rain_Hunch_Upper`LU`, Ambient_Rub_Arms, Ambient_Scratch_Head, Ambient_Shade_Eyes, Ambient_Shift_Weight, Ambient_Stretch_Morning, Ambient_Wipe_Brow, Ambient_Yawn, Eat_Bowl_Sit`LP`, Eat_Bread_Stand`LP`, Mocap_Cold, Mocap_Look_Around, Mocap_Shift_Weight`L`, Mocap_Stretch_Yawn, Read_Sit`LP`, Read_Stand`LP`, Write_Desk`LP` |
| rest | 14 | Mocap_Sit_Stool_Enter, Mocap_Sit_Stool_Exit, Mocap_Sit_Stool_Idle`L`, Rest_Doze_Bench`L`, Rest_Sit_Bench_Enter, Rest_Sit_Bench_Exit, Rest_Sit_Bench`L`, Rest_Sit_Chair`L`, Rest_Sit_Ground_Enter, Rest_Sit_Ground_Exit, Rest_Sit_Ground`L`, Rest_Sleep_Ground_Enter, Rest_Sleep_Ground_Exit, Rest_Sleep_Ground`L` |
| walk | 12 | Guard_Patrol_Walk`LP`, Walk_Brisk`L`, Walk_Cane`LP`, Walk_Careful`L`, Walk_Drunk`L`, Walk_Elder`L`, Walk_Happy`L`, Walk_Limp`L`, Walk_March`L`, Walk_Proud`L`, Walk_Sad`L`, Walk_Tired`L` |
| carry | 10 | Carry_Basket_Upper`LUP`, Carry_Bucket_Upper`LUP`, Carry_Crate_Upper`LUP`, Carry_Pick_Up`P`, Carry_Plank_Upper`LUP`, Carry_Put_Down`P`, Carry_Sack_Upper`LUP`, Carry_Sheaf_Upper`LUP`, Carry_Two_Buckets_Upper`LUP`, Cart_Push`L` |
| kid | 9 | Kid_Chase_Chicken`L`, Kid_Clap_Jump, Kid_Hopscotch, Kid_Run_Play`L`, Kid_Skip`L`, Kid_Tag_Touch, Mocap_Hopscotch, Mocap_Skip`L`, Mocap_Tag_Bluff |
| ritual | 4 | Pray_Kneel_Enter, Pray_Kneel_Exit, Pray_Kneel`L`, Pray_Stand`L` |
| eat | 4 | Mocap_Chug, Mocap_Drink, Mocap_Eat_Soup, Mocap_Eat_Table |
| music | 1 | Mocap_Fiddle`L` |

Per library: Work 49, Town 39, Social 44, Mocap 56 = 188


In-engine checks on the real villager rig, with props and anchors: `frames/gallery_*.jpg`. Blender sheets per library:
`clips/{work,town,social,mocap}/*.jpg`. Known weaknesses, as reported per library:
- fingers use a single curl value (pointing is a fist);
- mouths are not animated;
- some mocap social takes slide up to 0.5 m, because the actors really step (Quarrel_A, Handshake_A);
- stir and scrub are still quite stooped;
- mocap tool clips are pantomime, with no prop contact.

## 5. Performance

**Per NPC, per LOD level** (`living_world_demo.tscn --mode=bench`, Mobile renderer, RTX 4070 laptop, vsync off).
- Method: 40 NPCs forced into one tier, then the same scene without them, as a pair; best of 3 pairs.
- A phone CPU is roughly 5x slower.
- The HIGH and LOW runs used different thresholds but the same per-tier code, and gave the same per-tier costs.

| LOD level | CPU µs / NPC / frame, HIGH (LOW run) | of which behaviour script | of which LOD script | what is left |
|---|---:|---:|---:|---|
| NEAR: full skeleton, every frame, look-at, shadows | **70.6** (67.0) | 2.5 | 1.8 | AnimationMixer ~31 µs + skeleton/skin ~39 µs |
| MID: process_mode pulse every 2–4 frames, speed × k, no modifiers | **35.1** (29.9) | 0.7 | 3.8 | ~50 % of NEAR |
| FAR: VAT twin, node kept (skeleton hidden, 1 Hz clock) | **3.7** (6.9) | 0.5 | 5.2 | ~5–10 % of NEAR |
| data VAT (VatResidents / VatCrowd, no node) | **< 1** (400 instances) | 0 | 0 | GPU only: ~1300 tris near / ~650 far |
| sprites (existing impostors) | ~0 | | | |

**Measured traps that shaped the design** (`tools_qa/living_world/anim_cost_probe.tscn`):
- `AnimationPlayer.advance()` in MANUAL mode costs ~320 µs per call on this rig, against ~24 µs for the engine's own
  processing. Manual stepping at 1/3 rate is therefore ~4x slower than full rate, and villager.gd's current 12 Hz
  "LOD" makes distant villagers ~2.5x MORE expensive (P13a §7).
- Toggling `active` or `callback_mode_process` per frame never processes at all.
- Toggling `process_mode` works and cuts the cost (see the MID row).
- A skeleton that owns SkeletonModifier3Ds re-poses every frame even when they are inactive, so every tier below
  NEAR sets `modifier_callback_mode_process = MANUAL`.

**Scenes:**
| scene | people | tier | result |
|---|---:|---|---|
| Demo showcase (`frames/showcase_sheet*.jpg`) | 271 (47 skeletal actors, 104 data-VAT, 120 sprites) | HIGH | 60 fps (vsync), main-thread CPU 9.9 ms; anim-LOD 0.14–0.3 ms, behaviour 0.9–1.7 ms |
| Stress (`stress_271_people_*.jpg`) | 271, all actors in VAT range | HIGH / LOW | 60 fps (vsync), CPU 10.3 / 7.2 ms; anim-LOD 0.2 ms, behaviour 0.5 ms |
| Real game, village bench, P13b diff applied (`before_after_village_*.jpg`) | 12 full + **140 VAT** (before: 12 full + 32 sprites, close residents hidden) | HIGH | before 77–87 fps, after 64–76 fps; +210k tris, GPU +0.1–0.7 ms, living-world scripts 0.4–0.7 ms/frame |
| Real game, same bench | 12 full + up to 40 VAT | LOW | before 99–119 fps, after 104–109 fps (within noise) |

Caveat: the PC was shared with other agents' Godot captures during most of these runs, so wall-clock fps is noisy
(±15 %). The paired per-NPC CPU numbers are the reliable ones.

Budget for 40+ visible villagers in a town:
- HIGH (8 NEAR + 30 MID + 100 VAT): about 0.56 + 1.05 + ~0.1 = **~1.7 ms PC CPU**, about 8–9 ms on a mid-range phone. This
  fits 60 fps, with the rest of the frame at the documented ~7 ms PC.
- LOW (3 NEAR + 10 MID + 40 VAT): **~0.6 ms PC**, about 3 ms phone. This fits 30 fps easily.
- VAT textures: 30 MB on HIGH (9 looks) and ~12 MB on LOW (4 looks). The far mesh reuses the same textures.

Open perf items are in the backlog (STATUS_LOCAL): a lighter far VAT (~650 tris) for LOW, finger-free MID clips
(-45 % of the mixer work), and GPU-side instance culling per settlement MultiMesh.

## 6. How to rebuild

```bash
# authored clips (Blender 5.2): work / town / social libraries
cd kingdom/tools/anim/life
blender -b -P author_life.py -- ../../../assets/incoming/animations/life/UAL_Life_Work.glb life_clips_farm,life_clips_craft,life_clips_chores
blender -b -P author_life.py -- ../../../assets/incoming/animations/life/UAL_Life_Town.glb life_clips_market,life_clips_tavern,life_clips_rest
blender -b -P author_life.py -- ../../../assets/incoming/animations/life/UAL_Life_Social.glb life_clips_social,life_clips_kids,life_clips_ambient
py ../glb_reduce_anim.py <glb> --rot-deg 0.25 --pos-m 0.001
# CMU mocap
bash fetch_life_cmu.sh; blender -b --python ../retarget_bvh.py -- cfg_life_cmu.json; py make_life_cmu_sidecar.py
# previews with props + anchors (Blender) and in engine
blender -b -P render_life_preview.py -- <glb> <out> "ClipA,ClipB"
Godot --path kingdom res://tools_qa/living_world/clip_gallery.tscn --write-movie g.avi --fixed-fps 30 --quit-after 90 -- --clips=A,B,C
# props
blender -b -P kingdom/tools/blender/make_life_props.py -- [names] [--sheet]
# VAT bakes (windowed)
Godot --path kingdom res://tools_qa/living_world/vat_bake.tscn [-- --looks=a,b]
py kingdom/tools/anim/check_unique_clips.py kingdom/assets/incoming/animations/life
```
