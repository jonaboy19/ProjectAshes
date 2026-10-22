# Bending and martial-arts sources: licence check, move list, VFX references

Date: 2026-10-05 (cloud session, Sonnet). Scope: clips for the five bending stances, sect and knight forms, and better elemental VFX.
Rules applied: only CC0 / MIT / OFL / CC-BY (with credit) / explicit commercial permission; GPL/AGPL/NC = reference only; never embedded.
Egress note: the cloud proxy blocks `mocap.cs.cmu.edu`, `mocap.cs.sfu.ca`, `helpx.adobe.com`, `accad.osu.edu`, `motifect.itch.io`, `ianxmason.com`. Rows marked **secondary** rest on a mirror's README or a web-search snippet, not the primary page, and need a one-time human check at the primary URL before anything new from that source is committed.

## 1. Licence record (verbatim key lines)

### CMU Graphics Lab Motion Capture Database (commercial use: yes)
- Primary page `http://mocap.cs.cmu.edu/` and FAQ `http://mocap.cs.cmu.edu/faqs.php`: blocked from this container (**secondary**).
- Verbatim from `READMEFIRST.txt` of the BVH mirror https://github.com/una-dinosauria/cmu-mocap (file copied to `kingdom/assets/incoming/mocap/cmu/_raw/READMEFIRST.txt`), which quotes the CMU page:
  > CMU places no restrictions on the use of the original dataset, and I (Bruce) place no additional restrictions on the use of this particular BVH conversion.
  >
  > Use this data!  This data is free for use in research and commercial projects worldwide.  If you publish results obtained using this data, we would appreciate it if you would send the citation to your published paper to jkh+mocap@cs.cmu.edu, and also would add this text to your acknowledgments section: "The data used in this project was obtained from mocap.cs.cmu.edu.  The database was created with funding from NSF EIA-0196217."
- A web-search summary of the same page adds a limit that is not in the mirror: "you may include this data in commercially-sold products, but you may not resell this data directly, even in converted form". We do not sell the data: raw BVHs stay out of git (`_raw/.gitignore` ignores `*.bvh`); only retargeted clips ship inside the game. The repo is public, so keep it that way.
- Credit line (already in `kingdom/CREDITS.md`): "Motion capture data from the CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), created with funding from NSF EIA-0196217."
- Verdict: **use** (already the base of `animations/cmu_mocap` and `animations_free/*`).

