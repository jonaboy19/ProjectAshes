# Systems continuation: resume here

## Current checkpoint after usage reset

### Active checkout and refs (refreshed 2026-09-30)

- This continuation is now being maintained on **`gpt/locomotion-jump-integration`**, currently `3a71c310`. Its Codex changes are pushed to that branch and update the attached Codex review; do not push them to Claude's branch.
- This checkout includes the earlier Claude source through **`ec7c4960`** and Codex's later movement/needs work. It does **not** include the latest fetched Claude ref.
- Latest fetched `origin/claude/focused-curie-m09hbd` is **`d163255f`** (includes `09febe67`); latest fetched `origin/main` is **`140c4eb5`**. These are source refs, not merge approvals. Claude's newer ref changes more than 7,500 lines and overlaps `life.gd`; preserve it separately until a deliberate coordinated merge.
- The historical `gpt/living-systems` / `main 6dd277e9` statements below describe the previous checkpoint. Use the active refs above for new work and treat old test/import notes as historical evidence only.

### Claude living-world package observed on 2026-09-30

Latest fetched Claude ref is `d163255f`, including `09febe67`: a `living_world` prototype with typed smart-object spots/sessions, props, clip library, crowd animation LOD, ambience, and a demo actor. Its integration seams with Codex's already-present station leases, NPC position ownership, persistent fact journal, and need rows are mapped in [Codex ↔ Claude living-world integration handoff](CODEX_CLAUDE_LIVING_WORLD_INTEGRATION.md).

This package is not merged into the Codex worktree and is not wired into the playable main scene in the inspected source. The branch diff is large and touches `life.gd`, so preserve both refs and use the handoff's smith/anvil vertical slice after coordinated integration. In particular, do not treat demo actor transform snaps or integer spot IDs as gameplay-ready movement/identity contracts.

Committed resume points: `86a9e339` (station reservations and local conversation topics), `72e09b25` (FIFO sight and observation age), `0a0ae349` / `9d2cc2b6` (regional event adapter and current-journal provider). Review these commits after the main merge `bacf11e7`; do not apply the entire old branch diff blindly to newer Claude work.

This section supersedes the older progress ledger below. Latest main `6dd277e9` was merged cleanly into the isolated systems branch in `bacf11e7`; Claude's appearance, character creation and dialogue UI additions remain present. The PC checkout was not edited. Re-fetch heads before taking ownership of overlapping files.

New code now connects crafting to exact station references and registration generations. World sites use site IDs and part slots; interior callbacks resolve settlement/lot identity, with explicit ephemeral identities when that context is unavailable. A craft reserves both the player and its specific station generation atomically, rechecks the same station/range/kind at commit, and cancels on room teardown. Returned descriptors are copies. This does not yet make NPCs approach, align with or use a workstation; animations and smart-object approach adapters remain separate work.

Threat sight now uses a FIFO queue capped at 64, with one pending request per observer, weak references, preserved waiting age, current target poses at cast time, and the existing 4 rays per 500 ms limit. Results retain observation time; old packets contribute decaying memory rather than fresh WATCH evidence. State clears on exit, indoor transitions and resync. Mailboxes and observer statistics are capped. This improves admission order but does not establish phone cost or a guaranteed detection delay: decisions must continue to drain the queue, hostile discovery still scans the shared cache, and only the nearest two candidates are sampled.

`region_event_bridge.gd` is an optional signal adapter, not a second simulation/event/save owner. It accepts the actual StringName module/event contract, bounds bindings and registry scans, uses weak sim references and generation guards, and never replays module rings. `configure_provider` resolves the current Life journal after save/load replacement. Region elapsed days and absolute receipt hours are stored separately. This adapter is **not wired into gameplay** because main still lacks Claude's Region1 scaffold; preserve that scaffold and attach/reconcile this adapter in the coordinated integration hook. Call `dispose()` on teardown. No permanent event deduplication or witness knowledge is implied.

Relationships now have sparse conversation-topic memory: 128 NPC records, 8 topics each, 512 total, 30 game days retention, coalescing and deep-copy queries. Actual dialogue-node presentation records a topic only for its participant; existing dialogue `event`/`no_event` conditions can use `discussed:<file>:<node>`. Existing opinions, gifts, conversations and save owner remain intact. This is bounded knowledge of conversations, not NPC-to-NPC biographies, identified crime evidence, rumour propagation or new authored dialogue. JSON integer-valued floats are normalized during restore; malformed topic sections reset independently of existing relationship data.

Evidence: isolated Godot 4.6.3 parser checks pass station identity, event bridge and relationships; crafting passes project-context check-only. Autoload-dependent checks stop at unresolved project singletons, so full integration remains unverified. A worker attempted headless startup and editor import; missing imported media and a stalled filesystem scan prevented a valid live run. No behavioral tests or device benchmarks were run. Do not equate absence of changed-file errors in that attempt with gameplay validation. Import-generated asset changes are excluded from the systems commits.

