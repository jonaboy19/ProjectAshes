# Execution brief: AAA mocap wiring + wall-contact / traversal realism (Opus plan 2026-10-23, one Sonnet executor)

Key finding: the 10 Antigravity packs hold 108 clips, but ~25 repeat the same source take/time range under different names, and many names are wrong (e.g. "Ledge_Shimmy" is a running turn; all "Magic_Chantless" are sword/run takes; "Wall_Climb_Mantle" = the vault clip). Wire ~45 distinct, plausible clips, **each gated on frame-sheet review**; record the rest as skipped with reasons. Don't wire all 108 blindly.

**Branch/worktree.** Work in `C:/Users/Jonna/Documents/PA_wt_w3` only after the world agent there has finished; branch `claude/anim-aaa` from the latest `origin/claude/focused-curie-m09hbd`. Reuse its `.godot` cache. One Godot instance at a time (laptop RAM is tight). Never `--headless` for Movie Maker. `export MSYS_NO_PATHCONV=1`, Windows paths with `git -C`. Commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. PC focus only.

**Hot files** (`player.gd`, `character_animator.gd`, `villager.gd`, `soldier.gd`, `monster.gd`, `wolf.gd`, `mount_controller.gd`): new logic in new files, hooks of a few lines only; `player.gd` is CRLF — keep it CRLF. Rebase before every commit; if a hot file changed underneath you, stop and report.

## 0. Facts (don't re-derive)
- **Shared library:** `kingdom/scripts/world/assets.gd` `_ual_for()` (~643) merges `UAL_FILES` into one `AnimationLibrary` per skeleton path; first name wins; `res://assets/incoming/animations/` files get `:root` position track disabled (in place); aliases only if missing. `CharacterAnimator.PREFERRED_CLIPS` overrides.
- **Villager life clips:** `kingdom/scripts/living_world/life_library.gd` installs every clip from `LIBS` (`animations/life/*.glb`), each with `<glb>.life.json` sidecar `{library, fps, clips:{Name:{category, loop, layer, props, enter, exit, blend_in, blend_out, events, anchor}}}`.
- **Combat:** `kingdom/scripts/combat/combat_moves.gd` rows `[anim, damage, lock, hit, speed, cost, knockback]`; hit frames in `animations/combat/combat_markers.json` (built by `tools/anim/combat/build_markers.py`).
- **Traversal:** `kingdom/scripts/actors/traversal.gd` (probe/classify/plan + `Driver`) reads `kingdom/data/movement/traversal.json`: vault (`Vault_Low/_B`), mantle low/high, ledge grab/hang/climb/drop, ladder (`interaction/kinds/ladder.gd` → `begin_ladder`), step-up (`step_assist`), auto-vault ≥ 4.5 m/s.
- **Foot IK:** `kingdom/scripts/actors/procedural_rig.gd` (`TwoBoneIK3D` + `Stage extends SkeletonModifier3D` for pelvis drop/foot tilt, torso spring, prop springs), player only (`player.gd:591`). **No NPC IK** (P6 measured 7–15 ms/frame) → no new SkeletonModifier3D on NPCs.
- **Wall contact:** none today. `player.gd` ~826–846: `move_and_slide()` → `_animator.update(planar velocity)` → `_update_lean()`. **Hypothesis for "running in place"** (confirm with a recording first): stick into a wall keeps `entry_speed < 0.3`, `_idle_time` grows, `_update_locomotion_transition()` (~1703) re-fires `Loco_RunStart_F`/`Loco_WalkStart_F` each time the transition ends.
- **AAA status:** staged, unwired (`kingdom/assets/incoming/animations/aaa/SOURCES.md`; CMU mocap on Quaternius UAL rig, CC0; a few KayKit CC0). Excluded IP-flavoured packs on `antigravity/aaa-mocap-animations` (Bending ×3, Mythic_Martial, Master_Combat_Universe, Weapons_Umbrella_Donghua) — **don't import without owner OK**.
- **Name collisions** (existing wins, AAA shadowed): `Jump_Land_Soft`, `Ledge_Shimmy_L/R`, `Bow_Draw`.
- **Same source range (duplicates):** 02_07 0.5–1.7 Sword_Light_Attack_01 = Knight_Pommel_Strike_Stun; 02_07 5.6–7.4 Sword_Heavy_Charge_Chop = Knight_Decapitation_Execution; 14_01 6.0–7.4 Head_Flinch_R = _L (mirror); 14_03 3.2–4.5 Guard_Break_Stumble = Hit_React_Gut_Wind_Knockout; 127_05 0.4–1.6 Assassin_Smoke_Vanish_Drop = Cast_Chantless_Blink_Step; 127_05 0.4–1.8 Sloped_Roof_Tile_Slide = Sword_Sprint_Dash_Attack; 127_15 0.2–1.3 Run_Turn_Bank_L = Ledge_Shimmy_L = _R (2.45 m travel in 1.1 s — not a shimmy); 127_25 0.3–1.8 Vault_Hurdle_Mocap = Wall_Climb_Mantle; 140_01 1.8–3.0 Sword_Plunge_Aerial_Attack = Assassin_Aerial_Drop_Impale; 143_01 0.0–0.8 Run_Natural = Knight_Shield_Rush_Charge; 144_07 0.24–1.4 Parry_Left_Deflect = Parry_Right_Deflect (mirror) = Knight_Greatshield_Guard_Stance (marked loop, is one-shot) = Cast_Chantless_Barrier_Conjure; 144_07 1.8–3.4 Blade_Clash_Lock = Guard_Impact_Heavy_Stagger.
- **LivingWorld overlap:** 17 of 28 clips re-cut BVHs already in `UAL_Life_Mocap.glb` (79_01, 79_04, 79_55, 79_87, 79_25, 79_34, 79_16, 79_33, 79_12, 79_17, 79_68, 62_07, 22_03, 14_24, 139_01, 139_02, 91_09).
- **Floor red flags:** `Hit_React_Leg_Sweep_Trip` min_foot −0.067 m; `Knockdown_*` and `Wall_Impact_Splat_Bounce` floor_fix −0.10…−0.13; KayKit clips hip_scale 1.336.

