# Feel audit follow-up for Claude

Based on `FEEL_AUDIT.md` and its P1–P6 patch notes at main commit `140c4eb5`. This branch changes only the three actor scripts listed below; it does not change animation assets, world construction, or the jump worker's work.

## Implemented here

| Audit item | File | Change | Remaining check |
| --- | --- | --- | --- |
| P1 / block facing | `kingdom/scripts/actors/player.gd` | In third person, blocking turns toward the nearest enemy within 6 m; camera heading remains the fallback. Lock-on and first-person paths retain their prior behavior. | In-game crowd check: the nearest enemy may differ from the incoming attacker. |
| P2 / wolf sideways slide | `kingdom/scripts/actors/wolf.gd` | Walking travel bends toward the wolf's facing, and hard turns slow its forward movement. Yaw interpolation is frame-rate independent. Monster circling is untouched. | Observe a wolf pursuing from behind and making a 180° turn. |
| P3 / get-up pop | `kingdom/scripts/actors/ragdoll.gd` | Capture the final simulated pose, hold it over the restarted animation with a `SkeletonModifier3D`, then fade its influence over 0.35 s. Death, revive, and normal cleanup remove the hold. Existing monster and wolf callbacks still choose the recovery animation. | Observe knockdown recovery and interruption by death on device; profile up to the existing three-ragdoll cap. |
| F16 / light-hit slowdown | `kingdom/scripts/actors/player.gd`, `kingdom/scripts/actors/impact_pause.gd` | Ordinary sword impacts briefly pause the attacker and struck actors' animation mixers. Nearby AI, camera, physics and effects keep their normal time. Parry and finisher impacts retain the existing global slowdown. | Compare ordinary hits and finishers in the real-game feel capture; confirm hit reactions still begin on the blade contact frame. |

`git diff --check` passes. Godot 4.6.3 `--check-only` passes for `ragdoll.gd` and `impact_pause.gd`. The same isolated script check for `player.gd` and `wolf.gd` stops at their existing global `Life` and `Frontier` references because it does not load the project's class registry. No gameplay or performance run was done.

## Waiting on the other work

- **P4 / well roof camera occlusion:** The well roof needs a camera-only collision proxy on `CAMERA_BLOCKER_LAYER`, like the stall proxies. That world-builder/content change should land before camera easing can be judged; without a roof hit, the SpringArm and ray cannot see the occluder. Please add equivalent proxies to thin canopies and overhangs. Keep the camera's immediate wall response.
- **P5 / transitions and jump:** The animation worker is making starts, stops, turns, and jump clips plus the mobile jump design. Integrate after the clips and design arrive; there is no jump mechanic in this branch.
- **P6 / villager foot IK:** Keep the reverted per-villager rig hook disabled. The audit measured a 14–22 fps loss on HIGH. A pooled near-resident rig is only worth enabling after a same-scene mobile-renderer benchmark shows less than 1 ms over the no-rig baseline.
- **Wolf size:** The audit says wolves read as dogs in grass. Scale/art adjustment belongs with the asset and world pass; this branch only changes their movement.
- **F15 / dodge through enemies:** The player already includes enemy layer 4 in its movement mask, and nearby monster/wolf capsules are enabled within 16 m. The audit sheet still shows the *rendered* roll crossing an orc in frames 19–23. Check the player capsule and animated model origins during that capture before adding a sideways offset; a steering patch without that observation may hide a collider/animation mismatch.
