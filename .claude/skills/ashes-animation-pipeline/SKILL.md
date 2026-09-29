---
name: ashes-animation-pipeline
description: How Rising Ashes gets animations - free mocap sourcing (licence rules), Blender retargeting, GLB AnimationLibrary export, preview strips, and the Codex handoff. Use for any animation, mocap, IK or motion task.
---

# Animation pipeline

**Ownership:** Codex owns animation BEHAVIOUR (state machines, controllers). The local and cloud sessions deliver only clips, libraries, techniques and demos, each with a handoff note.

## Sources (commercial use only)
- **OK:**
  - CMU mocap (free; attribution appreciated)
  - Quaternius Universal Animation Library (CC0)
  - 100STYLE (CC BY 4.0; credit required)
  - Kenney and OpenGameArt CC0 packs
  - Truebones free packs (check each pack's licence text)
- **NOT OK:**
  - Mixamo (needs an account)
  - LaFAN1 (CC BY-NC-ND)
  - the Bandai-Namco dataset (non-commercial)
  - anything derived from AMASS
  - anything marked "research only"
- Keep raw downloads outside the repo, in `C:\Users\Jonna\Documents\ProjectAshes_art_staging\anim_raw*`.

## Build
1. Retarget in Blender 5.2 with `tools/anim/retarget_bvh.py`, onto the game humanoid (the UAL skeleton; see `kingdom/assets/incoming/characters/`).
2. Clean up root motion, then trim, loop and decimate keys.
3. Export one GLB AnimationLibrary per category into `kingdom/assets/incoming/animations_free*/<category>/`.
4. Name clips `Category_Action_Variant` (e.g. `Sword_Combo_A3`, `Cast_Fire_Projectile_1H`).

## Verify
- Render frame strips or GIFs to `docs/anim/...` and READ them. Check that feet stay planted, wrists aren't broken, facing is correct, and there are no pops at the loop point.
- Runtime tech in Godot 4.6 is the SkeletonModifier3D stack: IK, LookAtModifier3D, SpringBoneSimulator3D, and PhysicalBoneSimulator3D for ragdoll. Measure ms per character for each quality tier.

## Handoff
Write a HANDOFF section for Codex covering:
- the clip list, and which state uses each clip;
- blend times;
- whether root motion is used;
- events, such as the hit frame and the VFX spawn frame for `ElementFX.play`.