## (a) Mapping
Rules: never overwrite an existing clip name; never replace owner-tuned player clips (authored combo, parry/riposte, directional hits, P5 loco transitions, P7 jump, F2 traversal). Every accepted clip gets a game name (removes IP names). ADD = wire; ADD? = only if the frame sheet confirms content; CMP = replace only if clearly better (list for owner); SKIP = reason. Roles P player, S soldier/bandit (`army/soldier.gd`), V villager, E enemy humanoid.

| Pack / clip | New name | Role / slot | Status | Reason |
|---|---|---|---|---|
| Locomotion Walk_Natural | Life_Walk_Natural | V walk style | ADD? | player walk is phase-synced; don't touch |
| Run_Natural | Soldier_Charge_Run | S charge loop 0.8 s | ADD? | dup of Knight_Shield_Rush_Charge |
| Run_Stop_Plant | — | P stop | CMP vs Loco_RunStop_L/R | P5 tuned |
| Run_Quick_Stop | — | — | SKIP | 127_05 family, uncertain |
| Run_Turn_Bank_L | Npc_Run_Bank_L (+mirror) | S/V run turn | ADD? | real content of "Ledge_Shimmy" |
| March_Soldier_Loop | Soldier_March | S patrol | CMP vs Life_Walk_March | same 138_01 |
| Jump_Leap_Takeoff / Jump_Land_Soft | — | — | SKIP | P7 tuned; name shadowed |
| Vault_Hurdle_Mocap | Vault_Run | P auto-vault ≥ 4.5 m/s | ADD? | measure touch_down/handover |
| Ladder_Climb_Mocap | Ladder_Climb_Up_Mocap | P ladder | CMP vs Ladder_Climb_Up | re-measure clip_speed |
| Sword_Slash_Combo_A/B | Bandit_Combo_A/B | S/E attacks | ADD | needs markers |
| Hit_React_Chest_Mocap | Villager_Hit_Chest | V hit | ADD | |
| Combat_Duck_Dodge | Soldier_Duck | S evade | ADD? | |
| Combat_Shield_Block | — | — | SKIP | 3.5 s one-shot; Idle_Shield exists |
| Combat_Adv Parry_High_Deflect | Duel_Parry_High | S parry | ADD | player keeps Sword_Parry |
| Parry_Sword_Riposte | Duel_Riposte | S counter | ADD | |
| Combat_Fencing_Lunge | Duel_Lunge | S/E lunge | ADD | |
| Combat_Shield_Bash_Stagger | Soldier_Shield_Bash | S | ADD | |
| Combat_Dodge_Sidestep_L/R | Soldier_Sidestep_L/R | S | ADD | player dodge is tuned roll |
| Combat_Chains Sword_Light_Attack_01–04 | Bandit_Light_1–4 | S/E chain | ADD | player keeps authored |
| Sword_Heavy_Charge_Chop | Bandit_Heavy_Chop | S heavy | ADD | drop Knight_Decapitation dup |
| Sword_Sprint_Dash_Attack | Bandit_Run_Attack | S | ADD? | sheet decides |
| Sword_Roll_Counter_Poke / Sword_Plunge_Aerial_Attack | — | — | ADD? / SKIP | 140_01 unknown; Plunge dup |
| Parry_Left_Deflect (+R mirror) | Guard_Deflect_L/R | S block impact light | ADD | canonical |
| Guard_Break_Stumble | Guard_Break | S guard break (now Block_Hit) | ADD | canonical |
| Blade_Clash_Lock | Guard_Impact_Heavy | S heavy block impact | ADD | canonical |
| Combat_Roll_Forward | — | — | SKIP | roll tuned |
| Combat_Backstep_Hop | — | — | SKIP unless sheet shows backstep | |
| Combat_Classes Assassin_Shadow_Crouch_Creep | Crouch_Creep | P crouch move | CMP vs Crouch_Fwd | |
| Knight_* ×4, Assassin_Throat_Slit / Ledge_Pull_Down / Aerial_Drop_Impale / Smoke_Vanish | — | — | SKIP | duplicates |
| Combat_Knockbacks Knockback_3Step_Stumble_Recoil | Stagger_Back_Mocap | S/V | CMP vs Stagger_Back | authored wins ties |
| Knockback_Airborne_Blowback | — | — | SKIP | ragdoll owns launches |
| Knockback_Heavy_Slide_Brake / Guard_Impact_Heavy_Stagger | — | — | SKIP | dups |
| Combat_Reactions Hit_React_Head_Flinch_R/L | Hit_Head_R/L | S/E light-hit alt (upper layer, 40 %) | ADD | |
| Hit_React_Gut_Wind_Knockout | — | — | SKIP | dup |
| Hit_React_Leg_Sweep_Trip | — | — | SKIP | foot below floor |
| Knockdown_Hard_Landing / Ground_Lie_Idle / Roll_Getup | Getup_Roll (getup only) | S getup after ragdoll | ADD? | verify no sink |
| Wall_Impact_Splat_Bounce | Wall_Impact | P/S hit into wall; P sprint-into-wall | ADD? | floor −0.13; verify |
| Combat_Weapons 2H_Greatsword_* ×5 | GS_Overhead/Slash/Spin/Thrust/Guard | S/E two-hand brutes | ADD (S) | KayKit hip_scale; check scale/feet |
| DualDaggers_* ×3 | Dagger_Flurry/Cross/Stab | E rogue | ADD | only if a dual-dagger enemy exists, else park |
| Bow_Draw / Bow_Aim_Idle_Loop / Bow_Release_Recoil | — | — | SKIP | authored bow set; collision |
| LivingWorld Tavern_Sit_Idle / _LegSwing / _Fidget_Ponder | Life_AAA_Sit_Idle / _Sit_LegSwing / _Sit_Ponder | V sit | ADD | new takes |
| Tavern_Stand_To_Sit / Tavern_Sit_To_Stand | Life_AAA_Sit_Enter / _Sit_Exit | enter/exit | ADD | 0.53 m travel: capsule must follow |
| Social_Laugh_Banter, NPC_Direct_Point_Wave, Brawler_Tavern_Jab, Worker_Carry_Cargo | Life_AAA_Laugh_Banter / _Point_Wave / _Tavern_Brawl / _Carry_Cargo | social/react, social/react, social/tavern, carry/full | ADD | new takes |
| Wounded_Limp_Walk / Tavern_Drunk_Stumble | — | walk style | CMP vs Life_Walk_Limp / _Drunk | |
| Social_Handshake | — | — | ADD? | single person? |
| other 15 LivingWorld | — | — | SKIP | same BVHs as Life_Mocap |
| Magic_Chantless all 6 | — | — | SKIP | relabelled sword/run/shield |
| Traversal_Rooftops Roof_Gap_Leap_Roll | Land_Roll_Mocap | P high landing roll | CMP | |
| Roof_Ridge_Balance_Walk | Balance_Walk | P balance stance | ADD? | may be a plain walk |
| Ladder_Climb_Down_Loop | Ladder_Climb_Down_Mocap | P | CMP vs Ladder_Climb_Down | |
| Wall_Climb_Mantle / Sloped_Roof_Tile_Slide / Ledge_Shimmy_L/R | — | — | SKIP | mislabelled dups |

