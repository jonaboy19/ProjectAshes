# Combat animation audit, frame by frame (2026-09-30)

This is the combat animation director's pass for the local session. It covers every weapon action in the real game (`main.tscn`) and 66 attack clips from the libraries, all scored against animation principles at 30 fps.

It follows `FEEL_AUDIT.md` (movement) and uses the same capture discipline:
- Godot Movie Maker at a fixed 30 fps.
- Mobile renderer, HIGH tier.
- Every sheet read frame by frame.

## Instruments (new; use them for every future combat clip)

| tool | what it proves |
|---|---|
| `kingdom/tools_qa/combat_audit/combat_studio.tscn` | Plays any clip on the **real player rig with the game's sword and shield**. It renders FRONT, SIDE and TOP views every frame, with the blade-tip trace, hip and shoulder lines, and a tip-speed graph. It measures per frame:<ul><li>fast frames</li><li>kinetic-chain order (hips → shoulders → arm → hand → tip)</li><li>edge alignment (`flat_ratio`)</li><li>arc ratio</li><li>follow-through</li><li>step-in</li><li>foot slide</li><li>blade-through-body</li><li>**`target_contact`**: the frames the blade crosses an enemy standing at the game's 1.3 m lunge standoff</li></ul>Useful flags:<ul><li>`--layer=upper` reproduces CharacterAnimator's upper-body layer.</li><li>`--rootmotion` simulates a capsule lunge matched to the root.</li><li>`--extra=<abs.glb>` loads work-in-progress clips without importing.</li></ul> |
| `.../render_sheets.sh` | Studio → 30 fps contact sheets (every frame) + `metrics_*.json`. `--pair=<VictimClip> [--pair_dist=m]` renders paired clips (finishers) with the victim facing the attacker on the same frame clock. |
| `.../combat_capture.tscn` | 12 deterministic in-game combat scenarios through the real input path. `telemetry.csv` logs per frame: blade tip position and speed, current clip, swing timers, `Engine.time_scale` (hit-stop), camera FOV, and the nearest enemy's state, wind-up and clip. |
| `.../analyse_capture.py` | Per swing: the tip-speed curve vs the hit-stop frame. Per enemy wind-up: the frames to player damage. |
| `.../metrics_table.py` | Scores metrics against the principles and outputs a markdown table: `docs/anim/combat/library_metrics.md`, `authored_metrics.md`. |
| `kingdom/tools/anim/combat/polish_combat.py` | Blender retime/polish of existing clips:<ul><li>time remap with moving holds</li><li>strike + `_Rec` concatenation</li><li>kinetic-chain overlap</li><li>overshoot</li><li>foot-locked hip twist (analytic leg IK)</li><li>hand roll / **auto edge alignment**</li></ul> |
| `kingdom/tools/anim/combat/author_combat.py` + `combat_common.py` | IK key-pose authoring (from the casting framework), plus:<ul><li>`blade_o(dir, flat_normal)`: points the game's sword exactly, with the edge leading</li><li>root travel</li><li>the shared `ready_pose()`</li></ul> |

Blade probe (`combat_studio --probe`): at rest the blade points straight up and the flat faces forward. This holds for the sword, the 2H sword and the spear.

## Scorecard (1 = broken … 5 = AAA)

Scores are before → after.
- "After" for the combo is the in-game capture with the new clips and the trail (`game_after/`).
- Rows marked (clip) are authored and verified in the studio, but not wired into gameplay yet (patches).

