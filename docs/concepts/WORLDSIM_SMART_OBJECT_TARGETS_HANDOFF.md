# WorldSim smart-object schedule targets — Codex handoff

Date: 30 September 2026  
Branch: `gpt/living-world-integration`  
Scope: data-tier schedule destinations only; Claude-owned scenes, assets, animation clips and VAT path are untouched.

## What changed

`kingdom/autoload/world_sim.gd` now owns a transient `SmartObjects` index. When an NPC enters work or market phase, WorldSim can use a generated semantic approach point instead of its deterministic free-form point **if that NPC's settlement is in the existing 320 m near-simulation ring and the activity has an eligible spot**. Otherwise the previous deterministic `_spot()` calculation remains the fallback.

Settlement spots are populated lazily once per near settlement using `WorldGen.height`. The near-settlement IDs are rebuilt alongside the existing near-person cache. Distant settlements do not build/query this index, preserving the cheap data-only path. Work/market lookup uses an indexed list of spots belonging to that settlement instead of scanning empty 16 m cells, with a 256 m target radius cap. Repeated goal refreshes reuse the resident's still-valid claim directly, avoiding a full candidate scan. Larger settlements fall back to their previous deterministic point beyond the radius. The streamed builder publishes exact plaza and clearance-adjusted gate-market stall positions, plus snapped centers of generated crop tiles, as plain activity-spot data in the shared plan. Merchants claim vendor slots, shoppers use customer slots, and farmers/laborers can claim generated field rows; nonmerchant work queries exclude customer stall slots. Slot reservations are released on every schedule phase change and when the resident's own goal returns home, preventing a missing/full activity or staggered schedule from leaving an old slot blocked. Claims and the index are reconstructed on reset/load and are not part of save data.

## What this does not do

- It does not make embodied `Villager` actors use `SmartObjects.Session` or play activity clips. Existing schedule-goal callers may receive the semantic approach point through `WorldSim._spot()`, while route following, movement, collision, and animation remain owned by their current systems.
- It does not guarantee that every job has a matching generated affordance. Missing work spots intentionally keep the existing fallback.
- Work spots are still sparse: generated field tiles and blacksmiths are covered, while jobs without a matching semantic spot use the deterministic fallback.
- It does not make distant residents' targets immediately reroute when the player enters their settlement. Their next schedule transition resolves a near semantic target.
- It does not establish runtime correctness, visual naturalness, save/load behavior, or mobile cost. No Godot parse, live run, device profile, or tests were run for this change.

## Coordination for Claude

Please preserve the `WorldSim.smart`, `_smart_done`, and `_near_settlement_ids` adapter when working on `world_sim.gd`. If P13a later connects embodied actors, use the same WorldSim-owned spot/slot claim or define an explicit atomic handoff; do not create a second competing claim owner. On demotion/despawn, release only the actor's matching claim. Schedule changes/load/reset already invalidate transient claims, so the actor session must treat revocation as cancellation and must not snap to stale targets.

The existing P13 proposal in `docs/anim/patches/P13_world_sim_smart_objects.md` remains useful context, but this adapter is narrower than the proposal's unbounded all-settlement wording: it is near-ring only and preserves fallback targets. Market and field spots arrive when `SettlementBuilder` streams the town in; WorldSim detects the new activity-spot count and idempotently indexes the added stable IDs on its next work/market goal request. Before expanding it, profile phase changes, first-time spot population, and time skips on target mobile hardware.

## Next useful system step

Review generated settlement plans against `smart_objects.json` and report coverage by job/activity without changing authored layouts. Then coordinate the embodied session adapter with Claude and test whether approach points are valid street/door destinations. Keep the position owner, route system, and collision path authoritative; a semantic slot is a destination and reservation, not permission to teleport or bypass navigation.
