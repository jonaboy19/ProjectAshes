# Closed biography chapter reentry

5 October 2026. Local source patch; no parser, save/load or gameplay validation.

`Biography.start_chapter()` now suppresses duplicate role/organization requests only while that chapter remains open. If the latest matching chapter has an end day, an explicit new start appends a new chapter. The old chapter's dates, rank and highlights remain intact. No save schema, rank progression, employment policy or event producer changes.

Source review confirmed the broader career handoff remains relevant: resignation reconciliation returns immediately when unemployed; dismissal clears the seat without the same transition signal; Life's daily rank path has no active-employment guard. This patch does not solve those integration paths or cause rehire callbacks to start a chapter automatically. `Biography.promote()` also requires separate review when its current chapter is closed.

Pending acceptance: repeated starts while open must append nothing; close then same-role/org start must append one open chapter; starts after save/load must behave identically; differing-role/org starts must retain their existing closure behavior. Overall employment/rank reconciliation needs the policy and ownership review described in `CAREER_BIOGRAPHY_LIFECYCLE_CONTRACT.md`.
