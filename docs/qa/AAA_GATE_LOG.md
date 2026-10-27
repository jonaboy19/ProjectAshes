
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