Record every decision in the manifest `"status"` + one-line `"why"`.

## (b) Files and formats
1. **`kingdom/data/anim/aaa_clips.json`:** `{"_doc":…, "packs":{"res://assets/incoming/animations/aaa/UAL_AAA_Combat_Adv.glb":{"Parry_High_Deflect":{"as":"Duel_Parry_High","role":"soldier","status":"add|cmp|skip","why":"…","loop":false,"layer":"full|upper","mirror_of":null}}}}` — all 108 clips listed.
2. **`assets.gd`:** after the `UAL_FILES` loop in `_ual_for`, call `AaaClips.merge_into(lib, sk)` in new `kingdom/scripts/actors/aaa_clips.gd`: load each pack once, duplicate only `add` (or promoted `cmp`) clips, rewrite track paths like `_ual_for`, disable `:root` position, add under `as`; refuse existing names (`push_error`). Don't append AAA files to `UAL_FILES` (memory).
3. **LivingWorld:** derived `animations/life/UAL_Life_AAA.glb` via `python kingdom/tools/anim/glb_edit_clips.py edit` on a copy (delete skips, rename `Life_AAA_*`); sidecar `UAL_Life_AAA.glb.life.json` like `tools/anim/life/make_life_cmu_sidecar.py`; append to `LifeLibrary.LIBS`; villagers pick by category (`clips_in("rest/sit")` …); a one-line `villager.gd` addition only if lists are hard-coded (~109–146).
4. **Combat:** `combat_moves.gd` new `BANDIT_ROWS` and `DUEL` tables; markers in `combat_markers.json` (build_markers.py or `tools/anim/measure_events.gd`: hits, windup_end, hit_start/end, cancel_window). `soldier.gd` hooks (minimal): ~352 `_hit_side` picks `Hit_Head_L/R` 40 % on light L/R hits; guard break → `Guard_Break` instead of `Block_Hit`; getup after ragdoll → `Getup_Roll` if verified.
5. **Traversal:** `traversal.json` + mirrored `DEFAULTS` in `traversal.gd`: `"vault": {"clip_run":"Vault_Run","run_min_speed":5.0,"touch_down_run":…,"handover_run":…}`; new blocks `wall_contact`, `slope_slide`, `balance`; `plan_for()` picks `clip_run` at `entry_speed ≥ run_min_speed`.
6. **New `kingdom/scripts/actors/wall_contact.gd`** (RefCounted, owned by the player): pure `classify(input_dir, wall_normal, speed, dist) -> StringName` + `tick()` (slide collisions + one forward ray).
7. **`procedural_rig.gd`:** optional arm chain — second `TwoBoneIK3D` with 2 settings (`upperarm_l/lowerarm_l/hand_l`, right), same setup as legs, targets + poles; lazy, only when `always_near`; API `set_hand_brace(side:int, point:Vector3, normal:Vector3, weight:float)`; torso Stage `set_torso_yaw_offset(rad)`.
8. **`player.gd` hooks:** after `move_and_slide()` → `_wall.tick(...)`; in `_update_locomotion_transition` treat `dir` as zero while `_wall.blocked()`; wall lean into `_update_lean()`; slope pitch; slope-slide + balance states.

