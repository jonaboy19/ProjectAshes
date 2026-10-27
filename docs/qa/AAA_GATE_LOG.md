
## 2026-10-28 · player lane · ladder climb (ref 02) — FAIL (improved, not shippable yet)
Files: docs/qa/golden/slice/ladder_before_vs_ref02.jpg (before, slice route), ladder_climb_after.jpg + ladder_after_vs_ref02.jpg (after, tools_qa/anim_states/ladder_movie.gd, Movie Maker 1280x720 30 fps, frame-diff checked).
| Check | Result | Note |
|---|---|---|
| Hands on rungs | PASS (partial) | hands grip the nearest rung on each rail during the clip's hold phase (rung IK), reach phases free; left hand sometimes on the rail rather than the rung end |
| Alternating limbs | PASS | Ladder_Climb_Up alternates; climb slowed 1.2 -> 0.62 m/s, rung spacing 0.31 m = the clip's contacts |
| Body tight to the ladder | PASS | was inside the ladder plane; now 0.42 m stand-off (hands at the rungs) |
| Clean top-out | FAIL (improved) | was a 0.35 s slide over the edge; now Mx_Trav_Ladder_Top_Exit hauls the body over and he stands on the deck; still a pose pop when the clip is cut (arm-out end pose -> idle, frame-diff spike at the hand-over) |
| Ladder prop | FAIL (improved) | box rails -> Blender split-log rails + round rungs with rope lashing, Poly Haven medieval wood; reads thin at distance, lashing barely visible |
| Weapons / camera | PASS | weapons go to the hip/back for the climb and come back with the draw clip; camera turns behind the climber and level (it used to dive into the loft floor and hide the body) |
| Overall vs ref 02 | FAIL | the pose is still stiff and frog-legged next to ref 02, the top-out hand-over pops, the prop is too thin; deck/platform in the test scene is flat colour (towns/world lane) |

## 2026-10-28 · player lane · slice movement route (ref 01) — FAIL (baseline)
File: docs/qa/golden/slice/slice_move_before_sheet.jpg (tools/qa/record_slice_move.sh, route tools_qa/acceptance/slice_move.gd, runtime clips logged as SLICECLIP: gait points Walk / Mx_Walk_Standard / Jog_Mid / Mx_Run_Slow / Mx_Run_Standard / Jog_Fwd). Verdict: the third-person camera is too far for the movement to read; the run is the repetitive high-knee Jog_Fwd at top speed; starts/stops are abrupt; recording still opens on the loading screen (wrong branding) — not judged further until the movement work lands.

## 2026-10-28 · player lane · ladder climb pass 2 (ref 02) — FAIL (closer)
File: docs/qa/golden/slice/ladder_climb_after2.jpg (dressed test platform: weathered_brown_planks deck, old_planks_02 posts, Poly Haven dirt; frame-diff: no spikes except the scripted camera cut).
| Check | Result | Note |
|---|---|---|
| Ladder prop | PASS (pending a closer look) | rails ~9 x 8 cm split logs, rungs 4.6 cm, width ~0.6 m, chunky rope lashing; medieval_wood |
| Square / centred on the ladder | PASS | the attach uses the ladder's own facing: chest square, centred between the rails whatever angle you walk up from |
| Hands on rungs, alternating limbs | PASS | rung IK in the hold phase |
| Weapons | PASS | shield on the back, sword across the back for the climb (no more hip blade sticking out); drawn back after with the draw clip |
| Top-out | PASS (motion) | root motion extracted from Mx_Trav_Ladder_Top_Exit (RootExtract): the capsule follows the clip, it ends standing over the capsule and fades into idle - the end-pose pop is gone |
| Overall vs ref 02 | FAIL | the climb pose itself is still stiff and wide-kneed (UAL Ladder_Climb_Up); left hand drifts toward the rail on some reaches. Next: the Mixamo climb or a pose pass |

## 2026-10-27 world worker: countryside route (Ashford edge -> wall stile -> copse -> bandit camp), real world + Terrain3D
Files: PA_plans/videos/slice_route_after.mp4 (v3), slice_route_before.mp4 (raw: route_before_raw.mp4), side-by-side PA_plans/videos/slice_route_vs_ref01.png. Tools: Movie Maker, ffmpeg, Terrain3D instancer/macro variation, Poly Haven CC0 muddy_tracks + stacked_stone_wall, authored data (slice_route.json).
| Check | Result | Note |
|---|---|---|
| Ground worn/used, ruts, puddle, soft edges (ref 01) | FAIL | road edge now soft and brown-red, but ruts do not read (flat smear at gameplay distance), puddle barely visible |
| Vegetation clustered/authored | FAIL | verge grass is separate clumps, not a continuous tall-grass mass; flowers too few |
| Grouped tree masses | FAIL | copse/belt still read as single lollipop trees from the road |
| Layered haze / soft cumulus sky | PASS-ish | haze layers on the fells read; sky cumulus OK but tiling pattern visible |
| Exposure natural | PASS | no blown sky, no crushed shadows |
| Materials (wall, road) PBR breakup | FAIL | wall OK; road albedo too saturated/red |
| HUD/branding | PASS | hidden |
Verdict: WIP, not sendable. Next: road texture scale + rut normal strength + desaturate; dense grass mass via GrassField/MultiMesh cards at 0.25 m; tree masses (8-15 trees per group, under-storey); puddle decal.

## 2026-10-28 · player lane · arming sword (Blender) — WIP (not gated at gameplay distance yet)
File: docs/qa/golden/slice/arming_sword_in_hand.png (walk / attack / block, side camera). tools/blender/props/build_arming_sword.py: 96 cm overall, 79 cm lenticular blade with a fuller to a point, 20 cm guard, 10 cm wrapped grip, wheel pommel, ~1k tris, origin at the grip; replaces the KayKit starter (Assets.ARMING_SWORD, fallback kept). Held in the fist through walk/attack/block, no ground contact. Fully metallic steel rendered black without a reflection probe -> 0.55 metallic, lighter albedo. Still to gate: at the game camera distance in the slice route, and vs the swing trail.

## 2026-10-28 · player lane · ladder pass 3 — top-out PASS, climb pose FAIL
File: docs/qa/golden/slice/ladder_topout_pass3.jpg. (a) Measured: the capsule and hips are centred on the ladder (hips x within +-3 cm of its centre); the off-centre read came from the hands on the rail ends (x +-0.24, rails at +-0.26) -> (c) each holding hand is now pinned a hand-width inside its rail on the nearest rung (arm IK, hold phase only). (b) The top-out arm flail is baked out of Mx_Trav_Ladder_Top_Exit at library build (arm tracks ease into the Idle arm pose from 1.6 to 2.5 s; RootExtract._calm_arms): arms stay down as he steps onto the deck. Frame-diff: no spikes besides the scripted camera cut. Still FAIL overall: the climb pose (UAL Ladder_Climb_Up) is stiff; the sword on the back sticks out past the shoulder at the top.

## 2026-10-28 · NPC anim lane · Meshy prime text-to-motion batch (20 clips, m01-m20) on the UAL villager — 2 PASS, 7 HOLD, 11 FAIL
Tools: Meshy prime FBX (SMPL-H 52 bones) -> Blender `tools/anim/mixamo_to_ual.py` rig `meshy_fbx` (auto bone orientation; mesh stripped; floor fix, foot lock with per-clip lock_vel/lock_wander, loop seam blend, lift_m), `tools/anim/meshy_pipeline.py` (retarget / sheet / measure with anim_qa on player_young + villager_man_a + villager_woman_a / grade with golden_gate), Movie Maker `tools_qa/living_world/clip_gallery.tscn` (villager_man_a with LifeProps, 1280x720 30 fps, q34 + front, gameplay distance 6-9 m), `tools_qa/living_world/sit_check.tscn --loop=` for the in-situ seat check, ffmpeg sheets. Sheets: docs/qa/golden/meshy/sheet_0-3.jpg (Blender, 8 frames per clip) and gallery_*.jpg; videos: PA_plans/videos/meshy_*.mp4.
| Clip | Gate | Slip mean/max m/s (villager) | Note |
|---|---|---|---|
| m19 Tankard_Laugh | PASS | lock 0.01/0.03 | seated, mug to the mouth with the head back, laughs, mug back to the knee; feet planted. In situ at tavern_table: pelvis-to-seat 3 cm, no pop at enter/exit. Wired: tavern_table.loop |
| m09 Sleep_Bed | PASS | n/a (lying) | on the back, arm across the chest, ankles crossed, slow breathing; lift_m 0.04 cleared 3.5 cm floor penetration. Wired: bed.loop |
| m10 Wake_Bed | HOLD | n/a | starts mid-air at bed height and ends facing ~180 deg away: needs a bed-exit offset check in situ |
| m16 Kneel_Down | HOLD | 0.04/0.43 | good kneel, but the lift that clears the toes (6 cm) makes the standing start float 6 cm; needs a phase-limited lift |
| m12 Milk_Stool | HOLD | 0.03/0.25 | frog-legged wide squat, hands reach low between the knees: only plausible next to a cow |
| m18 Butcher | HOLD | 0.01/0.03 | hunched, knife at thigh height, hands barely move: low energy, the knife never meets a table top |
| m08 Nail_Bench | HOLD | 0.01/0.02 | small hand movement at hip height, no readable hammer strike |
| m05 Stir_Cauldron | HOLD | 0.01/0.05 | small waist-height circles, weak reach into the pot |
| m04 Laundry_Scrub | HOLD | 0.01/0.04 | stooped scrub, small motion; 1.2 cm penetration on the player rig |
| m11 Eat_Seated | FAIL | 0.00/0.02 | bread and bowl stay in the lap; the food never reaches the mouth (robotic) |
| m17 Forge_Glowing | FAIL | 0.02/0.08 | bent over with limp arms reaching toward the ground at nothing |
| m02 Smith_Hammer | FAIL | 0.03/0.08 (player rig 0.16 max) | hammer and tongs held crossed at the chest and waved; no strike at anvil height (hands miss the prop) |
| m15 Lute | FAIL | 0.01/0.04 | lute held upright like a cello, strumming near the face: wrong grip |
| m06 Sweep | FAIL | 0.19/0.80 | lunging golf swings, broom head in the air, steps |
| m01 Chop_Wood | FAIL | 0.07/0.31 | overhead swing into a deep crouch, axe into the ground beside the feet, steps |
| m07 Mine_Pickaxe | FAIL | 0.09/0.30 | lunging swings with steps |
| m13 Scythe | FAIL | 0.39/1.30 | wild lunges with big steps; reads like stretching, not mowing |
| m03 Plant_Kneel | FAIL | 0.04/0.11 | on all fours, knees 10 cm through the floor |
| m20 Carry_Sack_Walk | FAIL | 0.69 (vs ground speed) | sack on the shoulder reads well, but the stride skates |
| m14 Wheelbarrow_Walk | FAIL | 0.67 (vs ground speed) | hunched walk with the arms hanging, no handle grip; skates |
Overall: the prime clips read low-energy and generic. Work loops hover hands at hip height instead of at the work surface, and tools are waved rather than struck. Only the two "rest" clips meet the bar. Re-prompt advice is in the coordinator report.

