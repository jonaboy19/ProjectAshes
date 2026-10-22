# VFX plan for later (owner note, 2026-10-01)

VFX is **on hold**; the owner will say when to start. This file keeps the agreed direction so nobody forgets it.

## The owner's guidance, adapted for Godot
The original advice was written for Unreal. Rising Ashes stays on Godot, so each tool maps like this:

| Unreal advice | Godot equivalent we use |
|---|---|
| Niagara (core VFX system) | GPUParticles3D, with CPUParticles3D as the fallback, plus `scripts/vfx/element_fx.gd` (pooled spawn API) |
| Material Editor / HLSL | `.gdshader` (dissolve, glowing runes, scrolling energy, distortion, force fields, Rift corruption, spirit bodies, sword glow) |
| EmberGen (fire, smoke, explosions → baked flipbooks) | EmberGen is paid. Use **Blender Mantaflow** to bake flipbooks (`tools/vfx/`, already working), plus Material Maker and Effekseer (installed in `C:\Users\Jonna\Tools`). If the owner buys EmberGen, bake to flipbooks only. |
| Blender mesh VFX | The same: magic rings, slash meshes, shockwaves, rune geometry, portals, debris, projectile shapes, scripted with Blender Python |
| Houdini | Not needed yet |

## The pattern to follow
Build a few reusable **base effect scenes** and give each element its own parameters (colours, textures, timing, mesh). Avoid hundreds of one-off effects.

Base scenes:
- `Element_Base`
- `Projectile_Base`
- `Impact_Base`
- `Aura_Base`
- `WeaponTrail_Base` (exists: the weapon trail module)
- `Charge_Base`
- `StatusEffect_Base`
- `Rift_Base`
- `Soulbeast_Base`

A new ability should come down to a mesh, textures, colour and parameters, timing, and gameplay values.

## Mobile rules
- Use mesh particles, flipbooks and shaders. No real-time fluids or volumetrics.
- Pool every effect.
- LOW tier uses CPU particles and fewer emitters.
- Budget: at most 1 ms GPU for the worst-case area effect.

## What already exists
- 8 elements: charge, projectile, impact, area effect and status (`scenes/vfx/elements/`)
- weapon trails
- 6 flipbooks (`assets/vfx/flipbooks/`)
- the Effekseer addon, not wired in

Documentation: `docs/art/vfx_elements/`, `docs/art/vfx_tools/`.