## (c) Wall contact + traversal realism (player)
- **Detection:** slide collisions with `|n.y| < 0.3`; one chest ray (1.2 m) forward, length `0.35 + speed*0.12`, mask 1; `push = input_dir.dot(-n_flat)`.
- **States:** NONE; APPROACH (ray hit, push > 0.7 → decelerate to stop 0.25 m from wall); BRACE (blocked, push > 0.7, speed < 0.3); GLANCE (push 0.2–0.7 while sliding); IMPACT (≥ 6.5 m/s, push > 0.85).
- **BRACE:** loco → idle, no start clip; hand IK to wall at shoulder height +0.05 m along normal, contact-side hand (both if head-on); blend in 0.15 s / out 0.2 s; only if wall 0.45–0.7 m from shoulder; lean 0.04 rad; off while attacking, blocking, carrying, mounted, traversing, first-person.
- **GLANCE:** torso yaw away up to 25°×(1−push); roll 0.05 rad away; speed kept.
- **IMPACT:** `Wall_Impact` if verified else `Hit_Heavy_Front` ×1.2 full-body; small camera shake (combat_feel limits); stamina −5; cooldown 1 s. Soldiers knocked into a wall within 1 m: `Wall_Impact` instead of ragdoll (logic only).
- **Slopes/steps:** keep foot IK; `_update_lean` pitch += `clamp(-floor_normal.dot(move_dir)*0.25, -0.08, 0.08)`; verify step_assist on stairs.
- **Slope slide:** on floor, `floor_normal.y < cos(40°)`, not stairs → accelerate g·sinθ·0.6, cap 7 m/s, steering ±30 %, jump allowed; stance `"slide"` in `CharacterAnimator.STANCES` with first existing of `Slide_Loop`/`Sloped_Roof_Tile_Slide` (check `has_clip`; that AAA clip is probably a run → fallback `Crouch_Idle`, foot IK suppressed); exit via `Jump_Land_Soft` or loco stop.
- **Edge balance:** feet ray hits, two side rays (±0.25 m) miss > 0.3 m drop → stance `"balance"`, speed cap 1.2, `Balance_Walk` if verified else slowed walk, arms out via hand-IK targets at shoulder ±0.6 m lateral, torso sway.
- **Ledge-edge stop (walking):** drop > 1.2 m from a downward ray 0.4 m ahead → 0.3 s brake at the edge unless stick held 0.4 s.
- Config: `"wall_contact": {"ray_h":1.2,"lead":0.35,"lead_per_speed":0.12,"brace_push":0.7,"glance_push":0.2,"impact_speed":6.5,"reach_min":0.45,"reach_max":0.7,"blend_in":0.15,"blend_out":0.2,"lean":0.04,"torso_yaw_max_deg":25}` + similar `slope_slide`, `balance`.

