# Horses and riding: handoff (P14)

Local session, 2026-09-30. Everything is standalone and nothing in the game calls it yet. `mount_controller.gd`, `player.gd`,
`critter.gd` and `character_animator.gd` are untouched. The wiring is in `docs/anim/patches/P14a–P14c`.

- Demo and proof scene: `kingdom/tools_qa/horses/horse_demo.tscn` (modes `gait`, `clip`, `course`, `mount`, `combat`,
  `crowd`, `bench`, `beauty`; see the header of `horse_demo.gd`).
- Captures and sheets: `docs/anim/horses/`.

## 1. What exists

| piece | file | what |
|---|---|---|
| Rig build | `tools/anim/horse/horse_build.py` (+ `hb_common.py`, `horse_mesh.py`) | Fits the Rigify horse metarig to the Mesh2Motion body (CC0). Rigify then generates the 454-bone authoring rig, kept in `source/horse_rig.blend`. **Own DEF extraction** (Expy Kit fails on horses) produces `HorseSkeleton`: one root, twist halves merged. Self-test: a posed Rigify rig baked onto it matches every joint within 8 mm. `bake_rigify_action()` retargets any hand-keyed Rigify action. |
| Skeleton | `HorseSkeleton` | 58 deform bones: root, hips, spine_1–3, chest, withers, neck_1–4, head, **jaw**, ears 2×2, belly (jiggle), tail_1–5, **mane 6×2** (forelock + 5 tufts), per fore leg scapula/humerus/forearm/cannon/pastern/hoof, per hind leg thigh/gaskin/cannon/pastern/hoof, rein_grip_L/R. Plus 7 non-deform sockets: `saddle` (seat top, rider anchor), `stirrup_L/R`, `bit`, `tug_L/R` (cart shafts), `cart_hitch`. |
| Model | `assets/generated/horses/horse_riding.glb` | Mesh2Motion body welded into one closed surface, then subdivided and decimated for rounder storybook forms. The chunky hanging tail and mane are modelled procedurally. Heat weights on the body, chain weights on the hair, at most 4 influences. **LOD0 7624 / LOD1 3436 / LOD2 1002 tris**, one material and one draw call each. |
| Coats | `horse_coat_{bay,chestnut,grey,black,dappled,warhorse}.png/.tres` | 1024 px hand-painted look: baked AO, dark topline, light belly, brush noise, points and markings. Swapping the material swaps the coat. |
| Tack | `horse_tack_{saddle,bridle,reins,saddlebags,cart_harness,barding}.glb` + `horse_tack.tres` | Separate skinned attachments on a shared 512 px atlas. `HorseRig.tack = [...]` attaches them and rebinds skins by bone name. The reins run from the bit (head) to rein_grip_L/R, so they stretch to the hands. The barding is the knight's warhorse: red caparison, chanfron and crinet. |
| Cart | `horse_cart.glb` | Two-wheel market cart. Its origin sits 2.05 m behind the horse and the shaft tips land on `tug_L/R`. |
| Horse clips | `Horse_Anims.glb` + `.clips.json` (50 clips) | Section 3. Sidecar per clip: frames, loop, speed_mps, root yaw, stride, footfall phases, duty, stance frame windows, measured hoof slide, hoof events, other events, jump splits. |
| Rider clips | `UAL_Horse_Rider.glb` + `.clips.json` (57 `Horse_Ride_*`) | Section 4. Sidecar: `synced_to`, layer (full/upper), events (hit, release, mount_done …), `hands_on_grips`, `end_ground_point`, and `world_check` (hand, foot and penetration residuals). |
| Gait engine | `tools/anim/horse/horse_gait.py`, `horse_clips{,2,3}.py`, `author_horse.py` | Section 2. Rebuild: `blender -b -P author_horse.py -- <out.glb> [clips]` (about 10 min for all 50), then `glb_reduce_anim.py --rot-deg 0.12 --pos-m 0.0008` and `py -3 rider_tracks.py`. |
| Rider authoring | `tools/anim/horse/rider/` | UAL IK key-pose framework (trav_lib). Reads `source/rider_tracks.json`, the saddle delta D(t) per horse frame. |
| Assets build | `tools/anim/horse/horse_export.py` (+ `horse_coats.py`, `horse_tack.py`, `hx_*.py`) | UVs, coat bakes, LODs, tack, cart and the GLB exports. Idempotent. See `README_ASSETS.md`. |
| HorseRig | `scripts/horses/horse_rig.gd` | The horse node: model, coat, tack, clip library, gait choice with hysteresis, speed matching, phase-kept gait changes, leads and turn loops, actions, idle variety, modes (graze/drink/rest/swim/cart), hoof signal, sockets, saddle delta, LOD ranges per tier. |
| HorseSprings | `scripts/horses/horse_springs.gd` | SpringBoneSimulator3D per tier. LOW: none. MED: tail. HIGH: tail, mane, forelock and belly. |
| RiderSync | `scripts/horses/rider_sync.gd` | Glues a UAL rider to a HorseRig. Moves it rigidly by the saddle delta and phase-locks the synced clip. An AnimationTree with TimeSeek layers blends upper-body actions (bone filter from `spine_01`) and full-body overrides (mount, dismount, fall) on top. `hold_full` keeps a dismount end pose. |
| RiderIK | `scripts/horses/rider_ik.gd` + `rein_follow.gd` | Four `TwoBoneIK3D` modifiers (arms to the rein grips, legs to the stirrups) with per-limb influence and a `calibrate()` for the authored offsets. `ReinFollow`, a SkeletonModifier3D on the horse, moves the rein ends into a free hand's fist. |
| Distant horses | `tools_qa/horses/horse_vat_bake.gd` → `assets/generated/vat/vat_horse_<coat>.res` | VAT bake of LOD2 with 9 clips at 15 fps. The position and normal textures are shared by all coats (2.0 MB total). Runs on the living-world `VatCrowd` and `CrowdAnimLOD` unchanged (P14c). |
| QA | `tools_qa/horses/horse_demo.gd`, `slide_report.py`, `footfall_diagram.py` | Movie Maker captures, foot slide measured in engine, gait diagrams measured in engine. |

