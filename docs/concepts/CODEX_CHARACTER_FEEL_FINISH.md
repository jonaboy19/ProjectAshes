# Character feel finish — Codex ownership

Source: published Claude branch `1983bfeb`, including Style G pass 4 and the locomotion merge. Work branch: `gpt/character-feel-finish`. These changes concern the run-stop sword pop and the unwired running reversal. Outfit, environment, controls and authored animation files are not part of this patch.

## Changes

- Run stops use a separate lower-body filtered OneShot. The existing armed upper-body pose stays in charge of the hand and sword.
- Both running pivot clips are registered. Heading samples unwrap the authored root rotation across 180 degrees.
- Player selects a pivot for a grounded running reversal, samples its root displacement, and sends that displacement through the existing CharacterBody movement and contact resolution. Root tracks remain disabled on the visual skeleton to avoid applying movement twice.
- Jump, attack, dodge and state reset use the existing transition cancellation path. Releasing movement or hitting a wall cancels the pivot. First-person, crouched and guarded movement retain their existing steering.
- Heading adjustment is restricted to 80–120% of the authored angle. Other angles retain existing steering.

## Evidence so far

Focused Godot 4.6.3 animator fixture passes lower-body filtering, armed-hand exclusion, independent stop playback, preserved full-body jump layering, and synthetic rotation unwrapping.

The actual shipped GLB also passes root sampling checks:

| Clip | Duration | Root yaw | Root displacement, metres |
| --- | --- | --- | --- |
| Left pivot | 1.233 s | +188.554 degrees | (-0.293, 0, -1.134) |
| Right pivot | 1.367 s | -181.623 degrees | (+0.308, 0, -0.635) |

Summed sampled movement matches each endpoint. This checks the sampler, not visual quality in the game.

Follow-up: the graph enters a requested clip on animation evaluation, so an independently accumulated controller timer can lead its pose. Player now reads the state machine's actual clip position for pivot movement and heading. A real-GLB fixture verifies agreement with that playback position and rate increments at 0.5x, 1x and 1.5x. Starting a new pivot explicitly resets its state to avoid reusing a previous pivot's end time. End-to-end physics/render interpolation and hit-pause appearance still require a game recording.

## Still required before merge

1. Run the full project startup. A direct isolated `--check-only --script player.gd` cannot compile the autoload identifier `Life`; that invocation does not establish a startup regression or a successful Player compilation.
2. Record both reversal directions with the Style G hero, including a wall, an edge, released stick, attack, dodge and jump interruptions.
3. Check end-to-end AnimationTree/physics/render interpolation, including slow motion and hit pause. The controller samples the graph clock; the live game's frame ordering and interpolated pose still need review.
4. Inspect foot contact, lean, outgoing gait and sword continuity frame by frame. The lower-body stop filter is a proposed fix, not an observed in-game pass yet.
5. Measure on S22. No phone performance claim is supported by these desktop checks.

Do not overwrite Claude's latest main to integrate this branch. Compare against its current actor files and retain subsequent changes on both sides.

## Continuing mission

Playable traversal remains pending: the existing lab's authored vault audit detects body penetration, so it is not ready for production approval. Map readability and intelligence-report work have separate handoffs. These should continue after the two animation issues are reviewed.

## 3 October verification update

The isolated full project import completed. Actual Player, Enterprise and Campaign scripts load with project autoloads; Campaign's pending and delivered spy-report JSON save round trips pass. A rendered Compatibility/OpenGL launch with `--quit-after 300 -- --codex_verify` takes the QA path into the real main scene, exits zero and logs no script parse, compile or runtime errors. This supersedes the earlier direct `--check-only` limitation as evidence of script loading and startup, but does not establish clean teardown or animation quality.

The default headless launch hits null image readback in the pre-existing impostor baker. Rendered startup was used to avoid treating that headless result as a game regression. Frontend boot and authoring captures also log shutdown resource leaks.

The existing production feel-capture harness is now recording scenarios 02 (run stop) and 04 (running reversal), using the real main scene and input path at 30 fps. Until the recording finishes and its frames are inspected, these motions remain visually unverified. No Style G outfit or environment source was edited. The user has directed work away from the map for now.

## Physics-clock recording review — 3 October

The production capture finished for scenarios 02 and 04. At 30 rendered fps, the idle AnimationTree clock gave alternating movement/zero samples across 60 Hz capsule ticks. The Player tree now evaluates on physics ticks. In the repeated real main-scene capture, pivot frames 408–430 show nonzero measured travel speed throughout, decelerating from 3.00 m/s to 0.41 m/s and accelerating back to 5.75 m/s. Heading progresses through the authored turn, with a maximum sampled step of about 18 degrees rather than a two-frame reversal. No script parse/compile/runtime errors were found in the capture log.

Recording: C:/Users/Jonna/Documents/Codex/2026-10-03/character-feel-physics-clock/stop_pivot.avi. Telemetry and scenario ranges are beside it. The contact sheet is pivot_physics_clock_review.jpg. Grass obscures feet; this fixture does not establish foot locking or the intended Style G outfit. Both-direction obstruction/interruptions, hit pause, sword continuity and S22 profiling remain pending. The physics callback is Player-only; review all other Player actions before integration.

3 October follow-up: the authored traversal lab's preflight initialization no longer creates all segment collision shapes in one burst. Reviewable source/data and reproduction notes are in traversal_preflight_lab/. Existing vault collision rejection is preserved; traversal remains unapproved.

## Action recording after physics clock change

