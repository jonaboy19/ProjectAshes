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

## Review boundary

- Claude should review this branch against its current work before merging; the player, combat, camera, and HUD paths overlap ongoing polish areas.
- No in-game validation was completed in this environment. In particular, confirm each creature's visual contact frame still lines up with its unchanged gameplay hit timer after the wind-up speed switch.
- No scripts, scenes, or `project.godot` files outside the focused systems integration were changed.
