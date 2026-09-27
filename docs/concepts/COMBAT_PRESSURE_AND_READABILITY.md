# Combat pressure and readable encounters

**Audience:** Claude implementation branch `claude/focused-curie-m09hbd`

**Scope:** design and implementation handoff only. This document does not change game scripts, scenes, assets, or project settings.

## Why this needs its own pass

The current playtest report records player death in all four fights: encounters with four wolves and with as many as seven goblins. Those runs included attacks, blocks, and dodges. It also records wolves fleeing below 15 HP at 8 m/s while the player runs at 7 m/s. The report is observed playtest evidence; it is not a controlled balance study, and it does not by itself identify which tuning change will fix the fights.

Source inspection gives concrete pressure points to investigate:

- `kingdom/scripts/actors/wolf.gd`: each wolf independently enters attack inside its territory, chases directly, starts a bite within 1.9 m, and schedules 9 damage after 0.25 s if the player remains within 2.4 m. Bite cooldown is randomized from 1.2 to 1.8 s. There is no shared pack attack schedule in this controller.
- `kingdom/scripts/actors/monster.gd`: goblins independently aggro the player within 9 m (or 16 m near home), approach directly, and schedule damage 0.3 s after an attack if still within 2.4 m. Damage is species damage plus level; the per-attack cooldown is 1.1 to 1.7 s. There is no shared group pressure limit in this controller.
- `kingdom/scripts/actors/player.gd`: dodge grants 0.35 s invulnerability during a 0.45 s dodge. `take_damage()` also has a 0.35 s hurt cooldown. Player melee resolves by distance and facing against `team1` actors; this function does not test intervening geometry.
- The enemy delayed-damage callbacks check distance at impact but do not test line of sight or a swept attack volume. Because these actors move by direct position updates rather than physics bodies, proximity alone can produce contact through a wall or after the visual attack has missed.

These are code facts from the inspected source. The consequences below are design risks to verify in a repeatable runtime capture, not claims that each case has already been reproduced. Refresh source locations and behavior against Claude's latest branch before implementing; this handoff was prepared from the reviewed baseline and playtest record.

## Design targets

1. **The player can read danger.** Every damaging move has a recognizable wind-up, contact moment, and recovery. A hit is avoidable by a response the player can reasonably perform at that time.
2. **A group takes turns applying close pressure.** Nearby enemies may surround, stalk, feint, reposition, or threaten from range, but only a bounded number own an immediate attack opportunity at once. The cap and cadence should scale deliberately with encounter size and difficulty.
3. **Geometry decides contact.** Attacks cannot damage through solid walls or props. Movement and knockback stop at world geometry. Valid doors and gaps remain traversable.
4. **Feedback confirms a real result.** Hit sparks, hit-stop, sound, and hit reaction occur only when the hit query confirms contact. A blocked or dodged attack gets its own readable feedback.
5. **The fight has a coherent ending.** Fleeing enemies use a reachable escape route and a defined retreat outcome; they do not run indefinitely just beyond the player's speed.
6. **Existing scale remains intact.** Apply detailed encounter coordination only to active nearby combatants; keep distant simulation inexpensive.

## Recommended order

### 1. Reproduce and measure before tuning

Create fixed encounters for one wolf, four wolves, one goblin, and a seven-goblin group. Record player/enemy health, damage events, who began each attack, attack wind-up/contact/recovery timestamps, distance and obstruction at impact, blocks, dodge invulnerability, and encounter duration. Record quality tier and frame-time context. Re-run each scenario with the same starting positions and input sequence after each change.

The chart in [the pressure-window viewer](COMBAT_PRESSURE_WINDOW_REVIEW.html) is a simplified editable design model. It illustrates theoretical overlap of independent attack timers and player protection windows. It is not a replay, a source simulation, measured sustained DPS, or a balance answer.

### 2. Coordinate attack opportunities

Add one lightweight encounter coordinator or equivalent shared ownership rule for nearby hostile actors. It should reserve a small number of attack slots, stagger openings, expire abandoned reservations, and release a slot on hit reaction, death, lost target, retreat, or invalid route. Actors without a slot should visibly circle, hold distance, reposition to an open angle, or briefly feint. Avoid a static queue where every enemy faces the player and waits in a line.

