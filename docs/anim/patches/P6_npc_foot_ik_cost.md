# P6 — NPC foot IK: the obvious hook is too expensive (FEEL_AUDIT F10)

**Tried (local, reverted):** `villager._attach_components()` → `ProceduralRig.attach(model, self)`
with the rig's own camera-distance budget (`Quality.rig_budget`: MEDIUM 3, HIGH 6) and
`set_state()` fed from the villager (IK off for sit/lie clips).

**Measured (village bench, Mobile renderer, `--uncapped`, alternating before/after on the same
loaded PC):** HIGH 37.3 / 29.5 fps with NPC rigs vs 51.2 / 51.6 fps without (≈ 7-15 ms per frame
on PC, ≈ 35-75 ms on a phone). LOW was unchanged (the attach was skipped at budget 0).

**Why it costs so much more than the 0.056 ms/char of `docs/anim/advanced/tech`:** every
attached rig adds `SkeletonModifier3D` stages (GDScript `Stage` callbacks + `TwoBoneIK3D`)
under the villager skeleton. Even when the rig is "far" (weights 0), a skeleton with
modifiers is re-evaluated every frame, which defeats the villager's 12 Hz manual-animation
LOD beyond 12 m and runs a GDScript callback per resident per frame. The tech-demo number
measured *active* rigs on a small set, not ~30 dormant ones.

**Proposal (Codex / local tech, new module, not in villager.gd):**
1. `NearRigPool` (new file, autoload-free, owned by `PopulationLOD`): keeps **N = rig_budget**
   pre-built rig nodes and *re-parents* them onto the N nearest visible residents every 0.35 s;
   residents never carry a rig otherwise (zero modifiers on the other ~30 skeletons).
2. Use the native `TwoBoneIK3D` targets only; move the pelvis/foot-tilt `Stage` work into one
   pool-level `_physics_process` that writes the target markers (one GDScript call per frame
   for all N, not N skeleton callbacks).
3. Rays: 2 per rig every 2nd physics tick (already how `procedural_rig` throttles NPCs).
4. Accept only if the village HIGH bench stays within 1 ms of the no-rig baseline.