## 2026-10-27 Combat full motion (combat-motion worker) - FAIL (improved, WIP)
Files: `PA_plans/videos/WIP_combat_full_motion_{before_after_sword,sword,three,greatsword,axe}.mp4` (Movie Maker 1280x720 30 fps, HUD hidden, same flat field near Ashford, `combat_capture.gd --only=fm01|fm02`). Side-by-side with ref 03: `docs/qa/golden/combat/fm_gate_ref03_vs_sword.jpg`, sheet `fm_final_sword_sheet.jpg`.
Tools used: Mixamo (owner packs) -> Blender 5.2 `mixamo_to_ual.py` (root kept, foot lock), Godot Animation root track as data (`Animation.position_track_interpolate`), AnimationTree one-shots, PhysicalBoneSimulator3D ragdoll knockdowns (existing `ragdoll.gd`), attack tokens, Movie Maker + ffmpeg sheets.
| Check | Result | Note |
|---|---|---|
| Attacker faces and closes on the target | PASS | swings travel 0.3-1.8 m into the foe (warped root motion), turn at <= 9 rad/s in the wind-up; before: swings stood in place |
| Wind-up -> contact -> follow-through -> recovery | PASS | full-body Mixamo swings, contact on the measured hand-speed peak, recovery capped at 0.8 s |
| Blades reach the target, target reacts in hit direction | PASS (partial) | blade reaches the body; light hits flinch, finishers knock down into the ragdoll; no directional light flinch clips yet (side clip only on heavy) |
| NPC turns, spaces, fights back | PASS (1v1) / FAIL (1v3) | bandit closes from 3 m and swings with root motion; in 1v3 the waiting bandits circle at 3.6 m but sometimes pair up shoulder to shoulder, and one walks through the camera |
| Wide bent-knee stances, shields raised (ref 03) | FAIL | the guard idle is on, but the player still reads upright and narrow between swings; the shield sits low; bandit stance is hunched rather than wide |
| Blades actually meet (blocks, parries) | FAIL | blocks play the existing upper-body clip; there are no blade-on-blade contact poses |
| Feet planted, no sliding | FAIL (minor) | warp scale capped at 1.6, but long lunges still skate a little in the stretched frames; no foot IK during attacks yet |
| UI restraint | PASS (combat lane) | removed the red silhouettes, ground rings on blockable blows, finisher flash and parry speed lines; the orange lock arrow (player lane) remains |
| Dust on footwork | FAIL | only on hits and dodges, not on steps |
Verdict: a clear step up from "swinging in place" (the 1v1 now reads as two people fighting), but this is not ref-03 quality yet. Fix list: wider guard stance clips (Meshy request), blade-contact block and parry poses, directional light flinches, foot IK during lunges, step dust, 1v3 ring spacing and camera.

## 2026-10-27 Slice movement pass 1: top run + gameplay camera (player-animation worker) - FAIL (improved, WIP)
Route: `tools/qa/record_slice_move.sh` (idle, walk, run, turn, stop, 180, sprint, hayloft ladder), Movie Maker 30 fps, loading screen cut. Ref 01 (KCD2 traversal).
Video: `PA_plans/videos/slice_move_before_after.mp4` (side by side). Sheets: `docs/qa/golden/slice/slice_move_before_after_sheet.jpg`, `slice_run_before_after.jpg`, `run_candidates_jogfwd_fast_medium.jpg`.
Runtime clips (SLICECLIP): gait points Walk 1.00 / Mx_Walk_Standard 1.56 / Jog_Mid 2.42 / Mx_Run_Slow 3.30 / Mx_Run_Standard 4.39 / top. The 6.5 m/s run sat 100% on UAL Jog_Fwd (the high-knee bounce). It now sits on **Mx_Run_Fast** (Mixamo, retimed by clip_retime_bake, stance 5.87 m/s). Candidates were picked by eye on the same side camera: Jog_Fwd (high knee, heel kick to the hip), Mx_Run_Fast (compact, forward lean, natural arms), and Mx_Run_Medium (calmest, but 4.54 m/s would need a 1.43x cadence at 6.5 m/s, which reads frantic).
| Check | Result | Note |
|---|---|---|
| Top run is not the high-knee Jog_Fwd | PASS | Mx_Run_Fast: lower knees, forward lean, and the drawn sword swings low instead of sticking out sideways |
| Camera frames the character like ref 01 | PASS (partial) | arm 3.9 -> 3.0 m, sprint push 0.9 -> 0.45 m, open-ground push 0.35 -> 0.15 m, sprint FOV +7 -> +4: the player is about 1.4x larger in frame |
| Starts / stops / 180 pivots read as weight shifts | FAIL | not touched yet: the starts still pop to speed and the stops are a short brake on the gait blend |
| Sword sheathed when out of combat | FAIL | the player crosses the town with the sword drawn (KCD2 sheathes it) |
| Route on clear ground | FAIL | the bot sprint clips a crate and a rune stone next to Ashford Ring, and the "The ring of stones" world label floats over the player |
| Planted feet | not graded | the loco_slide numbers are unreliable on this machine right now: headless gives a foot/body ratio of 0.4 under CPU contention (other Godot instances), windowed gives 1.0. Judged by eye: no visible skate at the top run in the side view |
Verdict: the run is calmer and the camera is closer, but the pass FAILs until the starts/stops/pivots and out-of-combat sheathing are done.

## 2026-10-27 Combat full motion pass 2 (combat-motion worker) - FAIL (improved, WIP)
File: `PA_plans/videos/WIP_combat_full_motion_slice_clearing_sword.mp4`. Recorded in the real slice (`--terrain_backend=terrain3d --world_macro=real`, copse clearing 360,152), not in the meadow. Meshy returns 402, so this pass uses only existing clips and built-ins.
Tools used: `stance_measure.gd` ranked every idle/guard clip by foot spread and pelvis drop. Mx_SnS_Block_Idle measured 1.05 m spread, a 22 cm drop and the shield hand at chin height, so it is now the guard idle (Axe_Block_Idle and GS_Blocking_2 for the other styles), and no additive layer was needed. Light hits use a PhysicalBoneSimulator3D partial ragdoll (`scripts/combat/partial_ragdoll.gd`, chest/head/arms at influence 0.3 for about 0.25 s, pushed along the hit, only within 18 m of the camera, capped by Ragdoll.MAX_LIVE). Contact dust uses the pooled `VFXSpells._dust` under the lead foot on the contact frame of travelling swings.
| Check | Result | Note |
|---|---|---|
| Wide bent-knee stances, shields raised | PASS (bandit) / FAIL (player) | the bandit now holds a low guard with the shield up. The player's guard stance switches on (log: stance=guard_sword), but between chained swings the player is mostly in follow-through, and the Mixamo slashes stand tall |
| Target reacts in hit direction | PASS | the upper body is pushed away from the blow on top of the side flinch clip; heavy blows still knock down into the ragdoll |
| Dust on footwork | PASS (partial) | a puff on the contact plant; plain steps still have none |
| Blades actually meet | FAIL | no blade-contact parry IK yet |
| Environment | n/a (world lane) | the real terrain reads better than the meadow; Terrain3D instancer errors in the log belong to the world worker |
Verdict: the bandit side now reads close to the ref 03 posture, and hits physically rock the body. The player's tall follow-through and the missing blade contact keep this at FAIL.

## 2026-10-27 Combat full motion pass 3 (combat-motion worker) - coordinator FAILs 1-3
File: `PA_plans/videos/WIP_combat_full_motion_slice_clearing_sword_v3.mp4` (same copse clearing, same script).
| Coordinator FAIL | Result | Evidence |
|---|---|---|
| 1 Bodies interpenetrate in the opening exchange | PASS | Both fighters now fade their closing speed to zero at BODY_GAP 0.85 m (capsule radii + 0.15 m) via `CombatMotion.limit_approach`, with a soft overlap push (`body_push`). The warp stops at 1.1 m. Telemetry: the closest centre distance was 0.69 m before and is 0.86 m now; 0 frames under 0.85 m. On the sheet the bodies no longer merge. |
| 2 Spiky starburst impact | PASS | impact_pool has no slash quads; light hits have no glow core (sparks + dust only); heavy cores are about half the size. |
| 3 Player tall between swings | FAIL (improved) | Recovery now ends at 70 % (stop_attack fades into the Block_Idle guard; soldiers do the same when _busy ends), so the guard shows sooner. The additive crouch layer during recovery is not done, and the player still reads tall in the Mixamo follow-through frames. |

