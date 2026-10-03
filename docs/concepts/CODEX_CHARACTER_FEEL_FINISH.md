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
