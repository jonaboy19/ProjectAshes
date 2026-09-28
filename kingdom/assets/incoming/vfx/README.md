# VFX sources (magic and martial-arts effects)

Everything the effect library (`scripts/vfx/`, `shaders/vfx_*.gdshader`) uses at
runtime is in `atlas/`. The other folders hold the untouched source files and
licences they were built from. They carry a `.gdignore`, so Godot doesn't import them.

| Folder | Origin | Licence | Commit | Used for |
|---|---|---|---|---|
| `kenney_particle_pack/` | https://github.com/Calinou/kenney-particle-pack (Kenney Particle Pack 1.1, kenney.nl) | CC0 1.0 (`LICENSE.txt`) | ab70866 | 14 sprites packed into `atlas/vfx_atlas.png` |
| `rpicster_vfx_textures/` | https://github.com/RPicster/Godot-particle-and-vfx-textures (Raffaele Picca) | CC0 1.0 (`LICENSE`) | 9bb6fe7 | radial streaks (impact frame) and the swirl (naming spiral) in the atlas |
| `vfez_reference/` | https://github.com/alexnikop/VFEZ-godot (Alexander Nikopoulos) | MIT (`LICENSE`) | 3538f5c | Reference only (`.txt`). The noise dissolve with burn edge, fresnel rim and UV twist ideas were rewritten into `shaders/vfx_fx.gdshader` and `vfx_ghost.gdshader` |
| `fiery_slash_reference/` | https://github.com/priyanshsingh102005/Fiery-Slash-Shader-for-Godot-Dynamic-Sword-Trail-VFX-3D- | MIT (`LICENSE`) | 23cf87d | Reference only. The noise-distorted, 3-colour gradient slash was reworked into the smear mode of `vfx_fx.gdshader`. Its textures are the Kenney pack, and an unlicensed JPG in that repo was **not** taken |

## `atlas/` (built by us, CC0 inputs)
- `vfx_atlas.png`: 1024², 8-bit greyscale, a 4×4 grid of 256 px cells (8 px padding). The shaders colour it with a hot, tint and edge ramp. Cells:
  `0 flame_05, 1 muzzle_02, 2 smoke_04, 3 fire_01, 4 spark_05, 5 spark_01, 6 star_06, 7 star_08,
   8 twirl_02, 9 slash_02, 10 scorch_02, 11 dirt_02, 12 trace_06, 13 light_03, 14 RPicster effect_1, 15 RPicster effect_4`
- `vfx_noise.png`: 256², tileable. R holds soft fbm, G finer fbm and B ridged noise (cracks, energy). It's our own procedural work (FFT-filtered random field), CC0.

To rebuild, clone the two CC0 repos into `/tmp/claude-0/src/` and run `python3 build_atlas.py` (it needs Pillow and numpy). Values are luminance × alpha, each cell normalised to full range.

Credit (optional for CC0, given anyway): Kenney (www.kenney.nl); Raffaele Picca (raffaelepicca.com).
MIT notices: VFEZ-godot © 2025 Alexander Nikopoulos; Fiery Slash Shader © 2026 Priyansh Singh.
