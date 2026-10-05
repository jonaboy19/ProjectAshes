# NPC activity cleanup: preserve replacement claims

Date: 2026-10-05
Branch: gpt/character-feel-finish

Villager._so_release previously always called SmartObjects.release(person). Session.update and Session._go(DONE) already use token-checked release, but the body cleanup immediately following DONE bypassed that protection. If a schedule refresh replaced a claim while an older session still existed, the old session correctly stopped, then villager cleanup could erase the replacement claim.

The body now calls the existing Session.cancel_now when it has a session. That releases only the session's captured token through release_claim. When no session exists, the existing resident-level release remains, preserving cleanup of schedule-only claims on teardown. Local props, clip, snap and session fields still clear as before.

Scope: one cleanup path in scripts/population/villager.gd. Claude's checkout is untouched. No new reservation framework or animation owner was introduced. Source review included claim refresh, token capture, revoked-session update, DONE handling and body release callers. No tests or runtime checks were run.

Remaining acceptance: replace an active session's claim, advance the old session to DONE, and ensure the replacement stays occupied; ordinary exit, urgent flee, body removal and repeated cancellation must still release their own claim. Blocked-route reservation expiry remains a separate follow-up, not solved by this patch.