Next: establish full-project import/compile on the real game checkout, then review cancel/reopen/load/unload/duplicate craft paths, multiple station identity collisions and sparse topic JSON round trips. For sight, measure queue wait, dropped/expired requests, wall occlusion and delayed memory with active NPC counts on the target phone. Keep existing movement/contact/LOD owners. Only then add NPC workstation approaches and observed social actions; do not implement Claude-owned Wardlines, Scar Tide, Ashsight replay or rumour-market packages in parallel.

## Checkout and coordination

Implementation branch: `gpt/living-systems`, review in [PR #2](https://github.com/jonaboy19/ProjectAshes/pull/2). Systems baseline: `origin/main` 4e03e000d2e68e32fea7bb0625d373e72bbbfe0d. Claude's shared branch d27d798f contains newer asset work; do not assume it is included in this base. The original PC checkout `C:\Users\Jonna\Documents\ProjectAshes` was left untouched by this systems work. Re-read remote heads and this branch's status before resuming; do not discard uncommitted review fixes or overwrite newer workers' changes.

The crafting and sight slices are committed as 24b254e6 and 1694b0df. Static review is complete; live integration remains pending. Presence of a function is not proof of a correct live-game result. Merge/rebase only after coordinating ownership and preserving newer Claude work.

## Delivered progress ledger

| Slice | Source | Current evidence and limits |
|---|---|---|
| Bounded fact journal | `kingdom/scripts/systems/world_event_log.gd`; Life record/crafting producers and snapshot/restore | Real producer/query/save integration exists; bounded 256 records, finite JSON validation, monotonic sequence and retention window. A journal, not an event bus; no automatic consequence dispatch |
| Crafting action lifecycle | `kingdom/scripts/systems/action_runtime.gd`; `kingdom/autoload/life.gd`; `kingdom/scripts/ui/crafting_screen.gd` | Working tree contains start/commit/cancel API and existing tween glue. Active max32, terminal cache64; review includes recipe-token match, reentrant commit guard and current nearby station-kind validation. ACTOR work-channel reservation only; no physical anvil/well/chair reservation |
| Local sight and danger memory | `kingdom/scripts/population/utility_brain.gd`; `kingdom/scripts/population/villager.gd` | Working tree contains shared visibility-ray budget4 per500ms and3-second anonymous last-seen danger memory; review pending. No field-of-view, hearing, culprit identification or permanent NPC memory |
| Planning and review record | `docs/SYSTEMS_MASTERPLAN.md`; `docs/SYSTEMS_CLAUDE_HANDOFF.md`; this file | System-by-system audit and ordered follow-up; not a claim that all planned systems are complete |

Parser checks cover the isolated new module scripts only where explicitly recorded in the PR. Full-game dependency/import/bootstrap/integration is unverified. No behavioral tests or mobile-device performance result have established these new slices. Latest review fixes must be inspected and verified before their status becomes accepted.

## Earliest required gate: establish live correctness

Before another subsystem, inspect the current diff, run/import on the actual Godot project and verify the existing crafting interaction. This gate is a proposed next activity, not a test claimed complete here.

Craft route: valid recipe once; duplicate finish callback; mismatched recipe token; cancel then finish; reopen menu; move away from station before finish; materials removed before finish; repair recipe; expired token; reload during tween. Confirm exactly one inventory effect, crafting XP, Life.record, time skip and audio result. Confirm legacy UI behavior remains and cancelled work grants nothing. A cached repeat may expose a result for diagnostics, but must not repeat player rewards/time effects.

Sight route: hostile visible; hostile behind solid wall; second hostile visible while nearest is hidden; all shared ray budget consumed; outdoors-to-indoors transition; target disappears; 3-second memory decay; sleep/load/time skip. Unknown due to budget must not become a new visible fact. Memory uses last-seen coordinates, not hidden live coordinates. Observe WATCH as well as FLEE. Building meshes without physics occluders may still fail line-of-sight; do not attribute this to a working ray budget alone.

Capture event/action/sight counts and compare sustained physics frame costs with baseline. Shared4-per500ms limits queries but does not prove mobile performance, fairness or detection latency. Existing decision stagger must remain; avoid all-person scans or an extra Node per distant resident.

## Next implementation: stable shared station identities

Read `kingdom/scripts/sim/crafting.gd` station registration, scan_interior and stations_near; Life `_craft_station_kinds_near_player`; UI opening/context flow. Current station kinds cannot distinguish two separate anvils. Add explicit stable object/slot references backed by deterministic world site/settlement/building identity; interior instance IDs alone are transient and unsuitable for save identity.

Extend station descriptors additively; preserve existing kinds queries for compatibility. Choose a nearby eligible station from real location, then reserve its exact usable slot alongside the actor channel. Revalidate actor/target identity, range, prerequisites and lease at commit. Two actors can use separate anvils concurrently; two actors cannot occupy one slot. Unload/cancel releases ownership; stale generation tokens cannot release a successor reservation. UI presentation and animation stay Claude-owned. Until actors walk/align/contact via an adapter, do not call this a natural physical interaction system.

## Following slice: significant NPC memory

Add a bounded pure-data memory store only after namespaced observers and verified sensory producers are defined. Copy significant event/belief snapshots so journal eviction does not erase a retained memory. Keep world facts separate from what an observer saw/heard. Suggested sparse caps: known observer128, per observer16 memories, global1024; configure and measure rather than promise these limits fit all devices.

Record anonymous danger without inventing a culprit. Identified theft/assault requires a verified witness and confidence. Coalesce repetitive cause/subject/kind events and decay salience; protected legal/economic consequences belong to their owning systems. Restore validates atomically. Dialogue and utility adapters should consume a bounded selection of beliefs. Never broadcast the entire journal to everyone.

## Remaining large systems

Still planned: physical SmartObject approaches/contact/slots; shared activities/work orders and opportunities; multi-occupation/knowledge/qualifications; sparse NPC-to-NPC social links; hearing/suspicion/search; crime/jurisdiction/reporting; belief-aware rumours; state-cast scenarios and personal matters; real production/cargo continuity; cause-driven migration and construction; military logistics and deed ledger; persistent creature/Soulbeast lives; unified ability/status interfaces. Existing partial foundations remain owners. Do not replace them wholesale.

## Ownership and invariants

Systems files touched in this slice: new `scripts/systems/*`, narrow `autoload/life.gd`, crafting lifecycle glue in `scripts/ui/crafting_screen.gd`, and reviewed sensing hooks in `scripts/population/utility_brain.gd` / `villager.gd`. Those population files are performance hotpaths and may overlap PC work: inspect current source and coordinate before changing further. Claude owns models, materials, scenes, sockets, rig/animation/camera and environment. No assets were needed for this slice.

Anti-duplicate: one authoritative effect owner; commit guard before callbacks; bounded terminal receipt; stale/evicted tokens reject rather than rerun. Anti-omniscience: facts do not imply knowledge; unknown sensor result neither confirms nor disproves sight; last-seen memory never tracks hidden live position. Mobile cost: hard shared budgets, sparse data, staggered decisions, expiry and retention metrics. Continuity: namespaced identity, existing save manager, old-save defaults, no double movement owner, and transient action cancellation on restore until an explicit resume protocol exists.

## Latest coordination checkpoint (29 September)

Remote main is now 6dd277e9; Claude shared branch is 73d66ef1. The PC checkout is eb805176 with active local/import/VFX changes; do not reset, clean or edit it. These refs are observations, not a promise they remain current. This branch still derives from 4e03e000 and has NOT been rebased onto the latest game.

Claude added Region1Sim, Region1Root, Region1State and a demo/scaffold (e86a57cd), with its own bounded module event logs and save registry. Read docs/regions/HOOKS_FOR_CLOUD.md and the current Region 1 plan before continuing. Reuse that scaffold for regional systems; do not introduce a competing ticker/save registry. Our player fact journal is a different producer but now needs an explicit bridging/deduplication decision: preserve authoritative owners, original causes and time units (journal game hours versus region game days). Do not fan module events back into themselves or broadcast every fact to every NPC.

Latest main adds character-creation appearance and snapshot/restore fields in Life. Preserve apply_creation, appearance and front-end integration when transplanting our narrow Life hooks. Current remote crafting/utility/villager changes do not replace our action-token or local sight implementation. Absence on these checked branches does not rule out Claude's unpushed cloud work.

Additional action-runtime change: begin_resources atomically acquires up to 8 distinct keys and releases all keys owned by the exact token. Legacy begin still delegates with one key. This is a foundation only: the current crafting adapter still reserves actor:player, and no physical station IDs were implemented. Both the final single-resource and multi-resource module pass Godot 4.6.3 isolated --check-only. The project-context utility_brain --check-only stopped at unresolved WorldSim (line651); it did not establish integrated compile or live correctness. No behavioral tests were run.

Execution workers hit the account usage limit during the next station task. Only action_runtime.gd has additional multi-key code; there is NO station_identity.gd or station registry/Life integration from that attempted task. Inspect status before resuming rather than assuming the assigned task completed.

Station implementation plan from source review: add optional reference/generation fields in Crafting.add_station and scan_interior; VillageServices._on_interior_entered already receives the door with lot_pos metadata. Resolve exact WorldGen settlement/plan lot index without editing settlement_builder; identify sites by site.id and part index. Interior room instance IDs are session-only fallback, never permanent identity. Dedup same owner/reference; reject colliding live registrations. Reserve both actor and exact station atomically. Commit must revalidate SAME station reference and registration generation, range and recipe prerequisites. Layout index identities need migration if the generator changes.

Sight limitations: four shared rays per500ms is first-come and can starve observers; decision staggering is not proof of fairness. Each observer still scans cached threats O(H), nearest two candidates can miss a third visible threat, and cached coordinates can be500ms old. No FOV/hearing/identified witnesses. Three-second memory expires at decision cadence; action changes can lag by the existing decision interval. Measure observer latency and phone costs before increasing budgets or claiming natural awareness.
