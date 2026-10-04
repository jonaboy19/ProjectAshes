# Exhausted attack timing correction — 4 October

Branch: `gpt/character-feel-finish`. Scoped source change: `kingdom/scripts/actors/player.gd`. Existing clips and move data are reused; no assets generated or added.

## Defect and correction

Exhaustion played attacks at 70% speed and delayed their contact frame, but left recovery, attack-cancel tail, combo duration and the protected active-frame interval at normal speed. This could permit the next action before the slowed visual swing reached its intended recovery.

The current swing now stores an action-time multiplier of `1 / playback_multiplier`. Hit time, total duration, cancel remaining time and active-frame offsets use that same multiplier. The combo input grace remains the original `COMBO_WINDOW` after the scaled duration. Finishers retain zero attack-cancel tail and terminate their chain. Normal-stamina playback is unchanged mathematically.

Move durations already include their normal authored animation speed. Do not additionally divide these timings by `action.anim_speed` during integration.

## Review status

The resulting source diff and all references to the changed timing fields were inspected. Runtime and visual verification have not been performed for this patch. Do not describe it as an in-game pass or phone performance result.

Required follow-up: exhausted first swing and finisher; buffered combo before/inside cancellation; dodge during slowed active frames and recovery; stamina restoration between swings; visual contact timing using the existing real-game capture harness. No new animation pack is needed.

## Separate open questions

Hit resolution still uses a SceneTree timer. Trace mixer-only impact pause before changing that mechanism. Dodge completion still has an unversioned timer callback; confirm action ownership in dodge-to-jump cases before patching it. Attack target acquisition still assigns yaw instantly; review its actual turn angle before changing combat assist.

### Additional source tracing

`impact_pause.gd` confirms ordinary impacts pause only selected AnimationTree/AnimationPlayer mixers until a wall-clock deadline; physics and action countdowns continue. Longer finisher/parry pauses use global time scaling instead. Therefore a local impact pause can separate visual progression from recovery countdowns. It is not yet established which observed transition is affected. A correction needs one explicit action clock policy shared by actor progress, visual playback, contact events and cancel windows; changing only a SceneTree timer would leave the other clocks inconsistent.

`combat_feedback.gd` already passes actual slowed animation speed to the blade ribbon and derives fallback slash time from the adjusted hit time. Those paths need no duplicated exhaustion multiplier. `HitResolver.CLASH_WINDOW` is an independent real-time clash tolerance; this patch deliberately preserves its units rather than scaling it with animation playback.

The traversal handoff contains historical assumptions that disagree with the inspected loader: it claims all `animations_free2/` root tracks are covered, while the current loader only covers its selected locomotion directory. It also proposes temporarily disabling wall collision during mantle/climb. Do not implement those instructions verbatim: retain collision-tested body movement and the current traversal lab's rejection of penetrating clips. Existing source and measured geometry take precedence over old integration recipes.

## Integration

Apply the focused player diff onto the latest actor implementation, preserving Claude's later changes. Do not copy the entire older actor file or stage unrelated generated import modifications. This branch's earlier stop/pivot work has its own evidence in `CODEX_CHARACTER_FEEL_FINISH.md`.