## 2. How the gaits are made (no mocap)

There is no commercial-safe horse mocap, so every clip comes from a **motion script** run by the gait engine:
- a root path;
- body offset and rotation;
- spine, neck and head bends;
- a list of **stances** per leg: (land time, lift time, world toe point).

**Legs** are solved analytically:
- **Fore leg:** the scapula swings with the limb angle. A 2-bone IK runs over the humerus and a "virtual" forearm+cannon whose length depends on the carpal flexion, so the knee is locked in stance and folds in swing.
- **Hind leg:** a 2-bone IK over the femur and a virtual tibia+cannon at the hock angle, so the stifle and hock flex together like the reciprocal apparatus. The hock opens in late stance for reach.
- **Pastern and hoof:** bottom-up from the planted toe in stance (the fetlock sinks under load, then breakover about the toe). Top-down in swing, blended at lift-off and touch-down so there are no pops.

**Planted toes are world-fixed**, so hooves cannot slide by construction.

**Body and hair:**
- Where a planted leg cannot reach, a support pass lowers and pitches the body. That correction is smoothed in time, so the saddle never jumps (less than 1 cm second difference per frame).
- Tail and mane are spring chains with gravity, drag in the horse's own airstream, and stiffness toward the FK pose. They are simulated over extra cycles, so loops are seamless. Wiggle 2 and Bone Dynamics were evaluated but not needed: the in-engine SpringBoneSimulator3D adds live reaction on top.

**Footfall patterns** (reference → authored → **measured in Godot**, `docs/anim/horses/footfall_diagram.png`):

