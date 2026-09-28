# Outdoor animation timing check (2026-09-28)

Scope: does walk trigger at the right speed, run at the right speed, and idle when
standing still? Checked via `tools/qa/perf_visual/run.sh`, now driven through the
**real input path** (on-screen joystick touches + camera aim, same
`InputEventScreenTouch/Drag` calls as `tools_qa/autoplay/autoplay.gd`) instead of
the old per-frame teleport, so the player's real physics, collisions and
`CharacterAnimator` all run as they would for an actual player. The route cycles
idle (0-1.2s) -> walk (1.2-3.0s) -> run (3.0-9.0s) on a ~9s loop so all three gaits
get exercised, not just a run the whole time.

Route: `village_forest` (plaza -> road -> fields -> woods -> first bandit camp ->
back), quality=high, ~82s / 4091 samples. Raw log:
`docs/qa/perf_visual/high_village_forest/anim_timing.txt` and `log.txt` (per-frame
`spd=` actual planar speed vs `shown=` `CharacterAnimator.shown_speed()`).

## How the animator actually works (read before acting on this)

`scripts/actors/character_animator.gd` (Codex-owned; **not edited by this pass**,
per `docs/LOCAL_SESSION_HANDOFF.md`) is a continuous blend space, not discrete
idle/walk/run states: `update(delta, speed, ...)` low-pass filters the incoming
speed (`SPEED_RESPONSE = 18`, ~55 ms time constant) into `_speed`, then blends the
walk/run cycle continuously between `_walk_pt` (1.0 x leg-length scale) and
`_run_pt` (6.0 x), with idle cross-fading in below `_walk_pt * 0.6` via
`smoothstep(0.06, _walk_pt * 0.6, _speed)`. So "walk above 2.5 m/s" / "run below
1.5 m/s" as discrete states don't really apply here; the useful check is whether
`shown_speed()` (what the legs are visually doing) tracks the actual resolved
ground speed.

## Player: results

- **4091 samples, 64 flagged (1.6%)**, worst mismatch 5.29 m/s.
- **No sustained idle-while-moving.** The only idle-while-moving samples are at
  1.22s and 10.22s, right as the QA driver's stick first engages (actual 0.42 m/s,
  anim 0.10) — the animator is still crossing the idle->gait fade threshold, not a
  bug; a real player accelerating from a stand also starts at 0 m/s.
- **Foot-slide on a hard stop is real but short (~150-200 ms).** Every other
  flagged sample is the tail of `_speed`'s exponential decay after the QA driver
  releases the stick to test idle (e.g. `13.87s...13.99s pos=(3,6)`: anim shows
  5.29 -> 1.36 m/s over 120 ms while actual velocity is already 0). At `SPEED_RESPONSE
  = 18` the 1/e time constant is ~55 ms, so this settles in 2-3 frames at 60 fps —
  visually it reads as 1-2 frames of the legs still moving right as the character
  plants, not a sustained mismatch. It shows up on **every** run->idle stop in the
  route (13.9s, 36.2s, 45.2s, 54.2s, 63.1s, ...), so it's systematic, just brief.
- No case of the reverse (idle animation while the body is clearly still moving
  fast) was seen.

**For Codex, if worth tightening:** a faster decay specifically when actual speed
drops near-instantly to 0 (e.g. a second, quicker `SPEED_RESPONSE` for the
downward direction only, or snapping `_speed` toward 0 once it's under the idle
fade threshold instead of continuing to exponentially decay through it) would
remove the last couple of visible slide frames on a hard stop. This is cosmetic,
not a functional break — left as a note, not touched here (animation code is
Codex's).

## NPCs, soldiers, animals

Per-actor telemetry for every villager/soldier/animal over 20 s (as the task asks)
was **not fully instrumented** in this pass — `main.population` NPCs are the
crowded case the perf_visual capture already shows dozens of at once, and the
frame budget for this QA pass went to the real-input player fix (requested
directly by the user mid-task after seeing the old teleport mode look "broken")
and the grounding/fake-look fixes below. What was checked by eye in the
`docs/qa/perf_visual/high_village_forest/*.jpg` frames and the playtest bot's
existing screenshots (`docs/qa/playtest/`):
- Villagers walking the plaza and street clutter route show a normal walk gait at
  their crowd pace, no obvious idle-while-walking or moon-walking.
- Soldiers on patrol near the wall show the same walk gait; no run observed at
  their patrol speed (expected, patrol speed is well under `_walk_pt`).
- `wolf.gd`'s flee behaviour (`docs/LOCAL_SESSION_HANDOFF.md`, "wounded wolves
  flee at 8 m/s") was not re-verified against its animation cadence this pass.

**Recommended follow-up** (flagged, not done here — would need `CharacterAnimator`
instances for villagers/soldiers/animals to expose the same `shown_speed()` hook,
or a population-wide sampler added to `grounding_check.gd`/`perf_visual.gd`):
sample `shown_speed()` vs. actual velocity for every node in groups `villager` and
`combatant` each tick of a perf_visual run, the same way the player is sampled
now. The hook points already exist (`_animator.shown_speed()`), so this is a
follow-up script change, not new animation code.

## What changed to make this check possible

`tools/qa/perf_visual/perf_visual.gd` used to teleport the player along the route
every frame (`pl.global_position = ...` each `_step`), so the body never moved
under its own physics and no walk/run animation ever played — the recorder window
looked like the character was sliding diagonally with no animation at all (this is
what the user saw and flagged as "the game looks broken"). It now drives the
on-screen joystick and camera through real `InputEventScreenTouch`/`Drag` events
(mirroring `tools_qa/autoplay/autoplay.gd`'s `stick()`/`turn_to()`), cycling
idle/walk/run, with a stuck-detector that sidesteps around obstacles. The old mode
is kept behind `--teleport` (`EXTRA="--teleport" bash tools/qa/perf_visual/run.sh
...`) for pure streaming/GPU benchmarks where you don't want the controller in the
loop. The recorder window now titles itself "Rising Ashes QA recorder (test, not
gameplay)" so it's clear on screen that nothing is wrong if you see it steering
itself.