Keep threat legible: one attacker commits while others create space and approach from distinct angles. Tune the number of simultaneous attacks and their cadence by encounter size, enemy role, and difficulty. Do not select a universal fixed cap from the theoretical chart alone.

### 3. Make attack timing and contact agree

Represent each attack with explicit wind-up, active window, and recovery values linked to its animation. Prefer animation call-method events or authored normalized windows when reliable; otherwise keep a single move definition as the timing source for both animation and gameplay. At the active window, revalidate that attacker and target are alive, the target is still valid, distance and facing qualify, and a physics query finds no solid obstruction. For lunges or bites, use a swept shape/raycast over the movement interval so fast movement cannot tunnel through a narrow target.

Apply the same contact discipline to player melee: use a swept arc/overlap query and world occlusion, so a target behind a wall is not hit and a valid close target is not skipped between frames. Preserve dodge's intended invulnerability interval, then check if the attack remains active at the moment that interval ends; do not let a stale timer silently convert a clearly evaded swing into damage.

### 4. Route and collide combatants

Once the approved building/prop collision profiles are reliable, give nearby combatants physical movement and obstacle-aware routes. Navigation/steering should lead around solid geometry; physics should still prevent penetration at the final contact. Keep a small near-actor cap and profile it. Enemy hit impulses, attack lunges, and retreat movement must also respect collision. For this slice, validate a wall, a corner, a cart or stall, an open doorway, and uneven ground.

### 5. Make retreat a finished behavior

Choose the intended wolf fantasy: a wounded animal may escape, but the escape should resolve visibly. Route it to a reachable retreat point or den, make it leave combat and despawn/return only according to the game's world rules, and provide clear feedback that it escaped. If the design expects the player to finish it, its chase/reposition behavior must leave a fair opportunity to do so. Do not solve this only by lowering the player's run speed or forcing a faster pursuit.

### 6. Tune survivability from the event log

Theoretical maximum overlap is not realized damage: range, wind-up, slots, blocking, dodge, missed attacks, and the player's 0.35 s hurt cooldown all affect outcomes. Use event logs to compare incoming attack attempts, successful contacts, blocked hits, dodged hits, and damage per encounter. Tune enemy damage, attack cadence, player health/stamina, recovery, and attack-slot count only after attack fairness and collision are correct.

The viewer uses 9 damage per wolf bite and a representative 1.5 s cooldown as an upper-bound illustration: roughly 6 raw damage/s per wolf, or 24 raw damage/s for four wolves if their attacks all landed at that rate. This is intentionally not presented as actual sustained damage or expected DPS.

## Acceptance checks for the implementation branch

- Four-wolf and seven-goblin encounters show staggered, readable attack starts; count simultaneous committed close attacks in the capture and explain the chosen cap.
- A player can identify the wind-up and avoid each attack with a deliberate move; delayed damage never lands after a confirmed miss, dodge, death, or invalid target.
- An enemy and player attack cannot hit through a solid wall, stall, cart, or building collider. Valid doorways remain open.
- Combatants and knockback cannot pass through solid world geometry. Route failures produce a visible recovery/reposition outcome rather than wall clipping or an infinite chase.
- A yielded, fleeing, dead, or otherwise inactive enemy releases any attack reservation promptly.
- The low-health wolf encounter reaches an understandable retreat or finish outcome without an indefinitely uncatchable target.
- Before/after captures include event logs and equivalent encounter setup. Report successful hits per attempted attack, player damage, block/dodge results, fight duration, active actor count, and frame-time percentiles on supported quality tiers.
- Recheck the existing NPC collision/path audit and player impulse review when the implementation changes movement, attack lunge, knockback, or body collision.

## Out of scope for this handoff

This is not a request to replace the combat system, import another project's combat framework, or copy code wholesale. The [open-world pattern study](OPEN_WORLD_PATTERN_STUDY.md) already recommends borrowing system boundaries and evaluating licenses before code reuse. Keep this implementation native to Rising Ashes' actors, encounter scale, art, and controls.