| gait | reference | authored (landing phase, duty) | engine: order and duty | engine hoof slide (max per plant) |
|---|---|---|---|---|
| walk | 4-beat lateral LH, LF, RH, RF, 25 % apart | HL 0, FL .25, HR .5, FR .75; duty .60 | LH f36 → LF f44 → RH f53 → RF f61 (8.5 f spacing); 57–69 % | 1.4–2.6 cm |
| trot | 2-beat diagonal, two suspensions | LH+RF 0, RH+LF .5; duty .42 | pairs land on the same frame; 41–49 %; suspension visible | 0.2–2.0 cm |
| canter (L lead) | 3-beat RH, LH+RF, LF, suspension | RH 0, LH .20, RF .24, LF .44; duty .33–.36 | RH f38 → LH f42 / RF f43 → LF f46 → air; 39–45 % | 0.1–0.4 cm |
| gallop (L lead) | 4-beat RH, LH, RF, LF, suspension | RH 0, LH .11, RF .30, LF .41; duty .25 | RH f30 → LH f32 → RF f34 → LF f36 → air; 23–31 % | 0.0–1.4 cm |
| back-up | 2-beat diagonal | diagonal pairs; duty .66 | as authored | ≤ 5.5 cm (the toes scuff at a 2 cm contact threshold) |

Blender-side check of every clip (`hoof_slide_m` in the sidecar): 0 cm in all stance windows except:
- Gallop_Stop hind: 3–4 cm while braking on its haunches;
- Trot and Trot_Turn: 1–2 cm after the support smoothing;
- Turn_InPlace fore: 0.8 cm.

**Head bob:** 2 nods per stride at the walk (down as each fore loads), a quiet head at the trot, 1 nod per stride at the canter and gallop (down in the fore stance, up in the hind stance).

## 3. Horse clips (50) and the gait speed table

Speeds are the clips' root-motion speeds; at `speed_scale = speed / clip speed` the hooves stay planted.

| state | clip(s) | speed m/s | stride | frames @30 | use band (HorseRig) | blend |
|---|---|---:|---:|---:|---|---|
| idle | `Idle` (loop 4 s) + one-shots `Idle_EarFlick`, `Idle_TailSwish`, `Idle_ShiftWeight`, `Idle_Snort`, `Idle_HeadToss` every 5–12 s; `Idle_RestHind` (loop, cocked hind) | 0 | – | 121 | < 0.12 (0.25 leaving walk) | 0.3 |
| walk | `Walk`, `Walk_Turn_L/R` (35°/s, 3° lean) | 1.50 | 1.70 m | 35 | 0.15 – 2.3 | 0.28 |
| trot | `Trot`, `Trot_Turn_L/R` (40°/s, 7°) | 3.60 | 2.64 m | 23 | 2.3 – 4.6 | 0.28 |
| canter | `Canter_L/R`, `Canter_Turn_L/R` (40°/s, 12°, lead = turn side) | 5.80 | 3.48 m | 19 | 4.6 – 8.2 | 0.28 |
| gallop | `Gallop_L/R`, `Gallop_Turn_L/R` (32°/s, 16°) | 11.0 | 5.13 m | 15 | > 8.2 | 0.28 |
| back up | `BackUp` | −0.70 | 0.93 m | 41 | < −0.1 | 0.3 |
| transitions | `Walk_Start` (0→1.5, 1.5 s), `Walk_Stop` (1.5→0, 1.8 s), `Trot_Start` (0→3.6, 1.2 s), `Trot_Stop` (1.6 s), `Canter_Start_L` (0→5.8 strike-off, 1.2 s), `Gallop_Stop` (11→0, 2.0 s, sits on the haunches) | ramps | – | 37–61 | on demand | 0.15 |
| turn in place | `Turn_InPlace_L/R` (90° on the haunches, 1.9 s, root yaw ±90°) | – | – | 58 | idle and yaw rate > 0.6 rad/s | 0.3 |
| cart | `Cart_Pull_Walk`, `Cart_Pull_Trot` (leaning into the collar) | 1.25 / 3.0 | 1.5 / 2.4 | 37 / 25 | mode "cart" | 0.28 |
| grazing | `Graze_Enter` → `Graze` (loop, chewing) → `Graze_Exit` | 0 | – | 49/121/49 | mode "graze" | 0.3 |
| drinking | `Drink_Enter` → `Drink` → `Drink_Exit` | 0 | – | 49/91/49 | mode "drink" | 0.3 |
| swim | `Swim` (root = **water surface**, paddling, tail floating) | 1.1 | 1.32 m | 37 | mode "swim" | 0.3 |
| actions | `Rear` (2.8 s), `Buck` (1.9 s), `Spook_L/R` (shies away from the threat side, 1.2 m sideways, 32°), `Hit_L/R` (0.8 s), `Death` (collapse, 3.4 s, rolls onto its right side), `Jump_Full` (1.9 s over ~1 m, arc in root Z) = `Jump_Takeoff` + `Jump_Air` + `Jump_Land` | – | – | 25–103 | `play_action()` | 0.15 |

