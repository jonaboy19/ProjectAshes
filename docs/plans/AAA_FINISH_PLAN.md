# Rising Ashes — AAA finish plan (2026-10-26)

> **Correction (coordinator, 2026-10-26):** the remote backup DOES exist: `origin/backup/anim-codex-wip-2026-10-26` = `026719f8` (snapshot of PA_wt_w3's uncommitted work minus the 451 MB `work/` folder) and `origin/claude/anim-aaa` = `dd0e4369`. Still do S0 properly (commit in logical pieces).

Owner brief: "Find the fastest way to finish the game. Animations must be AAA level, like Assassin's Creed. We have many clips, but buggy or weak ones are no use to us. Codex does the work and will run out of usage, so every step must be very detailed."

Inputs read: `docs/plans/HANDOFF_CODEX_2026-10-26.md`, `READY_V1.md`, `ANIM_AAA_BRIEF.md`, `PERF60_BRIEF.md` (branch `origin/claude/focused-curie-m09hbd`); in `C:/Users/Jonna/Documents/PA_wt_w3` (branch `claude/anim-aaa`, HEAD `dd0e4369`, **1318 dirty paths**): `work/CLAUDE_HANDOFF_2026-10-25.md`, `docs/anim/aaa_wiring/AUDIT_2026-10-24.md`, `docs/qa/PC_QUALITY_STATUS_2026-10-26.md`; and the owner's reference sheets in `C:\Users\Jonna\Documents\PA_plans\ref_videos\` (all 7 images viewed).
Note: `backup/anim-codex-wip-2026-10-26` could not be found as a local or `origin/` ref when this plan was written. Treat the dirty `PA_wt_w3` worktree as the **only** copy of that work. Step 0 makes it safe first.

## Hard constraints (apply to every step)
- PC only. Godot 4.6.3: `C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64_console.exe`.
- Laptop: 15 GB RAM, so run **at most 2 Godot instances** in total, and only one when running `--import`. Disk is tight: **C: had 23 GB free (98 % used) on 2026-10-26**. Each worktree with `.godot` is about 14.5 GB. Run `df -h /c` before any import or worktree step, and **stop if less than 8 GB is free**. Do not create a new worktree. Reuse `PA_wt_w3`, `PA_wt_audit` and `PA_wt_mcp`.
- Perf numbers are valid only on AC power. Check with `(Get-CimInstance Win32_Battery).BatteryStatus` (2 means AC) and log the result with every perf run.
- Never use `--headless` for screenshots or Movie Maker. Read every image you claim to have checked.
- `player.gd` and `hero_face_driver.gd` are **CRLF**. Keep them CRLF (`git diff --stat` must not show the whole file changing).
- Git Bash: `export MSYS_NO_PATHCONV=1`; use `git -C "C:/Users/..."`.
- Never commit `.import`/`.uid` churn, `kingdom/.godot/` or `project.godot` rewrites from `--import`. Never commit `work/` (451 MB).
- Commit trailers: Claude commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Codex uses its own trailer.
- Licences: only CC0, CC-BY or MIT (plus the CMU "free for any use" terms). No NC, ND or IP-flavoured packs. Every download needs the owner's OK first (name, source, licence and size). No account creation. No Meshy spend without the owner's OK.
- Never `taskkill /IM`. Stop only processes you started, by PID.

---

## External tools & sources (checked on disk 2026-10-26)

### 1. Installed on this PC
| Tool | Where | Use in Rising Ashes |
|---|---|---|
| Godot 4.6.3 (console exe) | `C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\` | engine, Movie Maker captures, gdUnit, gate tools |
| Godot editor MCP (dcc-mcp) | `C:\Users\Jonna\Tools\dcc-mcp` (`start_godot_mcp.ps1`, http://127.0.0.1:8765/mcp) | Claude drives the editor on `PA_wt_mcp` |
| Blender 5.1 + 5.2 | `C:\Program Files\Blender Foundation\` | re-rig Meshy NPCs to UAL, retarget, hand-fix clips, creature gaits |
| Blender add-ons (`Tools\BLENDER_ADDONS.md`) | Rigify 0.6.10, AnimAll, Copy Attributes, TexTools, MPFB (faces/expression units), Expy Kit (retargeting), Bone Dynamics + Wiggle 2 (secondary motion, not enabled), dcc_mcp_blender | S5/S6 retarget and rigging, cloak springs |
| agi | `Tools\agi` | binary only; purpose not documented — ask before use |
| azgaar | `Tools\azgaar` | fantasy map generator (world/parchment map for the 12 km region) |
| context7 | `Tools\context7` (node) | up-to-date docs lookup for agents (Godot API) |
| debug-draw-3d | `Tools\debug-draw-3d` + `addons/debug_draw_3d` | draw IK targets, contact points, foot locks in state tests |
| effekseer | `Tools\effekseer` + `addons/effekseer` | hit sparks, dust, blood VFX for combat |
| gdtoolkit | `Tools\gdtoolkit` | `gdlint`/`gdformat` for GDScript checks |
| gltfpack | `Tools\gltfpack` | compress/reduce GLB animation keys (the traversal pack went 154k → 12k keys) |
| instantmeshes | `Tools\instantmeshes` | retopology of Meshy meshes before rigging |
| jsfxr, rfxgen | `Tools\jsfxr`, `Tools\rfxgen` | placeholder SFX generation (UI, hits) |
| krita | `Tools\krita` | texture paint, face cards |
| material-maker | `Tools\material-maker` | procedural ground/stone/wood materials |
| perfetto, renderdoc | `Tools\perfetto`, `Tools\renderdoc` | CPU trace / GPU frame capture for the 60 fps work |
| piper | `Tools\piper` | offline TTS for NPC voice placeholders |
| realesrgan | `Tools\realesrgan` | upscale textures/concepts |
| rtmlib | `Tools\rtmlib` (venv) | pose estimation from video → compare our motion against reference video poses |
| scrcpy | `Tools\scrcpy` | Android mirroring (mobile, unused now) |
| serena | `Tools\serena` | code-navigation MCP for agents |
| terrain-erosion-3-ways | `Tools\terrain-erosion-3-ways` | heightmap erosion for macro terrain |
| VectCutAPI | `Tools\VectCutAPI` | CapCut video editing API (trailers) |
| Python 3.14 (+3.12, 3.10), numpy, Pillow, scipy, opencv 4.13 | `py -E -B` | GLB edit/audit scripts, metrics |
| ffmpeg 9.0 | WinGet package | Movie Maker → video/sheets |
| gh CLI, Codex CLI (npm) | PATH | PRs, Codex sessions |
| TripoSG/TripoSR (Codex 3d-tools) | **not found on disk** under `C:\Users\Jonna` | — (ask Codex where they are installed) |
| Repo Godot addons (`kingdom/addons`) | terrain_3d, proton_scatter, gdUnit4, limboai, dialogue_manager, phantom_camera, road-generator, godot_material_footsteps, effekseer, debug_draw_3d, debug_menu, gloot (inventory), godot-sqlite, GodotGAS (ability system), guide (input), quest_weaver, simplegrasstextured, sky_3d, voronoishatter, mobile_texture_limit | Phantom Camera for the A7 shoulder/lock-on camera; footsteps for foot-plant sounds synced to `foot_contacts`; LimboAI for NPC behaviour |
| Meshy (Claude-only) | MCP, ~180 credits/month | NPCs, gap animations |
| Cloud agents | Claude Code routines (claude.ai/code/routines), Codex, Antigravity | parallel lanes |

### 2. To download (free + commercial-OK only; all need the owner's OK)
| Priority | Name | Official URL | Licence | Size (approx.) | For | Who |
|---|---|---|---|---|---|---|
| 1 | Quaternius Universal Animation Library 2 (Standard) | https://quaternius.itch.io/universal-animation-library-2 | CC0 | 9.7 MB | 130+ clips on our UAL rig: combos, parkour, farming, fishing (**not in repo yet**) | **Claude now** |
| 1 | Quaternius animal/creature packs (Ultimate Animated Animals etc.) | https://quaternius.com / https://quaternius.itch.io | CC0 | 5–50 MB each | replacement creature gaits | Claude now (pick after S5 gate) |
| 2 | KayKit Character Animations / Adventurers | https://kaylousberg.itch.io/ | CC0 | 10–50 MB | extra combat/interaction clips | Claude now |
| 2 | CMU mocap BVH subsets (subjects 02, 13, 14, 79, 127, 143, 144) | http://mocap.cs.cmu.edu/ | free for any use | ~50–200 MB | more retarget sources (already partly used) | Claude when needed |
| 3 | godot-motion-matching | https://github.com/GuilhermeGSousa/godot-motion-matching | MIT | ~5–20 MB | v2 MM spike only (A4) | later |
| 3 | 100STYLE | https://zenodo.org/record/8127870 | CC BY 4.0 (verify on the official page) | several GB | v2 locomotion styles/MM data | later, after licence check |
| 2 | Rokoko free motion packs | https://www.rokoko.com/resources | per-pack (check) | varies | extra mocap | **owner downloads (login)** |
| 2 | Poly Haven (HDRIs, textures, models) | https://polyhaven.com | CC0 | per asset | ground/stone textures, skies | Claude as needed |
| 2 | ambientCG | https://ambientcg.com | CC0 | per asset | PBR materials for towns | Claude as needed |
| 2 | Kenney assets (UI, audio) | https://kenney.nl | CC0 | 1–100 MB | UI icons, UI SFX | Claude now (UI + audio packs) |
| 1 | Sonniss GDC Game Audio Bundles | https://sonniss.com/gameaudiogdc | royalty-free commercial (no resale of the raw sounds) | 20–30 GB per year — **too big for disk; pick 1 year or subsets later** | combat/foley/ambience | owner decides |
| 2 | freesound.org (CC0 filter only) | https://freesound.org | CC0 (per sound) | small | footsteps, swords | Claude as needed |
| 3 | Godot plugins already covered (Jolt is built in on 4.6; Debug Draw 3D, Phantom Camera, LimboAI installed) | — | — | — | nothing new needed | — |

Claude asks the owner once for: UAL2, Quaternius animals, KayKit, Kenney UI/audio and CMU subsets (≈ 300 MB in total). Disk check before each download.

### 3. Owner reference material (`C:\Users\Jonna\Documents\PA_plans\ref_videos\`)
`271e4a02-RDT_20261024_033700.jpg` (melee field battle), `55d3f055-RDT_20261025_084141.jpg` (BotW opening), `5a1c29e0-RDT_20261021_215748.jpg` (Unreal medieval town), `1205b946-image.jpg` / `49f04d13-image.jpg` / `b256d5b3-image.jpg` (anime half-timbered towns), `4cdc0fe6-image.jpg` (RuneScape Dragonwilds). They are translated into targets in A7.

---

## A. Strategy — the fastest path to "finished + AAA"

### A1. The core idea
AAA animation quality comes from a **small set of clean clips plus strong runtime systems**: foot locking/IK, root-motion consistency, short correct blends, contextual warping, hit-sync and look-at. It does not come from many clips. AC, For Honor and BotW use a few hundred excellent clips per character archetype and hide seams with procedural layers. We already have ~1 038 catalogued clips, of which 190 FAIL and 94 WARN. **The fastest route is subtraction:** build a "golden set" of clips that pass strict measured gates and route all gameplay through it. Disable everything else. A missing animation is better than a visible bad one, because a fallback to a passing clip is invisible while a sliding foot is not.

### A2. Cut / keep / replace
| Area | Decision |
|---|---|
| **Keep** | UAL (Quaternius) skeleton as the only humanoid rig. Player P5 locomotion transitions, P7 jump, authored combo/parry/riposte, F2 traversal (19-clip `UAL_Authored_Traversal.glb`), `procedural_rig.gd` foot IK, `wall_contact.gd`, the AAA manifest (19 add / 6 cmp / 83 skip), LifeLibrary sidecars, CrowdAnimLOD + VAT residents. |
| **Cut from gameplay** (disable via golden-set filter, don't delete files) | All 190 FAIL rows. Every WARN row until it is re-measured. All 83 AAA "skip" clips. Excluded IP packs. Ride lean clips until a rider/horse pass is done. Giant wasp ground locomotion (switch to hover-only flight or remove from spawns). |
| **Replace** | Sheep Run, Pig Walk/Run, horse/donkey Run/Gallop (hoof slip 114 cm/s, shoulder stretch 28 %), fox, dog, `Stagger_Back` (root motion), `Death01`/hit replacements with floor intersection, vault (leg penetration 6.7 cm). Order: existing PASS clip → UAL2/KayKit CC0 → Meshy → Blender hand fix. |
| **Cut scope** (Ready v1 "L" items stay out) | Conquest/sieges, >1 settlement, full taming minigame, mobile, Regions 2–4, 32 km map, faces beyond v1 + Meshy key NPC heads. |
| **Defer** | Motion matching (see A4). Full-body NPC IK (P6 measured 7–15 ms). |

### A3. The golden set
- **Source of truth:** new `kingdom/data/anim/golden_set.json` (format in C1.2). For each gameplay *slot* (e.g. `player.loco.run_start_fwd`, `villager.sit.idle`, `wolf.run`, `bandit.attack.light_1`), it lists one primary clip plus optional variants. Each clip carries measured metrics and a `status` of `gold`, `probation` or `banned`.
- **Gate:** a clip becomes `gold` only if it passes **every** automated metric in Section B for its category **and** a human/agent frame-sheet review (B3) recorded with the sheet path.
- **Runtime enforcement:** `assets.gd _ual_for()`, `life_library.gd`, `combat_moves.gd` and the creature tables resolve clip names through `GoldenSet.resolve(slot_or_clip)`. Resolution order: `banned` clip → the slot's gold fallback; no gold clip → the category fallback (e.g. `Idle`) **plus a `push_warning` once per slot** that lists the slot in `user://golden_missing.log`. In debug builds `--golden-strict` turns warnings into errors so QA finds every gap.
- **Size target:** player ~120 clips, humanoid NPC shared ~150, life/work ~80, per-creature 6–10 (idle ×2, walk, trot/run, turn-in-place L/R, eat/graze, hit, death). About 400 gold clips in total. Everything else stays on disk, unused.

### A4. Motion matching vs. blend space + transitions + foot locking — **recommendation: no MM for v1**
Evidence:
- Motion matching (Clavet, For Honor, GDC 2016: https://www.gdcvault.com/play/1023280/Motion-Matching-and-The-Road; Holden, Learned Motion Matching: https://theorangeduck.com/page/learned-motion-matching) only pays off with a **dense, unstructured mocap database**: long "dance cards" of starts, stops, plants, pivots and circles at every speed, ~10–30 min per gait/style, all from one actor. We don't have that. Our clips are short cut loops from mixed sources (CMU, UAL, KayKit, authored). MM on sparse data produces exactly the jitter and foot skating we are trying to remove.
- The Godot option is `godot-motion-matching` (MIT, GuilhermeGSousa, v0.2.x, "still under development", GDExtension, Godot ≥ 4.4: https://github.com/GuilhermeGSousa/godot-motion-matching, https://godotengine.org/asset-library/asset/3822). It is a native build to integrate and maintain, with unproven perf on a laptop that is already script-bound at 41–45 ms.
- **100STYLE** (Ian Mason, CC BY 4.0 according to derivative listings; verify on https://www.ianxmason.com/100style/ and https://zenodo.org/record/8127870 before use) is the one free dataset dense enough for MM. It is a **v2 option**: one Xsens actor, 100 styles, BVH. Retargeting it to UAL is several days of work.
- AC Unity/Origins locomotion (pre-MM) and BotW both use **state machines/blend spaces + stride warping + foot IK + start/stop/pivot transitions**, which is what we already have half-built (P5, `procedural_rig.gd`).

**Decision:** v1 uses an AnimationTree/BlendSpace locomotion with distance-matched starts/stops, pivots, turn-in-place, stride/speed warping, foot locking and IK. Codex timeboxes a **1-day MM spike after v1 ships** on the player only, using UAL+UAL2 loco clips. Promote it only if it beats the blend space on the B2 locomotion metrics.

### A5. Runtime systems that make clips look AAA (build or finish them; this is where most of the quality comes from)
1. **Foot locking** (new): during planted phases (from per-clip foot contact curves `foot_contacts` in the golden-set metrics), lock the foot's world position and solve with the existing `TwoBoneIK3D` legs. Release over 0.1 s at heel-off. Player and the ≤ 4 "contact" NPCs only. Kills residual slide.
2. **Stride/speed warping:** clamp playback-rate scaling to 0.85–1.15. Outside that, pick another clip or blend, and scale stride length via pelvis/foot IK (Godot has no built-in stride warping, so implement it in `procedural_rig.gd` `Stage`).
3. **Distance-matched starts/stops:** stop clips are chosen by predicted stopping distance (`v²/2a`), and playback is driven so the stop pose lands where the capsule stops (root-motion error ≤ 5 cm).
4. **Pivots and turn-in-place:** 90°/180° turn clips selected by input-angle delta. Upper body leads via `LookAtModifier3D` (Godot 4.4+: https://docs.godotengine.org/en/stable/classes/class_lookatmodifier3d.html).
5. **Motion warping for traversal:** `traversal.gd` `Driver` already warps root motion to vault/mantle targets. Add hand/foot contact IK targets from `traversal.json` contact frames (≤ 2 cm error).
6. **Synced hit pairs:** attacker hit frame from `combat_markers.json` → victim reaction starts within ≤ 2 frames. Directional reactions (front/back/L/R) × (light/heavy). Hit-stop 40–80 ms. Ragdoll blend on death (partial ragdoll exists: `docs/anim/advanced/tech/ragdoll_*`).
7. **Look-at/head & eyes:** `LookAtModifier3D` on player + nearby NPCs (≤ 8). Targets: speaker, threat, point of interest. Clamp yaw 70°, pitch 40°.
8. **Animation LOD:** the existing CrowdAnimLOD/VAT stays. Near full rig + IK ≤ 9 m; mid 9–45 m, AnimationPlayer at 30 Hz with no IK; VAT 45–120 m; sprites beyond. Godot `AnimationMixer.callback_mode_process` manual + ticker for mid tier.

### A6. Sourcing missing clips (in priority order)
1. **Existing PASS clips** in the repo (297 PASS rows plus traversal, life and authored sets). Always check `docs/qa/anim_qa_results.csv` first.
2. **Free packs on the same UAL rig (no retarget):**
   - **Quaternius Universal Animation Library 2**: CC0, 130+ animations (melee/armed combos, parkour, farming, fishing, zombie loco), same universal humanoid rig. Standard zip ≈ 9.7 MB, free. https://quaternius.itch.io/universal-animation-library-2 , https://opengameart.org/content/universal-animation-library-2 . **Highest-value download. Check first whether it's already in `assets/incoming/animations/`** (`git ls-files | grep -i ual2`). Owner approval needed if not.
   - UAL 1: CC0, already the base (https://quaternius.itch.io/universal-animation-library).
   - **KayKit Character Animations** (Kay Lousberg, CC0, https://kaylousberg.itch.io/): some are already in `aaa/`. Note hip_scale 1.336, so scale-check them.
3. **Mocap needing retarget (Blender + Expy Kit, or Godot BoneMap):** CMU Graphics Lab Motion Capture DB (free for any use, http://mocap.cs.cmu.edu/; already used via the UAL retarget). 100STYLE (CC BY 4.0, verify) for walk-style variety. Rokoko free packs: the owner must log in and download them himself, and **verify the per-pack licence on the download page** before use.
4. **Meshy via Claude:** preset animation library (3 credits/action) or text-to-motion (3 swift / 10 prime). Clips come on Meshy's rig → retarget to UAL in Blender (Expy Kit) → must pass the full B gates. Good for: kneel-revive, horn blow, calm-animal lean-in, carry-sack, door push, specific idles. Bad for: creatures (humanoid only), anything contact-precise.
5. **Hand-authoring in Blender** (Rigify/AnimAll installed) only for contact-critical or non-humanoid clips: sheep/pig/horse gaits (the analytic-limb approach that fixed Sheep Walk is proven, so reuse it), vault fix, synced pairs.

### A7. Reference targets from the owner's sheets (translated into specs)
| Ref | What it shows | Concrete target for us |
|---|---|---|
| **Melee field battle** (`271e4a02…jpg`, Bannerlord/KCD-like; heraldic yellow/red knight) | Third-person shoulder camera, directional sword swings, enemies reacting and falling, bodies left on the grass, minimal HUD (health/stamina bars bottom right, compass top) | **Combat set:** 4-direction light attacks (L/R/overhead/thrust) + 2 heavies + shield bash; directional hit reactions (front/back/L/R × light/heavy); stagger; block impact; parry; 3 deaths by direction blending into ragdoll; bodies persist 60 s. **Camera:** over-the-shoulder offset 0.45 m right, FOV 70, lock-on soft. **HUD:** bars bottom corner, compass top, nothing else in combat. **World:** tall wind-blown grass up to the knee. |
| **BotW opening** (`55d3f055…jpg`) | Leaving a cave into light, running across a green plateau, a vista of a castle in haze, picking up a branch and swinging it | **Exploration feel:** run → sprint → slide/vault without hitches; a vista "reveal" point near the Ashford start (camera pulls back, place name card); pick up any stick/tool as a weapon (pickup clip + equip ≤ 0.6 s); lush green, height fog with blue-violet tint (matches Style G); minimal HUD that fades out when idle 5 s. |
| **Unreal medieval town** (`5a1c29e0…jpg`) | Cobbled lanes, half-timbered houses, orange roofs, a castle on the hill, flowers in pots and beds, autumn trees, a cloaked hero running | **Town look/density:** Kingsreach/Ashford lanes 3–5 m wide with continuous façades (no gaps showing terrain), flower boxes/planters every ~8 m, a hilltop keep visible from every main street, a ring of houses around the market. Cloak secondary motion on the hero (spring bones via `procedural_rig.gd` prop springs). |
| **Anime half-timbered towns** (`1205b946`, `49f04d13`, `b256d5b3` `*_image.jpg`) | Blue-toned alleys, deep shade, a cloaked girl, a guard with a spear, a cart in the street, steep slate roofs and chimneys, town walls | **Mood/architecture:** cool blue shadow in alleys (already Style G rule: shadows blue-violet, never grey), lamp posts, carts and barrels as street props, guards on posts with idle variety (shift weight, look around), steep roofs with chimneys and dormers. Use as a colour-grade check for night/shade. |
| **RuneScape Dragonwilds** (`4cdc0fe6-image.jpg`, "making the downtime fun") | Chasing creatures across a meadow, NPC working at a crate wall, chickens, a river | **Things to do between quests:** catchable/huntable creatures with readable flee animations (C10 hunting), gathering spots, NPCs doing visible work at stations, small chickens/critters near homes. Every creature in gold has idle/walk/run/turn/flee/hit/death that pass B. |

---

## B. AAA animation quality bar + automated QA

### B1. Global metrics (computed per clip, in-engine, at 60 Hz sampling, on the UAL rig, root motion **on**)
| Metric | How | Gold | Probation | Ban |
|---|---|---|---|---|
| Foot slide (planted) | foot bone world speed while height < 4 cm and vertical speed < 0.1 m/s (`tools/anim/foot_slide.gd`) | mean < 0.03 m/s, max < 0.10 | mean < 0.05, max < 0.15 | worse |
| Ground penetration | min sole/toe height vs floor plane; per-segment vs obstacle collider for traversal | ≥ −1.0 cm | ≥ −2.0 cm | < −2 cm |
| Float | planted-phase sole height | ≤ 2 cm | ≤ 3 cm | > 3 cm |
| Pops | per-bone angular accel spike > 6× clip median, or > 30° change in 1 frame (`verify_clips.gd` + `motion.png`) | 0 | 0 | any |
| Loop seam | pose distance first vs last frame (rot ° sum major bones) and velocity continuity | ≤ 3° / ≤ 10 % vel | ≤ 6° | > 6° |
| Root-motion error | capsule travel vs root travel over clip | ≤ 3 cm/m | ≤ 5 cm/m | > 5 |
| Speed match | clip ground speed / gameplay speed (playback-rate ratio) | 0.9–1.1 | 0.85–1.15 | outside |
| Bone stretch/scale | bone length change | 0 % | ≤ 1 % | > 1 % |
| NaN/explosion | any non-finite or bone > 150° from rest | 0 | 0 | any |
| Contact IK error | hand/foot to declared contact target during contact window | ≤ 2 cm | ≤ 3 cm | > 3 cm |

### B2. Category criteria (in addition to B1)
- **Locomotion** (idle, walk 1.4, jog 3.5, run 5.0, sprint 7.0 m/s): starts reach speed in 0.3–0.5 s with no foot slide in the first step; stops land within ±5 cm of the predicted spot; 90°/180° pivots plant the outside foot (contact lock ≤ 2 cm drift); turn-in-place triggers at ≥ 45° and has no skating; blend 0.15–0.25 s full body; no `Loco_*Start` re-fire while braced at a wall; slopes ±20° pelvis drop ≤ 25 cm and no sinking; stairs show no hop. **Idle variety:** ≥ 3 idles per archetype, 6–15 s random fidgets, no synchronised fidgets within 10 m (phase offset random).
- **Combat:** hit frame = marker ±1 frame; victim reaction ≤ 2 frames after; directional reaction matches hit direction (≥ 95 % in the sim); block impact plays on every blocked hit; dodge i-frames match the visual (±2 frames); attacks track the target with ≤ 30° rotation warp during wind-up only; finishers are synced pairs with relative transform error ≤ 3 cm/3°; recovery cancel windows marked; hit-stop 40–80 ms.
- **Traversal** (vault, climb, mantle, ledge, wall): hand contact ≤ 2 cm, no body segment penetrates the obstacle > 1 cm, warped root ends within 3 cm of target, entry from walk/run/sprint without stopping, exit blends into loco at matching speed (no idle pop).
- **Interactions** (sit, talk, work, carry, doors, pickup): entry aligns to the anchor ≤ 3 cm/5° before contact (warp ≤ 0.3 s); seat pelvis ≤ 2 cm from seat; hands on tool/prop ≤ 2 cm (prop attached to bone); doors: hand on handle ≤ 3 cm at push frame, door motion starts at that frame; pickup: hand within 3 cm of the item at grab frame; talk: gesture loops vary, LookAt to listener.
- **NPC crowds:** no two adjacent NPCs in the same clip phase; LOD swap without visible pose pop (VAT ↔ rig cross-fade ≥ 0.2 s or at > 30 m); ≤ 0.3 ms extra per 20 NPCs.
- **Creatures/horses:** per-gait hoof slip mean < 0.05 m/s; shoulder/hip stretch 0 %; gait speed matches movement (B1); turn clips or procedural spine bend ≤ 25°; rider hands ≤ 3 cm to reins, pelvis ≤ 2 cm to saddle.
- **Death/ragdoll:** death clip → ragdoll blend over 0.15–0.3 s starting at the knee-buckle frame; no floor penetration > 2 cm at rest; no jitter > 1 cm after 2 s (sleep).
- **Face/look-at:** head/eye look-at clamps above; blink every 2–6 s; talk jaw/face card in sync ±2 frames with VO/text ticks.

### B3. Frame-sheet review rules (visual gate)
- Movie Maker windowed, `--fixed-fps 30`, side **and** front views, 1 m grid floor; `tools/qa/video_to_sheets.sh <frames> <out> 10`; read `sheet_*.png` and `motion.png`.
- Reject when any of these are seen: foot skating against the grid, knee popping straight/flip, elbow flip, hands through body/weapon, weapon not following the hand, head snapping, clothes intersecting legs at more than one frame, robotic symmetric arms, loops with a visible hitch, the "running in place" look.
- Record the verdict and sheet path into `golden_set.json` (`review: {sheet, verdict, by, date}`).

### B4. Automated pipeline (one command → PASS/FAIL per clip and per state)
- **New `kingdom/tools/anim/golden_gate.gd`** (Godot script tool, run **windowed**, not headless, because it needs real skinning):
  1. Load a list of clips (from `golden_set.json` or `--clips=` or `--lib=`) on a test UAL rig (player_young + a villager + armored) and per-creature rigs.
  2. For each clip, sample at 60 Hz with root motion applied and compute the B1 metrics (reuse code from `foot_slide.gd`, `verify_clips.gd`, `aaa_static_metrics.gd`, the existing catalog QA that produced `anim_qa_results.csv`).
  3. Read foot-contact windows from metrics (auto-detect: height < 4 cm and speed < 0.15 m/s, ≥ 3 frames) and write them back as `foot_contacts` for runtime foot locking.
  4. Write `docs/qa/golden/golden_results.csv` (`clip,rig,category,metric...,verdict,reasons`) and `golden_report.md`.
  5. Exit code 1 if any clip listed as `gold` fails.
- **State tests** (`kingdom/tools_qa/anim_states/*.tscn`, windowed): scripted input sequences record the live player/NPC: start/stop/pivot/turn, wall brace, vault at walk/run/sprint, combat exchange vs bandit, sit/stand, door, pickup, crowd walk past 20 villagers, wolf chase, horse ride. Each writes per-frame bone positions → the same metrics + Movie Maker frames → sheets. Script: `bash kingdom/tools_qa/anim_states/run_all.sh` → `docs/qa/golden/states/<case>/`.
- **Unit tests:** `kingdom/tests/test_golden_set.gd` (schema; every gameplay slot resolves to a gold clip; no banned clip referenced by `combat_moves.gd`, `life_library` LIBS, creature tables, `traversal.json`, `PREFERRED_CLIPS`).
- Run from `tools/qa/run_tests.sh 10` + `golden_gate.gd` before every animation commit.

---

## C. Work order for Codex

### C0. Resume protocol (read first, every session)
1. `cat docs/plans/AAA_PROGRESS.md` in the active worktree (`C:/Users/Jonna/Documents/PA_wt_w3`). The last line names the step and sub-step in progress.
2. `git -C "C:/Users/Jonna/Documents/PA_wt_w3" status --short | head; git log --oneline -5; df -h /c`; check AC power.
3. If the working tree is dirty with your own half-step: either finish it to its acceptance check or `git stash push -m "wip <step>"` and log the stash in AAA_PROGRESS.md. **Never leave the branch broken.** Every commit must parse (`test_scripts_parse`) and boot.
4. **Progress log format** (`docs/plans/AAA_PROGRESS.md`, append-only):
   `| 2026-10-27 14:05 | S2.3 | done | commit abc1234 | golden_gate: 41 gold / 3 fail (wolf_run) | next: S2.4 |`
   Columns: time, step id, status (`started` / `done` / `blocked:<why>`), commit, evidence, next. Commit the log with each step.
5. Branch scheme: work branch `aaa/finish` (from `claude/anim-aaa` after S0). One commit per sub-step, message `S<n>.<m>: <summary>`. After each **step**, push `aaa/finish` and merge into `claude/focused-curie-m09hbd` (fast-forward or `--no-ff`) only when its acceptance passes.

### S0. Make the uncommitted Codex WIP safe and commit it properly (½ day)
1. `cd C:/Users/Jonna/Documents/PA_wt_w3; git status --short > ../PA_plans/wt_w3_status_2026-10-26.txt` (record of all 1318 paths).
2. Safety snapshot (the backup ref is missing): `git stash push --include-untracked -- . ':(exclude)work' ` is **not** allowed (it would clear the tree). Instead:
   `git checkout -b backup/anim-codex-wip-2026-10-26` → `git add -A -- . ':!work' ':!*.log'` → `git add work/CLAUDE_HANDOFF_2026-10-25.md work/*.md` → commit "WIP snapshot (unreviewed)" → `git push -u origin backup/anim-codex-wip-2026-10-26` → `git checkout claude/anim-aaa` → `git checkout backup/anim-codex-wip-2026-10-26 -- .` → `git reset` (tree back to dirty, now backed up remotely). If the ref already exists remotely, skip this.
3. Create `aaa/finish` from `claude/anim-aaa`. Commit in logical pieces, each `git add` path-limited:
   - S0.a docs/QA: `docs/anim/aaa_wiring/AUDIT_2026-10-24.md`, `docs/qa/PC_QUALITY_STATUS_2026-10-26.md`, `docs/qa/WHOLE_LIBRARY_AND_TERRAIN_AUDIT_2026-10-25.md`, `docs/qa/anim_qa_report*.md`, `docs/qa/anim_qa_results*.csv` (strips/sheets only if total < 30 MB; else just CSV/MD).
   - S0.b animal fixes: `kingdom/assets/generated/animals/sheep_contact_walk.glb` + atlas, `critter.gd` sheep walk + speed tables (show the diff hunk first).
   - S0.c traversal pack: `kingdom/assets/incoming/animations_free2/traversal_authored/UAL_Authored_Traversal.glb` + sidecar.
   - S0.d living world: discretionary-visit penalty + `tests/test_discretionary_visits.gd`.
   - S0.e terrain: horizon coverage + `horizon_canopy_impostor.gdshader` + `tests/test_horizon_ground_coverage.gd`.
   - S0.f tools: QA tools and scripts (not `work/`). Skip `incoming/animals/*_2026102x/` experiment dirs (move them to `C:/Users/Jonna/Documents/ProjectAshes_art_staging/animal_experiments/` if > 20 MB; no deletion).
   - Leave `.import`/`.uid` churn and `*.log` unstaged; afterwards `git checkout -- '*.import'` only for files that existed before (never for new assets).
4. Accept: `git status --short | grep -v '^??' | wc -l` small and explained; one `--import` run (alone; check disk) → no errors; `tools/qa/run_tests.sh 10` has no new failures vs `claude/anim-aaa`; boot test passes. Push `aaa/finish`. Log in AAA_PROGRESS.md (create it, with these C0 rules at the top).

### S1. Merge `claude/anim-aaa` → main (½ day)
1. `git fetch origin; git checkout claude/focused-curie-m09hbd; git pull; git merge --no-ff aaa/finish` (it contains anim-aaa + S0).
2. Conflicts: hot files → take the anim-aaa side then re-apply any main changes by hand; keep CRLF in `player.gd` (`git diff --ignore-cr-at-eol` to compare).
3. Accept: tests + boot + `traversal_standalone.gd` Movie Maker run (wall head-on, vault) reviewed; push. Delete `claude/ag-merge` remotely only with owner OK (list it in E).

### S2. Golden set infrastructure (1–1.5 days)
1. **S2.1 schema** `kingdom/data/anim/golden_set.json`:
```json
{"_doc":"see docs/plans/AAA_FINISH_PLAN.md B",
 "version":1,
 "slots":{
  "player.loco.run_start_fwd":{"category":"locomotion","primary":"Loco_RunStart_F","variants":[],"fallback":"Run"},
  "wolf.run":{"category":"creature","primary":"Run","rig":"wolf","fallback":"Walk"}},
 "clips":{
  "Loco_RunStart_F":{"rig":"ual","source":"res://assets/.../UAL_Loco.glb","status":"gold|probation|banned",
    "metrics":{"slide_mean":0.02,"slide_max":0.07,"pen_cm":-0.4,"float_cm":1.1,"pops":0,"seam_deg":null,"rm_err_cm_per_m":2.1,"speed":3.4,"stretch_pct":0},
    "foot_contacts":{"foot_l":[[0,9],[24,33]],"foot_r":[[12,21]]},
    "review":{"sheet":"docs/qa/golden/sheets/Loco_RunStart_F/sheet_00.png","verdict":"pass","by":"codex","date":"2026-10-27"},
    "why":""}}}
```
2. **S2.2** `kingdom/scripts/actors/golden_set.gd` (class `GoldenSet`, static, loads once): `resolve(name:StringName, slot:="") -> StringName`, `is_banned(name)`, `contacts(name) -> Dictionary`, `slot(slot_id)`. Missing/banned → fallback + one `push_warning` + append to `user://golden_missing.log`. Flag `--golden-strict` (read in `game.gd` cmdline parse) → `push_error`.
3. **S2.3 hooks** (≤ 3 lines each, comment `# golden`): `assets.gd _ual_for()` (skip banned clips when building the library; keep aliases), `character_animator.gd` play path (`resolve` before `has_animation`), `life_library.gd` install (skip banned), `combat_moves.gd` row lookup, creature clip tables (`critter.gd`/`wolf.gd`/`monster.gd` speed tables), `traversal.gd` plan_for.
4. **S2.4 `golden_gate.gd`** as in B4. Seed: import `docs/qa/anim_qa_results.csv`; PASS → `probation`, FAIL → `banned`, WARN → `probation`. Nothing is `gold` until the gate + sheet review.
5. **S2.5 test** `tests/test_golden_set.gd`.
- Accept: game boots with strict off and logs missing slots; `golden_gate.gd --lib=player` writes CSV; tests green. Commit `S2.x`, push, log.

### S3. Player animation to gold (3–4 days) — the most visible part
Per slot group, in this order. For each: run the gate → fix/replace → frame sheets → mark gold.
1. **Locomotion:** idle ×3, walk/jog/run/sprint loops, starts F/L/R/B (P5), stops L/R, pivots 90/180, turn-in-place 90/180 L/R, crouch set, slope lean. Implement **foot locking** (A5.1) in `procedural_rig.gd`: new `FootLock` inner class reading `GoldenSet.contacts(clip)` against the current clip time. Lock world pos at contact start, IK weight 1 → 0 over 0.1 s at contact end. Disable while airborne/traversing/mounted. Stride warping (A5.2) next. **Accept B2 locomotion**: state test `loco_suite` shows slide mean < 0.03 m/s.
2. **Wall/traversal:** fix `Vault_Low/_B` leg penetration (raise the trailing knee-pole target, or a lead-foot IK target over the obstacle top during frames 17–23 in the Blender authoring script under `tools/blender/traversal/`; keep both rebuild and checker), `Ledge_Hang_Idle` hand 2.4 cm → ≤ 2 cm, running vault `Vault_Run`. Clean reimport of the traversal GLB. Accept B2 traversal on walk/run/sprint.
3. **Combat:** `Stagger_Back` root motion → re-extract with root motion on; or replace with `Stagger_Back_Mocap` (AAA cmp) if better. `Block_Hit`, directional hits, 3 deaths → ragdoll blend, pickup-and-swing (BotW ref: `Pickup_Item` + equip ≤ 0.6 s). Hit-stop 40–80 ms. Accept B2 combat in `feel_clip.tscn` + duel sheet vs the melee reference (side by side in `docs/qa/golden/ref_compare/combat.md`).
4. **Camera/HUD per A7:** shoulder offset, FOV 70, soft lock, idle HUD fade 5 s (data/settings only; `hud.gd` visibility).
- Accept: `run_all.sh` player cases all PASS; owner-facing sheet page `docs/qa/golden/PLAYER.md` with 1 sheet per state.

### S4. Humanoid NPC + crowds to gold (2–3 days)
- Soldier/bandit rows from the AAA manifest (Bandit_Light_1–4, Duel_*, Guard_Deflect, Guard_Break, Hit_Head_L/R) → gate + markers (`build_markers.py`).
- Villager life/work: sit (Life_AAA_Sit_*), talk, work stations, carry, doors, pickup. Anchor alignment ≤ 3 cm/5° (warp in the life driver).
- Crowd phase randomisation + idle variety; LookAtModifier3D on the ≤ 8 nearest talkers.
- Accept: B2 interactions/crowds; perf ≤ 0.3 ms/20 NPCs (`anim_cost_probe.tscn`).

### S5. Creatures and horses (2–3 days)
- Re-author with the proven analytic-limb tool (sheep walk): Sheep Run, Pig Walk/Run, Horse/Donkey Walk/Trot/Gallop, Fox, Dog. Wolf: gate the existing set. Wasp: hover-only or remove from spawns.
- Rider pass: reins/saddle IK (B2 creatures).
- Accept: every creature slot gold or the creature is removed from spawn tables (`ambient_life.gd` data) for v1.

### S6. Meshy key NPCs (1–1.5 days)
For each of Brannoc, Oriel, Hesk, Hollis, Hesta and Aldric (`C:/Users/Jonna/Documents/ProjectAshes_art_staging/npc_meshy/<name>/rigged.glb`):
1. Blender 5.2 headless script based on `tools/blender/hero_tier_a/` (the same route as hero v2): import → delete the Meshy armature, keeping the mesh → scale/align to the UAL rest pose (A-pose; height from the concept) → parent with automatic weights to the UAL armature → weight-fix the cloak/skirt (Aldric, Oriel, Brannoc: add 2–3 cloak spring bones, reusing the hero cloak setup if present) → decimate LODs at 12 m/30 m (~10k/4k/1.5k tris) → export `kingdom/assets/generated/characters/npc_tier_a/<name>.glb`.
2. Hook them up where the NPC is spawned (companions from PR #9; Hollis/Hesta/Aldric in `TownRoster`/story directors) via a `NpcTierA.body_for(npc_id)` lookup (new file; same pattern as `hero_tier_a.gd`).
3. Accept: in-engine lineup render + walk/idle/talk sheets per NPC; gate-clean skinning (no candy-wrapper at elbows/knees, cloak no leg intersection over 1 frame); the owner rates ≥ 7.
4. Disk: GLBs ≤ 15 MB each.

### S7. Merge the cloud PRs #14, #8, #13, #9, #12, #11, #10, #7 (in that order; 1.5–2 days)
For each: `gh pr checkout <n>` → `git rebase origin/claude/focused-curie-m09hbd` → resolve conflicts (#12 `critter.gd`: keep the anim speed tables + golden hooks, add the hunting signals) → `bash kingdom/tools_qa/v1/run_v1.sh boot,intro,menus,st_birth,st_a1` (after #14 exists) → gdUnit → `gh pr merge <n> --merge` → log. #13: route its missing clips (revive kneel, Down pose) into golden slots → S9 Meshy list. #3 (old Codex, feel follow-up): cherry-pick only block facing/wolf turns if they still apply; close otherwise.

### S8. Remaining Ready-v1 tasks (4–6 days; specs in `READY_V1.md`)
Order: **C3** found-a-camp (needs #8) → **C4** growth + ledger → **C5** lordship → **C8** taming (after #13; animations from golden slots `tame.calm_lean_in`, `wolf.follow`, `wolf.guard`) → **C9** raids → **C12** Acts 2–5 fixes → **C14** whole-state save soak (last). Each: its own sub-branch `v1/<task>` off main, tests + bot stage as in the spec, merge, log. Add the Dragonwilds "downtime" items as acceptance on C10/C8: ≥ 3 catchable/huntable species near Ashford with gold flee/hit/death clips.

### S9. Perf to 60 fps (3–4 days; `PERF60_BRIEF.md`)
Steps 2–7 (sprite pass rewrite → BodyRegistry → critter director → NpcTicker → VillagerPool → results). Re-measure step 1 (ResidentIndex) **on AC**; drop it if < 1.0×. Each step: `run_hitch.sh` A_stand_1440 + B_walk_1440, 2 runs each, record AC/battery. Accept as in PERF60 §5. Animation LOD (A5.8) mid-tier 30 Hz is part of NpcTicker.

### S10. World polish (2–3 days)
Terrain3D multi-slot blend (hard-edged patches), remove flat planes, time-of-day pinning near towns; town dressing to the A7 targets (continuous façades, planters every ~8 m, keep visible from main streets, carts/barrels/lamps, guards with idle variety); vista point at the Ashford start; tall grass in the battle meadows. Flip defaults only after the owner's OK. Accept: screenshot set `docs/qa/golden/world/` compared side by side with the ref sheets.

### S11. Release gate
`run_v1.sh` full sequence headless + local windowed 60-min bot on HIGH (fps p95, 0 freezes > 250 ms, flat memory) + `golden_gate.gd --all` with 0 failures among gold + `--golden-strict` boot clean.

Rough total: ~25–33 Codex-days. Animation (S2–S6) is front-loaded so the game *looks* AAA early.

---

## D. Claude in parallel (Meshy and other Claude-only work)
| Task | When | Credits (owner OK needed) |
|---|---|---|
| Golden gaps from S3–S5/S7 (e.g. revive kneel, Down idle, horn blow, calm-animal lean-in, door push, carry sack, sit-on-ground eat, pickup-from-ground, pray, sweep): Meshy preset actions on a rigged UAL-proportioned proxy, retarget-ready FBX/GLB | after S2 lists the missing slots | ~15 clips × 3 = 45; text-to-motion prime for 5 special ones = 50 → **~95** |
| Re-check the 6 key NPCs; if a Meshy re-texture/fix is needed (Hesk hands, cloaks) | after S6 review | ≤ 2 × 10 = 20 |
| Extra named NPCs (Mab Larkin, Lucan from PR #9 follow-ups) | after S7 | 2 × 23 = 46 |
| Reference/review: read Codex's frame sheets and gate reports, do the B3 visual verdicts on contested clips | ongoing | 0 |
| Owner-assisted downloads: UAL2 (≈ 9.7 MB, CC0), optionally 100STYLE (CC BY 4.0, large; v2) | when the owner approves | 0 |
Monthly budget ~180 credits: this plan uses ~115–160, so keep ~20 in reserve.

## E. Risks and owner decisions
1. **The WIP is not backed up remotely** (the backup ref was not found). S0.2 fixes that first. If the laptop disk fills (23 GB free now), the WIP is at risk, so do S0 before anything else.
2. **Approve:** UAL2 download (CC0, ~9.7 MB) and the Meshy budget (~95–160 credits over the next month).
3. **Approve:** motion matching deferred to after v1 (recommendation A4).
4. **Approve:** creatures without gold clips are removed from v1 spawns, and the wasp becomes hover-only or is cut.
5. Still open from before: physics 30 Hz on PC_HIGH; flip Terrain3D + Valencious defaults; delete `claude/ag-merge`.
6. Risk: Codex runs out mid-step. Mitigated by C0 (one commit per sub-step + progress log).
7. Risk: Blender automatic weights on long cloaks (Aldric, Oriel, Brannoc). Fallback: cloak as a separate mesh with spring bones, or shorten the cloak.

## Sources
- Quaternius UAL2 (CC0): https://quaternius.itch.io/universal-animation-library-2 , https://opengameart.org/content/universal-animation-library-2 , https://digitalproduction.com/2026/02/10/130-animations-one-rig-zero-drama/
- Quaternius UAL1: https://quaternius.itch.io/universal-animation-library , https://store.godotengine.org/asset/quaternius/universal-animation-library/
- 100STYLE (CC BY 4.0 per derivative listings — verify): https://zenodo.org/record/8127870 , https://arxiv.org/pdf/2201.04439 , https://booth.pm/en/items/8868549
- Godot Motion Matching (MIT): https://github.com/GuilhermeGSousa/godot-motion-matching , https://godotengine.org/asset-library/asset/3822 , https://godotengine.org/asset-library/asset/edit/16087
- Motion matching background: https://www.gdcvault.com/play/1023280/Motion-Matching-and-The-Road , https://theorangeduck.com/page/learned-motion-matching
- CMU Mocap: http://mocap.cs.cmu.edu/ ; KayKit (CC0): https://kaylousberg.itch.io/
- Godot docs: https://docs.godotengine.org/en/stable/classes/class_lookatmodifier3d.html , https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html
