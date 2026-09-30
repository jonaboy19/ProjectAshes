# Villager movement hearing — Codex handoff

Date: 30 September 2026  
Branch: `gpt/living-world-integration`  
Scope: inexpensive outdoor reaction to nearby player movement noise. This is a first hearing cue, not the wider perception, stealth, crime or rumor system.

## Behavior added

- `UtilityBrain.heard_player_at()` checks only the player already referenced by the embodied Villager. It requires a live player with `noise_radius()` and planar movement above 0.35 m/s, then uses that existing crouch/walk/run/mount radius (capped at 18 m).
- The active weather's existing `noise_mult()` attenuates the radius in rain and wind.
- Successfully resolved combat techniques also publish an anonymous acoustic event into a shared queue capped at 32 entries and 10 seconds lifetime. Nearby outdoor villagers can hear these even if the player is stationary. New game, save restore and WorldSim resync/time-skip clear the transient queue.
- The existing villager hammer/chopping animation impact cues publish quieter one-second events from their already-timed impact point. No additional animation polling or sound node was added.
- The check runs on the Villager's existing staggered utility-decision cadence and only while that Villager is outdoors. It adds no node, timer, physics body, ray, or per-frame scan.
- The brain retains only the last approximate sound point for three real-time seconds, decaying linearly. This memory belongs to the embodied brain, is not saved, and clears with the existing danger-memory reset when entering interiors or after a time skip.
- Villager combines the heard cue with its existing sight/spectacle interest and uses the strongest signal for WATCH. WATCH may take a few cautious steps toward its existing stand-off point. The reported point is biased toward the listener by 0.75–3 m so it is approximate rather than the exact player position.
- Hearing does not cause FLEE, attack, crime attribution, recognition, or a persistent witness fact.

## Limits and next step

- The cue currently has no wall/terrain occlusion or indoor-to-outdoor sound propagation model. An outdoor villager could hear through a building. Do not use it as evidence for law or exact identification.
- Technique resolution publishes sound separately from the existing visual spectacle cue; worker impact sounds use the existing animation cue. Player footsteps, weapon impacts, other combatant sounds, doors and NPC voices do not yet publish sound events through this queue.
- The short point memory is not a search system: after three seconds, villagers stop acting on it. Persistent memories, confidence and belief updates are not implemented.
- Static source review only. No Godot parser, runtime, behavioral or mobile profile was run for this slice.

## Coordination

Claude can extend this by publishing discrete sound stimuli from the existing audio/gameplay event points, with loudness, position, category and expiry. Keep one bounded shared event queue, apply weather/occlusion at query time, and preserve anonymous approximate localization. Avoid a raycast per NPC; share the existing sensor budget or use an authored acoustic/indoor-region approximation. Sound must remain distinct from visual spectacle and factual event history.
