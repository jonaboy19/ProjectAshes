# Life identity input fixes — 5 October

Refreshed `origin/claude/focused-curie-m09hbd` at `1983bfeb` and `origin/main` at `31ecc059`. Both historical handoff gaps were still present in the inspected Claude actor/system source. Focused candidate fixes are on `gpt/character-feel-finish`, not in Claude's shared checkout.

## Awakening culture

Life now selects the single recognized `culture:<id>` flag from the persisted life path. Recognized IDs come from the existing Awakening culture-element mapping. Missing, unknown or conflicting identities retain the historical Caldric fallback; conflicting flags never select a culture by dictionary order. RNG seed, character name, day and weighting formula are unchanged.

This corrects the culture input; it does not guarantee a particular element for any culture. Existing completed awakenings are not rerolled or migrated.

## Den cull attribution

Life's wolf-body kill handler now obtains the guild species from the referenced ecology den. Valid troll/bear/wyvern/corrupted-wolf dens therefore supply their actual species even when the spawned body uses the wolf/bear presentation. Invalid or unknown den identities supply no guessed species and cannot match den-specific commissions.

Region 1 signal identity, progress subject, merit, pelt/meat, soul and echo policies are preserved. Den identity retains the current index contract used by FrontierPresence and the existing handler; no universal creature-ID system is introduced.

## Evidence and acceptance status

Source contracts checked: persisted culture flags, Awakening.CULTURE_ELEMENT, existing den lookup and Guild.on_kill's exact species/den gate. No parser, runtime, save/load or behavior checks were run. Review each culture plus legacy/conflicting flags, deterministic restoration, each den species, invalid den IDs and unchanged unrelated rewards before integration approval. Preserve later Life changes when applying the narrow diff.
