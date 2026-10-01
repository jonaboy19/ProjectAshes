---
name: ashes-world-interaction
description: How to add or extend interactive world objects in Rising Ashes - doors, locks and keys, chests/drawers, levers, carryable physics props, trigger volumes, noise/damage impact, and their persistent save-state. Use before touching interior_door.gd, breakable.gd, home_chest.gd, adding any "press interact" object, trigger, lock or lockpicking, or saving world-object state.
---

# World interaction and save-state

Full design: `docs/research/MINING_PERCEPTION_INTERACTION.md` (2.7-2.12, 4.6, gap list 5).
Reference ideas from Amnesia/Penumbra/Doom 3/The Dark Mod (GPL; read-only, see `ashes-reference-mining`).

## Contract (one shape for every usable thing)
- **Stable id** `"<settlement_or_site>/<kind>/<plan index or id>"`. Never node paths, never instance ids, never random.
- **Type** in `data/world/interactables.json` (JSON with `extends`, like smart_objects.json); instance = id + overrides.
- **Interactable**: `verbs()` -> ordered `{id,label,enabled,reason}`, `use(verb, actor)`, `max_focus_distance`, `owner` (household/faction). Priority: use/open > unlock (key) > pick up > lockpick > examine > break. Label shows "(stealing)" when owned and seen.
- **WorldState** (RefCounted, pure data): `id -> state dict`, only DELTAS from spawn defaults. `get_state(id, defaults)`, `set_state(id, patch)`.
- **Focus**: one ray/overlap at 10 Hz picks the best interactable (distance + view angle + bias). Mobile: tap prompt = primary verb, long-press = radial of at most 3 more verbs.

## Doors and locks
- Door states `CLOSED, OPENING, OPEN, CLOSING, LOCKED, JAMMED, BROKEN`; `open_amount` 0..1 by Tween (no physics joints on mobile). `interior_door.gd` currently only swaps scenes: make the swap the result of `use("open")`, keep `InteriorDoor.active` single-interior rule.
- Lock = data, not a node: `{lock_id, key_id, level 0..5}`, shared by door/chest/gate. Keys are items. Household has its lot keys, guards a master key for public buildings, shops lock by `work.gd` hours.
- Routing: street-graph door edges get `blocked_for(npc)` (locked and no key) - Dark Mod "forbidden areas" idea. NPC passing = approach, short pause, open, pass, optional close (3 states).
- Lockpicking = short timing mini-game (sweet spot, pins by level), makes noise (hearing event), failure wears the tool. Forced/broken doors are loud and a crime when owned and witnessed.
- Containers/drawers: slider 0..1; contents rolled once with `hash([WORLD_SEED, container_id])` from ItemsDB, then stored as taken/added delta; owned container + witnessed take = `report_crime("burglary")`. Extend `home_chest.gd`, do not fork it.

## Props, triggers, impact
- Levers/buttons/wheels: 1-DOF state with `targets[{id,verb,args,invert}]` (Amnesia connections).
- Physics props: tap-to-carry (hold point ahead, spring with max force, mass slows player, drop on distance/hit, throw impulse scaled by mass). At most ~8 live RigidBody3D near the player, freeze on settle and write a transform delta only if moved > 0.5 m. Shards stay capped (`breakable.gd` MAX_SHARDS).
- Triggers: `{id, shape, on enter|exit|use|state, wait, delay, once, targets[]}` in `data/world/triggers.json`, evaluated by a 5 Hz service on active-region Area3Ds. Delays go through a `Scheduler` of plain ints/strings saved in WorldState; never store Callables or lambdas in state.
- `Impact.hit(kind,pos,radius,force,instigator)`: damage through the existing `take_damage(amount, from, knockback)` contract, emit a noise event (see `ashes-perception-ai`), ownership crime, splash falloff with one occlusion ray for blasts.

## Save-state rules (Doom 3 / Amnesia lessons)
- Snapshot goes under `interactives` inside the Life snapshot so `save_manager.gd`'s atomic write, checksum and backup apply. Adding a key inside `data` needs a default in restore, NOT a schema bump; bump only if the envelope changes (add `migrate`).
- Two-phase restore: (1) load the dictionary only; (2) when a region/interior builds nodes, each Interactable pulls its state by id and applies it silently (no sound, no events, no tweens). Ids for regions not loaded yet stay in the store.
- Ignore unknown ids/keys; default new keys. Cap ~4000 deltas (~200 KB); drop deltas equal to default; props regenerate like `breakable.gd`.
- Chunk by region so loading a settlement is one dictionary read; snapshot work belongs on the autosave tick, <= 5 ms.

## Checklist for a new interactive object
1. Type entry in JSON + stable id scheme. 2. Verbs + prompt text. 3. State keys with defaults. 4. Noise/crime hooks. 5. NPC access rule (smart-object type or door edge). 6. Save round-trip test (state equality, mid-delay scheduler). 7. Cost test. 8. Lab screenshot at phone resolution.
