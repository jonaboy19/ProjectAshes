# Player mechanics response review: impulse integration

**Status:** source-grounded review for Claude; no controller changes made.

**Baseline:** `claude/focused-curie-m09hbd` at `e3563fc4`; re-check current source before implementation.

Open [PLAYER_IMPULSE_REVIEW.html](PLAYER_IMPULSE_REVIEW.html) to adjust the fixed physics tick rate and compare horizontal speed after a 3 m/s kick.

## Evidence in the controller

In `kingdom/scripts/actors/player.gd`:

- Lines 201–202 blend horizontal velocity toward the requested movement velocity, then add `_impulse.x/z` directly on that physics step.
- Line 203 reduces the remaining vector toward zero by `30 * delta` each step.
- `_start_swing()` assigns a forward vector of magnitude `2.5` at line 286, apparently to create a short melee lunge.
- Blocking assigns a backward vector of magnitude `3.0` at line 355. Received hit knockback is assigned at line 370. Enemy attack damage passes a direction multiplied by `2.0` in `monster.gd:221`; player melee passes magnitude `1.5` by default or `7.0` for the finisher (`player.gd:298`, `317`).

The variable is stored as a vector, decayed over time, and added to velocity every physics iteration. If its magnitude is intended to mean an instantaneous velocity change (m/s), this applies it repeatedly instead of once. At the default 60 physics ticks/s, the isolated chart simulation of a 3 m/s value peaks at about 6.24 m/s and moves about 0.88 m over two seconds, compared with a one-time 3 m/s kick that peaks at 3 m/s and moves about 0.25 m with the same subsequent `lerp` damping. These are calculations from the source recurrence, not measurements from gameplay.

The current `project.godot` does not override the physics tick setting. Godot 4.6 documents 60 fixed physics ticks/s by default, separate from rendered FPS. The response changes if the physics tick rate is changed; it is not correct to describe the current issue as directly tied to render FPS.

## Recommendation for a small code review

First decide what the values mean. If they are intended as **velocity kicks**, queue each event and consume it once inside `_physics_process` (or otherwise add it to `velocity` once at the event boundary). Keep velocity damping/friction as a separate, measured rule. If they are intended as **acceleration**, multiply by `delta`, rename the field to communicate those units, and retune the values because `2.5 m/s²` applied for roughly 0.08 seconds is a very different effect from a 2.5 m/s kick.

Keep a little authored forward attack lunge if combat needs it, but use a separate, tunable lunge parameter so changing defensive knockback does not also change sword movement. Preserve walls and body collision during all impulses. Do not convert every hit to root motion: physics must still stop attacks and recoil at obstacles.

Before adopting either interpretation, record the same idle hit, frontal block, ordinary swing, finisher, dodge-cancel, and wall-adjacent hit at the current 60 Hz. Compare peak speed, total displacement, stopping time, wall penetration, and whether the upper-body hit/attack animation remains aligned. Keep the QA capture and the selected numbers with the gameplay change.

## Scope and limits

This review only examines the player's horizontal `_impulse` integration. It does not prove that the controller currently feels wrong in every scenario, choose a final combat tune, or diagnose NPC wall traversal. The separate [natural-world plan](NATURAL_WORLD_FEEL_PLAN.md) and [NPC life-loop design](NPC_LIFE_LOOP_DESIGN.md) cover NPC movement and solid-world collision.

## References

- Project source: `kingdom/scripts/actors/player.gd`, `kingdom/scripts/actors/monster.gd`, `kingdom/project.godot`.
- [Godot 4.6 `Engine.physics_ticks_per_second`](https://docs.godotengine.org/en/4.6/classes/class_engine.html#class-engine-property-physics-ticks-per-second): fixed iteration rate, default 60 ticks/s, distinct from rendered FPS.
- [Godot 4.6 physics introduction](https://docs.godotengine.org/en/4.6/tutorials/physics/physics_introduction.html): physics callbacks run on the fixed physics cadence and receive the elapsed physics-step `delta`.
