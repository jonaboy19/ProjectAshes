# NPC activity alignment collision

Date: 2026-10-05
Branch: gpt/character-feel-finish

Normal near-NPC travel used collision movement, but SmartObject ALIGN and loop pose corrections assigned global_position directly. A blocked final step could therefore bypass world collision after an otherwise valid street route.

The body now converts the existing _so_step target into displacement. Contact-range actors apply one move_and_collide sweep for nontrivial displacement; distant noncontact actors keep their existing cheap position update. This does not add move_and_slide actors or change the population cap, collision mask, animation owner or approach transforms. Measured movement still feeds the existing resolved-speed calculation. The Session's existing alignment tolerance and 1.5-second timeout remain responsible for cancelling a blocked alignment instead of starting the contact clip from the wrong position.

Limit: the body's mask remains WORLD_LAYER = 1; player blocking depends on existing player-layer configuration and the player's own LOCAL_ACTOR_LAYER mask. This patch is not proof of complete mutual NPC contact. Distant noncontact alignment still does not use physics. Existing imperfect content colliders/anchor locations may now reveal blocked interactions rather than permit penetration.

Source/diff review only; no tests, captures or runtime run. Claude's shared checkout untouched. Pending acceptance: block bench/workstation alignment with a solid shape, verify no wall crossing and clean cancellation, then verify unobstructed chair, prayer and work poses still align, and inspect dense near contacts on a phone.
