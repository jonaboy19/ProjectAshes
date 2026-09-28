# Footstep and activity sound handoff

Source review at `e3563fc4`; game files are unchanged. Apply after the accepted movement/animation pass and reuse the existing audio director.

## Active implementation

`project.godot` wires `Audio` to `scripts/audio/audio_director.gd`, not the older `autoload/audio.gd`. The active director already provides music/context beds, spot sounds, surfaces, creature responses, UI, and voice pools. `assets/audio/README.md` records the current processed assets and sources. Do not rebuild this system or duplicate its source downloads for this handoff.

`_poll_player()` runs in the physics step and accumulates planar player displacement. It suppresses steps when dead, airborne, moving below 0.6 m/s, or moving over 3 m in one sample (treated as a teleport). It emits a step at accumulated distance 1.4 m, or 2.1 m above 4.5 m/s, then resets the accumulator to zero. It does not read foot contact or gait phase. Dodge detection emits a whoosh but does not independently exclude ordinary footsteps during a grounded roll. These are source facts; audible artifacts require a recorded comparison.

The visible villager controller does not call the footstep API. Village/smithy spot sounds are selected by ambience context; they are not evidence that a particular visible worker struck an anvil at that moment. Atmosphere already exists, but close visible action synchronization is a separate task.

## Contact-based footsteps

Start with the player and one nearby resident. Mark valid left/right stance contacts on accepted clips at game scale, then feed an actor-local contact event into the existing sound selector. Ensure a blended walk/run pair emits one perceptual step per plant rather than both child animations firing duplicate events. Use stable event identity (actor, foot, cycle/contact index) or a single authoritative gait contact signal; clear its history on a deliberate seek/teleport/ownership reset.

Require grounded support and appropriate action state. Suppress ordinary walk steps during a roll, death, airborne action, seated/work pose, stationary transport, and idle. Give rolls, landings, and work actions their own supported cues. Choose the surface at the supporting foot or contact location; the player-root terrain classification may not describe a stair, counter edge, wooden bridge, or surface boundary under that foot.

If no reliable contact marker exists, keep a measured distance-based fallback with per-rig/gait stride distances. Preserve remaining distance after a step instead of discarding it, cap catch-up emissions after a hitch, and reset on discontinuities. This fallback should be explicitly labeled in QA; distance travelled does not establish that a foot is planted.

## Work and local ambience

Tie close anvil/tool/carry/place cues to the worker's accepted action impact/release event and its actual world anchor. Reserve context spot sounds for plausible distant activity. Avoid playing both an ambient close anvil and a synchronized strike at the same location as two unrelated impacts. Stop or transfer scheduled cues when an activity is interrupted, its anchor is released, the actor changes ownership, or the settlement unloads.

Preserve the existing voice budget and spatial routing. Prioritize player contact and nearby visible action over distant incidental cues; profile any extra NPC step voices rather than giving every simulated resident an audio player. Do not change the listener/SubViewport setup without verifying it: the current director already owns that routing.

## Evidence to accept

Record normal video with audio and a paired event trace containing actor, clip/state, playback scale, foot/contact, surface, sound variant, accepted/dropped event, and timestamp. Align the trace clock with captured frame/audio time; device output latency is a separate measurement from event timing.

Compare walk/run, starts/stops, block-back/side travel, wall pressure, roll, hit recovery, dirt/cobble/wood boundaries, stairs, a platform if supported, and LOD promotion. Include two residents stepping simultaneously and a work interruption. Acceptance requires no duplicate plant cues, no walking sounds from a stopped/rolling actor, believable surface changes, synchronized visible work impacts, and stable sound/voice counts at LOW and HIGH. Source inspection does not prove the result sounds natural; listen to the paired gameplay capture.

Related: [locomotion response](LOCOMOTION_START_STOP_TURN_CONTRACT.md), [contact/LOD ownership](NPC_CONTACT_LOD_CONTRACT.md), [daily life](NPC_LIFE_LOOP_DESIGN.md), and [recorded movement trace format](NPC_CAPTURE_TRACE_VIEWER.md). Footstep events require an additional synchronized event export; the current speed CSV viewer does not display or play audio events.