| Action | Anticipation | Body mechanics | Timing | Feet | Weapon / edge | Contact on target | Secondary | Hit feedback | Trail/smear | Camera | Overall |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1H light combo (4 hits) | **1 → 4** | 2 → 4 | 2 → 4 | 2 → 2 (P9) | 3 → 4 | **1 → 5** | 2 → 3 | 3 → 4 | **1 → 4** | 3 → 3 (P12) | 1.9 → 3.9 |
| Running attack | 1 → 1 (clip, P9) | 2 | 2 | 2 | 3 | 1 | 2 | 3 | 1 → 4 | 3 | 2.0 |
| Heavy charged | – (did not exist) → 4 (clip) | 4 | 4 | 3 | 5 (flat 0.04) | 5 | 3 | – | 4 | – | new |
| Parry → riposte | 2 → 4 (clip) | 2 → 4 | 2 → 4 | 3 | 3 | 1 → 5 | 2 | 3 | – | 3 → (P12) | 2.3 → 4 (clips) |
| Shield bash | – → 4 (clip) | 4 | 4 | 3 | – | – | 3 | – | – | – | new |
| Finishers ×3 (paired) | – → 3–4 (clip) | 4 | 4 | 3 | 4–5 | 5 | 3 | – | 4 | – | new |
| Two-hand overhead | 2 (G6/Kay) → 5 (clip) | 4 | 4 | 3 | 1 → 5 | 5 | 3 | – | 4 | – | new |
| Spear thrust combo | 2 (Souls) → 4 (clip) | 3 | 4 | 2 (rear foot slide) | – | 5 | 3 | – | – | – | new |
| Bow draw/hold/loose + aim | 1 → 4 (clip) | 4 | 4 | 4 | – | – | 3 | – | – | – | new |
| Block / guard hit | 3 | 3 | 3 | 4 | 3 | – | 2 | 3 | – | 3 | 3.0 (P1 still open) |
| Dodge roll | 3 | 3 | 4 | 3 | – | – | 3 | – | – | 4 | 3.3 |
| Hit reactions (player/soldier) | – | **1 → 4** (clip) | 2 → 4 | 3 → 4 | – | – | 2 → 3 | 1 → 4 (P10) | – | 3 | 1.8 → 3.9 (clips) |
| Stagger / guard break | – | 2 → 4 (clip) | 2 → 4 | 3 → 4 | – | – | 3 | 2 | – | 3 | 2.4 → 3.8 (clips) |
| Deaths | 3 (Death01) → 4 (weapon-specific clips) | 3 → 4 | 3 → 4 | 3 | 3 → 4 | – | 3 | – | – | – | 3.0 → 3.8 |
| Enemy attacks (goblin/orc/troll) | 3 (readable but floaty) | 3 | 2 (one global rate) | 4 | – | – | 3 | 2 | – | 3 | 2.8 (P11) |
| Wolf bite | 3 | 3 | 3 | 3 | – | – | 3 | 2 | – | 3 | 2.9 |

## Issues, ranked by impact

Legend for evidence:
- `gb/` = `docs/anim/combat/game_before/`
- `ga/` = `docs/anim/combat/game_after/`
- `b/` = `docs/anim/combat/before/` (studio)
- `a/` = `docs/anim/combat/after/`
- `cmp/` = `docs/anim/combat/compare/`
- `#n` = sheet tile. 30 fps sheets: tile = frame. 15 fps sheets: tile n = frame 2n.

