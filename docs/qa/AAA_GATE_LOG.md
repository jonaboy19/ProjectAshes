
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
