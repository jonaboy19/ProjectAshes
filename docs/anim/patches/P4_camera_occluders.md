# P4 — Chase camera hides behind the plaza well roof, then snaps in (FEEL_AUDIT F12)

**Evidence:** `docs/anim/feel/before/15_crowd_sheet_004.png` #66-#69: the well's shingle roof
fills the screen for ~0.2 s while the camera orbits, then #69 → #70 the camera jumps ~3 m
closer in one sample.

**Cause:** the well roof (and similar thin canopies: stalls are already covered by the
`CAMERA_BLOCKER_LAYER` proxies) has no collider on layer 1 or on the camera-only layer 10, so
neither the SpringArm sweep nor the extra occlusion ray sees it until the pivot ray hits the
well's post. Then the "instant pull-in" rule in `player._update_camera` fires.

**Fix (two parts):**
1. *Content (cloud/local world code):* give wells, lamp canopies, market awnings and roof
   overhangs a camera-only box on `CAMERA_BLOCKER_LAYER` (same helper as the stalls). This is
   the real fix.
2. *Camera (Codex, `player.gd`):* keep the instant pull-in for *walls* but ease thin
   occluders: when the new hit distance is more than 1.5 m in front of the current camera,
   move in at `1 - exp(-30 * delta)` (~3 frames) instead of one frame; and fade the occluding
   mesh's `transparency` 0 → 0.6 for props under 3 m thickness (a dither fade is what AAA
   games do for foliage/canopies). Keep the 0.3 m wall margin.
