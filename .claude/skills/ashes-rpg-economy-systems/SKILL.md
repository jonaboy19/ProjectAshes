---
name: ashes-rpg-economy-systems
description: Gathering, crafting, inventory/equipment, skill progression and world-persistence patterns (learned from Ryzom, re-implemented Godot-native) applied to Rising Ashes. Use before changing crafting.gd, gathering_items.gd, progression.gd, items_db.gd, equipment, save_manager.gd, or adding deposits, recipes, missions.
---
# Rising Ashes RPG economy systems

Design source: `docs/research/MINING_COMBAT_WORLD.md` sections 3 and 5. Ryzom is AGPL: patterns only, never copy code or data.

## Existing (kingdom/scripts/sim)
- `crafting.gd`: recipes (skill, station, tools), `can_craft`, `craft`, `roll_quality(lvl, recipe_level)`, `add_xp`, salvage, `tool_bonus`, stations incl. interior scan.
- `progression.gd`: `award(activity, ctx)` with `repetition_factor` decay, attributes.
- `gathering_items.gd`: hunting/fishing/forage item and market tables (`register(Life)`).
- `items_db.gd` (1,200 items), `equipment.gd`, `save_manager.gd`. See the `ashes-items` skill for adding items.

## Patterns to apply
1. Skill by use, with parents: leaf use grants XP and 25% to the parent skill; action level vs skill level changes success and quality (`chance = clamp(0.55 + 0.04*(skill - recipe_level) + tool_bonus, 0.35, 0.98)`).
2. Gathering = short session, not one roll: find deposit -> `extract` taps -> optional `care` tap that cancels the next hazard -> collect. Hazard odds fall with skill delta. 3-6 taps, never > 10 s on mobile.
3. Deposits are persistent entities: `{qty, regrow_per_day, quality_range}`. Static definition in data; only the overlay (depleted/qty/regrow day) is saved. Far regions catch up by formula on activation.
4. Materials carry quality; mean input quality adds up to +/-20% to output quality in `roll_quality`.
5. Failure has tension: on failed craft return ~50% materials and half XP; never destroy tools.
6. Creatures carry part tables (hide, bone, gland) by species; harvest needs a tool and skill threshold for rare parts.
7. Equipment armour by location (head/torso/arms/legs) multiplies incoming damage by hit lane (see `ashes-melee-combat`).
8. Death = small XP-progress debt plus a temporary weak debuff, never item loss.
9. Missions are data rows `{id, prereq, steps[{event,target,count}], rewards}` handled by a realm module; only per-step progress is saved.
10. Persistence: separate dirty-flagged containers (player, inventory, each realm module, region overlays, missions), autosave dirty ones on a 30-60 s idle tick and on app pause, write temp file then rename, versioned dicts with migration.

## Rules
- New content = data rows; new mechanics need a pure-logic class plus a test.
- Use own RNG streams (see `ashes-region-content`, `ashes-realm-module`) so adding a gatherable does not shuffle the world.
- Every new item goes through `ItemsDB`/protoset and the market tables; run the items validation.
- Budgets: save overlay < 1 MB per region, write on a worker thread < 20 ms, no per-frame allocation in sessions.
- Check Ryzom/other GPL repos only as a textbook; record licences in `docs/research/`.
