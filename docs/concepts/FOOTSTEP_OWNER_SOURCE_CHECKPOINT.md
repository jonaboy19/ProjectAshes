# Footstep ownership: current source finding

4 October, `gpt/character-feel-finish`. Read-only finding; no audio patch applied yet.

## Confirmed competing emitters

`kingdom/project.godot` loads `scripts/audio/audio_director.gd` as Audio. Its `footsteps_enabled` defaults true, and no other assignment was found in the inspected scripts. `_poll_player()` emits a distance-triggered `play_footstep()` while grounded and moving. It detects dodge for a whoosh but does not suppress ordinary distance footsteps during that dodge.

Meanwhile Player `_update_footsteps()` emits `Audio.sfx("step_" + surface, ...)` from the animator's gait signal or a distance fallback. This path already suppresses ordinary steps during dodge, death and unsupported movement. Both paths therefore claim authority for the same player's walking sounds. Actual audible duplication has not been recorded; the competing source paths are confirmed.

## Reuse correction to pursue

Keep the existing AudioDirector voice pools and surface selector. Give the production Player explicit ownership of its accepted animation contact cues, and let AudioDirector's polling retain its fallback only for actors without that contact owner. Preserve dodge whoosh polling independently. Route accepted player cues through the existing footstep API rather than introduce another audio service.

When a full-body standing attack plays, ordinary gait cues must be suppressed; its authored step requires a separate accepted marker cue. A standing attack's capsule lunge is not evidence that locomotion feet planted. Preserve a bounded fallback for moving attack/locomotion if reliable contacts are unavailable.

Required evidence: paired audio/video and cue trace for walking, running, standing combo, dodge, landing, surface boundaries and interruptions. No runtime or listening pass has been performed.

## Documentation read

Read the partial-route arrival handoff and optional-inn routine handoff in full. Read the well activity and footstep/activity sound handoffs in a combined batch, with truncated output; full coverage is not claimed. The partial-route handoff is explicitly a hypothesis awaiting current-source confirmation, not an accepted bug. The well contract keeps intent, physical movement, reservations and need effects under separate existing owners; reuse that contract rather than invent an additional brain or station registry.

## Implemented ownership adapter

Player now exposes `owns_footstep_events()`. AudioDirector caches that contract when acquiring the player, resets displacement/dodge history on replacement, and skips only its distance-step emitter for that owner. Dodge whoosh polling occurs before the skip and remains intact. Actors without the method keep the old polling fallback. No per-frame ownership discovery or additional audio nodes were added.

Player sends accepted gait cues through existing `Audio.play_footstep()` instead of the generic SFX pool. This preserves the director's two-voice footstep budget and surface selector. The API's existing -4 dB offset plus the player -2 dB request targets -6 dB output; audible mixing equivalence remains unverified. `footsteps_enabled` now gates that API too, so the existing flag still suppresses steps after changing ownership.

Ordinary gait/fallback cues are suppressed during a standing full-body attack. An authored attack foot-plant cue is still pending; do not substitute gait sounds merely because the collision body lunges. This patch addresses competing owners, not full contact synchronization or support-foot surface sampling.

Runtime/audio validation remains pending. Review the focused diff against Claude's latest audio work before integration.
