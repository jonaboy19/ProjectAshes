# Codex bending integration on current GitHub code

Base: Claude branch 84e716eb, fetched 2026-10-05.
Branch: gpt/bending-current.

## Implemented
- Registered Claude's existing UAL_CMU_Bending.glb last in Assets.UAL_FILES; existing first-match priority is preserved.
- Disabled optional root position tracks on CMU bending imports. Collision bodies remain responsible for travel.
- Reused the published assets directly; no models, materials or VFX were replaced.

## Source reconciliation findings
The current TechniqueCaster uses AbilityRunner, unlike the older Codex checkout. AbilityRunner owns windup execution and recovery. TechniqueVfx listens to that runner. Animation release timing must be integrated through this lifecycle.
Player overlap_windups is currently enabled. Multiple paid casts can therefore have pending windups while a single animation is replaced. This needs a deliberate gameplay decision before long bending clips are assigned.
TechniqueCaster currently advances runner.update(delta) on the physics clock. Synchronization with the player's impact pause and animation clock remains to be implemented.

## Remaining
Review contact sheets and clip metadata, choose suitable technique mappings, synchronize release and playback, handle interrupted casts, review mobile cost and runtime appearance. Claude documents several floor-penetration clips, a crouched ending and lightning placeholders; importing them does not resolve those issues.

No runtime, import or tests were run for this patch. This branch is local until pushed. Older gpt/character-feel-finish gameplay patches are not merged into this checkout; reconcile them separately with current GitHub changes.
