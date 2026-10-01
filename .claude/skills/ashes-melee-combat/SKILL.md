---
name: ashes-melee-combat
description: How to build or extend melee combat and NPC fighters in Rising Ashes (player swings, parry/guard-break/clash, monster and humanoid fighter AI, attack tokens). Use before touching player.gd combat, monster.gd, wolf.gd, creature_attack_tokens.gd or adding a new weapon, creature attack or enemy fighter.
---
# Rising Ashes melee combat

Design source: `docs/research/MINING_COMBAT_WORLD.md` (patterns studied from GPL games; never copy their code or data).

## What exists (kingdom/scripts/actors)
- `player.gd`: `COMBO` array (anim, speed, damage, cost, hit, lock), `_start_swing`, `_resolve_hit` (timer at hit time, cancelled by `_swing_id`), buffers (`ATTACK_BUFFER`, `DODGE_BUFFER`), cancel tail (`SWING_CANCEL`), `_in_active_frames`, `_parry`/`_track_block`, hit-stop, lunge/target assist.
- `monster.gd`: SPECIES table (windup, recover, cooldown, reach, damage, knock, ring), `_strike` -> `_impact`, telegraph, states WANDER/ALERT/ATTACK/FOLLOW/YIELD, `_decide`.
- `creature_attack_tokens.gd`: shared close-attack slots (cap 1/2/3, STAGGER, STRIKE_GAP). Always go through it for anything that can gang up.
- `wolf.gd` duplicates parts of monster logic: change both or extract.

## Rules when extending
1. Timing is data. Every attack is windup / active / recovery seconds plus cancel windows. Never hardcode timings in branches. Prefer a table row (later a `CombatAction` resource) over new if/else.
2. Hit resolution happens once per swing per victim during the active window; keep a `hit_ids` set; cancelled swing (dodge/stagger) must drop its hit.
3. Outcomes are graded: HIT, BLOCKED, PARRIED, GUARD_BROKEN, CLASHED, DODGED. Put the logic in one pure static resolver (like `Tokens`) so tests run headless without scenes.
4. Attacking commits you: no free parry mid-swing; dodge may cut startup/recovery but waits for active frames (existing rule).
5. Clash: both swings active within ~0.12 s and parryable -> compare poise_damage + stat + seeded random; loser CLASHED 0.45 s pushed back, winner shortened recovery. No lock minigame (animation cost too high for mobile).
6. Guard: hold = block (stamina = 0.6 x damage), first 0.18 s = parry (riposte bonus, stamina refund), poise overflow = GUARD_BROKEN 0.9 s.
7. Lanes (high/mid/low) only change block effectiveness and armour location, never need unique animations.
8. Telegraphs are mandatory for any attack that deals > 15% player HP: use the existing nameplate/orange telegraph and keep windup >= 0.35 s on touch.

## NPC fighter model (cheap, rank-weighted dice, 4 Hz think)
- Data per archetype: moves (weighted action ids), rank 0..10, poise, react, style tags.
- `aggression` 0..1 adjusted every 2-5 s: up when target recovers/is tired/ranged-idle, down when own HP low.
- States: APPROACH, CIRCLE (ring radius, existing), POKE, COMBO, GUARD, RETREAT, FEINT (rank 6+).
- Reaction to a player windup in reach: `chance = rank*0.07`, delay `0.25 - rank*0.015` s, no repeat within 1.2 s.
- After winning a clash/guard-break: `rank/30` chance to press immediately.
- Tokens still gate who may close in; extras circle.
- Sleep far fighters (0.5 s tier beyond ~25 m, none beyond ~60 m).

## Mobile budgets
Combat logic <= 0.5 ms/frame, <= 8 awake fighters, <= 3 sampled hit shapes per attack, pooled VFX, one resolver call per attack, no per-frame physics queries from idle NPCs.

## Tests (required)
Add pure-logic tests: resolver truth table, cancel-window timings, token caps, and a seeded headless duel arena (N fights, assert win rates within a band) before tuning content. See `ashes-cloud-testing` for how to run gdUnit in the cloud. Do not run all of Godot at once (OOM).

## Do not
- Copy any GPL/AGPL code, tables, animation names or numbers from reference games.
- Add per-weapon branches in player.gd; add data rows instead.
- Call VFX/Audio inline from new combat code; emit signals (`swing_started`, `hit_confirmed`, `parried`) and subscribe.
