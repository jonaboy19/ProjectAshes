# NPC failed-spot retry cooldown

Date: 2026-10-05
Branch: gpt/character-feel-finish

Completes the immediate retry seam after blocked-approach release. Villager tells its existing UtilityBrain which SmartObject approach stalled before cancelling the session. Brain retains at most four spot ids with 30-second expiry. Its ordinary find_spot query removes expired ids and passes the remaining ids as an optional exclusion filter to SmartObjects.find. The candidate search skips those objects and retains its existing role, job, occupancy and distance ranking for all other objects.

This is local route-failure memory, separate from fear/danger memory; it does not create crime knowledge, danger steering or world-wide bans. It is transient and not saved. Other residents remain eligible to use the object. Once the cooldown expires it becomes eligible again. Exclusion applies to the entire object, not just one slot; this conservative scope can temporarily skip reachable slots on a partly obstructed object. Current 30-second duration and 12-second stall threshold need live tuning.

Changes: scripts/population/villager.gd, utility_brain.gd, scripts/living_world/smart_objects.gd. No new nodes, global scans, framework or animation assets. Source/diff inspection only; no tests or runtime run. Claude's shared checkout remains untouched.

Pending acceptance: block nearest work spot and verify an alternate is selected after stall; confirm another resident can use the released spot; unblock and confirm expiry permits reuse; verify four-entry cap and ordinary no-exclusion selection behavior. This does not change direct schedule-target queries or non-SmartObject water leases.
