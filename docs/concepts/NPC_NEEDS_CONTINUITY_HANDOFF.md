# NPC need continuity handoff

**Status:** implementation brief for Claude; no gameplay code changed in this document.
**Source checked:** `gpt/locomotion-jump-integration` at `22de9271`, against the merged game base `b6cc215c`.
**Scope:** preserve a small amount of life state across NPC presentation LOD and save/load. Keep the existing schedule, utility AI, and population budgets.

## The gap in the current system

`WorldSim` owns the deterministic population rows and currently serializes day/time, treasury, resident money, and season. `PopulationLOD` promotes a capped nearby group into `Villager` bodies. Each body creates a `UtilityBrain` with food, rest, social, faith, and water needs. Those five values are not stored in `WorldSim` or serialized.

`Villager._make_brain()` calls `seed_needs()` whenever a body is created. `resync()` also seeds those needs again after a time skip or load. That gives a plausible initial state for a newly encountered person, but it means a person's recent meals, sleep, water, prayer, and conversations do not survive a body despawn or a save/load. Re-entering view reconstructs a plausible day state instead of continuing that person's state.

This is a source-confirmed continuity gap, not a claim that the whole NPC schedule or population simulation is missing. The current design already has the important mobile boundary: data rows for the population, utility decisions only for embodied villagers, a time-budgeted `WorldSim`, and capped body/animation work.

## Preserve the current architecture

- Keep `WorldSim` the durable owner for a person's low-cost needs while that person is not embodied.
- Keep the active `UtilityBrain` as the decision/motive owner while its villager is embodied.
- At promotion, transfer the stored needs into the brain exactly once. At demotion, write the brain's latest needs back before its node exits.
- Ensure only one owner advances an NPC's needs at a time. Do not let `WorldSim` decay an embodied person's needs while `UtilityBrain.tick()` is doing so.
- Continue creating no brain, node, skeleton, or physics body for distant residents.
- Preserve the seeded `UtilityBrain.seed_needs()` behavior as a backwards-compatible fallback for old or invalid save data.

## Recommended implementation slice

1. Add compact per-person need storage to the existing `WorldSim` data rows. Keep the five values normalized to `0..1`; do not add per-resident Nodes or Resources. Include a last-simulated game-time value or another explicit catch-up marker so an NPC's needs can advance while its brain is asleep.
2. Give `UtilityBrain` a small state export/import boundary for these five needs. Keep the utility scoring and need rates in one place so the embodied and unembodied paths cannot drift apart.
3. On body promotion, restore the row and advance it from its stored game time to now using cheap schedule-aware arithmetic. While embodied, let the existing brain tick. Persist the current values at a bounded cadence and on body removal.
4. On save, store the compact population state with a version marker. Prefer a packed representation (for example, base64 of packed floats) over thousands of verbose nested dictionaries. On old saves with no field, keep the existing seeded fallback. On a size/version mismatch, fall back safely and report a concise diagnostic rather than failing the whole save.
5. Keep save schema additions inside `WorldSim.serialize()/deserialize()` unless the existing save format requires a migration hook. Do not change global population identity, schedules, money, or positions as part of this slice.

### Offline need progression

Keep this intentionally approximate. It should create continuity, not simulate every meal and gesture. Use `DailyRhythm` and the same meal/sleep assumptions as the current brain to bound catch-up. Do not restore social/faith/water needs merely because time passed. If exact act history is needed later, introduce it as a separate feature after this state handoff is stable.

Use elapsed **game hours**, not wall-clock time, so pause, time skips, and the game's 720-second day stay coherent. Clamp or segment unusually large elapsed intervals so corrupted timestamps cannot produce extreme arithmetic. A time skip that already invokes `WorldSim.advance_hours()` should not apply the same interval twice.

## Acceptance evidence

- The same resident keeps approximately the same needs when promoted, demoted, then promoted again without a world-time jump.
- A resident's needs change appropriately over a controlled in-game time advance while unembodied, then continue after promotion; they do not snap back to a newly seeded profile.
- A save made with active and unembodied residents reloads with both groups at coherent need levels. An old save without the new field still loads.
- A large time skip advances needs once, not twice. Loading an earlier save does not inherit the later session's in-memory state.
- A deterministic multi-hour schedule capture shows needs affecting existing choices (sleep, eat, socialise, water, pray) without changing schedule ownership or causing every resident to travel at the same moment.
- Compare `WorldSim` slice cost and save size on the same build before and after. The change must not add per-frame scans of all residents or active brains for the distant population.

## Out of scope for this slice

- New personality traits, persistent episodic memories, family/relationship histories, dialogue generation, new routines, or new physical actors.
- Replacing `UtilityBrain`, `WorldSim`, `PopulationLOD`, `DailyRhythm`, or the save system.
- Changing activity weights to hide reset behavior. First make the existing state survive the handoff, then balance it from a reproducible in-game capture.

## Current source map

- `kingdom/autoload/world_sim.gd`: population rows, time-sliced distant movement, and world serialization.
- `kingdom/scripts/population/utility_brain.gd`: five needs, seed/tick formulas, action scoring, and lightweight shared sensing.
- `kingdom/scripts/population/villager.gd`: brain creation, periodic need ticks, and NPC body lifecycle.
- `kingdom/scripts/population/population_lod.gd`: promotion/demotion and the existing body/physics/visual budgets.
- `kingdom/scripts/population/daily_rhythm.gd`: staggered per-person schedule and local clock.

Related design: [NPC life-loop design](NPC_LIFE_LOOP_DESIGN.md), [open-world pattern study](OPEN_WORLD_PATTERN_STUDY.md), and [performance budgets](../qa/PERFORMANCE.md).
