# CMU bending integration: library registration checkpoint

Date: 2026-10-05
Source: Claude branch dee6793b, GitHub handoff in docs/LOCAL_SESSION_HANDOFF.md.

Imported Claude's existing UAL_CMU_Bending.glb, sidecar, README and LICENSE from the fetched branch into Codex's worktree, without changing the model or clips. Registered the pack last in Assets.UAL_FILES, preserving first-match precedence for existing animation names. Extended the loader's root-position disable rule to this pack: gameplay capsule motion remains authoritative and travel tracks cannot inadvertently translate the visible rig in addition to the controller.

This makes the pack available through the existing UAL animation loader after Godot import; it does not yet choose these animations for gameplay techniques. No import, tests or runtime were run. Claude's asset README reports cleanup needs: floor penetration in several clips, large Air evade travel, crouched Earth ending, placeholder Lightning, and mixed-performer transitions. Those need preview/contact review before assigning techniques. Do not treat library availability as verified animation quality or end-to-end casting integration.

Remaining Codex work: inspect all supplied preview sheets, choose appropriate clips per stance/technique, derive actual release/contact frames, and connect timing to the same animation/action clock with cancellation. Current TechniqueCaster's independent timer path must be reconciled before changing release duration. Existing Taichi/Karate/Kata/MA/Cast coverage stays the base. Claude/local own floor/contact cleanup and VFX lab; the lab is not ElementFX-integrated and phone performance is unmeasured.

No Claude shared checkout edits. Changes are on gpt/character-feel-finish only; assets are copied from Claude's published Git commit, not newly generated. Upstream combat-feedback/camera changes still need a controlled reconciliation before this branch merges back.