| Rank | ID | Issue | Evidence | Cause | Status |
|---|---|---|---|---|---|
| 1 | C1 | **The blade never goes through the enemy on 3 of the 4 combo hits.** Measured against a target at the 1.3 m lunge standoff, in the in-game upper-body layer at the game rates: <ul><li>Regular_A@1.7 crosses it on f7–8, 3 frames *after* the hit fires.</li><li>Regular_B@1.7 crosses it only on f0.</li><li>Regular_C@2.2 never crosses it.</li><li>Sword_Attack@1.4 never crosses it.</li></ul>In game, hit 3's sparks fire while the blade is behind the player. | `cmp/ingame_c02_hits2_3_before_after.jpg` top half #37–#39 (blade vertical behind the player at the hit-stop), then #42 (the blade reaches the orc). `cmp/studio_hit3_before_after.jpg` top (TOP view: the blade ends to the right and behind). | The UAL swings turn through the **pelvis**, and the upper-body layer drops the pelvis. Regular_C's 360° spin-leap becomes an arm whirl to the side. | **Fixed** (applied): the authored `Sword_Light_1..4` + `_Upper` variants hit the target on their contact frame (studio f9/f7/f9/f16). In game the hit-stop lands on the blade's peak frame: L1 f+8, L2 f+6, L3 f+8 (`ga/telemetry.csv`, `cmp/ingame_c02_*`). |
| 2 | C2 | **No anticipation and no follow-through.** A and B are strike-only clips (0.43 / 0.53 s) played at 1.7× without their `_Rec` recoveries, so each is 9–11 frames. <ul><li>The 0.08 s fade-in hides the first frames, so the wind-up is 1 frame.</li><li>The "recovery" is a 0.18 s cross-fade to idle.</li></ul> | `b/Sword_Regular_A_upper_x1.70` #0–#8. `cmp/studio_hit1_before_after.jpg` top. | Clip choice | **Fixed**. L1–L4 have:<ul><li>a 5–13 f coil</li><li>a 1–2 f moving hold</li><li>hips first</li><li>3–5 fast frames</li><li>overshoot</li><li>a 6–8 f follow-through</li><li>a recovery</li></ul>Each hit's follow-through pose is the next hit's frame 0, so chains never detour through idle. `a/Sword_Light_1_Upper_upper/`. |
| 3 | C3 | **Feet slide on every swing.** The 0.375 m capsule lunge moves idle or locomotion legs. | `gb/c02_combo_on_orc_30fps_sheet_001.jpg` #1–#8, `sheet_002` #44–#47; still in `ga/…sheet_001` #1–#3 | Code (upper-only layering + a fixed lunge) | **Patch P9**: full-body clips when standing, and a lunge that equals the clip's authored step (`step_in_m`, `step_frames`), started on the step frame. |
| 4 | C4 | **The slash VFX is not the blade.** It is a fixed crescent at 1.15 m, spawned 0.07 s before a guessed hit. <ul><li>Hit 1: the arc sits above the orc's head while the blade is low.</li><li>Hit 2: the arc appears 2 frames before the blade comes down.</li></ul> | `gb/c02_combo_on_orc_30fps_sheet_001.jpg` #3–#9, #17–#19 | Design | **Fixed**:<ul><li>`WeaponTrail` ribbon from the blade base to the tip.</li><li>Driven by the marker `trail` window and a 3 m/s tip gate.</li><li>Follows the real arc.</li></ul>See `ga/c02_…sheet_001` #7–#11 and `docs/anim/combat/trail/`. |
| 5 | C5 | **Hit reactions carry no weight and no direction.** Every hit on the player or a soldier plays `Hit_Chest`: <ul><li>0.33 s at 1.5× = 7 frames</li><li>upper body only</li><li>3 cm of chest travel</li></ul>An orc slam reads as a twitch. | `gb/c07_orc_attacks_15fps_sheet_001.jpg` #11–#13. `cmp/hit_reaction_before_after.jpg` | Clip + code | **Clips added**: `Hit_{Light,Heavy}_{Front,Back,Left,Right}` and `Stagger_{Back,Forward}`. **Patch P10** picks them by side and weight. |
| 6 | C6 | **Pop at every combo hand-over.** In telemetry the tip jumps 40–47 m/s on the first frame of hits 2–4, because re-firing the active `upper` OneShot restarts it from the base pose. | `gb/telemetry.csv`, `analyse_capture.py` (swings 5/8/13/16) | Engine behaviour + code | **Mitigated** by the new clips (each starts in the previous follow-through pose; the after telemetry shows no spike above 8 m/s on a swing's first frame). **Patch P9** removes the cause (A/B attack slots). |
| 7 | C7 | **Enemy attacks play the whole clip at one global rate** (`impact / windup`), so anticipation and strike stretch together. <ul><li>Orc: arm-raise over 20 frames, the slam in 1 frame.</li><li>After the slam it sits on the ground for 0.7 s.</li></ul> | `gb/c07_orc_attacks_15fps_sheet_001.jpg` #1–#21; `c08`, `c06` | Code | **Patch P11**: hold, then snap. The contact time is unchanged, plus a 2-frame telegraph flash. |
| 8 | C8 | **Hit-stop is global and one-size.** `Engine.time_scale` 0.05 for 0.05–0.12 s freezes the world. There is no FOV punch, and the sparks sit at the enemy centre, not at the blade. | telemetry (hit-stop 4 frames per hit, c02/c10) | Code | **Patch P12**: tiers, local freezes for light hits, FOV punch, sparks at `WeaponTrail.tip_position()`. |
| 9 | C9 | **Parry is untestable in game, and the riposte is just a normal swing.** The block faces the camera heading, so the orc's blow lands (FEEL_AUDIT F6). <ul><li>The parry clip is `Sword_Block` upper at 1.8×.</li><li>The riposte is combo hit 1 with 1.5× damage.</li></ul> | `gb/c04_parry_riposte_orc_15fps_sheet_001.jpg` #10–#13 (hit taken while guarding sideways) | Code (P1 open) + clips | **Clips added**: `Sword_Parry` (deflect f4, `parry_active` 2–6) and `Sword_Riposte` (step-in thrust f9). Still needs **P1** plus wiring. |
| 10 | C10 | **Bandit/soldier hits land at a fixed 0.3 s,** about 0.1 s after the Chop blade passes at 1.4×. There is no hit-stop and no sparks on the player. | `soldier.gd _attack`; `gb/c10_bandit_duel_15fps_*` | Code | **P9**: `play_attack("Sword_Light_n")` + `CombatMarkers.time_s(clip, "hit")` |
| 11 | C11 | **Most library attacks are unusable with the game's sword grip.** Of 66 library attack clips: <ul><li>40 flat-slap (`flat_ratio` > 0.6: the flat, not the edge, leads).</li><li>Only 18 put the blade through a target in front.</li></ul>This covers the KayKit `Weapon_*`, Souls, G6 and CMU swordplay sets. | `docs/anim/combat/library_metrics.md` | Source grips ≠ `Assets._attach` grip | Documented. The polish tool's `auto_edge` fixes roll (e.g. hit 1: 0.55 → 0.29), but aim needs authoring. The new set is authored against the real grip and target (16/18 on target, 2 flat = thrusts). |
| 12 | C12 | **Missing clips**: directional light combo, heavy charged, running attack, parry → riposte, finishers, shield bash, 2H overhead, spear combo, bow draw/hold/release with aim, directional reactions, stagger, weapon-specific deaths | – | – | **Added**: 44 clips in `UAL_Combat.glb` (table below) |
| 13 | C13 | Deaths: one generic `Death01` (2.4 s, 7 floaty fast frames); the weapon stays glued to the hand | `library_metrics.md` | Clip | **Clips**: `Death_1H_Front/Back`, `Death_2H_Knees` and `Death_Bow_Side`, each with the knees before the hips before the chest, a landing bounce, and the sword laid beside the body (it stays attached; see backlog). |
| 14 | C14 | Wolf bites have no body lunge in the bite; the player reaction is the same `Hit_Chest` | `gb/c09_wolf_bite_15fps_sheet_001.jpg` | Clip (Meshy) + code | P10 (player side). The wolf clip is untouched (Meshy rig). |

## What was changed

### Applied, small and documented

| file | change | why |
|---|---|---|
| `kingdom/scripts/world/assets.gd` | `UAL_FILES` += `animations/combat/UAL_Combat.glb` (the root track is auto-disabled like the rest of `animations/`) | new clips |
| `kingdom/scripts/actors/player.gd` | `COMBO` → `Sword_Light_1..4_Upper` at 1.2×.<ul><li>hit = contact frame / 30 / speed: 0.25 / 0.19 / 0.25 / 0.44 s</li><li>lock = follow-through end</li></ul>Also:<ul><li>`_trail = WeaponTrail.attach(body)`</li><li>`_trail.swing()` replaces the fixed slash crescent in third person</li><li>the trail stops on a dodge cancel</li></ul> | C1, C2, C4 |
| `kingdom/scripts/vfx/weapon_trail.gd` (new) | pooled blade ribbon | C4 |
| `kingdom/scripts/actors/combat_markers.gd` (new) | markers sidecar loader | gameplay timing for Codex |
| `kingdom/assets/incoming/animations/combat/UAL_Combat.glb` (new, 1.3 MB) + `combat_markers.json` (110 clips) | clips + markers | C12 |

### Patches for Codex (`docs/anim/patches/`)

- **P9**: attack layering. Full body when standing, `_Upper` when moving. A/B slots remove the hand-over pop. The lunge equals the authored step. `soldier.gd` uses the markers.
- **P10**: directional light/heavy reactions + stagger on guard break, victim local hit-stop.
- **P11**: enemy hold-then-snap wind-up + telegraph flash + creature local hit-stop.
- **P12**: hit-stop tiers, FOV punch, sparks at the blade, contact-frame order.
- Still open from FEEL_AUDIT: **P1** (block faces the threat). The parry depends on it.

## New clip library (`UAL_Combat.glb`, 44 clips, 30 fps, UAL skeleton, CC0/own work)

Frames are at rate 1.0. `hit` = the frame the blade crosses a target 1.3 m ahead (studio-verified). Full events for every clip are in `combat_markers.json`.

| clip | len | hit | step/root | use |
|---|---:|---:|---:|---|
| `Sword_Light_1` / `_Upper` | 1.00 s | 9 | 0.22 m | light 1: forehand diagonal R→L |
| `Sword_Light_2` / `_Upper` | 1.00 s | 8 (upper 7) | 0.24 m | light 2: backhand rising L→R |
| `Sword_Light_3` / `_Upper` | 1.07 s | 9 | 0.26 m | light 3: horizontal R→L, chest height |
| `Sword_Light_4` / `_Upper` | 1.37 s | 16 | 0.40 m | light 4: lunging thrust finisher |
| `Sword_Heavy_Charge_Start` → `Sword_Heavy_Charge_Hold` (loop) → `Sword_Heavy_Release` | 0.33 / 1.0 / 1.2 s | 5 | 0.45 m | charged heavy |
| `Sword_Run_Attack` | 1.0 s | 8 | 1.6 m (skid) | sprint attack |
| `Sword_Parry` → `Sword_Riposte` | 0.6 / 1.1 s | 4 / 9 | 0 / 0.35 m | parry (active 2–6) → riposte |
| `Shield_Bash_Step` | 0.9 s | 10 | 0.30 m | shield bash |
| `Finisher_Stab_Through` / `_Victim` | 2.0 s | 14 | 0.22 m | execution; victim 1.35 m ahead, facing (`victim_dist_m`) |
| `Finisher_Overhead_Cleave` / `_Victim` | 1.8 s | 20 | 0.35 m | execution on a kneeling victim, 1.2 m |
| `Finisher_Spin_Slash` / `_Victim` | 1.67 s | 16 | 0.25 m | spinning execution, 1.35 m |
| `TwoHand_Overhead` | 1.5 s | 17 | 0.35 m | 2H overhead chop |
| `Spear_Thrust_1/2/3` | 0.8 / 0.93 / 1.33 s | 7 / 8 / 12 | 0.25 / 0.35 / 0.5 m | spear combo |
| `Bow_Draw` → `Bow_Hold` (loop) → `Bow_Loose`; `Bow_Aim_Up/Down` | 0.53 / 1.2 / 0.6 s | loose f1 | – | bow; Blend3 Hold/Up/Down by pitch, upper-body filter |
| `Hit_{Light,Heavy}_{Front,Back,Left,Right}` | 0.5 / 0.87 s | contact f0 | 0.045 / 0.14 m | directional reactions |
| `Stagger_Back/Forward` | 1.33 s | f0 | 0.63 m | guard break / heavy blow |
| `Death_1H_Front/Back`, `Death_2H_Knees`, `Death_Bow_Side` | 1.5–2.2 s | down f24–50 | ≤ 0.56 m | weapon-specific deaths (terminal) |

Sheets: `docs/anim/combat/after/<clip>/`. Metrics: `docs/anim/combat/authored_metrics.md`.

## Weapon trail: performance (`trail_bench.tscn`)

Measured on the PC, quiet machine (no other Godot or Blender running), 300 frames per case, fixed 60 fps.

| tier | active trails | ms per active trail-frame | all trails, ms/frame avg (p99) |
|---|---:|---:|---:|
| HIGH | 1 / 4 / 8 | 0.043 / 0.025 / 0.020 | 0.018 / 0.038 / 0.062 (0.28) |
| LOW | 1 / 4 / 8 (cap 2 used) | 0.032 / 0.015 / 0.010 | 0.012 / 0.020 / 0.024 (0.13) |

Budget check:
- One draw call per active trail.
- Tier caps: LOW 2, MEDIUM 4, HIGH 8.
- No allocation after warm-up, and zero cost when idle (process off).
- Phone ≈ ×5: 0.3 ms for 8 trails on HIGH, 0.06 ms for the player alone on LOW.

The frame-time difference with vs without trails is within noise (6.4 vs 6.4 ms).
Raw data: `docs/anim/combat/trail/bench.json` and `bench_rerun.json`.

## Import / guard checks

- `check_unique_clips.py` on `animations`, `animations_free` and `animations_free2`: **0 problems**. `Shield_Bash` → `Shield_Bash_Step` and `Bow_Release` → `Bow_Loose` were renamed to avoid the Souls/Mesh2Motion clips shadowing them.
- The Godot import of `UAL_Combat.glb` is valid, and all 44 clips resolve through `Assets.UAL_FILES` on the player rig.
- In-game run (`game_after`): no script errors. The error count in the log is unchanged from before (pre-existing Movie Maker rendering noise).

## Known weak spots (backlog)

1. **Studio grading.** `metrics_table.py` grades reactions and deaths as if they were strikes; ignore its "issues" column for them.
2. **L4 finisher.** The blade lift-over (f0–6) is slightly faster than the thrust itself.
   - Paired review (`after/pairs/`) found the stab's wind-up kept the blade on the victim. It now draws back to the hip.
   - At 1.2 m the ready guard touched the victim, so the placement is per finisher: stab 1.35, cleave 1.2, spin 1.35 (`victim_dist_m` in the markers).
3. **Feet** (authored clips). The spear rear foot slides 25–42 cm. `Finisher_Spin_Slash` pivots a full turn on one foot, so the studio reads 1.1 m of "slide".
4. **Deaths drop nothing.** The sword stays attached; add a drop at the `down` event (detach the BoneAttachment → RigidBody, 2 s).
5. **Bow.** It is a procedural test prop; check the grip on the real bow model when one exists.
6. **Enemy clips** (Meshy wolf/orc/goblin/troll) were measured through the code path only (P11). They were not re-authored.
7. **Running attack is not wired** (P9). The legs keep running while `Sword_Light_1_Upper` plays: acceptable, but `Sword_Run_Attack` is better.
8. **Cloth and hair secondary motion.** Only on the player (ProceduralRig springs); not re-audited here.
9. **Camera.** FOV punch and directional shake are patch-only (P12).

## Reproduce

```bash
# studio sheets (every frame, FRONT|SIDE|TOP + metrics); in-game layer + matched lunge:
bash kingdom/tools_qa/combat_audit/render_sheets.sh docs/anim/combat/after "Sword_Light_1_Upper" --layer=upper --rootmotion
# in-game capture (12 scenarios, ~2 min):
Godot --path kingdom --rendering-method mobile --windowed --resolution 1280x720 --write-movie <dir>/combat.avi --fixed-fps 30 \
  res://tools_qa/combat_audit/combat_capture.tscn -- --adult --skipintro --out=<dir> [--only=c01,c02]
python kingdom/tools_qa/combat_audit/analyse_capture.py <dir>
# rebuild the library + markers:
cd kingdom/tools/anim/combat && blender -b -P author_combat.py -- <out.glb> combat_clips_light,combat_clips_reactions,combat_clips_finishers,combat_clips_weapons,combat_clips_bow_deaths
python ../glb_reduce_anim.py <out.glb>
python build_markers.py <markers.json> --metrics <library metrics.json> <authored metrics.json> --authored <out.glb>.clips.json --aliases
```
