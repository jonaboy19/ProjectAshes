# Combat reaction ownership — local source checkpoint

5 October 2026. Branch: `gpt/character-feel-finish`. Source implementation only; no parser, runtime, visual or phone performance acceptance recorded.

## Reuse and behavior

Reuse the existing four directional `Hit_Light` clips and the rest-relative conversion from `tools_qa/anim_tech/lib/at_util.gd`. Local copies retain only upper-body bone rotations. A filtered additive OneShot joins the player's existing AnimationTree; no second tree, imported assets, or QA runtime dependency.

Light recoil preserves the underlying attack and its contact receipt when the additive clips are available. Missing clips use the previous replacement reaction and explicitly cancel the replaced attack. Heavy hits, blocked attacks, parries and death clear pending contact, attack travel, combo window and trail ownership together. Full-body actions abort residual additive recoil. An old dodge completion callback only fades a dodge clip, never a newer heavy reaction.

## Gameplay change to review

Heavy reactions now prevent new attacks/dodges while their full-body OneShot owns the pose, including a pending FIRE before tree evaluation. This extends commitment relative to the previous timer-only gate. Do not merge without reviewing responsiveness and intended poise rules. Existing damage, heavy thresholds, stamina costs and rewards are unchanged.

Light-hit knockback still cancels standing step travel through the existing kick path. This gives physical displacement priority; it does not guarantee planted feet during recoil.

## Acceptance still needed

- Parse and launch with the existing project tools.
- Frame review each directional light reaction while idle, moving, attacking and airborne; watch shoulders, weapon hands and extreme poses.
- Heavy reaction before contact must cancel damage; light additive recoil must retain the visible attack/contact timing.
- Block, parry, death/revive and dodge completion during heavy recoil must not revive old contact or fade the new pose.
- Missing-clip fallback and repeated hits, including impact pauses.
- Real phone frame cost and memory. Conversion happens at player setup; no performance claim is made.

This is a local patch for integration review. Claude's shared checkout and asset/model work were not edited.

## Mount transition follow-up

Mounting now calls the same interruption cleanup before handing movement to MountController, replacing the older swing-only reset. Pending contact, marker travel, combo window and weapon trail therefore relinquish ownership together. This does not integrate RiderSync, mounted sword clips or mount/dismount animations. Review mounting during windup, active/recovery frames and after local impact pause; no runtime result is recorded.
