# Meshy building collision visual audit

**Purpose:** give Claude a quick visual review of the building/market collision approximation currently produced by the game. This is an offline preview and source-grounded handoff, not an edit to the runtime collision code.

Open [`COLLISION_VISUAL_AUDIT.html`](COLLISION_VISUAL_AUDIT.html) to compare each fitted mesh with a wireframe of the current collider. It works from the checkout without external services. Every card has a three-quarter view and a top view.

## What is shown

The previews use the current Meshy LOD0 GLBs, scale their longest horizontal dimension to the target metres in `kingdom/scripts/world/assets.gd`, center the footprint, and place the mesh base on the ground. Orange wireframes visualize the collider shape used by `SettlementBuilder`: a box 80% of the mesh AABB in both horizontal dimensions and 100% of its height. The model is rendered in a neutral material so the geometry and openings are easier to inspect.

The runtime uses `SettlementBuilder._footprint()` for size and creates a `StaticBody3D`/`BoxShape3D` for every lot. LOW may use the LOD2 mesh to calculate a footprint; the preview uses LOD0 so the visible geometry is easier to read. The mesh and box are aligned at the fitted base and the lot yaw rotates both in-game.

## Findings to verify in Godot

1. **The box is volumetric across the whole footprint.** It occupies the interior and doorway height as well as the exterior walls. If the open door is meant to be traversable, the current box blocks it. This is especially worth checking on the inn, healer house, peasant house, and guild.
2. **Covered space is treated as solid.** The inn/healer/guild have visible porch or awning space; the market stalls have a canopy and an open working area. The full-height box can prevent walking under the canopy or up to the counter, even though those spaces look open.
3. **The 80% shrink leaves visible geometry outside the box.** Eaves, porch posts, protruding trim, and stall supports extend beyond parts of the orange outline. Some of these are harmless overhangs; lower posts and solid corners may let a character clip through.
4. **A single box cannot fit multiple wall segments.** It cannot represent a front wall with a doorway cut out, an L-shaped footprint, open market access, or a courtyard. Each hero/interactive building needs a small compound profile or intentionally blocked entrance, not a triangle-mesh collider by default.
5. **The same collider is not automatically a navigation route.** Once paths are introduced, the nav surface must exclude solid geometry and lead to an intentional service/door anchor. A door trigger or open/closed state should not leave a stale route or a permanently blocked path.

These are high-confidence structural risks based on the box dimensions in code. The gallery does **not** claim that a specific in-game doorway has already been blocked: lot yaw, entrance side, game camera, interior transition behavior, and player path need to be checked in the running settlement. Use the Phase 1 checks in [`NATURAL_WORLD_FEEL_PLAN.md`](NATURAL_WORLD_FEEL_PLAN.md) to close that loop.

## Asset dimensions

Dimensions are metres after production horizontal fit. “Box X × Z” is the current 80% horizontal box footprint; the box uses the full mesh height.

| Asset | Fitted mesh X × Z × height | Current box X × Z |
|---|---:|---:|
| Inn | 13.50 × 12.48 × 7.98 | 10.80 × 9.98 |
| Blacksmith | 11.00 × 9.18 × 6.63 | 8.80 × 7.35 |
| Adventurer guild | 16.00 × 9.52 × 9.08 | 12.80 × 7.61 |
| Healer house | 8.83 × 9.50 × 6.82 | 7.06 × 7.60 |
| Peasant house A | 7.50 × 6.69 × 7.02 | 6.00 × 5.35 |
| Family house | 7.67 × 9.00 × 9.06 | 6.14 × 7.20 |
| Manor house | 10.00 × 6.33 × 8.62 | 8.00 × 5.06 |
| Produce stall | 3.80 × 2.85 × 2.86 | 3.04 × 2.28 |
| Cloth stall | 3.80 × 3.17 × 3.15 | 3.04 × 2.53 |

Raw calculated dimensions are in `collision_review/asset_dimensions.json` beside the renders.

## Recommended next check

In Godot, enable visible collision shapes and walk the player capsule toward each asset from its visible front and sides. Check both directions through each intended opening, under each covered area, around protruding posts, and at lot rotations. Record one row per asset as `pass`, `door blocked`, `covered area blocked`, `solid edge leaks`, or `not traversable by design`; then replace only the failing full box with an authored local compound shape.
