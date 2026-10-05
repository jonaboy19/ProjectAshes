# vfx_lab: Godot-native bending VFX prototypes (water whip, fire blast, earth spikes)

Files: `kingdom/scenes/vfx_lab/` (`lab_fx.gd` base, `water_whip.gd`, `fire_blast.gd`, `earth_spikes.gd`, shaders `water_whip`, `fire_blast`, `earth_rock`, `crack`, `puff`, demo `vfx_lab.tscn`, sheet renderer `sheet.gd`).
Sheets: `vfx_lab_sheet_high.png` (HIGH tier, rows water / fire / earth, frames at 0.1 0.22 0.4 0.6 0.85 1.1 1.45 1.9 s) and `vfx_lab_sheet_low.png` (LOW tier: no inner fire shell, half particles, no light).
Render: `xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan --fixed-fps 30 --path kingdom -s scenes/vfx_lab/sheet.gd -- --out=/tmp/vfx --quality=2`
(`--fixed-fps 30` is required: particles are real-time. The Quality autoload caps SubViewport height, so the sheet renders on the root window.)

API (all `LabFX`): `play()`, `seek(t)`, signal `finished`, `quality` 0..2, effects point along -Z with the origin at the hand. Not hooked into `ElementFX`; the game already has `scripts/vfx/element_fx.gd` with 8 elements x 7 types, and these are candidates to replace `water/projectile`, `fire/beam` and `earth/aoe` after review.

| Effect | Draw calls | Transparent meshes | Particles (HIGH / LOW) | Lights | Mesh verts | Notes |
|---|---:|---:|---|---:|---:|---|
| Water whip | 1 tube + 1 ring decal + 2 particle systems | 2 | 40 / 20 | 0 | 319 | everything in the vertex shader |
| Fire blast | 2 shells (1 on LOW) + scorch + embers | 3 (2 on LOW) | 28 / 14 | 1 (HIGH only) | 315 per shell | pixel shader = 2 noise lookups; additive |
| Earth spikes | 1 MultiMesh (11 spikes) + crack decal + 2 particle systems | 1 (decal) + dust | 34 / 17 | 0 | 18 per spike | spikes are opaque, no overdraw |

Budget status: NOT measured on a phone. Desktop-GPU timing was not taken (software Vulkan in the cloud). Risks to check on the S22: fire blast pixel cost near the camera (full-screen overdraw when the cone fills the view: cap `base_radius` or fade by camera distance), GPUParticles3D under `gl_compatibility` (`ElementEffect` converts to CPUParticles at <= 24; these effects do not yet), and the 3 simultaneous casts that would exceed the 120 particle guideline.
Techniques are re-written from the descriptions of the MIT sandbox `achrefelouafi/AvatarCastingAbilitiesThreeJS` (see `docs/research/BENDING_SOURCES.md`); no code or assets were copied.
Known polish gaps: no heat-haze, water has no refraction, earth has no impact decal on the ground beyond the crack quad, fire core looks white at the base (tune `c_core` / alpha), water colours pale under the dusk light.