## (d) Verification
- **Baseline first:** add cases to `kingdom/tools_qa/traversal/traversal_standalone.gd` (wall head-on, 45°, sprint); Movie Maker `--write-movie <png> --fixed-fps 30 --quit-after N`; sheets `tools/qa/video_to_sheets.sh <frames> docs/anim/aaa_wiring/<case> 10`; READ every `sheet_*.png` + `motion.png` (skill `ashes-video-review`).
- **Static metrics (cheap, first):** add AAA GLBs to `verify_clips.gd` LIBS (NaN, feet under floor, bone > 150° from rest, explosions); `tools/anim/foot_slide.gd -- --glb=<glb>`; `glb_edit_clips.py audit` (no double pelvis travel).
- **Life:** `tools_qa/living_world/clip_gallery.tscn -- --clips=Life_AAA_… --view=side` + CMP pages side by side.
- **Soldier combat:** `tools_qa/combat/feel_clip.tscn` with bandit using new rows; check `CLIP f=` events vs sheets.
- **Traversal/wall cases:** head-on, glancing, sprint impact; stairs 0.2 m; 20° and 45° slopes; 0.2 m beam; running vault; ladder; ledge-edge stop.
- **Acceptance:** foot slide planted mean < 0.05 m/s, max < 0.15; feet ≥ −2 cm; no single-frame spikes in `motion.png` at blends/loops/IK toggles; blends full 0.15–0.25 s, upper 0.10–0.15 s; hit frame ±1 frame of marker, reaction within 2 frames; wall: no `Loco_*Start` while braced, legs idle within 0.15 s, hand within 3 cm of wall, no elbow flip/jitter over 1 s hold; slopes/stairs: no sinking, pelvis drop ≤ 25 cm, no stair hop; CMP accepted only if better on metrics AND looks better — list CMP results for the owner.
- **Perf:** ≤ 0.3 ms/frame extra with 20 NPCs: `tools_qa/living_world/anim_cost_probe.tscn` (40 rigs) + 20-soldier `feel_clip`/`tools/qa/bench` before/after; NPC code logic-only; report library build time + process memory on first `_ual_for` (flag > ~50 MB).

