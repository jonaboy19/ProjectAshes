# NPC blocked activity approach

Date: 2026-10-05
Branch: gpt/character-feel-finish

Villager._so_frame returned immediately while walking to a SmartObject approach. The Session therefore never updated during that walk and had no way to release an indefinitely blocked approach. A resident could retain a workstation claim despite making no physical progress.

The body now tracks actual planar displacement from an approach checkpoint. Moving at least 0.5 m resets the stall clock; after 12 seconds without that progress, excluding active yielding, it releases its session through token-safe cancellation, clears the obsolete route and marks the activity ended. The existing budgeted utility decision then selects a new plan. Claim start and cleanup reset the transient tracker. Longer successful walks and detours are not capped by total travel duration.

Scope: villager.gd only. No new brain, scans, navigation calls or timer nodes; constant work only for embodied SmartObject approaches. Session ALIGN/ENTER/LOOP/EXIT behavior is unchanged. Claude's checkout was not edited.

Limits: an NPC may select the same blocked spot again; there is no per-spot failure blacklist yet. Movement in a sufficiently large loop can reset the timer, so this is physical-stall recovery rather than complete reachability proof. Route-budget waits count toward the stall, intentionally preventing indefinite resource reservation; 12 seconds needs representative crowd/device tuning. Explicit yield time does not count. Reservations without a body Session are outside this change.

Source and diff reviewed; no tests or game runtime were run. Pending acceptance: obstruct a workstation, verify claim release and another resident's access, clear the obstruction and verify recovery, then check a long valid approach, detour, crowd yield and promotion/demotion. No mobile timing claim is made.
