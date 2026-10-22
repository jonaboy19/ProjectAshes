# NPC need continuity handoff

**Status:** implementation shipped on `gpt/locomotion-jump-integration`; live runtime/performance acceptance is still open.
**Source checked:** `gpt/locomotion-jump-integration` after sync with Claude `ec7c4960` (2026-09-30).
**Scope:** preserve a small amount of life state across NPC presentation LOD and save/load. Keep the existing schedule, utility AI, and population budgets.

## The gap in the current system

`WorldSim` owns deterministic population rows. Its version-2 save payload includes flat packed values for food, rest, social, faith, and water, a double-precision last-updated game-hour column, and a valid marker. The reader remains compatible with the earlier version-1 float timestamp. `UtilityBrain` can export/import that stable five-value order. `Villager` restores valid state on promotion, syncs after its existing staggered brain tick, writes it on removal, and keeps it through `resync()`. If a save is loaded while the world scene is still alive, `Life.restore()` refreshes each registered brain from the newly deserialized rows before the next LOD resync. Old or malformed saves fall back to deterministic seeding; loading a save without valid need fields first clears in-memory state from the replaced run.

Need values now survive ordinary body despawn/promotion and save/load. Distant residents with initialized state advance during their existing time-sliced `WorldSim._step()` visit; there is no extra resident scan. That path applies the shared food/rest/social/faith/water depletion rates, recovers rest at the coarse home/sleep schedule, and assumes three half-hour meals using the existing eat restoration rate. Unembodied catch-up is capped at 24 game hours, enough to cover one representative day without looping over arbitrarily old/corrupt times. Embodied `UtilityBrain.tick()` keeps its existing two-game-hour bound. During `advance_hours()`, the already existing all-resident settle pass advances unembodied rows once while body-owned rows wait for brain resync.

This closes the source-confirmed need reset across ordinary LOD and save/load boundaries; it does not claim the whole NPC schedule or population simulation is complete. The design keeps the existing mobile boundary: packed population rows, utility decisions only for embodied villagers, a time-budgeted `WorldSim`, and capped body/animation work.

## Preserve the current architecture

- Keep `WorldSim` the durable owner for a person's low-cost needs while that person is not embodied.
- Keep the active `UtilityBrain` as the decision/motive owner while its villager is embodied.
- At promotion, transfer the stored needs into the brain exactly once. At demotion, write the brain's latest needs back before its node exits. **Implemented.**
- Ensure only one owner advances an NPC's needs at a time. Do not let `WorldSim` decay an embodied person's needs while `UtilityBrain.tick()` is doing so.
- Continue creating no brain, node, skeleton, or physics body for distant residents.
- Preserve the seeded `UtilityBrain.seed_needs()` behavior as a backwards-compatible fallback for old or invalid save data.

## Recommended implementation slice

1. ~~Add compact per-person need storage to WorldSim.~~ **Implemented:** five flat packed floats, last-game-hour, and valid byte per resident; no per-person Nodes/Resources.
2. ~~Add a UtilityBrain export/import boundary.~~ **Implemented:** stable order is food, rest, social, faith, water.
3. ~~Transfer on promotion/removal, tick while embodied, and preserve through resync.~~ **First layer implemented:** restoration and bounded-cadence sync use the existing brain; catch-up remains capped at two hours.
4. ~~Add versioned save fields and old-save fallback.~~ **Implemented:** fields live in `WorldSim.serialize()/deserialize()`; old/malformed dimensions use seeded fallback, and need rows clear before loading so older saves cannot inherit the prior session's values.
5. ~~Advance unembodied needs without an all-resident per-frame pass.~~ **Implemented:** the existing time-sliced visit handles only valid rows; `advance_hours()` reuses its population settle loop. Schedule and meal assumptions are deliberately approximate. **Open:** measure storage/load and CPU cost on the same mobile build.

### Offline need progression

Keep this intentionally approximate. It should create continuity, not simulate every meal and gesture. Current implementation uses the shared work/home schedule phase (without per-person departure delay) to infer nighttime rest, the brain's three meal hours for assumed food recovery, and the same trait-scaled need depletion rates. It does not restore social/faith/water merely because time passed. If exact act history is needed later, introduce it as a separate feature after this state handoff is stable.

Use elapsed **game hours**, not wall-clock time, so pause, time skips, and the game's 720-second day stay coherent. Clamp or segment unusually large elapsed intervals so corrupted timestamps cannot produce extreme arithmetic. A time skip that already invokes `WorldSim.advance_hours()` should not apply the same interval twice.

## Acceptance evidence

- The same resident keeps approximately the same needs when promoted, demoted, then promoted again without a world-time jump.
- A resident's needs survive save/load and LOD handoff. Unembodied time passage uses coarse schedule/meal catch-up (24-hour cap); verify this does not double-advance on a time skip or snap to a new seed.
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