Events (30 fps frames, in the sidecar):
- `hoof_FL/FR/HL/HR` footfalls (the `hoof` signal; use them for sounds, dust and camera micro-shake);
- `snort`, `neigh`, `kick`, `startle`, `chew`, `swallow`, `tail_swish`;
- `takeoff`/`land`;
- Death: `knees`, `body_ground`, `roll`.

**Root motion:** the travel (and the yaw of the turn clips, spooks and turns in place, plus the jump arc) is on the `root` bone. HorseRig sets `root_motion_track`, so the model never drifts. Controllers either move the body at the chosen speed (the normal case: `speed_scale` matches the clip) or apply `root_motion_delta()`, for the jump arc and turns in place.

## 4. Rider (57 clips on the UAL skeleton) and the sync contract

**Contract:** every `Horse_Ride_*` clip is authored against the horse at REST, with the rider root at the horse root. In game:
- `rider.global = horse_skeleton.global * saddle_delta` each frame, with `saddle_delta = saddle_pose * saddle_rest⁻¹`;
- the synced clip plays at the **same normalized time** as the horse clip.

The rider therefore moves exactly with the horse, including blends, turns, rears and jumps, and never drifts out of phase.

Inside each clip, world-stable intent (two-point torso, calm head, leaning into the rear) is authored against the smoothed saddle motion and mapped back. Measured by the rider agent on the reduced GLBs with the rider moved by the saddle bone:

| check | result |
|---|---|
| hands to rein grips | ≤ 2.4 mm on synced clips, except Gallop_Stop 8.5 mm and Buck 12 mm |
| feet to stirrups | ≤ 3.2 mm |
| pelvis above the seat | ≥ 8.1 cm |
| thigh/calf into the barrel, riding clips | 1.6–2.9 cm |
| thigh/calf into the barrel, ground clips | 6–10 cm while the leg swings over the croup |

Clips:
- **Synced gaits:**
  - `Horse_Ride_Idle` and `_Idle_LookAround`;
  - `_Walk`;
  - `_Trot`: **posting**, rising 9.2 cm on the FR+HL diagonal (f0–10) and sitting on FL+HR (f11–22);
  - `_Trot_Sit`;
  - `_Canter_L/R`: hips follow the rocking;
  - `_Canter_TwoPoint_L`;
  - `_Gallop_L/R`: **two-point**, 8.5 cm out of the saddle, torso about 32° forward and stabilised, hands on the neck;
  - `_BackUp`.
- **Synced turns:** `_Walk/_Trot/_Canter/_Gallop_Turn_L/R`, `_Turn_InPlace_L/R`.
- **Synced starts and stops:** `_Walk_Start`, `_Walk_Stop`, `_Trot_Stop`, `_Gallop_Stop` (sit deep, lean back).
- **Synced reactions:** `_Rear` (grab the mane), `_Buck`, `_Spook_L/R`, `_Hit_L/R`, `_Jump_Full` and its three splits (folds over the fence), `_Swim`, `_Graze`, `_Drink`, `_Death` (rolls clear, `end_ground_point`), `_FallOff` (on the Buck).
- **Full-body, horse at rest:** `_Mount_L/R` (2.2 s from the stirrup), `_Dismount_L/R`, `_Dismount_Jump`, `_Spur`.
- **Upper layer** (over any gait): `_Rein_Turn_L/R`, `_Stop_Pull`, `_Sword_Idle`, `_Sword_Swing_L/R` (windup 0–10, **hit f14**, follow-through to 21), `_Bow_Draw` → `_Bow_Aim` (loop) → `_Bow_Release` (release f2), `_Hit_React_L/R`.

