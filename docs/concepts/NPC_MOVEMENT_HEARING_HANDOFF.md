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
- Player movement uses one existing `StreetGraph.clear_line()` query per decision; discrete sounds geometry-check at most the four strongest nearby candidates. A blocked direct path is damped to 35% strength behind generated building footprints or settlement walls. This is a cheap direct-path approximation, not an acoustic ray: open doors, terrain, floors, materials and sound traveling around corners are not modeled. Listeners without a settlement graph retain full transmission.
- The brain retains only the last approximate sound point for three real-time seconds, decaying linearly. This memory belongs to the embodied brain, is not saved, and clears with the existing danger-memory reset when entering interiors or after a time skip.
- Villager combines the heard cue with its existing sight/spectacle interest and uses the strongest signal for WATCH. WATCH may take a few cautious steps toward its existing stand-off point. The reported point is biased toward the listener by 0.75–3 m so it is approximate rather than the exact player position.
- Hearing does not cause FLEE, attack, crime attribution, recognition, or a persistent witness fact.

## Limits and next step

- The cue has only coarse settlement footprint/wall damping; terrain and indoor-to-outdoor sound propagation remain unmodeled. Treat it as approximate interest, never as evidence for law or exact identification.
- Technique resolution publishes sound separately from the existing visual spectacle cue; worker impact sounds use the existing animation cue. Player footsteps, weapon impacts, other combatant sounds, doors and NPC voices do not yet publish sound events through this queue.
- The short point memory is not a search system: after three seconds, villagers stop acting on it. Persistent memories, confidence and belief updates are not implemented.
- Static source review only. No Godot parser, runtime, behavioral, occlusion-quality or mobile profile was run for this slice.

## Coordination

Claude can extend this by publishing discrete sound stimuli from the existing audio/gameplay event points, with loudness, position, category and expiry. Keep one bounded shared event queue, apply weather and coarse geometry damping at query time, and preserve anonymous approximate localization. Avoid a physics raycast per NPC; the current query reuses the route graph's building/wall footprints. Sound must remain distinct from visual spectacle and factual event history.
