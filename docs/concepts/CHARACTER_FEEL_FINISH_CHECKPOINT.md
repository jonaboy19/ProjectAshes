> Historical checkpoint from 2 October. For current implementation, recordings and unresolved checks, read [CODEX_CHARACTER_FEEL_FINISH.md](CODEX_CHARACTER_FEEL_FINISH.md). The pivot wiring and full-project startup described as pending below have since progressed.

# Character feel finish checkpoint

2 October 2026. Isolated branch gpt/character-feel-finish now starts from published Claude head 1983bfeb. Explicit fetch showed origin/main at 31ecc059 is behind; origin/claude/focused-curie-m09hbd contains locomotion integration merge 0fa52409 and Style G pass 4 bf05e677. Do not infer that Codex's local code is missing because main is behind. Both existing dirty Claude worktrees remain untouched.

The user's Claude handoff assigns two remaining player animation problems to Codex: pivot180 clips not hooked up, and run-stop sword pop. Source confirms player._steer brakes then replaces move direction while character_animator's air machine has run stops but no pivot180 states. Run-stop is passed through play_locomotion_transition -> play_air, replacing the full body including held-weapon/arms pose. These are mechanisms to investigate, not yet verified causes for every visible pop.

Next implementation: preserve upper-body armed pose during locomotion transitions with a dedicated lower-body filter whose fade-out does not change abruptly; register the authored pivot180 clips and coordinate facing progression with the same movement/action clock. Keep jumps/rolls full-body, preserve combat override/cancellation, avoid double root/yaw application, and verify frame by frame with the current G hero. Stop root displacement and visible stopping stride must remain aligned. No production animation fix is claimed at this checkpoint.

## Run-stop layer implemented

## Pivot yaw sampling implemented; controller hookup still pending

Both authored Pivot180 clips are registered in the air machine. `pivot_yaw()` reads the actual disabled root rotation track as data, caches 30 Hz samples, unwraps heading past ±180 degrees and interpolates at clip time. It applies no rotation itself, preserving Assets' existing prevention of double root yaw. The same headless diagnostic now checks disabled synthetic root tracks ending +188 and -182 degrees, plus midpoint interpolation; checks pass. Actual imported-clip frame capture and Player movement/facing coordination remain pending. Registering clips alone does not fix the reversal snap.

CharacterAnimator now has a dedicated filtered locomotion OneShot with independent playback rate, 0.08 s blend-in and 0.18 s blend-out. Only the existing LOWER_KEYS bones are included; armed arms/hand/weapon pose remains with the normal upper-body layers. Stops no longer borrow the full-body air blend. Player transition expiry/cancellation now finishes that OneShot separately; jumps and landings keep the existing full-body air machine. No clip or outfit was edited.

Headless Godot 4.6.3 check passed using a copied animator with only its Assets.animation_player lookup replaced by a direct model lookup, and a synthetic three-bone fixture. It confirms the lower filter includes pelvis/thigh, excludes hand, locomotion transitions leave air target at zero, filters persist through fade-out, and jump uses an unfiltered air blend. This verifies code parsing and layer configuration, not the real hero's pose or a visible sword-pop fix. Real equipped-hero frame capture and interruption coverage remain required. Pivot clips are still unwired.

Separate lab traversal continues with imported root/body samples and bounded pose preflight. The fixture rejects the authored vault's obstructed leg poses; sample-only clearance is not approval to commit an action. Map changes db9abd8c and 50b40257 belong to the older isolated living-world branch and have not been merged here. Preserve them when integrating, without pulling incidental asset-import sidecar changes into the animation patch.