**IK spec (RiderIK, runtime):**
- **Legs:** `thigh → calf → foot` targets `stirrup_L/R`, with the authored offset from `calibrate()`. Poles are 1 m ahead of the knees and slightly out. Influence 1 when mounted, 0 during mount, dismount and fall.
- **Arms:** `upperarm → lowerarm → hand` targets `rein_grip_L/R`. Poles are behind the elbows and out. Per-hand influence `hands`: set it to 0 for the sword hand and both bow hands, and follow the sidecar `hands_on_grips` for Graze and Drink.
- **ReinFollow** on the horse: `weights = 1 − hands`, so a released rein goes to that fist.
- **Tiers:** LOW runs the feet only.

## 5. Wiring for Codex (patch index)

- **P14a** `P14a_mount_controller_horse_rig.md`:
  - speed constants (walk 1.5, new trot 3.6, canter 5.8, gallop 11, back 0.7) and stick bands;
  - `sync()` → `HorseRig.drive(speed, yaw_rate, delta)`;
  - hoof sounds from the `hoof` signal;
  - swim mode;
  - actions and stops.
- **P14b** `P14b_player_rider_sync.md`:
  - RiderSync and RiderIK on mount;
  - Mount_L/R from the side you stand on;
  - dismount clips, and a jump-off when moving above 3 m/s;
  - mounted sword, bow, rein turns, stop pull, spur, hit react, fall-off;
  - skip the old `ride` stance.
- **P14c** `P14c_critter_horses_and_herds.md`:
  - ambient horses become HorseRigs (coats per kind, graze/drink/rest modes, spook on flee);
  - CrowdAnimLOD + VatCrowd registration for NEAR/MID/FAR;
  - carts.

**Mount state machine:**
```
IDLE_ON_FOOT -(interact)-> MOUNTING (Mount_L/R, stick locked, IK off)
MOUNTING -(mount_done)-> RIDING (IK on, calibrate, HorseRig.drive)
RIDING -(interact)-> DISMOUNTING (Dismount_L/R, or Dismount_Jump above 3 m/s)
DISMOUNTING -(done)-> ON_FOOT at end_ground_point
RIDING -(rider dies or horse bucks the rider off)-> FALLING (FallOff) -> ragdoll/get-up
RIDING -(horse dies)-> horse Death + rider Horse_Ride_Death -> ON_FOOT
```

## 6. Camera suggestions for riding

- **Pivot** at `rig.socket("saddle").origin + 0.75 m up`. It follows the saddle delta low-passed at 8 Hz: the trot bounce reads without shaking the view.
- **Distance and FOV per gait:** walk 5.5 m / 55°, trot 6.0 / 57°, canter 6.8 / 60°, gallop 7.5 m / 64°, plus a subtle 1.5° roll into leaning turns.
- **Position lag** 0.3 s behind, **yaw lag** 0.45 s, so turns show the horse's lean from the outside. Look-ahead is 1.5–2.5 m along the velocity (the course capture uses a 2.5/s yaw follow).
- **Footfall shake** at gallop only: 1–2 mm per `hoof` event, so it is felt, not seen.
- **Mounted combat:** with a lock target, shift the pivot 0.6 m toward the weapon side and frame horse plus target. On the sword hit frame (f14), 0.05 s hit-stop and FOV −2°.
- **Mount and dismount:** hold the camera on the mounting side during the 2.2 s clip, orbit it behind the horse at `mount_done`, and do not auto-recenter during the mount.

## 7. Performance

