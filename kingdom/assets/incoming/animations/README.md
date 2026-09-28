# Animation libraries (UAL skeleton): souls-like combat, magic, martial arts, mocap

Two clip libraries retargeted onto the **Quaternius UAL 65-bone skeleton**. Every humanoid
in the game uses it (player, soldiers, villagers, G6/CDmir NPCs; see
`../characters/README.md`), so these clips play on all of them with no BoneMap. Both files
are in `Assets.UAL_FILES` (`scripts/world/assets.gd`), so `Assets._ual_for` adds them to
every humanoid's AnimationPlayer by name (`_Loop` clips import as looping).

| folder | file | clips | length | size | licence |
|---|---|---:|---:|---:|---|
| `souls_cat/` | `UAL_Souls_Cat.glb` | 43 | 54 s | 1.3 MB | Unlicense (Cat Prisbrey) |
| `cmu_mocap/` | `UAL_CMU_Mocap.glb` | 23 | 255 s | 2.0 MB | CMU mocap terms (free for commercial use) |

Each folder has `LICENSE`, `README.md` (the clip list with durations and sources) and
`*.clips.json` (per-clip trim, floor fix, contact lift and travel, used by the verifier).
Contact sheets are in `_previews/`.

## Which clip for which gameplay

| gameplay | clips |
|---|---|
| **Spell casting** | `Magic_Cast_L` / `Magic_Cast_R` (one-hand cast), `Magic_Attack_1` (palm blast), `Magic_Attack_2` (two-hand spell), `Magic_Casting` (channel loop), `Magic_Idle_L` (caster stance loop) |
| **Melee chains (souls-like)** | light: `Souls_Light_Attack_1` → `_2`, finishers `Souls_Light_Special_1/2`; heavy: `Souls_Heavy_Attack_1` → `_2`, `Souls_Heavy_Stab`, `Souls_Heavy_Special`; spear/thrust: `Souls_Thrust_Attack_1` → `_2`, `Souls_Thrust_Special`; stance idles `Souls_Light/Heavy/Thrust/Shield_Idle`; riposte `Souls_Visceral_Attack`; plunge `Souls_Fall_Attack_Start` → `Souls_Fall_Attack` (loop) → `Souls_Fall_Land` |
| **Block / parry** | `Souls_Guard` (loop), `Souls_Guard_Hit`, `Souls_Guard_Hurt` (guard break), **`Parry_Quick`**, `Shield_Bash`, `Karate_Gedan_Barai` / `Karate_Shuto_Uke` (unarmed blocks) |
| **Dodge / move** | `Souls_Roll`, `Souls_Strafe_L` / `_R` (lock-on strafes) |
| **Unarmed / kicks** | `Souls_Fist_Attack`, `Karate_Oi_Zuki` (punch), **`Karate_Mae_Geri`** (front kick), **`Karate_Mawashi_Geri`** (roundhouse), **`Karate_Yoko_Geri`** (side kick); kata `Kata_Heian_Shodan`, `Kata_Bassai`, `Kata_Empi` (training / dojo NPCs) |
| **Meditation / cultivation** | **`Taichi_Idle`** (12.7 s loop, calm and breathing-paced), `Taichi_Form` (40 s flowing form); combine with the existing `Meditate` (seated) |
| **Sword training NPCs** | `Swordplay_A/B/C` (long mocap practice sequences) |
| **Chores / villagers** | `Chore_Sweep` (loop), `Chore_Pick_Up_Box`, `Chore_Stool_Sit_Stand`, plus the existing `Farm_*`, `TreeChopping`, `Walk_Carry` |
| **Rest / sleep / KO** | `Lie_Down` → `Lie_Down_Idle` (loop) → `Lie_Down_Get_Up`; `Stand_From_Floor` (get up from prone, e.g. after a knockdown) |
| **Interaction** | `Open_Door`, `Open_Gate`, `Open_Chest`, `Door_Locked`, `Lever_Pull_Floor`, `Lever_Pull_Wall`, `Drink_Potion`, `Torch_Idle` (loop) |
| **Swimming** | `Swim_Breaststroke`, `Swim_Freestyle`, `Swim_Backstroke` (loops; body horizontal, see `cmu_mocap/README.md`) |

