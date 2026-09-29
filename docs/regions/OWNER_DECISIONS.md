# Owner decisions (Region 1)

## 2026-09-29: canon names (answers REGION_1_PLAN.md §0)
**Decision:** use the poster names on screen and keep the data ids. This is the recommended default in §0.
- Nation `caldrenn` is displayed as **Kingdom of Valencious**. **House Caldrenn** is the royal dynasty (King Aldric III). The Caldric culture stays.
- `solmarch` is displayed as **Aurelis Patriarchate (Church of the Dawn Throne)** and moves east. Varska and Serathi become its vassal realms.
- `ongur` is displayed as Zephyr Steppe, `veylwood` as Verdanweald Enclaves, `hollowdeep` as Ashenreach Forgeholds, `shenlu` as Jadecliff Dominion, and `seirune` as Tideclad Isles.
- Solkar Dominion, Frostcrown Holds and Umbrafen Marsh are new data rows, teasers only.
- Poster places (Highwatch Keep, Silverford, Crownstead, Greenhollow, Elden Road) become sites or display aliases as planned in §0.
- The **cloud session can start C0 now.**

## 2026-09-29: Retinue, Settlement and Ascension (answers docs/design/RETINUE_SETTLEMENT_ASCENSION.md §11)
- **Follower death:** permanent, after a knocked-down revive window. An easier difficulty setting turns death into injury. *(recommended default)*
- **Treason:** playable as a doomed path behind two confirmations. All stones go dark and it leads to the usurper ending. *(recommended default)*
- **Royal courtship: traditional male–female pairs only.** Heirs come by birth. This **overrides** the design's default of any sex plus adoption; update the courtship and succession sections and data accordingly.
- **Settlements you found:** max 3. Holdings taken over don't count toward the cap. *(recommended default)*
- **Village tax** (`lordship.gd` 0.045 → 0.25 gold/person/day): not decided by the owner. Treat it as a balance proposal, to be validated by the L47 balance sim before the cloud changes it.

## 2026-09-29: who builds what
- The owner handed the **Retinue / Settlement / Ascension** implementation (`docs/design/RETINUE_SETTLEMENT_ASCENSION.md`, every wave including the L-packages) to the **cloud session**. The local PC session will not start those packages.
- The **local session now focuses on animation, movement and natural feel**:
  - clip quality;
  - locomotion, IK, camera and combat feel;
  - creature and NPC motion.

  Where that touches Codex-owned controllers, the local side writes patches and notes in `docs/anim/` rather than editing them directly.
- Region 1 packages already in progress locally (L3, L4, L7, L8, L10, L11, L14, L16) will be finished and pushed. Everything after that in `REGION_1_PLAN.md` is open for the cloud.
