# Stagborn creatures (L5): Stagborn elk and the Antlered Warden

Two rigged, animated signature creatures for the Stagborn Glade (Region 1 plan, section 1.5, work package L5). **No Meshy credits were spent.**
Both are customised from one CC0 donor, the Quaternius *Ultimate Animated Animals* **Stag**
(`../../../quaternius/ultimate-animated-animals/glTF/Stag.gltf`, licence CC0 1.0, https://quaternius.com).

| | Stagborn elk (herd animal) | The Antlered Warden (guardian miniboss) |
|---|---|---|
| Files | `stagborn_elk.glb`, `stagborn_elk_lod1.glb` | `stagborn_warden.glb`, `stagborn_warden_lod1.glb` |
| Look | warm russet coat, cream chest, bone antlers; the antlers carry faint glowing rune rings and a glowing tip | chestnut-umber coat with a silver mane and chest, mossy dark-bark antlers, glowing cyan rune glyphs on the flanks, haunch, brow, leg bands and antler rings |
| Size (model space, metres) | ~1.25 m at the withers, 2.1 m long, 2.6 m to the antler tips (head up) | ~2.0 m at the withers, 3.8 m long, 5.0 m to the antler tips, 3.3 m antler span. Scale the visual node by 0.8 if the antlers are too tall for a scene; collision is yours. |
| Tris LOD0 / LOD1 | **3,668 / 2,000** (budget 8k) | **5,728 / 4,600** (budget 15k) |
| Bones | 26 (no IK helpers), 4 weights per vertex | same rig, 26 bones |
| Texture | one 1024 px albedo + one 1024 px emissive (LOD1: 512 px), embedded JPEG | same |
| Facing / origin | origin between the hooves on the ground, faces -Y in Blender = glTF +Z (the same convention as the other Quaternius animals in `animals/quaternius/`). Real-world scale. | same |
| File size | 1.3 MB / 1.1 MB | 1.8 MB / 1.6 MB |

The **emissive texture is the rune mask**. The glTF material has `emissiveTexture` and `emissiveFactor` = 1, so Godot shows the glow with no extra setup.
Drive the pulse from code by animating `StandardMaterial3D.emission_energy_multiplier` (elk: 0.6 to 1.2, Warden: 1.0 to 3.0 in phase 2 or 3). The elk's emissive is deliberately subtle (65 % strength).

## Clips (30 fps, all in place, no root motion in the clips)
Clip names are lower case. Loops are exact: the last frame is the frame before the first.

| Clip | Elk length (frames / s) | Warden length | Loop | Use |
|---|---|---|---|---|
| `idle` | 101 / 3.33 | 126 / 4.17 | yes | stand |
| `idle_alt` | 101 / 3.33 | 126 / 4.17 | yes | idle variation (weight shift, slight head turn); use as the alert pose while it decides |
| `graze` | 364 / 12.1 | 454 / 15.1 | yes | head down and chewing (herd graze) |
| `walk` | 36 / 1.17 | 45 / 1.47 | yes | ~1.15 m/s (Warden ~1.5 m/s) |
| `run` | 17 / 0.53 | 21 / 0.67 | yes | gallop, ~5.2 m/s (Warden ~6.9 m/s); flee |
| `run_charge` | 17 / 0.53 | 21 / 0.67 | yes | gallop with the head lowered and the antlers levelled; ~5.0 m/s (Warden ~5.9 m/s) |
| `attack` | 56 / 1.83 | 70 / 2.30 | no | **antler charge and gore**: telegraph, strike, upward toss |
| `attack_butt` | 25 / 0.80 | 31 / 1.00 | no | quick antler jab (herd shove; Warden phase 1 poke) |
| `hit` | 15 / 0.47 | 16 / 0.53 | no | flinch |
| `death` | 34 / 1.10 | 42 / 1.37 | no | topples onto its side, ends lying on the ground |
| `kick` | - | 31 / 1.00 | no | Warden only: hind-leg kick |
| `roar` | - | 72 / 2.37 | no | Warden only: crouch, rear up, head thrown back and shaken, slam down |

## HANDOFF for Codex (X3, Stagborn behaviour)
Ownership: Codex owns the behaviour and the state machines. This is the clip contract.

**Root motion: none.** Every clip is in place. The controller moves the body. Speeds that match the feet (measured, see `docs/art/region1/stagborn/*_metrics.json`):
elk `walk` 1.15 m/s, `run` 5.2 m/s, `run_charge` 5.0 m/s; Warden `walk` 1.5 m/s, `run` 6.9 m/s, `run_charge` 5.9 m/s. Feet slide by at most about 20 % of the speed in `walk`; run is tighter.
The `attack` clip has a small in-place lean (torso moves forward 0.10 m for the elk, 0.15 m for the Warden). Move the capsule forward yourself during the strike frames if you want a real lunge.

**State to clip mapping (suggested)**

| State | Clip | Blend in | Notes |
|---|---|---|---|
| Graze / rest | `graze`, `idle` | 0.25 s | herd default; `graze` is one long loop, so start it at a random offset per animal |
| Alert (threat seen) | `idle_alt` | 0.2 s | subtle; add a look-at on the head bone toward the threat |
| Walk / migrate | `walk` | 0.25 s | scale `speed_scale` to the actual speed / 1.15 (Warden / 1.5) |
| Flee | `run` | 0.15 s | |
| Threatened, charging | `run_charge` -> `attack` | 0.15 s | `run_charge` up to about 2.5 m from the target, then `attack` (the charge lunge is inside `attack`) |
| Hit reaction | `hit` | 0.1 s, back to previous 0.2 s | can overlap the run loop with a one-shot |
| Death | `death` | 0.15 s | the clip ends with the animal lying down at the origin, recentred (it does not drift) |

**Event frames (30 fps, counted from the clip start)**

| Clip | Telegraph / commit | Damage frame (antlers hit) | Damage window | Peak / VFX frame | End |
|---|---|---|---|---|---|
| elk `attack` | wind-up is frames 0-22 (paw scrapes, head lowering); commit at 22 | **29** | 27-36 | gore toss peak **41** (VFX: dust or rune sparks on the antlers) | 56 |
| Warden `attack` | wind-up 0-28 (about 0.9 s, long enough to read); commit at 28 | **37** | 34-46 | toss peak **51** | 70 |
| elk `attack_butt` | 0-6 | **10** | 8-13 | | 25 |
| Warden `attack_butt` | 0-8 | **12** | 10-16 | | 31 |
| Warden `kick` | 0-13 | **20** | 17-23 | | 31 |
| Warden `roar` | crouch 0-12 | | | rear-up hold 29-51 (use for the phase-change aura and the AoE fear telegraph); **front hooves land at frame 60** (stomp shockwave VFX, camera shake) | 72 |
| `hit` | | | | flinch peak at frame 8 (elk), 9 (Warden) | end |

Audio hooks already in `assets/audio/region1/` (L17): Stagborn bellow and snort, Warden roar. Play the roar at `roar` frame 14 (head starting to throw back), the bellow at `attack` commit.

**Warden 3-phase suggestion** (behaviour is yours): phase 1 `attack_butt` combos and `walk` circling; phase 2 adds `run_charge` -> `attack` and `kick` when the player is behind it; phase 3 opens with `roar` (rune glow up to 3x), then alternates `attack` (long telegraph, punishable) with `run_charge`.

## How they were made (reproducible)
Scripts are in `tools/creatures/stagborn/` (Blender 5.2 headless, `-b --python`):
1. `s1_base.py` imports the CC0 stag, deletes the IK, pole and foot-helper bones (their hoof weights merge into the lower legs), merges the separate antler mesh into the skin (weighted 100 % to `Head`), and scales it to metres (elk x0.48, Warden x0.72).
2. `s2_model.py` builds the variant: the **Warden** gets new procedural antlers (2 beams and 14 tines, tube meshes skinned to `Head`), a neck mane and throat ruff of cone tufts skinned to the neck bones, a wider body and heavier neck and chest (weight-driven). The **elk** keeps the stock antlers. It welds the mesh, UV-unwraps it, and bakes vertex-colour albedo, ambient occlusion, an object-space position map and masks with Cycles. It then paints in numpy: warm/cool colour drift, fur strokes, baked AO, and moss on the Warden. The **rune glyphs are drawn per texel from the baked position map** (3 flank glyphs, a haunch glyph, leg bands, spine dashes, neck bands, a brow mark, antler rings and tip glow), so they follow the surface with no extra UV art.
3. `clips.py` and `s3_export.py` rename and retime the stock clips (the Warden runs 1.25 x slower for weight), author `attack`, `run_charge` and `roar` on top of the stock poses (rotations about armature axes, hooves ground-fixed per frame), lift the `walk`, `run` and `death` clips so the mesh never dips below the ground, recentre `death`, build LOD1 (decimate, 512 px textures) and export GLB.
4. Checks: `qa_metrics.py` (hoof floor contact, stance speed, loop seam), `events.py` (event frames), `render_clip.py` + `sheet.sh` (frame sheets), `preview_glb.py` (turntable).

Stock clips retained from the donor (CC0, retimed): `idle`, `idle_alt`, `graze` (Eating), `walk`, `run` (Gallop), `attack_butt` (Attack_Headbutt), `kick` (Attack_Kick), `hit` (Idle_HitReact1), `death`.
Authored by us: `attack`, `run_charge`, `roar`.

## Verification (frame sheets are in `docs/art/region1/stagborn/`)
- Turntables: `stagborn_<name>_turntable.png` and `..._lod1_turntable.png`.
- One stop-motion sheet folder per clip: `stagborn_<name>_<clip>/sheet_00N.png` (`SRC_FPS=30 bash tools/qa/video_to_sheets.sh <frames> <out> 12 4 3 400`; idle, idle_alt and graze were rendered at every 3rd, 4th, 10th or 12th frame, and the sheet time is corrected for that).
- Read: no mesh tearing in any clip; gaits are natural (the stock Quaternius cycles); `attack` has a readable telegraph (paw scrape, then the head lowers and the antlers level at the target for about 0.4 s before the strike); the rear-up in `roar` reads at phone size.

## Known limitations
- Rendered and checked in Blender only (workbench and EEVEE); **not yet imported or run in Godot** (no Godot import in the worktree, disk). Run `bash tools/qa/anim_qa/run.sh --only=<id>` once the entries are added to `tools/qa/anim_qa/catalog.gd`.
- Flat-shaded low-poly donor shapes with smooth shading: silhouettes are faceted around the head and antlers, softened by the painted texture.
- In `run_charge` and at the head-down moment of `attack`, the antler tips dip up to about 9 cm (elk) or 14 cm (Warden) below the ground plane. Grass hides it.
- `walk` has some foot slide (stance speed varies by about 20 % between feet) because the stock clip was ground-fixed by lifting the body, not by IK. Use foot IK if it shows.
- The Warden antlers are 3.3 m wide and can pass through the body in the `roar` rear-up hold (they rest across the back). Collision is not affected.
- `death` recentres the body, so the carcass rolls in place and the hooves slide a little.
- The mane and throat ruff are small cone tufts: they read as fur clumps, not flowing hair.

## Licence
Donor mesh, rig and stock clips: **Quaternius, CC0 1.0** (public domain, no attribution needed, credited in `kingdom/CREDITS.md`).
Textures, antlers, mane, rune glyphs, retiming and the authored clips: own work for this project (also usable as CC0). No Meshy output involved.