## 2026-10-27 Combat full motion pass 4 (combat-motion worker) - steps 3-4, FAIL (improved, WIP)
File: `PA_plans/videos/WIP_combat_full_motion_slice_clearing_sword_v4.mp4` (copse clearing, now with 6 guard presses for parries). Parry close-up sheet: `docs/qa/golden/combat/fm_v4_parry_sheet.jpg`.
| Step | Result | Note |
|---|---|---|
| 3 Additive crouch during recovery | PASS (improved) | `guard_legs.gd` (SkeletonModifier3D) blends only the legs and the pelvis height toward the weapon's measured guard pose (Block_Idle), up to 75 % and 0.25 s in/out, from 0.08 s after contact to the end of the recovery. The arms keep the follow-through. Player and bandit now read wide and low between blows. The leaping sword finisher (Mx_SnS_Slash_4, pelvis drop 0.37 m) is out of the chain. |
| 4 Parry blade contact | PASS (partial) | `parry_contact.gd`: TwoBoneIK3D on the right arm pulls the sword hand to the attacker's blade (0.55 m along its sword arm toward the defender) for 0.32 s. Sparks fly from that point, plus the existing parry hit-stop. Blocks on the shield get 8 sparks and a 0.05 s hit-stop. On the sheet the blades cross on several parries. Contact is approximate (it uses the hand, not the measured blade tip), and the bandit's arm has no IK. |
| VFX | fixed | the parry glow star (heavy impact core) is now a light-tier dust and spark puff |
Still FAIL overall vs ref 03: lock-on strafing and pivots, foot IK during lunges (step 5) are not done; the spark sprites still read slightly star-shaped up close.

## 2026-10-28 Refined props (Blender refine worker): asset-level gate, 12 PASS / 1 FAIL / 2 FAIL (borderline)
File: `docs/plans/props_refined/sheet.jpg`; details in `docs/plans/props_refined/README.md`. Tools: Blender 5.2 headless (Cycles CPU bake, Eevee gate renders), Poly Haven CC0 scans already on disk, ffmpeg/PIL for the sheet. The new bake extensions were checked: the custom `refine_lib.bake_asset` already covers multi-slot to one-set baking with the weathering stack. Godot auto-LOD is used. DeepBump could not run because its venv is incomplete.
| Asset | Result | Note |
|---|---|---|
| cart, well, crate_stack, trestle_table, belt_pouch | PASS | Real-scan wood and stone replace the AI painting. Wear, grime and mud are baked into one 1K/2K set. Real scale, origin at the feet. |
| market_stall, bench_hewn, haystack | PASS (borderline) | Stall: the produce is still Meshy's AI painting. Bench: the top is plain. Haystack: the silhouette is smooth (no straw cards). |
| tavern_sign, barrel_rack, fence_post_rail, hay_bundle, firewood_stack | PASS | Procedural at exact real dimensions. |
| hearth | FAIL | The Meshy hood geometry is a boulder-shaped lump; it needs a remodel. |
| trough_granite | FAIL (borderline) | Concrete-like streaky stone and soft edges; needs a granite scan and crisp arrises. |
| fence_wattle | FAIL (borderline) | The weave is too sparse and regular compared with ref 12/14. |
Not yet in-game: the towns worker must re-gate each prop in context at gameplay distance after placing it.

## 2026-10-27 Slice movement pass 2: real-terrain route, occluder, sheathing, starts/stops/turns (player-animation worker) - FAIL (improved, WIP)
Route now records in the real-terrain world (`--terrain_backend=terrain3d --world_macro=real`, recorder default). The start is chosen on clear ground: a 20x24 m box query around the route footprint, free of props and NPCs, 56 m SW of Ashford. The loading screen is cut at the logged movie frame. Bot `wait()` now runs on game time: under Movie Maker it used wall time, so every idle and stop in the old route lasted about 0.2 s.
Video: `PA_plans/videos/slice_move_real_terrain_wip.mp4`. Sheets: `docs/qa/golden/slice/slice_transitions_before_after.jpg`, `slice_sword_sheathed_hip.jpg`.
| Check | Result | Note |
|---|---|---|
| "Orange-brown rounded object beside the player" | PASS (found) | NEARMESH dump of every mesh within 1.5 m of the player: nothing non-player rides along. The object is the golden round haystacks (static dressing next to the hayloft and Ashford Ring), and the bot ran into or stopped against them. The new route stays clear of them |
| Route on clear ground, no prop collisions | PASS | no stuck legs on the open-ground route |
| Sword sheathed out of combat (KCD2) | PASS | starts sheathed and auto-sheathes after 5 s with no swing, no block, no guard foe, no lock-on and no hostile within 15 m. Fixed a rebuilt body (age change) dropping the holster flag. Sword hangs at the left hip |
| Lock-on marker restrained | PASS (by code, not filmed) | small pale tick, depth-tested, no spin or bob (was a large orange x-ray cone) |
| Floating sign text | PASS (by code) | the board subtitle was set on one line at the two-line size and ran about 2x past the board ends ("The ring of st..." in the air); it now wraps like the title |
| Starts | PASS (partial) | ACCEL_START 17 -> 8 m/s^2: walk speed in about 0.3 s instead of 0.14 s, so the first step carries the weight shift; ACCEL_TOP 11 -> 9 |
| Stops | PASS (partial) | walk brake 16 -> 9 m/s^2 (0.27 s, one settling step); run stop unchanged (0.43 s with the stop clips) |
| 180 turns in place | FAIL | FACE_TURN_IDLE 14 -> 9 rad/s, but the back camera does not show the turn-in-place steps well. Needs a side-on review shot |
| Ladder segment | not graded | this run crashed in the ladder leg on a Vulkan pipeline-creation error (-13) under machine load; the movement legs before it are complete |
Verdict: blockers cleared (occluder, route, sword, sign, marker). Movement is still FAIL until the 180 and start steps are reviewed side-on and the ladder leg is re-recorded on a quiet machine.

## 2026-10-27 Combat full motion pass 5 (combat-motion worker) - owner AAA bar, layers 1/3/4/5 - FAIL (improved, WIP)
File: `PA_plans/videos/WIP_combat_full_motion_slice_clearing_sword_v5.mp4`; close sheet `docs/qa/golden/combat/fm_v5_close_sheet.jpg` (before = v4 sheet).
| Layer | Verdict |
|---|---|
| 1 Variety | bandits pick from every light step and directional cut of their style at random, never the same clip twice in a row. PASS for NPCs; the player chain still goes in fixed order unless a direction is held |
| 3 Procedural layers | `lean_aim.gd` (SkeletonModifier3D) on fighters: upper-body twist toward the foe, a lean into lunges and away from hits (lean spring kick). Visible as torso twist and recoil on the sheet. Head look (LookAtModifier3D) was already on the player. Shield-arm threat IK and the tired breathing additive are not done |
| 4 Footwork | bandits in range between blows now circle (side flips every 1.2-2.6 s) and step in and out (1.6-2.6 m) with the strafe clips driving the feet, instead of standing frozen. PASS (bandit) |
| 5 Impact | hit-stop by weight: light 40 ms, heavy 90 ms, finisher 100 ms, parry 120 ms. Steel sparks are small streaks with a 0.08 s light (no STAR glow), dust on footwork contact |
Not done: set4 clips (directional reacts, deaths, dodges), player-side footwork, foot IK during lunges, lock-on pivots, NPC feints.

## 2026-10-28 world worker: countryside route v11 (gameplay camera, same route), real world + Terrain3D
Files: PA_plans/videos/slice_route_v11.mp4, side by side PA_plans/videos/slice_route_v11_vs_ref01.png. Tools: Movie Maker, ffmpeg contact sheets, Blender 5.2 (Python tree generator, Poly Haven CC0 bark), Poly Haven CC0 scans (grass_medium_01/02), Poly Haven dirt + muddy_tracks normal, Terrain3D instancer (LOD0-2 per mesh asset), Environment AgX tonemap.
| Check | Result | Note |
|---|---|---|
| Camera framing like ref 01 | PASS | gameplay camera behind the walking player, ~2.5 m, slight down-look |
| Grade / exposure natural | PASS-ish | AgX + saturation 0.85: no more cartoon greens; sky still flat grey-blue vs ref 01 contrasty cumulus |
| Ground worn, ruts, soft edge | FAIL (close) | ruts and trampled verge read; road too reddish-brown and dead straight in places vs ref 01 beige winding track; no visible puddle |
| Meadow to the road edge | PASS-ish | dense scan grass both sides; lacks flowers and the yellow-green variation of ref 01 |
| Tree masses | FAIL (close) | realistic broadleaf trees everywhere now (no lollipops); crowns are flat-topped umbrellas and groups too sparse vs ref 01 dense masses |
| Stylised assets in frame | FAIL | Ashford-edge bushes/props at the route start are town dressing (towns lane); stylised conifers remain in the instancer |
| Sky | FAIL | Sky3D clouds read flat; HDRI/cumulus pass not done |
| HUD | PASS | hidden |
Verdict: WIP. Big step from v3 (no toy greens, no lollipops), not yet ref-01 level. Next: rebuild the tree set with the installed Blender tree add-ons (sapling/modular_tree + leaf_gen) for rounder dense crowns + impostors; beige dirt albedo + curving road + puddle decal; meadow flowers (dandelion/wildflower scans); sky pass.

## 2026-10-27 Combat pass 6 (combat-motion worker) - set 4 converted, layer 2 reactions - FAIL (improved, WIP)
File: `PA_plans/videos/WIP_combat_full_motion_slice_clearing_sword_v6.mp4`; sheet `docs/qa/golden/combat/fm_v6_reactions_sheet.jpg`.
- Combat set 4: 43 clips retargeted to UAL (`UAL_Mx_combat_set4.glb`, root kept) and measured. The root axes check out: ReactLargeFront travels -0.74 m (backwards), ReactLargeBack +0.73 m.
- Layer 2: `combat_reactions.gd` picks the clip by direction (F/B/L/R) x strength (small < 2.5 m/s knockback <= large < 4.5 <= stagger) x guarding (block react). Bandits play it whole-body, and the clip's root travel moves the capsule (they give ground away from the blow). Partial ragdoll and lean kick stay on top. Death fall clips by killing-blow direction are mapped but not wired yet (the ragdoll death already falls with the hit).
- Verdict: bandit hits now read as hits (doubling over, stepping back, recoiling behind the shield). FAILs left: finisher impact sparks still a little spiky (spark share reduced again), the player's own reactions/footwork/dodges use the old clips (player lane), the player's shield shows as a pale flat square from some angles (equipment lane), 1v3 not re-recorded.

