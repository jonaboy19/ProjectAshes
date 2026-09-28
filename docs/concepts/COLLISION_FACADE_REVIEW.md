# Meshy hero building facade and collider review

Open [COLLISION_FACADE_REVIEW.html](COLLISION_FACADE_REVIEW.html) to select the inn, blacksmith, healer house, or adventurer guild, then rotate through four asset-local sides. The orange wireframe reproduces the current simple box proxy.

## Method

- Rendered the actual Meshy LOD0 GLB used by `Assets.BUILDINGS` in Blender 5.2.
- Applied the production target horizontal fit sizes from `kingdom/scripts/world/assets.gd` and grounded each fitted asset at `z=0` in the Blender preview.
- Drew a proxy with 80% of the fitted horizontal AABB in each axis and the full fitted model height. This matches `SettlementBuilder._build()`'s box dimensions and center height at default lot rotation.
- Rendered each side against the real fitted model and saved compressed WebP review frames.

## Exact dimensions

| Building | Fitted mesh (X × Y × height in Blender preview) | Current collider footprint (X × Y) |
|---|---:|---:|
| Inn | 13.50 × 12.48 × 7.98 m | 10.80 × 9.98 m |
| Blacksmith | 11.00 × 9.18 × 6.63 m | 8.80 × 7.35 m |
| Healer house | 8.83 × 9.50 × 6.82 m | 7.06 × 7.60 m |
| Adventurer guild | 16.00 × 9.52 × 9.08 m | 12.80 × 7.61 m |

The HTML uses Blender preview `X/Y` as the horizontal asset-local axes and `Z` as up. The game imports the GLB into Godot’s horizontal `X/Z` ground plane; use each face label to identify the side, then verify the transformed orientation in Godot at a real lot yaw.

## What the review suggests

The current box covers the whole footprint interior and full visible height. Several views show porches, counters, awnings, and ground-level openings within that volume. At the same time, shrinking both horizontal bounds to 80% leaves a ten-percent edge band beyond the box, where some low posts or solid corners may not be protected. A single box therefore risks both blocking useful access and leaving some visible solids exposed.

Treat these as collision-profile candidates, not approved pass/fail results. The images cannot decide whether the main entrance should be blocked by a visible closed door, lead to a real interior, or remain an NPC approach point outside the threshold. They do not include lot rotation, uneven terrain, the player capsule, triggers, or a runtime collision trace.

## Next runtime check for Claude

For each building, record the asset-local side of each ground-level opening and assign an explicit use: sealed facade, traversable entrance/portal, or approach/service point. Then test the fitted player capsule from both sides of that opening and around the solid corners. Replace only the failing box with a few local primitive profiles, rotate them with the same lot yaw, and add a short before/after capture with collision debug shapes. Keep navigation connected to the same verified approach points.

## Sources

- `kingdom/scripts/world/assets.gd`: `BUILDINGS` production fit sizes.
- `kingdom/scripts/world/settlement_builder.gd`: `_footprint()` and current per-lot `StaticBody3D`/`BoxShape3D`.
- [Broader collision visual audit](COLLISION_VISUAL_AUDIT.html) and [full phased plan](NATURAL_WORLD_FEEL_PLAN.md).
