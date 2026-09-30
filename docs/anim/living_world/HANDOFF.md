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

(counts per category and the full list: section 7)

## 5. Performance

(filled from the bench below)

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
