# Adventurer Guild cull species attribution — Claude handoff

## Confirmed mismatch

Guild cull commissions store the ecology den's species as their target. `FrontierPresence` keeps each spawned body's `den_id`, but reuses Wolf bodies for several den species: troll, wyvern and bear bodies present as `bear`; `corrupted_wolf` presents as `wolf`. The den ID still refers back to the original ecology den.

`Life.on_wolf_killed()` currently calls `guild.on_kill(PLAYER, "wolf", den_id)` before resolving the actual den species. Since cull progress now requires both the exact target den ID and target species, wolf culls work but culls targeting bear, troll, wyvern or corrupted_wolf dens cannot progress.

## Correct owner and bounded fix

The correction belongs in `Life.on_wolf_killed()`: validate the supplied den ID against `Frontier.ecology.dens`, resolve that den's ecology species, then pass the resolved species and known den ID to `guild.on_kill()`. Unknown or invalid den IDs should not be assigned a guessed species for den-specific cull progress.

Keep existing creature-body presentation and merit, pelt, echo and drop policies unchanged. The species lookup for cull attribution should not silently change those unrelated rewards.

## Handoff and manual review

No game code was changed in this handoff. `Life` overlaps the current Codex PR, and the visible Claude checkout has unpublished changes to `Life`; Claude should fetch and review the current file before editing or coordinating ownership.

After the change, manually check den-targeted culls for wolf, bear, troll, wyvern and corrupted_wolf; confirm an unknown den ID does not advance a den-specific cull; and confirm active culls retain their target across save/load. No tests, parser or runtime validation were run for this handoff.