## 2026-10-28 Refined props round 2 (Blender refine worker): the 3 FAILs fixed
File: `docs/plans/props_refined/sheet.jpg`.
| Asset | Result | Note |
|---|---|---|
| hearth | PASS (borderline) | Meshy's boulder hood is deleted. A modelled lime-plaster smoke hood and flue (to a 3.0 m ceiling) sits on the mantel shelf, sooted at the mouth. The plaster is a bit blotchy. |
| trough_granite | PASS (borderline) | Exact-boolean basin, crisp 7 mm arrises, chipped edges, chisel tooling in the normal map, grey granite with speckle, rain streaks, moss. Slightly regular vertical streaking remains. 2.0k tris. |
| fence_wattle | PASS | 42 dense courses of thin irregular rods; nothing shows through at 3 m. 4.6k tris (within 5k). |
| market_stall | PASS (borderline) | The canopy is faded ochre-linen (-35 % saturation). |
Tools: DeepBump normals from Meshy albedo (cart, stall, table; not the pouch, where they made it worse); blender.sh now loads the user_default extensions through a junction. The Poly Haven downloads were not done: they need the owner's OK.

## 2026-10-27 Combat pass 7 (combat-motion worker) - slice road, no glow, player reactions + variety - FAIL (improved, WIP)
File: `PA_plans/videos/WIP_combat_full_motion_slice_road_sword_v7.mp4` (real terrain, on the dressed slice footpath near the Kingsreach road, 492,176); sheet `docs/qa/golden/combat/fm_v7_road_sheet.jpg`.
- VFX: impact glow core and ground ring removed for every tier; hits show small sparks + dust only. No orb on the sheet.
- Player side (split with the player worker: logic in `scripts/combat/player_combat_motion.gd`, one-line hooks in player.gd): flesh hits play the set-4 reaction by direction x strength (light = upper-body flinch over the guard legs, heavy = whole-body); the attack chain opens with its own step and then varies (never the same clip twice, a held direction still picks the cut).
- Verdict: the duel now sits in the real route and both sides react, vary and keep spacing. Still FAIL: the review camera dips into roadside grass (raised to 2.0 m for the next run); some stylised orange/golden trees remain in the background (world lane); dodges still use the old roll; lock-on footwork, deaths by direction, shield-arm tracking, feints and 1v3 still open.

## 2026-10-28 · NPC anim lane · Mixamo Farming Pack + Meshy probation fixes, gated in the real Ashford square
Tools: Blender `tools/anim/mixamo_to_ual.py` (new passes: `toe_floor` foot/toe pitch on the bone's side axis with eased angles, `lift_ramp` piecewise pelvis height, `yaw_deg`/`yaw_shift` whole-take turn in the root bone's frame), `tools/anim/meshy_pipeline.py` (now any library: --lib/--queue/--out, tag from --out), anim_qa on player_young + villager_man_a + villager_woman_a, Movie Maker in the game itself: `tools_qa/video/slice_route.gd` clip-street mode (SLICE_CLIPS env; hero at the Ashford square edge, game camera, bodies on the real cobbles 10-14 m from the lens, LOW tier), `sit_check.tscn --type=bed --loop= --exit=` (bed model under the sleeper, side camera), ffmpeg sheets. Blender retarget/root_maker extensions: not needed (our passes already measure and fix per frame).
Videos: PA_plans/videos/slice_2026-10-27_1116_205b95674_clipgate5.mp4 (street gate, 2 pages), meshy_bed_sleep_wake.mp4 (bed). Sheets: docs/qa/golden/mixamo_farm/sheet_0-2.jpg.
| Clip | Gate | Note |
|---|---|---|
| Life_Mx2_Pick_Fruit_B | PASS, wired field_harvest | side reach and pick at chest height, feet planted; metrics gold on all 3 rigs |
| Life_Mx2_Water | PASS, wired field_row | bucket held low, pour sweep, feet planted; gold on all rigs |
| Life_Mx_Milk_Cow (owner set 2) | PASS, wired milking_stool | was gold but unwired; steady working squat reads at gameplay distance |
| Life_Mz_Sleep_Bed | PASS (bed type, sole loop) | re-rooted into a bed frame: lies on a 0.45 m mattress with the root on the floor (villagers never take slot y); head on the pillow |
| Life_Mz_Wake_Bed | HOLD | re-rooted: starts exactly on Sleep_Bed's pose, ends standing over the root facing forward (DONE pelvis 0.00 m/s: the exit_to/turn pop is gone); the source's 133 deg turn swings the legs out past the headboard post |
| Life_Mz_Kneel_Down | FAIL | lift removed (the standing start no longer floats 6 cm); toe_floor tucks the toes, but 4 toe pops remain on the villager rig |
| Life_Mx2_Wheelbarrow_Walk / Holding_Walk / Box_Walk_Arc | HOLD / FAIL | stride is clean once the root track is off (stance 2.02 / 1.45 / 1.41 m/s, speed_mps set); Holding/Box have empty hands; wheelbarrow needs the prop and a carry state |
| Life_Mz_Carry_Sack_Walk | FAIL (legs) | planted-foot speed swings 0.7-1.8 m/s inside one cycle: no playback rate can fix it. The sack upper body can layer on our walk (LifeLibrary.composite), but villagers have no carry-errand state yet: the sack would pop in and out at every stop |
| Life_Mx2_Dig_Plant / Plant_Plant | FAIL | 7 / 13 elbow pops: hands need 15-29 cm of IK (UAL arms longer than the actor) |
| Life_Mx2_Pull_Plant_B / Kneel_Idle | HOLD | metrics gold except a 3.5 cm float on the dressed woman; hidden by the crowd in the street gate |
Overall: three new work loops pass in the real street. They read at gameplay distance among the real townsfolk, with no sliding or pops. The bed pair is consistent, but no beds are placed in the world yet.

## 2026-10-27 Combat pass 8 (combat-motion worker) - deaths by direction, shield-arm tracking, NPC rhythm, 1v3 - FAIL (improved, WIP)
Files: `PA_plans/videos/WIP_combat_full_motion_slice_road_sword2_v8.mp4` (1v1), `..._three2_v8.mp4` (1v3), same road spot; sheets `docs/qa/golden/combat/fm_v8_road_*.jpg`.
- Deaths: when the ragdoll is unavailable (far, capped), the death clip falls away from the killing blow (set 4).
- Shield arm: a blocking bandit's left arm is pulled into the incoming blow (TwoBoneIK3D window), so the guard tracks the threat.
- NPC rhythm: a hurt bandit (< 40 % HP) backs off 0.8-1.5 s at 45 % chance; 18 % of swings against the player are feints (the wind-up shows, then is pulled at 55 % of the way to the contact, no damage).
- 1v3: one bandit engages and the other two circle at 3.6 m (tokens). Readable on the wide camera; one circler still passes close to the lens.
- Verdict: 1v1 on the road reads as a fight (approach, exchanges, knockdown, get-up, recoils). Still FAIL vs ref 03: stylised orange/golden trees in the background (world lane), player dodges/footwork unchanged, no foot IK during lunges, no lock-on pivots.

## 2026-10-27 Player props pass: kite shield + refined belt pouch (player-animation worker) - PASS (lookdev), gameplay distance pending
Viewed: loco_movie idle, adult, sheathed (shield on the back), front / three-quarter / side ortho frames (scratch, not kept: /tmp was cleared before the copy).
| Check | Result | Note |
|---|---|---|
| Kite shield replaces the round shield on the player | PASS | Poly Haven kite_shield (CC0 scan, 10.3k tris, 1K PBR, double-sided materials), 95 cm. Bandits keep the round shield |
| No pale flat square from some angles (combat report) | PASS (expected) | the old round-shield GLB is no longer on the player; the kite scan is double-sided with real thickness |
| Belt pouch | PASS (lookdev) | refined pouch (props_refined, Meshy geometry + CC0 scan materials) on the pelvis, front-left of the belt, 16 cm; replaces the procedural box on the Tier-A hero |
| Sheathed sword at the hip | WATCH | the 95 cm blade hangs nearly to the ankle and crosses the back of the thigh in side view. Needs a steeper scabbard angle check in motion |
| Side-on movement review (starts/stops/180) | BLOCKED | the side camera was fixed (it lived in the root viewport, but the game renders in a SubViewport). The re-record is waiting on RAM (517-657 MB free; the recorder now refuses below 3 GB) |

