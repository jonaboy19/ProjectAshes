# NPC destination basics: blocked routes

Date: 2026-10-05
Branch: gpt/character-feel-finish

## Changes

- StreetGraph.route returns an empty partial route when attachment fails after clear_line has rejected direct travel. It previously returned the obstructed goal as a direct waypoint.
- Villager snapshots last_route_partial immediately after its graph query; this graph flag is shared and may change on another resident's query.
- Reaching a partial path endpoint no longer sets arrived. The actor waits 2.0–3.2 seconds based on its resident id and retries using the existing shared route budget.
- Empty paths use the same delayed retry. Completed routes keep existing arrival and push-out semantics.

## Why

Arrived allows indoor hiding, activity animation and need/activity progression. A closest reachable street node is not proof the resident reached its workstation or door. Missing graph attachments also must not bypass a rejected wall segment.

## Integration

Changes are limited to scripts/population/villager.gd and street_graph.gd in Codex's worktree. Claude's shared checkout was not edited. Its recent villager commits include contact-budget and animation work; review this narrow patch alongside those changes before merging. PopulationLOD's sprite route caller already checks empty paths and applies its own 2.5-second retry.

## Remaining limits

This does not add missing Meshy colliders, guarantee mutual collision for every visible NPC, or introduce a new navigation framework. Permanently inaccessible activities still need fallback selection/reservation timeout policy; this patch prevents false arrival while retaining the existing decision system. Routes without a graph keep their existing direct-path behavior.

Source paths and callers were inspected. No tests or game runtime were run. Acceptance remains: block an activity entrance, verify the resident waits outside without indoor hiding or work effects, unblock it and verify recovery; repeat with disconnected streets, sprite/full promotion and dense crowds. Mobile timing is unmeasured.
