# Codex systems handoff

Branch: `gpt/locomotion-jump-integration`  
Base: `claude/focused-curie-m09hbd`

This branch keeps the authored project intact and adds small integrations around existing systems. It does not replace Claude's active game line.

## Scouting offers are now answerable

`Life` already rolled and saved scout offers, but the player-facing message only said to check the Pack; no screen read `pending_offers` or provided a response. The Journal now lists live offers and shows the recruiter, organization, reason, terms and expiry, with Accept and Decline actions.

The Journal reads `Life.scouts.offers` so offers restored from saves remain visible even though the old transient `pending_offers` queue is not serialized. Answering routes through `Life.answer_offer()`, which now reads the persistent scout record directly, rejects expired offers, clears the transient queue, records the recruitment flag, grants any configured signing bonus, and adds a biography highlight. Expired offers are removed from the queue and announced at the daily scout tick.

**Follow-up for Claude:** the offer contains an ongoing wage, but this patch does not activate payroll or move the player into the organization. That requires an explicit career/organization transition design; do not treat the displayed wage as paid until that system is wired. Current acceptance does grant recruitment-based skill access through the existing `recruited:<org>` flag, and signing bonuses are paid immediately.

## Combat and locomotion

See [CODEX_LOCOMOTION_JUMP.md](../anim/CODEX_LOCOMOTION_JUMP.md) for the player jump/run-stop integration, impact feedback, directional reactions, enemy wind-up timing and camera improvements, plus the required in-game validation checklist.

## NPC need continuity: first layer implemented

`WorldSim` now stores five normalized needs per resident in flat packed rows and includes versioned base64 fields in its save dictionary. Active `UtilityBrain` values sync at the existing staggered decision cadence and on body removal; promotion and time-skip resync restore the resident's saved needs, with the existing two-game-hour catch-up bound. Saves without valid fields keep the seeded fallback, and loading such a save clears any needs left in memory by the replaced session.

This does not yet advance unembodied needs continuously from schedules, and its serialized memory/cost has not been measured in a live mobile build. Remaining design, acceptance cases, and that limitation are tracked in [NPC_NEEDS_CONTINUITY_HANDOFF.md](NPC_NEEDS_CONTINUITY_HANDOFF.md).

## Dialogue presentation: F13 partial fix

Opening a conversation now eases the full dialogue layer (including the world shade) in over 0.25 seconds. Changing to a different speaker also fades the bust holder over 0.25 seconds so a duplicated NPC model or fallback portrait does not hard-cut into place. This is UI-only and adds no world scans or NPC work.

The feel-audit camera issue is still open: the camera can end inside the speaker or a cart. `dialogue_ui.gd` receives the model used by the portrait, not a reliable actor root and camera focus target, so this patch does not attempt a shot change. Claude should review the camera ownership/mask and interaction target path before adding a temporary talk-camera focus; validate on mobile and keep the current camera as a fallback when no safe actor target exists.

## Dodge lanes: F15

At dodge start, the player now sweeps the expected roll path once. If its first obstruction is a hostile actor, it probes nearby directions in 10-degree steps (up to 50 degrees), preferring the side away from the actor and using the nearest clear lane. This lets the roll skirt an enemy capsule while preserving ordinary wall blocking and invulnerability timing. No per-frame work or NPC scans were added; the extra physics probes happen only when a dodge would otherwise collide with a hostile.

## Review boundary

- Claude should review this branch against its current work before merging; the player, combat, camera, and HUD paths overlap ongoing polish areas.
- No in-game validation was completed in this environment. In particular, confirm each creature's visual contact frame still lines up with its unchanged gameplay hit timer after the wind-up speed switch.
- No scripts, scenes, or `project.godot` files outside the focused systems integration were changed.