## (e) Tests (`tools/qa/run_tests.sh 10`, one Godot at a time)
- `kingdom/tests/test_aaa_clips.gd`: every manifest clip exists in its `.clips.json`, all 108 listed; `as` unique and no collisions (reuse `tools/anim/check_unique_clips.py` logic; also run the script over `assets/incoming/animations`); no Knight/Assassin/Chantless-style names accepted; every combat row anim has a marker.
- `kingdom/tests/test_wall_contact.gd`: `classify()` head-on → BRACE, 45° → GLANCE, sprint → IMPACT, walking away → NONE, out of reach → no hand.
- Extend `kingdom/tests/test_traversal.gd`: run-vault by speed; slope-slide threshold; balance on 0.2 m beam vs 1 m wall top; ledge-edge probe.
- `kingdom/tests/test_life_aaa_sidecar.gd`: `LifeLibrary.info("Life_AAA_Sit_Idle")` has category/enter/exit.
- Plus `test_scripts_parse` and the boot test.

## (f) Risks — don't guess
- Clip content (CMU subjects 127, 140, 144, 090, 104, 013_33) unverified; names often wrong → every ADD?/CMP decided from frame sheets.
- IP-flavoured packs: excluded; ask the owner.
- Wall bug cause is a hypothesis — confirm with the baseline recording first.
- Hot-file ownership: rebase; stop and report on conflicts.
- Godot 4.6 `TwoBoneIK3D` arm setup: mirror the leg setup exactly; report if the elbow pole is unclear.
- KayKit Weapons (hip_scale 1.34) may differ in pelvis height/scale on MakeHuman/G6 — check both rigs.
- Getup/wall-impact floor fixes −0.04…−0.13 m may still sink.
- First `--import` of 10 GLBs costs memory — run it alone.
- Licence: keep `SOURCES.md` attribution; add `UAL_Life_AAA.glb` + the manifest.

Finish: push `claude/anim-aaa`, fetch + merge into `claude/focused-curie-m09hbd`, push. Report: mapping decisions (added / CMP results for owner / skipped), wall-contact + traversal results with sheet paths + your read, perf numbers, tests, commits.
