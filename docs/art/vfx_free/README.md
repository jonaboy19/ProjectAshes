# Free VFX and shaders (gallery)

Gallery scene: `kingdom/tools_qa/vfx_gallery/vfx_gallery.tscn` (F6). Keys: 1 effects row, 2 scenery, K painterly post, G god rays, F fps label.
Screenshots (Godot 4.6.3, Mobile renderer, RTX 4070): `view1_plain.png`, `view1_painterly.png`, `view2_plain.png`, `view2_painterly.png`, `view2_no_godrays.png`. Raw timings: `fps.txt`.
Regenerate: `Godot --path kingdom --rendering-method mobile res://tools_qa/vfx_gallery/vfx_gallery.tscn -- --capture=<dir>` (add `--only="fireflies"` for one group).
Not wired into any gameplay scene.

## Licences
| Item | Licence | Where |
|---|---|---|
| Kenney Particle Pack (31 textures) | CC0 | `kingdom/assets/incoming/vfx_free/kenney_particle_pack/` |
| RPicster textures (7, 256 px) | CC0 | `kingdom/assets/incoming/vfx_free/rpicster_vfx_textures/` |
| SimplestGodRay3D (Re_Lo) | MIT | `kingdom/shaders/free/god_ray_mesh.gdshader`, `kingdom/assets/incoming/vfx_free/simplest_godray/` |
| kuwahara_post, fluffy_leaves, stylized_grass, stylized_water, storybook_sky | original project code | `kingdom/shaders/free/` |

Full quotes and URLs: `kingdom/assets/incoming/vfx_free/LICENSES.md`. Not imported: the godotshaders.com items (site firewall blocked the licence check) and Binbun3D Flame FX (CC0 confirmed, download not scriptable).

## How to use
- Particles: see `_emitter()` in `vfx_gallery.gd`: GPUParticles3D + `ParticleProcessMaterial` + one `QuadMesh` with an unshaded, vertex-colour-driven StandardMaterial3D using `BILLBOARD_ENABLED` + `billboard_keep_scale`. Colour over life comes from a `GradientTexture1D`. With `BILLBOARD_PARTICLES` the particle scale was ignored in 4.6.3, so avoid it.
- Recipes in the gallery: campfire (flame 14 + embers 8 + smoke 10 + flicker light), magic sparks in 3 colours (20 + glow 3), portal (2 spinning twirl quads + 24 ring sparks), hit sparks (18 burst + flash), dust puff (10), falling leaves (CPUParticles3D, 12), fireflies (14).
- `shaders/free/fluffy_leaves.gdshader`: needs a `leaf_mask` noise texture, for blob canopies. `stylized_grass.gdshader`: MultiMesh of quads (UV.y = 0 at the tip). `stylized_water.gdshader`: plane, no depth or screen reads. `storybook_sky.gdshader`: Sky material. `kuwahara_post.gdshader`: ColorRect in a CanvasLayer. God rays: `simplest_godray/simplest_god_ray_3d.gd` as a Node3D (class SimplestGodRay3D).
- All shaders compiled and ran on Godot 4.6.3 with the Mobile renderer without errors.

## Cost (from `fps.txt`, RTX 4070, 1280x720)
Wall frame time was noisy because other Godot/Blender jobs were running; the GPU column is the trustworthy one.
- Every emitter or shader adds under 0.2 ms GPU on the desktop GPU. All 9 effects together: about +0.02 to +0.15 ms. Scenery (1800 grass blades, tree, water, sky, rays): about +0.2 ms.
- Painterly Kuwahara (radius 2, 36 taps per pixel): +0.14 to +0.3 ms on the 4070 at 720p, so a phone GPU will pay 10x or more. HIGH/desktop only, never LOW.
- Mobile rules followed: 8-24 particles per emitter, textures at most 512 px, no screen or depth texture reads except in the post shader. On Compatibility or LOW, use CPUParticles3D (the leaves emitter shows the pattern) with amounts under 12.

## Where to use them (suggestions only)
- Torches and campfires at night: the campfire recipe (drop the smoke on LOW).
- Magic and quest moments: sparks; rift gates: portal swirl.
- Combat hit feedback: hit sparks; sprinting and footsteps: dust puff (CPU, 6-8 particles).
- Forest and autumn: falling leaves; night meadows: fireflies (the game already has `ambient_fx`, compare before adding).
- Foliage: `fluffy_leaves` and `stylized_grass` are lighter than the current `tree_wind` and `grass` shaders on LOW. The existing shaders are richer (interactors, seasons), so only adopt where those are too heavy.
- Water: `stylized_water` for LOW lakes; `shaders/water.gdshader` stays for HIGH.
- Sky: `storybook_sky` matches the reference (saturated blue, white cumulus); measure before replacing the current sky.
- God rays at the Kingsreach gate or under big trees (one quad each); painterly post only as an optional HIGH/desktop toggle.