## Root motion (optional)

The clips are **in place**. The pelvis keeps only its sway around the travel path, and the
travel itself (smoothed hip path, horizontal) is keyed on the `root` bone position track.
`Assets._ual_for` **disables** that track for libraries in this folder, so nothing slides.
To drive a CharacterBody by root motion:
`anim.root_motion_track = NodePath("<skeleton path>:root")`, re-enable the track
(`a.track_set_enabled(i, true)` on a *duplicate* of the Animation, because the library is
cached per skeleton path and shared), and read `anim.get_root_motion_position()` each
frame. Travel per clip (`travel_m` in `*.clips.json`): the karate techniques step 0.7–0.9 m
and `Chore_Sweep` walks 1 m per cycle. Most Souls clips move ≤ 0.3 m because the template
moves the body in code.

## Pipeline (re-runnable)

```bash
bash tools/anim/fetch_sources.sh                  # raw sources -> $ANIM_SRC (not committed)
pip install bpy==5.0.1 numpy                      # python 3.11 bpy wheel (or Blender 5.x)
ANIM_SRC=... python tools/anim/retarget_clips_to_ual.py tools/anim/cfg_souls_cat.json
ANIM_SRC=... python tools/anim/retarget_clips_to_ual.py tools/anim/cfg_cmu.json
python tools/anim/glb_reduce_anim.py assets/incoming/animations/souls_cat/UAL_Souls_Cat.glb
python tools/anim/glb_reduce_anim.py assets/incoming/animations/cmu_mocap/UAL_CMU_Mocap.glb
godot --headless --path kingdom --import
godot --headless --path kingdom -s tools/anim/verify_clips.gd                 # metrics
xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver vulkan --path kingdom \
      -s tools/anim/verify_clips.gd -- --render                              # contact sheets
```

`retarget_clips_to_ual.py` uses the same method as `../characters/_tools/retarget_to_ual.py`:
direction-matched rest, world-space rotation deltas, parents first, so the rest
orientations are exactly UAL's. It adds the following:
- BVH input and rigged `.blend` input with the control-rig constraints kept live.
- Trims and auto-trim.
- Smoothing, then resampling to 30 fps.
- In-place clips with the travel moved to `root`.
- Floor fix and contact lift.
- Loop-point search and crossfade.
- Finger poses sampled from UAL clips.
- Scale from leg length (the BVH hips sit at z = 0).

With `check_directions: true` it prints the bone-direction error against the source; it
measures **0.0–0.1°** on the Souls clips. The Blender glTF exporter bakes every channel,
so `glb_reduce_anim.py` then cuts the keys by about 94 % (22 MB → 2 MB).

## Verification (Godot 4.6.2, `Assets.character("Player", 1.8, [])`, 30 samples per clip)

- All 66 clips resolve by name. Loop flags are correct. No NaN transforms and no exploding
  bones (max joint distance from the hips is 1.21 m).
- Karate, tai chi, swordplay, chores, lie-down and swim clips: no joint centre under the
  floor.
- Remaining flags, all small and caused by proportions on the MakeHuman player rather
  than by the retarget (on UAL proportions they measure ≥ -0.001 m):
  - A toe (ball joint) dips 4–6 cm on push-off in `Magic_Cast_L/R`, `Souls_Strafe_L/R`,
    `Souls_Thrust_Special`, `Souls_Fall_Attack_Start` and `Kata_Empi`.
  - Fingers go 7–10 cm into the floor in `Souls_Roll` and `Stand_From_Floor`.
  - Runtime foot IK would remove the toe dips.
- Knee or hip bends of 153–158° in `Lie_Down`, `Lie_Down_Get_Up` and `Stand_From_Floor`
  are real deep kneels, not flips (visually checked in `_previews/anim_problems.png`).

## Looked at and not used

| candidate | why |
|---|---|
| CMU 111_12 "Lay down" | knee marker flip (shin 21 cm through the floor); replaced by 113_08 |
| Cat template actions named `mixamo.com` | none exist; nothing Mixamo-derived was taken |
| Cat template bow / crossbow / ladder / death / hurt clips | we already have CC0 equivalents (Mesh2Motion, G6, UAL) |