## 2026-10-27 · towns lane · Ashford slice route re-gate (same route, after steps 1-5) — FAIL (honest try; remaining list below)
Files (Movie Maker 1280x720 30 fps, HIGH, 0 script errors): PA_plans/videos/slice_ashford_street_final.mp4 (14:30), slice_ashford_street_night_final.mp4 (21:30), slice_ashford_interior_final.mp4 (13:00); tools_qa/towns_medieval/flythrough.gd --path=slice, interior_walk.gd. Refs 05/06/08/09/17/20.
| Check | Result | Note |
|---|---|---|
| Main street composition (05/08) | PASS (partial) | frontage + narrowed street, chapel on the axis closes the view; waiting on the refined church tower / gate from props_refined/buildings to replace the chapel |
| Materials, no flat colour (06/17) | PASS main street / FAIL edge | CC0 timber, plaster, slate, cobble on the kit and hero houses; the edge kit houses (end of the route) still read pale beige planks, nearly self-lit at night |
| Dressing supports focal points (06/17) | PASS (partial) | Meshy/refined cart, well, crate stacks, stall, CC0 barrels/pots replace the toy props; no toy baskets on the route |
| Ground: mud, puddles, grass in cracks (09/20) | PASS (partial) | verge mud decals + cobble cracks; puddles only by the wet map |
| Night (09/20) | PASS (partial) | inn porch glare FIXED (street_benchmark door-lantern emission decal 3.0 -> 0.5); warm windows vs cool sky; FAIL: tiled cloud pattern in the night sky reads repetitive; one fully black frame where the camera enters a building at the edge |
| Camera | FAIL | brushes through NPCs and a wall corner on the side street; one frame inside a building at night |
| NPCs | FAIL (NPC lane) | faceted low-poly villager bodies at close range next to the realistic props |
| Interior (scenario-A house) | FAIL | CC0 detail now on walls/floor, but walls read grey stone instead of limewashed plaster, flat blue-grey daylight, windows flat white panes |
| Beds (for the NPC lane) | PASS | interior kit beds now use the smart-object bed frame: Life_Mz_Sleep_Bed lies on the mattress (scenario house: 4 sleepers at 23:30, inn loft: 2), headboard lowered to 0.55 m |
**Verdict: FAIL. Not sent to the owner.** Remaining, in order: (1) edge kit-house plaster/limewash + night exposure, (2) interior plaster tone + warm window light, (3) camera path clearance (NPC + wall avoidance), (4) landmark swap when the refined tower/gate lands, (5) night sky cloud tiling (sky owner), (6) NPC bodies (NPC lane).

## 2026-10-27 Combat pass 9 (combat-motion worker) - root-motion dodge, lunge foot IK, 1v3 camera - FAIL (improved, WIP)
Files: `PA_plans/videos/WIP_combat_full_motion_slice_road_sword4_v9.mp4` (1v1 incl. back dodge + side roll), `..._three4_v9.mp4` (1v3); sheets `docs/qa/golden/combat/fm_v9_road_*.jpg`, lunge feet close-up `fm_v9_lunge_feet.jpg`.
- Root-motion dodge: set-4 rolls trimmed to their travel (`tools/anim/combat_packs/dodges.json` -> `UAL_Mx_dodges.glb`). The forward/side roll (Mx4d_RollForward, 1.23 s of root travel) plays in 0.55 s and the capsule follows the clip's own speed curve, scaled to 2.7 m. The back dodge stays on the old back-step: Mx4d_DodgeBack is a 0.5 m high hop and read as floating (seen in the first take).
- Foot IK on lunges: the rig keeps foot IK during root-motion swings (`is_stand_attack() and not _cmotion.active`). On the side-on close-up the front foot plants and holds at contact, with no ski-slide or snap visible at 8 fps.
- 1v3 camera: a camera-avoid radius (3 m) plus a sight-line lift (any fighter between the lens and the fight raises the camera 1.6 m). On the 1v3 sheet no bandit fills the near lens any more.
- Contact dust only after a real step (> 0.5 m warped): fewer puffs.
- Lock-on pivots: NOT done. The Mx_SnS turn clips turn in the pelvis, not the root, so rotating the capsule as well would double-turn. They need root-rotation extraction first (Blender RootMaker, or a converter pass that moves pelvis yaw into the root).
- Timing (hit-stop 40/90/100/120 ms by weight, camera shake/roll by tier) is unchanged from pass 5; it holds on these takes.

## 2026-10-27 Combat pass 10 (combat-motion worker) - player guard between exchanges - FAIL (improved, WIP)
File: `PA_plans/videos/WIP_combat_full_motion_slice_road_sword5_v10.mp4`; sheet `docs/qa/golden/combat/fm_v10_guard_sheet.jpg`.
- GuardLegs now also runs between exchanges. Standing guard (foe within 7 m, not swinging or dodging, < 0.4 m/s): the legs take the wide Block_Idle base. Strafing / moving: a pelvis-only crouch (the hips drop to the guard height) and the leg rotations are left to the stepping clip. The modifier now runs FIRST in the skeleton stack, so the rig's foot IK keeps the soles on the ground. Bandits get the same pelvis crouch while engaged.
- Verdict: the player reads lower and wider between blows on most frames (row 3 of the sheet); a few recovery frames are still upright. Back dodge still the old back-step (the only low Mixamo back-dodge in our packs is the longbow one, which holds a bow). Lock-on pivots wait for the player worker's yaw extraction in root_extract.gd. Background: some stylised orange pines are still on the road edge after the world worker's v13/v14 tree swap.