The real-game follow-up finished combo, standing/running/buffered jump, three fall/landing cases, parry and directional hit-reaction scenarios (09, 19, 20, 21, 22), 1,534 rendered frames. Video, telemetry and scenario ranges: C:/Users/Jonna/Documents/Codex/2026-10-03/character-action-physics-clock/. Reviewed contact sheets: jump_physics_clock_review.jpg and combo_physics_clock_review.jpg. Visible jumps and sword poses progress; these wide views do not prove precise foot contact, blade-hit timing or outfit clipping. Close views and interruptions remain required.

No script parse/compile errors were logged. At teardown the harness wrote telemetry after closing its CSV because quit() is deferred. It now disables _process before closing the files. This small harness fix has not yet been checked in a repeated recording. Other renderer/resource leak messages remain unresolved; exit zero is not clean teardown. Auto quality stepped down under the 30 fps Movie Maker cap, so this capture provides no mobile performance measurement.

## Default hero close-up recording — 3 October

The harness now accepts --default-hero (clears the in-memory appearance selection and rebuilds the existing default hero) and --closeup (35-degree camera FOV). Both are optional QA flags. Existing default capture behavior is unchanged. No outfit source was edited.

The repeated production recording finished scenarios 02, 04 and 19, using the default-hero path at LOW quality. Source video/telemetry: C:/Users/Jonna/Documents/Codex/2026-10-03/styleg-closeup-clock/. Reviewed sheets: styleg_run_stop_closeup.jpg and styleg_pivot_closeup.jpg. The pivot shows progressive heading and a transition back into running. The stop samples retain the armed sword pose through settling; these three-frame samples cannot exclude a one-frame pop. Some grass still obscures ankle contact, and LOW geometry cannot establish high-quality outfit deformation. More precise hand/foot telemetry and both-direction interruption checks remain required.

The telemetry-after-close error is absent in this repeated capture, confirming the harness shutdown fix. The recording still logs renderer/resource leaks at shutdown. It exited zero with no logged script parse/compile errors. No mobile performance or AAA-quality claim follows from this recording.

## Measured pose discontinuities — not a quality pass

The optional --pose-data flag records foot_l, foot_r and hand_r world positions/quaternions after frame_post_draw, plus analytic terrain gaps and pivot playback clocks, to pose.csv. It does not run in ordinary gameplay. pose_motion_summary.py summarizes against telemetry.csv and outputs pose_summary.json. Reproduction uses --default-hero --closeup --pose-data --only=02,04 with the existing real-scene capture invocation.

Capture completed: C:/Users/Jonna/Documents/Codex/2026-10-03/hero-pose-diagnostics/. No script parse/compile errors or closed-file telemetry error logged; renderer teardown leaks persist. Summary is checked in as hero_pose_summary.json.

Important follow-up: pivot scenario frame 407 flags 0.673 m right-ankle relative displacement and 64.94 degree right-foot rotation in one recorded frame; hand rotation changes 65.81 degrees. Stop scenario frame 278 flags 0.590 m left-ankle relative displacement. These indicate frames requiring investigation, not proven penetration or sword pops. The pose sampler combines final bone poses with interpolated skeleton world transforms; bone-local render interpolation is not exposed. The reviewed every-frame pivot-entry sheet is pivot_entry_pose_review.jpg. Improve transition entry/stop phase continuity only after distinguishing graph blend, procedural modifiers and source clip pose differences. Do not claim planted feet or completed AAA movement from the earlier smooth root-travel recording.

## Transition refinement and isolation evidence

The --no-procedural QA flag disables the five SkeletonModifier3D nodes for a comparison recording. Stop/pivot discontinuities were essentially unchanged in that LOW fixture. This narrows this fixture's cause to clips/graph rather than those modifiers; it does not establish behavior at HIGH. The authored pivot clock now correctly records _pivot_clip, rather than the unrelated fallback _pivoting flag.

Refinement: run-stop fade-in increased from 0.08 to 0.14 seconds. Authored running pivots use a 0.167-second outer entry blend; other air clips retain the existing rate. On pivot completion, the last pivot pose fades directly into the underlying armed graph, avoiding the extra bare-Idle transition. Exit rate remains the original 12/s. Root playback clocks, collision movement and turn durations are unchanged.

Repeated actual-game recording: C:/Users/Jonna/Documents/Codex/2026-10-03/hero-transition-final/. It completed 02/04 with no logged script parse/compile or closed-CSV errors. Renderer/resource shutdown leaks remain. Final summary: hero_pose_final_summary.json. Every-frame exit sheet: pivot_exit_final_review.jpg.

| Diagnostic maximum | Baseline | Refined |
| --- | --- | --- |
| Stop left ankle relative step | 0.590 m | 0.441 m |
| Stop right ankle relative step | 0.334 m | 0.274 m |
| Pivot scenario right ankle relative step | 0.673 m | 0.526 m |
| Pivot scenario sword hand relative step | 0.339 m | 0.212 m |
| Pivot scenario sword hand rotation step | 65.81 degrees | 48.08 degrees |
| Pivot scenario left ankle relative step | 0.334 m | 0.389 m |

The later left-foot maximum at frame 492 worsened; this scenario also includes release/stop and a walking reversal, so it remains an explicit follow-up. Entry changes are still large: this is incremental improvement, not phase-matched or planted-foot approval. Bone sampling/interpolation and analytic-ground limitations remain as above. Repeat HIGH outfit review, opposite pivot, collision/edge and attack/jump/dodge interruption checks before integration approval.
