# Entrances, services, and interaction selection

Claude implementation handoff based on source at `e3563fc4`. No doors, services, or game scripts are changed by this document. Use one inn as the first implementation slice after its collision profile is verified.

## Current source

`VillageServices.setup()` puts the innkeeper Station at `lot.pos + Vector2(sin(yaw), cos(yaw)) * 5.2`, labels it with the inn name, and gives it the `Enter` verb while opening the inn menu. This is a fixed lot-relative offset rather than a verified doorway marker.

`Player.nearest_interactable()` chooses the nearest member of the interactable group within 3.2 m. It does not itself check facing, line of sight, enabled/visible state, or whether the candidate is on the accessible side of a wall. Stations remain in that group; an `InteriorDoor` joins it while the player is inside its Area. The door's input handler yields when the player selects a different nearest candidate. These rules explain how a nearby service can win over a door, but the exact geometry and input dispatch must be captured before accepting a particular fix.

The current playtest report records missing production door wiring and an innkeeper/door conflict. Its temporary test door proved an interior could be loaded in that run; it does not prove every lot has a working production entrance. Confirm runtime door counts and associations against the current builder before implementation.

## One entrance record, distinct use points

Give each entrance a stable settlement/building/portal ID, an authored local threshold pose, exterior approach/exit poses, a clearance envelope, and its supported interior or abstract indoor destination. Transform those poses with the same fit, centering, scale, and yaw as the installed building. A raw Blender marker cannot be assumed to match a separately fitted and recentered render mesh. Preview all points with the real building, compound collider, player capsule, and route surface.

Use separate service/worker/customer anchors beside or inside the entrance, with occupancy limits and facing. A service should not physically stand in the door clearance corridor or show an `Enter` prompt that only opens a food/bed menu. Describe the actual action in the prompt. Preserve the existing menu and interior APIs; first fix placement and selection with one concrete building.

## Choose and execute one interaction

Filter candidates for lifecycle/enabled state, actual permitted range, and accessible approach. Respect collision occlusion so a station behind a solid wall cannot be selected merely by short Euclidean distance. Evaluate facing or player focus where appropriate, then use deterministic priority/ties and a short focus hold to avoid prompt flicker as the player edges between the keeper and door. Do not make every door globally override every NPC; test the intent expressed by approach and camera aim.

The visible prompt and the keyboard/touch/gamepad action must resolve the same candidate. Review all dispatchers, including the door's own input handler, so one input cannot open a service and enter a room in the same frame. Revalidate the selected object's existence and eligibility on use. Clear focus when entering/leaving an interior or unloading its settlement.

## Transition and resident lifecycle

The existing interior system loads a room above the outdoor world and teleports the player to its spawn, then restores the player outside using a door-local offset. Validate both spawn and return poses for capsule clearance and support. If the exit is occupied, wait or select an approved nearby return point; do not return the player inside a resident, wall, or counter. Preserve camera/environment/audio context and cleanup if the door/building disappears or the player loads another save during the transition.

NPC indoor arrival is a separate decision. A coarse resident may become abstract only after reaching a verified portal and releasing/transferring its physical ownership and anchor reservations. Do not automatically teleport all residents to the player-only elevated interior, or hide them solely because they reached a service offset. The player and NPC systems should share the portal identity even when their interior representation differs.

## Acceptance route

Approach the inn from both street directions and face the keeper, door, wall, and counter in turn. Capture candidate IDs, distance, occlusion result, focus, prompt, actual use target, portal/anchor positions, and capsule/collider shapes. Check keyboard, touch, and gamepad; exactly one intended action should fire each time, without through-wall selection or prompt oscillation.

Enter and exit repeatedly, including an occupied exterior return spot, interrupted/load transition, and settlement teardown. Watch one resident arrive at that same entrance and leave again: it should use the valid approach and indoor policy without blocking the doorway or vanishing outside. Record normal video alongside diagnostics; source review does not establish production door reachability or completed indoor life.

Related: [collision facade review](COLLISION_FACADE_REVIEW.html), [life-loop anchors](NPC_LIFE_LOOP_DESIGN.md), [contact/LOD transfer](NPC_CONTACT_LOD_CONTRACT.md), and [current playtest limitations](CURRENT_RUN_VISUAL_REVIEW.md).
