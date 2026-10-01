# LifeCourses marriage kinship guard — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: eligibility checks for new `LifeCourses.try_marry()` pairings. No spouse/parent schema changes, save migration, or retroactive marriage edits.

## Rules added

- The initiating person must exist, be alive, be unmarried, and be at least 16 years old at the supplied day.
- Candidate eligibility retains the prior alive/unmarried, opposite-sex, adult and same-or-nearby settlement rules. Before random selection, it now rejects parent-child pairs in either direction and full siblings who share at least one nonnegative parent ID.
- Parent lookup is defensive: a missing or non-Array `parents` field yields no recognized parents; Array entries count only when they are actual integer values greater than or equal to zero. Malformed values are ignored as IDs, so unknown kinship cannot be excluded when lineage data is absent or invalid.
- Candidate ordering and the existing RNG choice among the remaining candidates are unchanged. Cousins and other extended relationships are not filtered. Existing marriages are not re-evaluated or migrated.

## Verification and limits

Static source review and `git diff --check` only. No parser, runtime marriage-generation, save/load or behavior check was run. This guard applies only when `try_marry()` creates a new pairing; it does not repair pre-existing records.