### mocap-ts (video to BVH): the real repo
- Canonical: https://github.com/ellyseum/mocap_ts ("Video to BVH motion capture, pure TypeScript", created 2026-04-28). A text-identical copy exists at https://github.com/DevLouix/mocap-ts (created 2026-08-30, same author name in the LICENSE); treat `ellyseum/mocap_ts` as upstream.
- LICENSE (read from `raw.githubusercontent.com/ellyseum/mocap_ts/main/LICENSE`): "MIT License / Copyright (c) 2026 Jocelyn Ellyse / Permission is hereby granted, free of charge, to any person obtaining a copy of this software ... to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software ..."
- README: "MIT-licensed end to end — safe to use commercially". Pipeline: ffmpeg frames, TF.js pose-detection ("BlazePose / MoveNet style", 33 keypoints + optional hands), temporal smoothing, skeleton calibration, IK, BVH. CLI: `mocap-ts --input video.mp4 --output dance.bvh`, `--fps 30 --no-hands --smoothing 0.5 -v`.
- Caveats: the README does not name which pose model or its licence (BlazePose/MoveNet in TF.js are Apache-2.0 upstream, but confirm at the model URL it downloads). Roadmap lists "foot contact detection + ground-locking" as NOT implemented, so expect foot sliding that our existing MediaPipe cleaner (`kingdom/tools/anim/video_mocap`) already handles. Output is our own recording, so the data carries no third-party licence.
- Verdict: **use as a tool** (output is the owner's own motion). Not run here (needs Node + a video).

### achrefelouafi/AvatarCastingAbilitiesThreeJS (MIT bending sandbox)
- https://github.com/achrefelouafi/AvatarCastingAbilitiesThreeJS, LICENSE first lines (cloned and read): "MIT License / Copyright (c) 2026 mohamedachrefelouafi / Permission is hereby granted, free of charge, to any person obtaining a copy of this software ... without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies ..."
- README: "Code is provided as-is for the purposes of this project. The bundled HDR probe and the character FBX retain their original licences." The character FBX is a **Mixamo** download (README says so): do NOT take the FBX or the HDR probe.
- Verdict: **MIT code, usable as a technique reference** (we re-wrote the ideas Godot-native, copied nothing; no credit required, courtesy line added to `CREDITS.md`).

### GlitchyTurtle/avatar-addon
- https://github.com/GlitchyTurtle/avatar-addon, licence shown as "GPL-3.0 license" (LICENSE file starts "GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007"). A Minecraft Bedrock add-on (behaviour pack + resource pack).
- Verdict: **reference only, never embedded.** Useful design notes only: chi bar, move binding to hotbar, move kinds standard / charged / toggle. Our `ashes-ability-system` already has those.

## 2. More sources: table

| Source | Licence (where verified) | What is useful | Verdict |
|---|---|---|---|
| CMU Mocap (BVH via cgspeed / una-dinosauria mirror) | free commercial, no restrictions (see above) | karate 135, boxing 13/14/17, Subject 144 (blocks, lunges, punches, Sun Salutation), basketball evasions 78/102, dance 05/49/55, acrobatics 85-90 | **USE** (this session added 36 clips) |
| 100STYLE (Mason, Starke, Komura, Edinburgh; retarget rig by D. Holden) | BVH: "licensed under the same terms as the original dataset which is Creative Commons Attribution 4.0 International" (https://github.com/orangeduck/100style-retarget); Geno mesh is "free for non-commercial research use" | 100 locomotion styles. Already 14 clips in `characters/_library/UAL_Extra_100STYLE.glb` | **USE with credit** (credit already in CREDITS.md). Locomotion only: no new bending value. Primary dataset page was blocked, so the style list was not re-read; check it before adding more |
| Quaternius Universal Animation Library 1 + 2 | CC0 (https://quaternius.com/packs/universalanimationlibrary2.html, OpenGameArt page) | 130+ clips: melee, combos, parkour, farming; native UAL rig | **USE** (already in game) |
| Mesh2Motion assets | code MIT, art and animations CC0 (https://github.com/Mesh2Motion, `mesh2motion-assets` shows CC0-1.0) | CC0 clips on a UAL-like rig, already used for Attack_Ground_Pound, Dodge_*, Backflip | **USE** (already) |
| Cat Prisbrey Souls-like template | Unlicense | Magic_*, Souls_* | **USE** (already) |
| KayKit character animations | CC0 | casts, swings, dodges | **USE** (already) |
| Truebones free BVH packs | web-search quote of Truebones ToS: "royalty free ... any and all purposes even commercial" **but** "Re-Distribution or ReSale of Truebones in .FBX, .BVH or i-Motion formats is strictly prohibited" and credit requested (**secondary**) | 500 free BVH, creature and martial motions | **NO for this public repo**: committing retargeted GLBs may count as redistribution. Owner can use privately and ship in the built game only after reading the ToS |
| Mixamo (Adobe) | Adobe FAQ via search snippet (**secondary**): usable royalty-free in commercial games, "you cannot create ... asset packages ... which redistribute character or animation raw files" | huge library | **NO**: public repo = redistribution; also needs an account. The sandbox's Mixamo FBX is excluded for the same reason |
| Bandai Namco Research Motion Dataset | https://github.com/BandaiNamcoResearchInc/Bandai-Namco-Research-Motiondataset: "CC BY-NC 4.0" (both datasets; only the viz scripts are MIT) | styled fighting and dance BVH | **NO** (non-commercial) |
| SFU Motion Capture Database (martial arts: kendo, wushu kicks) | search summary (**secondary**): free for research, not for commercial products or resale | kendo kata, wushu kicks | **NO** |
| LaFAN1 (Ubisoft) | CC BY-NC-ND 4.0 (recorded in `animations_free/LICENSES.md`) | | **NO** |
| ACCAD Open Motion Project (Ohio State) | search summary only: CC BY 3.0 (**unverified**, site blocked) | dance, martial BVH | **MAYBE**: verify the licence page, then CC-BY with credit would be fine |
| Motifect Martial Arts Motion Pack (itch.io) | page blocked; search summary claims "free for personal and commercial use", 40 clips FBX+BVH | karate, taekwondo, kung fu | **MAYBE**: owner to read the itch page; likely forbids redistribution of the raw clips in a public repo |
| AMASS / anything derived | research only | | **NO** (already a project rule) |
| "Kinetic" / CMU conversions for Blender | the cgspeed BVH conversion (B. Hahne) is the CMU data with "no additional restrictions" (READMEFIRST above); I found no separate "Kinetic" source | | covered by the CMU row |
| **VFX** achrefelouafi sandbox | MIT code (see above); Mixamo FBX and HDR excluded | tube-hull water, ray-marched fire, plate-and-tower earth, shader-sphere air | **REFERENCE** (techniques re-written, nothing copied) |
| haowg/GODOT-VFX-LIBRARY | README: "licensed under the MIT License"; asset provenance not documented (`tools/vfx/README.md` already flagged it "provenance of assets unclear") | 35 particle effects + 17 shaders for Godot 4.5+ (torch, fireball trail, water splash, lightning chain, ice, dash trails, dissolve) | **CODE ONLY if needed**, textures not taken. Not used here |
| gdquest-demos/godot-4-VFX-assets | "source code ... shaders ... available under the MIT license"; "Art assets (image textures and 3D models) are CC-BY-NC-SA 4.0" | stylised Godot 4 particle and shader examples | **SHADER CODE usable (MIT, credit); textures and models NEVER** (NC-SA). Not used here |
| Kenney Particle Pack, Effekseer samples, Material Maker | CC0 / MIT | sprites, authoring | **USE** (already, see `tools/vfx/README.md`) |
| ShaderToy shaders | default CC BY-NC-SA | | **technique reading only** (rule already in `tools/vfx/README.md`) |
| godotshaders.com | per-shader licence (CC0 / MIT / GPL mix) | many elemental shaders | **check each shader's licence line**; skip if absent |

## 3. Move list: element stance to concrete mocap

Existing coverage first (do not duplicate): CMU karate Subject 135 trials 01, 02, 04, 05, 06, 07, 09, 10, 11 (Bassai, Empi, front kick, Gedanbarai, Heiansyodan, Mawashigeri, Oiduki, Syutouuke, Yokogeri) are all already clips in `animations/cmu_mocap`. CMU has **exactly one Tai Chi trial** (Subject 12, trial 04, 13.5 MB, 40 s): `Taichi_Idle` and `Taichi_Form` already come from it. There is **no Bagua / Xingyi / Wing Chun** in any permissive set found, so Water/Air flowing arts are built from modern dance (Subjects 05, 49, 55), yoga (Subject 144 Sun Salutation) and evasive basketball footwork (Subject 78).

New CMU trials fetched this session (39 trials, 63 MB, `kingdom/assets/incoming/mocap/cmu/_raw/`, local only): 05_03 05_04 13_17 13_26 14_02 17_10 49_09 49_12 49_18 49_21 55_01 75_08 76_01 76_02 76_04 78_13 78_18 78_19 81_05 81_07 82_06 86_01 86_06 88_04 88_06 90_07 141_06 141_14 143_23 144_03 144_11 144_13 144_15 144_17 144_20 144_22 144_24 144_28 144_31.

Clips produced (`UAL_CMU_Bending.glb`, 36 clips, in `kingdom/assets/incoming/mocap/cmu/clips/`), with technique ids from `kingdom/data/powers/*.json`:

| Stance | Techniques (ids) | New clips (CMU subject_trial, window s) | Existing clips to pair |
|---|---|---|---|
| Water (flow, redirect, heal) | `bn_water_whip`, `bn_water_mend`, `bn_tide_wall`, `bn_flow` | `Water_Dance_ArmsHigh` (49_09, 0.4-4.2: slow rising arms), `Water_Flow_SunSalute` (144_31, 0.7-5.4), `Water_SpinReach_L` (144_15, 4.4-6.8), `Water_Whirl` (55_01, 0.5-6.5), `Water_Lean_Sway_A` (05_04, 4.8-8.4), `Water_Lean_Sway_B` (49_12, 1.9-5.4) | `Taichi_Form`, `Taichi_Idle` (12_04), `Cast_Water_Charge/Release` |
| Air (evade, step, cyclone) | `bn_gust`, `bn_air_step`, `bn_cyclone`, `st_step` | `Air_Evade_L/R` (78_18, 78_19: sprint-dodge), `Air_Duck_Weave_L` (78_13), `Air_Balance_OneLeg` (49_18), `Air_SpinJump_360` (75_08, 1.6-3.0), `Air_Jump_Twist` (141_06, 3.6-5.2), `Air_Jump_Kick` (90_07, 5.0-7.5), `Air_Handspring_Evade` (88_04, 3.3-4.6) | `MA_Acro_*` (cartwheels, flips), `Cast_Wind_*` |
| Earth (root, hold, break) | `bn_stone_fist`, `bn_rampart`, `bn_quake` | `Earth_Lunge_R/L` (144_17, 144_11), `Earth_PunchSeq_L` (144_13), `Earth_PunchSeq_Deep` (144_20, 3-4.6), `Earth_Punch_Hold_Deep` (144_13, 5-11.7), `Earth_Crouch_Reach_R/L` (144_24, 144_22), `Earth_Spin_Reach_R` (144_28) | `Karate_Gedan_Barai`, `Karate_Oi_Zuki`, `Kata_Bassai/Empi` (135), `Cast_Earth_*`, `Cast_AoE_Slam` |
| Fire (strike, wheel, breath) | `bn_flame_jab`, `bn_fire_wheel`, `bn_dragon_breath` | `Fire_Box_Combo_A/B/C` (13_17, 14_02, 17_10), `Fire_Box_Jab_Hook_B`, `_Straight_C`, `_Hooks_D`, `_Flurry_E`, `Fire_Stride_Strike_F`, `Fire_Punch_Kick` (141_14, high kick), `Fire_Aerial_Flip` (88_06) | `Karate_Mae/Mawashi/Yoko_Geri`, `MA_Kick_*`, `MA_Combo_*` |
| Lightning (sharp arm work, manual later) | `bn_storm`, `st_nine`, `st_thunder_palm` | `Lightning_Point_Snap` (13_26 traffic-point arm, 6.1-9.0), `Lightning_Punch_Snap` (143_23). Placeholders: a proper snap-to-point set should be keyed by hand | `Cast_Lightning_*`, `Cast_Push_Palm_*` |
| Sect (cultivation, palms, qi) | `st_palm`, `st_circ`, `st_flowing_palm`, `st_nine_breaths`, `st_breath_gather` | `Cultivate_Yoga_Floor_Flow` (144_31, 7.9-15.1, hands-on-floor flow, for breath circulation) | `Taichi_*`, `Kata_Heian_Shodan`, `Kata_Bassai`, `Kata_Empi` (forms for sect trainers) |
| Knight (guard, charge, forms) | `kn_guard`, `kn_brace`, `kn_charge`, `kn_shoulder_rush` | `Guard_Ready_Defensive` (76_04), `Fire_Stride_Strike_F` doubles as a lunging charge strike | `Swordplay_A/B/C` (02_07-09), `Sword_Light_*`, `Souls_*` |

Fetched but not yet cut (good candidates for the next batch): 144_03 Figure8s (37 s, arm figure-eights, low amplitude), 144_13 and 144_22 later segments, 144_28 other spin-reaches, 86_01 and 86_06 (squats, jumps, knee kick; 86_06 is 83 s, mostly walking), 76_01/76_02 (retreat then punch: mostly walking), 81_05/81_07/82_06 (push or pull heavy object: awkward from behind, rejected for Earth), 49_21 (rope hang, rejected), 14_02 and 13_17 remaining boxing windows (13.7-19.4 used, 21-32 unused), 17_10 other segments, 13_26 other pointing windows.

## 4. VFX: how the sandbox does it and what we built

How `AvatarCastingAbilitiesThreeJS` works (read from README + `src/`): a pooled `Ability` base runs travel, impact, fade, done along a drawn spline; each element only describes how it looks.
- **Fire:** a camera-facing proxy hull around the flight path; the fragment shader ray-marches a density field (capsule falloff eroded by 3 noise octaves streaming backwards and climbing with buoyancy), emission = pow(heat, 2.4), soot absorbs (premultiplied "over" blend, not additive). Quality dial = march steps (26 steps about 1.3 ms at 960x540 on a desktop GPU). Too heavy for a phone.
- **Water:** same hull; the shader marches to the first sign change of `radius*(1+swell+chop) - distanceToAxis`, refines with 4 bisections, normals from the field gradient, Schlick fresnel, Beer-Lambert depth tint, voronoi foam cells, a refraction pass via a distortion buffer; impact = crown of jets, foam sheet, rings. Plus a ribbon geometry (re-used for flame stream, water twist, wind ribbons) and instanced GPU quads with 6 procedural silhouettes (soft, smoke, streak, leaf, chip, ring).
- **Earth:** real instanced geometry in three beats: paving plates flush with the floor along the path, a fracture wave (plates lever, tip, slide apart, dust and chips), then a tower climbs out and a ring of boulders is shouldered up; everything sinks after a hold. Plate count cap 420, rock cap 96.
- **Air:** a shader sphere partitioned into streamlines by longitude plus twist times latitude, warped by fbm, additive; band count must be a whole number or a seam shows.
- **Shared:** depth prepass, distortion pass, bloom + ACES, contact shadows, light pool parked at zero intensity to avoid shader recompiles.

What we built Godot-native in `kingdom/scenes/vfx_lab/` (nothing copied; cheaper variants of the same ideas):

| Effect | Technique | Mobile cost (see `docs/art/vfx_lab/README.md`) |
|---|---|---|
| Water whip | tube built in the vertex shader on a cubic Bezier (4 uniforms), swell wave, bulb head, fresnel + scrolling foam + fake glint, droplets and splash particles, wet-ring decal | 1 mesh of 29x11 verts, 1 draw, 40 particles max, no screen reads |
| Fire blast | additive cone shell built in the vertex shader, 2 octaves of 3D value noise for dissolve and a heat ramp (core, mid, edge), inner shell dropped on LOW, embers, scorch decal, one flickering light (HIGH only) | 2 transparent shells (1 on LOW), 28 particles max, 1 noise-heavy pixel shader on a small screen area |
| Earth spikes | one MultiMesh of 11 flat-shaded rock spikes, per-instance delay/height/width/lean in custom data, rise (ease-out-back), hold, sink all computed in the vertex shader from one uniform, crack decal, dust + chip particles | 1 draw for all spikes, 34 particles max, opaque so no overdraw |

Not done on purpose (mobile): ray-marching, refraction/heat-haze (needs the screen texture), bloom dependence, per-frame CPU mesh building. The lab effects use a procedural soft sprite shader, so no new texture files are shipped.
