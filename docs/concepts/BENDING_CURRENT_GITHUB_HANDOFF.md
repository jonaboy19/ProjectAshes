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

## Hit pause synchronization (Codex)
AbilityRunner.update now accepts optional action_dt, defaulting to the existing dt. Only windup, recovery and cast lock use it; cooldowns, timed chants and effects keep world time. TechniqueCaster queries ImpactPause's actual mixer ownership and supplies zero action time during a held animation pause. TechniqueVfx uses the same query to hold unreleased anticipation timelines; released effects remain on world time. Existing NPC callers keep their original single-argument behavior.
This addresses impact-pause drift only. Clip contact mapping, playback speed matching, multiple overlapping casts and interrupted action ownership remain open. Existing visual particle nodes are not frozen by this change. No runtime or tests were run.

## Body interruptions (Codex)
Player hit reactions, lost clashes, guard breaks and death now call TechniqueCaster.interrupt_cast. AbilityRunner.interrupt_all drains all pending windups, including casts overlapping a chant, using existing interrupt rules and signals. The seal pad closes as failed; existing TechniqueVfx interruption listeners remove unreleased runs. Casting is blocked during player stun/flinch recovery. Released projectiles, target effects and cooldowns remain independent.
Existing refund behavior is preserved: the player currently has custom commit hooks but no refund hook, so this patch does not promise half-cost refunds for player casts. Dodge, jump and other action replacements still need an ownership policy. No runtime or tests were run.

## Melee / dodge / jump ownership (Codex)
Successful action starts cancel unreleased casting: melee and both dodge types at their start functions; jump only after its stamina check succeeds. Buffered or rejected inputs do not cancel a cast. New casts are rejected during swing, dodge, landing or jump states. Interrupted casting fades its upper/full animation layers, including recovery, before the replacement action starts. Air casts are not introduced by this pass. Casting-to-casting overlap is still the existing policy and remains open for contact mapping.
No runtime or tests were run.

## Cast-to-cast ownership and HUD eligibility (Codex)
Player overlap_windups is disabled. AbilityRunner now rejects another technique during an unreleased windup or recovery, preserving its existing lockout and cooldown rules. This removes the previous multiple-paid-windups/single-replaced-animation case. can_cast_slot uses runner.can_use so HUD callers receive the same body-state, lifecycle and path checks as actual casting. No automatic cast queue is added; existing button feedback can explain Busy.
No runtime or tests were run. Long bending clips still need measured contact/recovery mapping before assignment.

## Delayed close-range follow-up hits (Codex)
The legacy multi-hit timer path now captures a body-action generation. Melee/cone follow-ups are discarded after interruption or a replacement cast; dead casters discard every scheduled area follow-up. Freed targets are replaced with null before area resolution. Released remote area effects retain their existing independent behavior while the caster lives. These timers still use world time, so follow-up contact timing during impact pause remains unfinished; migrate to the action clock when clip events are mapped.
Mobile technique_buttons and hotbar were source-reviewed: both consume can_cast_slot's ok flag, so the runner eligibility change has existing consumers. No runtime or tests were run.
