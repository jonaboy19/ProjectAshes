---
name: ashes-ability-system
description: How to design and add techniques and powers for Rising Ashes power paths (magic, bending, sect donghua arts, knight arts, beast): resources, cooldowns, chant vs chantless, targeting, effects. Use before editing technique_caster.gd, skills.gd, power_paths.gd, or adding any technique, spell or special move.
---
# Rising Ashes ability system

Design source: `docs/research/MINING_COMBAT_WORLD.md` section 2; canon in `docs/design/ACADEMY_PLAN.md`.

## Existing pieces (kingdom/scripts)
- `realm/power_paths.gd`: paths magic|bending|sect|knight|beast, per-path resource POOL, `can_use(path,cost,ctx)` -> {ok,risk,reason,cost,power}, `use()`, strain/injuries, cross-training penalty, prodigy gate.
- `sim/skills.gd`: trees and ranks, equip slots, passives, `cost_of`, `cooldown_of`, `damage_of`, `can_cast`, `begin_cast(id,pools,sealed)`, `needs_seals`, `tick`, cultivation realm/stage/breakthrough, manuals.
- `actors/technique_caster.gd`: slots, seal minigame, `_pay`, `_resolve` -> area/launch/chain/dash/blink/support, burns, training tags.

## Canon rules (do not break)
- Sect = donghua-style martial arts: qi, cultivation, manuals, channel strain, breakthroughs.
- Knight = its own anime/fantasy-knight arts: aura, reinforced sword forms, charge, armour arts. Separate tree, not a reskin of sect. Works with empty qi (stamina + conditioning).
- Chantless magic is advanced only: needs high magic level, spell-theory mastery and several path milestones. Beginners must chant (seal minigame). Enforce in data + `can_use`, never only in UI.

## Ability definition (data row, one per technique)
`id, path, tier, cast{instant|chant|channel|charge, seals, chant_time, chantless_req}, costs{resource:amount}, cooldown, targeting{self|target|cone|line|circle|chain|projectile, range, radius, angle, max_targets}, effects[{type, magnitude, duration, family}], action (optional CombatAction id), vfx/anim/audio roles`.
Resource names must exist in `power_paths.POOL` for that path.

## Lifecycle (one runner, usable by player and NPCs)
can_use (resources, cooldown, silence/stun, injuries, path gate) -> begin (instant: pay now; chant/charge: pay on release, refund part on cancel) -> windup/chant -> resolve (targeting query, apply effects) -> recover. Global lockout 0.3 s (`CAST_LOCK`).

## Effects
Keep an `EffectSet` per actor keyed by `family`; stacking rule per effect: refresh | replace-if-stronger | stack-to-N. Tick at 2 Hz. Serialise active effects. Counters (ward, absorb) are effects checked before damage.

## Cooldown and resources
- Per-ability cooldown timestamp (see `skills.cooldown_left`), plus lockout.
- Resource per path: magic mana (overdraw -> headache/instability), sect qi (+strain), knight stamina (+armour load), beast bond. Never invent a sixth resource without updating `power_paths`.
- NPC abilities use cooldown only (no drain accounting) to stay cheap.

## Targeting on mobile
Tap-lock target, auto-aim cone assist, max 4 equipped slots + dash, radial button cluster. Area queries once at resolve, not per frame. Projectiles <= 8 live.

## Checklist for a new technique
1. Add the data row (no new if-branch in `_resolve` unless a new targeting kind).
2. Decide chant vs chantless and set `chantless_req`.
3. Set costs from the path's resource only; cooldown >= windup + recovery.
4. Add training tag so use trains the path (`TRAINING_TAGS`).
5. Test: `can_use` truth table, cost payment, cooldown, chantless gate (run `test_realm_power_paths`-style tests).
6. VFX/audio via roles and `ashes-performance` budgets.
Never copy code/data from GPL/AGPL reference games; describe and re-implement.