Machine: RTX 4070 laptop, Mobile renderer, 320×180 CPU-bound window, vsync off. A second Godot from another session was running (CPU load about 60 %), so the numbers are ±15 µs per horse. Method: paired runs with and without N horses; each row is the median of 3 pairs.

| tier (HorseRig, 66 bones, 50-clip library) | horses | main-thread µs / horse (PC) | phone (×5) |
|---|---:|---:|---:|
| NEAR, springs HIGH (tail, mane, belly) + tack | 128 | **≈ 21** | ≈ 0.1 ms |
| NEAR, springs MED (tail) | 128 | ≈ 3–11 | ≈ 0.05 ms |
| NEAR, no springs (LOW) | 128 | ≈ 8–20 | ≈ 0.07 ms |
| MID (CrowdAnimLOD pulse 1 in 2–4 frames, LOD1) | 128 | ≈ 0 (within noise) | – |
| FAR (VAT twin, skeleton idle) | 128 | ≈ 4 | GPU only: 1002 tris, shared 2 MB textures |
| rider (UAL body + RiderSync tree + RiderIK) | 8 | **≈ 130** | ≈ 0.65 ms |

Budget for a busy scene:
- **PC:** 1 ridden horse + rider, 6 NEAR horses, 10 MID and 20 VAT is about 0.35 ms.
- **Phone:** about 1.8 ms, which fits 60 fps next to the living world's ~1.7 ms villagers.

Memory:
- anims 2.0 MB;
- model 1.2 MB;
- coats 6 × 1024² (ETC2/ASTC about 0.7 MB each);
- tack atlas 512²;
- VAT 2.0 MB total.

Draw calls per horse: 1 body plus 1 per tack piece (saddle, bridle, reins = 4). On LOW, ship only the bridle on ambient horses.

Proof of 20 horses in LOD: `engine_crowd_20_lod.jpg` and `engine_crowd_lod_tint.jpg` (blue = VAT tier).

## 8. Proof images (all captured in Godot with Movie Maker at 30 fps, unless marked Blender)

- `footfall_diagram.png`: gait diagrams measured in the engine for walk, trot, canter and gallop.
- `engine_gait_{Walk,Trot,Canter_L,Gallop_L,BackUp}.jpg`: every frame, side view, 0.5 m ground ticks.
- `engine_rider_{walk,posting_trot,canter,gallop_twopoint}.jpg`: rider sync, every frame.
- `engine_course_gallop_turns_rider.jpg`: gallop with leaning turns.
- `engine_mount_dismount.jpg`, `engine_mounted_combat.jpg`, `engine_rear_jump.jpg`, `engine_crowd_20_lod.jpg`, `engine_beauty_coats_tack_cart.jpg`.
- Blender: `coats_lineup.jpg`, `tack_lineup.jpg`, `lods.jpg`, `rider_Horse_Ride_{Trot,Gallop_L,Rear,Mount_L,Death,Sword_Swing_R}.jpg`.

## 9. Known issues and backlog

- **Mane:** reads as stacked plates when the neck is down (Graze, Drink). Rebuild it as fewer, longer clumps that follow the crest normal, or add a crest bone chain.
- **Clipping:**
  - rider legs go 6–10 cm into the croup while swinging over (mount/dismount), and FallOff/Death feet 6–8 cm;
  - the barding hem touches the legs in swing;
  - the harness collar dips into the neck when grazing.
- **Walk support smoothing** leaves 1.4–2.6 cm of toe drift in the engine. Real horses show a few cm too, but a per-stance toe pin in the solver would remove it. The walk saddle bob is also small (1.6 cm).
- **Terrain:** no foot IK on slopes yet. A 4-hoof `TwoBoneIK3D` + raycast module is next, and it will cost about 20 µs.
- **Rear and buck while mounted** work, but `FallOff` is only synced to Buck.
- **Jump:** the arc is in root motion. The mount controller needs a vertical root-motion consumer (P14a §5).
- **Carts:** the cart wheels are one mesh, so they do not spin.
- **Measurement:** the perf numbers were taken on a shared machine; re-bench on a quiet machine and on a phone.