## 2026-10-27 Combat pass 11 (combat-motion worker) - masked back dodge, guard-crouch axis fix - FAIL (improved, WIP)
File: `PA_plans/videos/WIP_combat_full_motion_slice_road_sword7_v11.mp4`; sheets `docs/qa/golden/combat/fm_v11_sheet.jpg`, back-dodge close-up `fm_v11_back.jpg`.
- Back dodge: built at runtime from the longbow "standing dodge backward" (the only low back-dodge Mixamo has): legs, hips, spine and root travel trimmed to the 10-95 % travel window (0.93 s, played in 0.55 s), with the clavicles, arms, hands and fingers held in the sword-and-shield guard (data-level upper-body mask, `PlayerCombatMotion.build_masked`). The capsule follows its speed curve, scaled to 1.8 m.
- BUG FOUND AND FIXED by eye: the first take showed the player floating about 1 m up. GuardLegs lowered the pelvis on the bone's y axis, but the UAL pelvis height is its z axis, so the bent guard legs lifted the feet instead of lowering the hips. It now finds the up axis from the rest pose. This also affected v10's standing guard.
- Verdict: the player now holds a wide, low guard on the ground between exchanges, and the back-step stays low with the shield up. Remaining: lock-on pivots (player worker's yaw extraction), tall roadside grass occasionally crossing the review lens (camera avoid only covers fighters), stylised orange pines still on the road edge.

## 2026-10-28 world worker: countryside route v14 (gameplay camera, same route)
Files: PA_plans/videos/slice_route_v14.mp4, side by side slice_route_v14_vs_ref01.png. Tools: Blender 5.2 Sapling Tree Gen (oak/beech/ash/pine/spruce from presets) + Poly Haven bark, Poly Haven scan grass + dandelion, Poly Haven kloofendal_48d partly-cloudy HDRI sky (sun-aligned shader), Poly Haven dirt + muddy_tracks ruts, Terrain3D instancer, AgX, Movie Maker + ffmpeg.
| Check | Result | Note |
|---|---|---|
| Camera like ref 01 | PASS | |
| Near field crisp, haze only far | PASS | depth fog from 300 m, volumetric off outdoors |
| Sky: deep blue + crisp cumulus | PASS-ish | real HDRI clouds, sun-aligned; brighter/whiter than ref 01 near the horizon |
| Worn winding road, ruts, edges | PASS-ish | beige winding track with ruts and trampled verge; puddle reads as a hard dark disc (FAIL detail) |
| Meadow (fresh yellow-green, darker clumps) | PASS-ish | per-instance hue + backlight; flowers still sparse |
| Tree masses (realistic) | PASS-ish | Sapling broadleaves and conifers everywhere, no stylised trees in the real world; groups could be denser |
| Walls | FAIL | still read red-brown/dark, too uniform |
| Distant hills | FAIL | smooth green far mesh, no forest cover/macro breakup |
| Stylised props at the route start | FAIL (towns lane) | Ashford-edge bushes/props |
| Perf on this route (RTX 4070 laptop, 1280x720, no capture) | FAIL HIGH / PASS LOW | HIGH 26.6 fps avg, p95 66 ms; LOW 60.7 fps avg, p95 39 ms. Sapling LOD0 trees (25-55k tris) + scan meadow are the cost; iGPU not measured |
Verdict: WIP but now the right family next to ref 01. Not sendable as final: walls, puddle, distant hills, HIGH perf.

## 2026-10-28 Refined buildings (Blender refine worker): asset-level gate vs refs 05/08/18/20
File: `docs/plans/props_refined/buildings_sheet.jpg`; verdicts are in `docs/plans/props_refined/README.md` (buildings batch). Tools: Blender 5.2 headless (weld → collapse decimate → high→low normal bake → Cycles CPU 2K bake), on-disk Poly Haven CC0 scans, gltfpack `-sa` (tried on the 2.5–3M-tri props).
| Result | Assets |
|---|---|
| PASS | B28 chapel, B44 tall timber house, B14 blacksmith, B54 half-timbered row, B70 tavern |
| PASS (borderline) | B07 church (plain box), B16 brick church (Victorian spire), B10 gate (soft merlons), B42 tower (stylised taper), B43 house (muddy plaster), B52/B53 Tudor houses (plaster too grey), B60 cottage (flat dark thatch) |
| DROPPED | P99 campfire (melts at budget), P112 tent (canvas shatters) |
Not in-game yet: the towns worker re-gates each building in the street after placing it.

## 2026-10-28 · NPC anim lane · carry errand, Mixamo work set 5, CMU household re-gate (Ashford street, Movie Maker)
Videos: PA_plans/videos/slice_2026-10-27_1200_6c8da63f1_carrygate.mp4 (carry), slice_2026-10-27_1246_cc15cdc05_set5gate.mp4 (set 5 + CMU), slice_2026-10-27_1153_44c565499_carry2.mp4 (route with ASHES_CARRY_SHARE=0.8).
| Item | Gate | Note |
|---|---|---|
| Carry errand (villager.gd + carry_errand.gd) | PASS | pick-up bend lifts the sack off the cobbles; sack on the shoulder reads naturally walking and standing; crate held at the waist reads OK; 30% of daytime trips >= 12 m, work trips set the load down at the spot's approach point, indoor trips set it down first. Headless check: 26 errands started in one slice run at share 0.8 |
| Life_Mx5_Talk_General / Talk_Explain / Talk_Funny / Argue_B / Agree_Nod | PASS, wired conversation | natural gestures, planted feet, read at 10-14 m among the real crowd |
| Life_Mx5_Sit_Cross_Legged / Sit_Reclined | PASS, wired sit_ground | on the ground, no penetration (+3 cm lift on reclined) |
| Life_Mx5_Look_Around_B | PASS, wall_idle loop | standing idle |
| Life_Mx5 wall leans | HOLD | lean on air in the open plaza: judge at a wall |
| Life_Mx5 chair sits (laugh / cheer / drink) | HOLD | tavern-table sit_check: pelvis 30-33 cm off the seat, exit pop 9 m/s: needs seat alignment |
| CMU Life_Mocap_Sweep / Dig / Slice / Eat_Soup / Eat_Table | PASS (metrics gold today; sweep with the broom seen in the street) | Sweep, Dig, Slice already wired |
| CMU Life_Mocap_Stir / Saw / Hammer_Nail | FAIL | feet slide 0.05-0.09 m/s mean: need a foot-pin pass (our pipeline doesn't take CMU BVH yet) |

## 2026-10-27 Slice movement pass 3: side-on review, ladder descent, shield on the back (player-animation worker) - PASS (movement legs), WATCH (sword at hip)
Video: `PA_plans/videos/slice_move_real_terrain_wip.mp4` (gameplay camera). Sheets: `docs/qa/golden/slice/slice_side_turn_start.jpg` (SLICE_CAM=side), `slice_shield_back_after.jpg`, `slice_ladder_descent_after.jpg`.
| Check | Result | Note |
|---|---|---|
| Starts read as a weight shift (side-on) | PASS | first step with a forward lean, about 0.3 s to walk speed |
| 180 turn steps around, no spin on the spot (side-on) | PASS | feet cross and re-plant through the turn; the body never pivots on planted soles |
| Stops | PASS | 2-3 decelerating steps from the run; one settling step from the walk |
| Ladder descent | PASS (fixed) | the route called "climb down" during the 2.9 s top-out, so the ladder fell back to a teleport and the landing code (fall apex still at the deck) played a hard-landing roll at the foot of the ladder. Now: the route waits for the top-out to end; a teleported or carried body resets the fall apex; descent hangs on the approach side facing the rungs and steps off at the stand-off |
| Shield on the back: no pale blob (ref 01 clean from behind) | PASS | root cause: hero_tier_a.upgrade_meshy put the body shader on EVERY textured mesh under the model, props included, so the kite shield lost its PBR and read pale and flat. Props on bone attachments now keep their own materials; scan albedo x0.55, roughness >= 0.75; 88 cm; sits 7 cm lower between the shoulder blades and the belt |
| Sheathed sword at the hip | WATCH | a naked 95 cm blade hangs from the belt with no scabbard. Next: a Blender scabbard (leather and chape) shown when sheathed |

## 2026-10-28 Refined buildings round 2 (Blender refine worker): coordinator review fixes
File: `docs/plans/props_refined/buildings_sheet.jpg`.
| Fix | Result |
|---|---|
| Half-timbered houses were uniformly muddy (B43/B44/B52/B53/B60) | PASS: a per-pixel limewash/oak frame from Meshy's painted framing; dirt only at the base, under the eaves and in streaks. B44 and B60 are now crisp; B43/B52/B53 are borderline (noisy shingle roofs). |
| Roof courses not following the slope | PASS: slope-aligned roof projection (eave direction snapped to 45° per face, courses on horizontal lines) |
| B07 church plain | PASS (borderline): buttresses, bell-cote and bell, darker slate |
| B16 Victorian | DROPPED |
Downloads: none. The approval was relayed by an agent; it needs the owner's own OK (see README).

## 2026-10-28 · NPC anim lane · recorder hygiene, wall leans, chair seats, firewood + dropped loads, CMU foot pin
Videos (PA_plans/videos): slice_2026-10-27_1331_3a0768bba_leans4.mp4 (leans, side camera at the real spots), slice_2026-10-27_1356_f106911f0_firewood.mp4 (firewood carry + drops), slice_2026-10-27_1411_8c8e39016_cmufix.mp4 (CMU fix). All recordings now start at the route (SLICEFRAME cut, no loading screen) with every UI layer hidden.
| Item | Gate | Note |
|---|---|---|
| Recorder (record_slice.sh / slice_route.gd) | PASS | loading screen cut at SLICEFRAME; HUD, tips, quest popups and subtitles hidden every frame |
| Wall leans (wall_lean_back / wall_lean_side) | PASS | spots on real facades, fitted to the collider on first claim: LEANGAP 0.17 / 0.33 m exact on 6 spots (was 0.35-0.65 m off from mesh bounds); back lean reads on the wall with the foot up; shoulder lean in profile at 0.33 m |
| Life_Mx5_Sit_Laughing / Sit_Cheer_Talk | PASS, wired tavern_table | missing sidecar seat_back (root never moved onto the seat); now pelvis-to-seat 4.3 / 2.1 cm, exit 0.6-0.7 m/s |
| Life_Mx5_Sit_Down_Drink | HOLD | turns ~180 deg to sit, pelvis ends 0.24 m forward: needs end alignment as a tavern enter |
| Firewood bundle (props_refined/firewood_bundle) + carry kind | PASS | 704 tris, firewood_stack CC0 textures; rides over the shoulder with the sack carry upper |
| Flee drop | PASS | the load leaves the hand and comes to rest on the cobbles (0.45 s), lies 30 s; no pop out of the hand |
| Life_Cmu_Stir / Saw / Hammer_Nail | PASS, wired cook_pot / sawhorse / nail_plank (re-enabled) | CMU clips re-run through mixamo_to_ual.py --rig ual (identity map: foot pin + seam), saw / hammer looped on their stationary windows; Saw and Hammer gold on all rigs, Stir gold on the villager rigs |

## 2026-10-28 Refine round 3 (Blender refine worker): coordinator's CC0 scans swapped in
Files: `docs/plans/props_refined/sheet.jpg`, `buildings_sheet.jpg`. The new scans (fbf4e24a9) are rusty_metal_02, rough_linen, brown_leather, plastered_wall_02, beam_wall_01 and roof_slates_03, in iron, sacks, canvas, limewash, framing and slate.
| Asset | Result |
|---|---|
| tavern_sign bracket, barrel hoops, well, hearth, crates, cart | PASS: dark wrought iron with rust (scan) |
| cart sacks, market_stall canopy | PASS: linen scan, faded ochre canopy |
| B43/B52/B53 roofs | PASS: calm grey slate replaces the noisy shingle |
| Tudor set and B14 walls | B44/B60 PASS; B43/B52/B53/B14 PASS (borderline; B14's limewash is patchy) |
| trough_granite | granite_wall rejected (masonry courses on a monolith); stays procedural granite, PASS (borderline) |
| scabbard_arming (new, player worker's geometry) | PASS (borderline): the leather is mid-brown and the frog is only a tab |

## 2026-10-27 Equipment: scabbard + shield carry (player-animation worker) - PASS (scabbard, shield size and offset), re-check shield tilt sign
Sheets: `docs/qa/golden/slice/scabbard_side_idle.png` (loco_movie side), `slice_shield_scabbard_back.jpg` (gameplay camera from behind, walk + run).
| Check | Result | Note |
|---|---|---|
| No bare blade at the hip | PASS | Blender scabbard (`tools/blender/props/build_scabbard.py`): near-black leather over the blade's own taper, iron throat and chape, two lacing bands, frog tab, and two hanger straps up to the belt, 1.5k tris. It is built in the sword's own frame and placed every frame by ProceduralRig in the hip socket, so a sheathed blade sits inside it; it stays at the hip when the sword is drawn. The textured refined copy (props_refined/scabbard_arming, Blender worker) is preferred when imported, darkened x0.5 |
| Angle ~25-30 deg back, hilt forward | PASS | socket tilt 18 deg from the pelvis up axis (about 28 deg in the world with the walk's lean), frog 9 cm forward of the pelvis line |
| Swings slightly | PASS | damped pendulum about the frog, driven by the pelvis's forward/back acceleration (max 0.3 rad); the sheathed sword shares it |
| Shield on the back smaller, high, offset to the left shoulder | PASS | 76 cm, raised 4 cm, 9 cm toward the left shoulder; the right arm and half the back read from behind |
| Shield angled ~20 deg, point toward the left hip | FIX APPLIED, re-check | the first take leaned the wrong way (point toward the right hip); the tilt sign is flipped, to re-check in the next recording |

## 2026-10-27 Combat pass 12 (combat-motion worker) - surface hit VFX, combat event bus - FAIL (improved, WIP)
File: `PA_plans/videos/WIP_combat_full_motion_slice_road_sword8_v12.mp4`; hit close-up sheet `docs/qa/golden/combat/fm_v12_hits.jpg`.
- VFX by surface (`scripts/combat/surface_hits.gd`, GPUParticles3D via vfx_kit, alpha-blended): blade into a body = a few dark-red droplets + a small pooled ground stain decal (12 max, fade after 25 s), with dust only from the impact pool (no hot sparks on cloth/flesh); metal (parry) = short steel streaks; wood (shield block) = brown chips. On the close-up sheet hits read as small, grounded contact (no glow, no starburst); the droplets are subtle at review distance.
- Effekseer verdict: not adopted. It needs authored .efk effects (no medieval CC0 set in the project), it is a GDExtension with per-effect cost, and the pooled GPUParticles3D path already covers sparks, dust and blood cheaply on iGPU. Recommend the coordinator removes the addon and the stray `~libeffekseer*.TMP` DLLs (I don't delete files).
- Foley hooks: `scripts/combat/combat_events.gd`, `CombatEvents.bus()` with signals swing {weight, speed, clip, kind slash/thrust/overhead}, hit {weight, surface, damage, killed}, block {weight, surface wood, broken}, parry {grade, surface metal}, dodge. Emitted for the player (combat_feedback) and soldiers (attack, landed hit, block).
- Camera: the PhantomCamera3D combat framing is the player worker's (CombatPCam, queued). The heavy-hit dutch/kick already goes through the existing API (`_camera_roll` / `_add_camera_shake`, tiered in combat_feel), so no second roll path.
- Pass 12b (event gaps for the foley worker): `dodge` is emitted on every player dodge (kind back / roll / dash; soldiers have no dodge yet), player `hit` events carry the real `victim` and `killed` (player.gd keeps `_last_hit_victims` parallel to the hit points), bandit `swing.kind` comes from the clip's measured cut (CombatEvents.swing_kind), and the struck surface comes from the victim's outfit (mail/plate/helmet -> metal sparks, leather -> hide flecks, outfit -> cloth, else flesh). Blood, dust, sparks and foley now match it.

## 2026-10-27 Lock-on guard turn (player-animation worker) - PASS (180 by eye), 90-150 deg pending a film
Sheet: `docs/qa/golden/slice/lockon_guard_turn_180.jpg` (`tools_qa/anim_states/guard_turn_movie.gd`, the bandit locked 3 m behind).
| Check | Result | Note |
|---|---|---|
| A locked foe behind the player is faced with a stepped guard turn, not a spin | PASS | Mx_SnS_180_Turn: feet step around over 0.8 s and end in the wide guard stance facing the foe |
| No double turn | PASS | RootExtract moves the clips' pelvis yaw to meta "root_yaw" about the rig's real up axis (the first try used +Y on a Z-up track and flipped the body upside down: caught by eye); the model turns along the curve scaled to the real angle. Measured: Turn -94 deg, Turn_2 +99 deg, 180_Turn -181 deg, 180_Turn_2 -180 deg |
| 100-150 deg (Turn / Turn_2) | NOT FILMED | same path; to film next |

## 2026-10-27 MPFB pilot stage 1: Ashford villager man (player-animation worker) - WIP (not in game yet)
Preview: `docs/qa/golden/slice/mpfb_pilot_villager_stage1.png` (Blender EEVEE, A-pose). Script: `tools/blender/mpfb/build_body.py --preset villager_man`.
| Check | Result | Note |
|---|---|---|
| Realistic body and face (vs the faceted crowd) | PASS (preview) | MPFB macro targets (male, about 27 y, lean-muscular, European); CC0 middle-aged skin, eyebrows, short hair |
| Medieval clothing | PARTIAL | CC0 suits02 viking tunic, hose, turn-up boots and belt read medieval. The tunic's mail chest panel is wrong for a villager: swap it for a plain wool tunic (retexture) in stage 2 |
| Rig | PASS (names) | MPFB game_engine rig, 53 bones with the Unreal names the game uses (Root, pelvis, spine_01-03, clavicle/upperarm/lowerarm/hand, thigh/calf/foot/ball, fingers). The UAL rig has 65 (extra twist and IK bones); mapping and rest-pose check in stage 2 |
| Budget | FAIL (expected at stage 1) | 45.7k tris unbaked. Stage 2: hidden-face delete under the clothes, decimate to 8k / 3k / 1k, bake to a 1K atlas, VAT tier |

## 2026-10-28 · NPC anim lane · L-1: MotionRules hooked into villager / micro_actor / follower_body / soldier + ClipPicker talk variety
Videos: PA_plans/videos/slice_2026-10-27_1515_fcbadbbed_l1_before.mp4 (ASHES_MOTION_OFF=1) vs slice_2026-10-27_1521_fcbadbbed_l1_after.mp4, same route and build.
| Check | Result | Note |
|---|---|---|
| Hook is a no-op while M1 rules are stubs | PASS | every channel is applied only when a rule won it (MotionApply); before/after differ only by normal schedule randomness; same 37 engine errors in both runs, all from tutorial_game_bridge.gd (not this lane) |
| villager.gd | done | _motion_think() at the think rate (NEAR/MID): ctx (speed, heading, act, carrying, weather, hour, tired), persona per archetype; steer, gait, upper, oneshot, look, lean (model-root roll) |
| micro_actor / follower_body / soldier | done | MotionApply.Body (3.3 Hz, staggered): gait override + lean; soldier lean only (combat motion stays with the combat worker until L-7) |
| ClipPicker crowd variety | done | talk / listen turns pick by verb with no repeat of the last 3 and never the partner's current clip (personality-weighted); fallback to the old lists |
| Tests | 47/48 + 39/39 | test_clip_picker + test_smart_objects_v2: one perf budget miss (find(needs) 3.06 ms vs 3.0 on a loaded machine); test_motion_rules does not exist yet (M1 merged as "tests pending"); companions / combat / path suites green |

## 2026-10-27 · towns lane · Ashford slice re-gate 2 (real world, shared grade) — FAIL (closer; list below)
Files: PA_plans/videos/slice_ashford_street_v4.mp4 (14:30), slice_ashford_street_night_v4.mp4 (21:30), slice_ashford_interior_v5.mp4 (13:00); all `--world_macro=real --terrain_backend=terrain3d` (the slice world), Movie Maker 1280x720 30 fps HIGH, 0 script errors.
| Check | Result | Note |
|---|---|---|
| Grade / sky consistency town vs country | PASS (partial) | town now records under the countryside AgX grade + sky; town timber/roof/cloth albedo -25% saturation toward grey-brown (Style G TOWN_DESAT). Sky HDRI swap is the world worker's (in progress) |
| Camera path | PASS (partial) | root cause found: in the real world the plaza was an NPC routing island (stalls on street mouths and on the well ring) so the route cut through houses; fixed for every town (plaza->street partial routes 260 -> 7 segments). Remaining: brushes standing stones / a kit-house corner at the lane end; NPCs within 1.6 m hidden for the shot |
| Night | PASS (partial) | kit houses no longer self-lit (bounce/rim emission x0.12 after dusk); warm lamps vs cool sky; no black frames |
| Interior | PASS (partial) | review camera now films with the room's own Environment (it used the outdoor grade: that was the blue-grey); VoxelGI baked at entry + ReflectionProbe + thin volumetric haze (HIGH); weathered limewash walls (worn_mossy_plasterwall, soft), plank floor. Still: flat light-wood furniture boxes, plain window panes |
| Street ground | FAIL (world lane) | streets/plaza read as meadow in the real world: the Terrain3D instancer put grass on them; world worker fix in progress |
| View closer | FAIL | B28 stone chapel (pr_chapel) wired + occluder, but the slice camera looks at the plaza bell tower; chapel placement on the real-world main-street axis not yet confirmed on screen |
| Edge kit houses (poor lane) | FAIL | still pale plank/plaster boxes next to the hero houses |
| NPCs / crowd impostors | FAIL (NPC lane) | faceted bodies; grey-blue distant impostors |
| UI restraint | FAIL (UI lane) | "ASHFORD RING" world sign board and nameplates: core/nameplates.gd + main.gd:1062 station labels (not towns code) |
**Verdict: FAIL. Not sent.**

## 2026-10-28 Interior kit (Blender refine worker): asset-level gate in firelit light vs refs 09/20 / KCD interiors
File: `docs/plans/props_refined/interior_sheet.jpg`; verdicts are in `docs/plans/props_refined/README.md` (Interior kit).
| Result | Assets |
|---|---|
| PASS | stool_three_leg, chair_woven, chest_iron, shelf_pottery, herbs_rack, window_closed, window_open, beam_2m/3m/4m, post_2m/3m |
| PASS (borderline) | bed_rope (the blanket reads light, not heavy wool), floor_rushes (opaque mat; a decal would blend better) |
Not in-game yet: the towns worker places them and re-gates in the actual rooms.

## 2026-10-28 · NPC anim lane · crowd far tier: grey-blue ghosts and a pixel person in the Ashford street (towns v4) — FIXED
Video: PA_plans/videos/street_alley_after_vatatlas.mp4 (same towns fly-through, HIGH) vs slice_ashford_street_v4.mp4.
| Problem | Cause | Fix |
|---|---|---|
| grey-blue ghost figures at 15-60 m | sprite impostors rendered `unshaded` (flat, ignoring sun, ambient and fog) with nearest filtering | impostor.gdshader lit (lambert, camera-facing normal tipped up, specular off) + linear filtering |
| pixel person at ~2 m | the pop-QA "keep the sprite while in view" hold let a held sprite ride right up to a moving camera | NO_SPRITE_R 15 m in PopulationLOD: inside it a resident is a body or VAT (VAT cap ignored there), never an impostor; the vanish-hold hands a near sprite to its VAT twin |
| near VAT figures faceted / flat-coloured | VAT albedo was baked into vertex colours of a 1.3k-tri mesh | VatAsset.albedo_tex + UV1: the VAT shader samples the same character atlas as the body (x vertex colour x tint); near mesh rebaked at the full _lod1 (~2.7k tris), far mesh ~1.4k; VAT texture total ~45 MB on HIGH (LOW loads 4 looks) |
| more than 8 people inside 9 m drawn as VAT on every tier | NEAR_HARD_CAP 8 clamped the documented 8 / 11 / 12 near-body caps | NEAR_HARD_CAP 12 (near cap = min(12, npc_full + 3)) |
vat_test side by side: the VAT twin now matches the skeletal body in colour, texture and lighting. The fly-through shows a lit, coloured crowd at every distance, with no impostor inside 15 m.
## 2026-10-28 · towns lane · Ashford interior pass 2 + refined interior kit, street v6 — interior closer, street FAIL items unchanged
Files: PA_plans/videos/slice_ashford_interior_v8.mp4 (13:00), slice_ashford_street_v6.mp4 (14:30), real world, 0 script errors; night bed stills (scenario house 3 sleepers, inn loft 2) on the kit rope beds.
| Check | Result | Note |
|---|---|---|
| Walls (a) | PASS (partial) | plastered_wall_02 limewash with big soft mottling, soot above the hearth, grime at the foot; kit post_3m posts and beam_4m sill/plate/joists. Still reads a little grey at noon |
| Lighting (b) | PASS (partial) | dim and firelit: hearth omni with soft shadows (MEDIUM+), embers by day, ambient x0.6, room daylight x0.55; VoxelGI bounce; window shaft spot on HIGH |
| Beds (c) | PASS | kit bed_rope on the floor, undyed bedding; sleepers lie on them (Life_Mz_Sleep_Bed frame) |
| Windows (d) | PASS (partial) | kit window_open (leaded panes, plank shutters) with warm horn glow; one shutter reads proud of the wall |
| Floor (e) | PASS (partial) | kit floor_rushes mats along walls, bare path from the door |
| Street camera | PARTIAL | margin 0.65 m and 1.6 m sideways search: no frames inside walls; the Ashford Ring menhirs have no collision, so the shot still passes close to one |
| Street ground | FAIL (world lane) | wild plants gone (76e2a588c) but the plaza/streets still read as yellow grass from the eye-level camera |
**Verdict: interior close to the refs' mood; overall slice still FAIL (street ground, NPCs, UI labels, edge kit houses).**

## 2026-10-28 · NPC anim lane · T-pose ship-blocker (three guards in the street fly-through) — FIXED
Video: PA_plans/videos/street_alley_after_tposefix.mp4 (towns fly-through, HIGH) with the T-pose watcher on: 0 rest-pose rigs.
| Item | Result | Note |
|---|---|---|
| Cause | found | RoadTraffic "patrol" built 3-4 Guard characters and never played a clip (pilgrims and drivers only had no fallback) |
| Fix at the source | done | road_traffic.gd: _walk_clip() for patrol guards (Life_Guard_Patrol_Walk / Walking_A / Walk, desynced) and pilgrims, Idle fallback |
| Safety net | done | scripts/living_world/anim_watchdog.gd (installed by PopulationLOD): every new AnimationPlayer driving a skeleton is checked 0.5 s later; visible and not playing, no active AnimationTree, no held pose -> the rig's idle starts and the spawner is logged (ANIM_WATCHDOG); hidden rigs are re-checked when they show |
| Test | 2/2 green | tests/test_no_tpose.gd: road-traffic patrol / wagon / pilgrims at all 4 tiers have a playing clip and arms off the rest pose; 16 looks spawned with no clip are animated by the watchdog at tiers 0 and 3 |
| Detector | tool | tools_qa/living_world/tpose_watch.gd (ASHES_TPOSE_WATCH=1 in the towns fly-through, SLICE_TPOSE in slice_route): reports any visible humanoid whose arms sit at the rest pose |

## 2026-10-27 MPFB pilot stage 2 + in-game side by side (player-animation worker) - PASS (body, face, clips, budget), FAIL (shadow speckle on one sleeve, flat clothing read)
Sheets: `docs/qa/golden/slice/mpfb_pilot_vs_crowd_3m.png`, `mpfb_pilot_vs_crowd_10m.png` (Ashford, current crowd villager on the left, pilot on the right; `SLICE_PILOT=1 tools/qa/record_slice_move.sh`), `mpfb_pilot_clip_check.jpg` (`tools_qa/anim_states/mpfb_clip_check.gd`), `mpfb_pilot_sleeves_godot.png`.
| Check | Result | Note |
|---|---|---|
| Clothing: plain worn wool tunic, no mail panel | PASS | undyed brown wool, fibre noise, hem dirt, sweat bands; pants and boots keep their texture plus mud toward the feet. Garments are baked into fresh non-overlapping UVs (MakeHuman mirrors sleeve islands); alpha cards (hair, brows, eyes) keep their own textures |
| Budget | PASS | 6.9k tris LOD0 (body 1.95k with head and hands protected, tunic 2.1k, pants 0.8k, boots 0.7k, hair 1.0k), 7 x 1K textures; 5.5k hidden body faces culled under the clothes. Godot auto-LOD is off for now (see below) |
| Rig: 53 vs 65 bones | PASS | the MPFB mesh is bound to the exact UAL armature (pose into the UAL rest, translation-only fit), so the 65-bone UAL skeleton is the skeleton. Root->root, head->Head; the leaf / neutral bones come with UAL |
| Every clip family plays | PASS | Idle, Walk, Jog_Fwd, Mx_Run_Fast, Sitting_Idle, Sword_Regular_A, Mx_Walk_Standard, Crouch_Fwd play without distortion; hands and fingers follow |
| Face silhouette after decimation | PASS | two-pass decimation keeps the head and hands (72% of the body budget) |
| In game at 3 m vs the current crowd | PASS (realism), FAIL (polish) | real proportions and face next to the stylised villager. FAIL: one sleeve shows a dotted dark speckle in game. It is identical across three asset rebuilds and not present in the clip-check renders, so it is shadow acne between the outer short sleeve and the under-sleeve (thin double layer), not texture. Next: cull the under-sleeve faces covered by the outer sleeve (self-cull pass). The wool reads flat and clean at 3 m in the game's light: grime and fibre contrast need to go up, plus a fabric normal map |
| At 10 m | PASS | both read as villagers; the pilot's silhouette and proportions are more natural |
| Spring chains (hood, belt ends) | NOT DONE | CHARACTER_PLAN has no spring-chain section yet; to add with the hood layer |

## 2026-10-28 · NPC anim lane · M5 G1 conversation circles in Ashford (wired)
Videos: PA_plans/videos/slice_2026-10-27_1752_d63fd2775_conv_before.mp4 (ASHES_MOTION_OFF=1) vs slice_2026-10-27_1755_758fe225c_conv_after.mp4: slice_route SLICE_CONV gate, 4 villagers sent to the square's conversation spot, fixed camera on the clearest side.
| Check | Result | Note |
|---|---|---|
| Circle layout | PASS | SmartObjects.stand_xform for "group" types uses GroupMotion.circle_slot / circle_yaw (ring sized for the slot count, open arc toward the spot's forward, everyone facing the centre); before: a tight 0.6 m cluster |
| Speaker turns | PASS | conversation_group.gd: one GroupMotion.Token per spot; turns rotate fairly (log: speaker 3 -> 1 -> 0 -> 2 -> 3, 3-7 s each); the speaker plays a ClipPicker talk clip, listeners listen / nod |
| Gaze | PASS (by log) | listeners look at the speaker's head, the speaker at GroupMotion.gaze_listener |
| Errors | 0 | GroupMotion is preloaded by path in smart_objects / villager / conversation_group (a stale class cache had broken every script that depends on smart_objects.gd) |
Still open: a semi-transparent (dither-fading) passer-by near the circle in both runs, to be checked in the pop lane.

## 2026-10-28 · towns lane · interiors pass 3-4 (WIP-good) + poor quarter + street v9 — interior PASS (WIP), street FAIL items narrowed
Files: PA_plans/videos/slice_ashford_interior_v13.mp4 (13:00), slice_ashford_street_v9.mp4 (14:30), real world, Movie Maker 1280x720 30 fps HIGH, 0 script errors.
| Check | Result | Note |
|---|---|---|
| Interior scale | PASS | ground ceiling 2.45 m (was 2.8), loft headroom 2.0; family_loft 6.2 x 5.4 m with the loft over the back 2.3 m; table out in the room, bench pulled up, stools at the hearth; layout validation + 81 interior tests green |
| Interior density | PASS (WIP) | ~50 clustered real-scan/refined pieces (7 kinds per room, batched: every room <= 60 draws, counted incl. MultiMesh), hearth corner, cloaks on a peg rail, herb rack, skins, spinning wheel; no white ceramic blobs |
| Interior walls / light | PASS (WIP) | limewash patches + rising damp tide line, close studding + mid rail + braces, soot over the hearth; dim firelit. Later polish: richer wall variation, darker room edges |
| Poor quarter | PASS (partial) | hovels are now the refined B60 thatched cottage (lot sizes and door sides unchanged: save compat); remaining kit houses re-baked with aged linear colours, grey-brown thatch, wattle patches, back lean-tos on the poor narrow houses. Some low pale sheds at the lane end still read flat |
| Street ground | PASS | setts / packed earth (world worker 0058ce261) |
| Camera | PARTIAL | 1.2 m clearance first, 0.65 m where narrow; no frames inside walls; still passes close to one Ashford Ring menhir |
| NPCs / UI labels | other lanes | |
**Verdict: interior WIP-good (parked); street still FAIL on the menhir pass, the lane-end sheds and the NPC/UI lanes.**

## 2026-10-28 · NPC anim lane · M8 L2 lean + L5 carry pace wired (villager)
Videos: PA_plans/videos/slice_2026-10-27_1801_635671851_gait_before.mp4 (ASHES_MOTION_OFF=1) vs slice_2026-10-27_1806_591b78391_gait_after.mp4 (slice route, ASHES_CARRY_SHARE=0.6), 0 script errors in both.
| Check | Result | Note |
|---|---|---|
| L2 lean | PASS | GaitRules.lean_step on NEAR/MID villagers: roll into turns (<= 5 deg) and pitch with speed (<= 3 deg) on the model root, critically damped; no tipping or pops on the route |
| L5 carry | PASS | carry errand loads slow the pace (carry_pace_mul) and add their lean bias (sack forward, crate back) |
| L3 / L4 / L6 | NOT YET | gait rungs, start / stop / turn transitions and gait sets change which loco clips play: staged next with their own foot-slide gate |

## 2026-10-28 · NPC anim lane · "glowing ring with a floating 2" on the conversation spot — explained, spot fitted off the landmark
The marker is not a gizmo: it is the Ashford Ring menhir's carved ward glyph (circle + chevrons) seen through the camera-occlusion fade, because the
square's conversation spot had been laid out ON the runestone circle's menhir (QA listing: road_stone_b_menhir at the spot centre).
Fix: NpcWorld.fit_group_spot() (first claim, like the wall leans) checks the circle footprint (cylinder 0.3-1.5 m above the ground)
against world colliders and nudges the spot out (0.5 m steps, 8 directions, up to 4 m): the Ashford spot moved 4 m clear of the
stone (PA_plans/videos/slice_2026-10-27_1831_385b5517a_conv_fit.mp4). The runestone glyph remains landmark art (towns / world lane).
