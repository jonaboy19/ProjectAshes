# Emotion map: "The Stones Are Dimming" (Region 1)

This page maps the emotional curve of the main quest, beat by beat, before and after the story v2 rewrite. Intensity runs from **−5** (grief, terror, betrayal) to **+5** (triumph, awe, belonging).

The v2 numbers live in the data as `staging.intensity` on every step of `kingdom/data/region1/quests/r1_main.json`. The lint (`tools_qa/region1/lint_quests.gd`) reports `curve_min`, `curve_max` and `curve_swings`. It warns when four steps in a row stay within one point of each other, and a test fails on any such flat stretch.

Related: `STORY_R1.md` (the story and the staging tables), `CAST_R1.md`, `AUDIO_R1.md` (music cues).

---

## 1. The v1 curve (as shipped in L14)

| # | Step | Beat | Int. | Emotion |
|---|---|---|---:|---|
| 1 | a1_dark_stone | Mother: stay in, the stone went out | 0 | curiosity |
| 2 | a1_first_glyph | First glyph with Idra | +3 | wonder |
| 3 | a1_hesks_ember | Hesk rests in the stone | +2 | tenderness |
| 4 | a1_wolf_at_dusk | Lone wolf, Maren shouts | −1 | fear |
| 5 | a1_staff_yard | Maren's arm story | +1 | respect |
| 6 | a1_blessing_eve | Idra: "I carve anyway" | +1 | nerves |
| 7 | a1_blessing | The ring lights | +5 | triumph |
| 8 | a1_after_blessing | "A throat cleared before bad news" | +1 | unease |
| 9 | a2_three_letters | Apprenticeship | +2 | pride |
| 10 | a2_dark_road | Captain's sums, relight 2 stones | 0 | duty |
| 11 | a2_greenhollow | Gilda's burned barn | −3 | sympathy |
| 12 | a2_first_ashsight | Ash replay | +1 | eerie wonder |
| 13 | a2_duskbriar | Corin caught | −1 | pity |
| 14 | a2_thief_truth | "Dying on their own" | −1 | unease |
| 15 | a3_silverford | Odrin's licence | +1 | comedy |
| 16 | a3_sunstone_oil | Imra's gift | +1 | kindness |
| 17 | a3_council | Relic choice before the King | 0 | weight |
| 18 | a3_scar_front | The Scar crawls | −2 | dread |
| 19 | a3_fallen_heart | Cold Elder Stone | −2 | dread |
| 20 | a4_glade_trial | Warden bows | +3 | awe |
| 21 | a4_greyseam | Harrok | +1 | comedy |
| 22 | a4_highwatch | Rowan dies | −4 | grief |
| 23 | a4_crownstead | Lucan, ash evidence | 0 | clarity |
| 24 | a4_elden | Ancestor stone | +3 | belonging |
| 25 | a4_five_hearts | Five hearts beat | +3 | hope |
| 26 | a5_rifts_edge | Tamsin's forty graves | −2 | moral weight |
| 27 | a5_turn_the_tide | Allies arrive | +3 | rally |
| 28 | a5_scarbound | The troll | −2 | fear |
| 29 | a5_seal | Idra or "all of them" | +4 | catharsis |
| 30 | a5_homecoming | "Sit. Eat." | +3 | home |

```
 +5 |             *
 +4 |                                                         *
 +3 |   *                                   *       * *   *     *
 +2 |     *           *
 +1 |         * *   *       *     * *         *
 0  | *                 *             *           *
 -1 |       *                 * *
 -2 |                                   * *             *   *
 -3 |                     *
 -4 |                                           *
 -5 |
      I               II           III         IV           V
```

### Diagnosis
- **Flat stretches.**
  - Steps 9 to 19 (Act II through Act III, 11 steps) sit between −2 and +2, except Gilda's barn. That barn belongs to a stranger we met 30 seconds earlier.
  - Steps 15 to 17 (Silverford, the market, the Council) are three political beats in a row at 0 to +1.
  - Act IV's four hubs share one structure (arrive, problem, relight, cutscene), so they feel like a checklist.
- **Missing emotions.**
  - *Early love with something to lose:* no friend, no pet, no family scene beyond one line each.
  - *Loss of someone we love:* the only death is Rowan, whom we have known for ten minutes.
  - *Betrayal:* there is none. Tamsin is a stranger, and her reveal is intellectual, not personal.
  - *A gut-punch twist:* "the stones are empty, it's everyone's fault" is a thesis, not a punch.
  - *A dark night of the soul:* there is no low point to climb out of, so the five hearts don't feel like a comeback.
  - *Humour in Acts III to V:* thin.
- **Choices don't hurt.**
  - Eight of nine choice groups only change reputation or one flavour line.
  - "All of them" at the seal is strictly better and costs nothing, so the finale has no bittersweet edge.
  - Nothing the player did in Acts I to IV changes who lives.
- **Mechanics.** Ashsight shows only new facts; it never makes you see an old scene differently. Ember Legacy is taught through a near-stranger's death rather than through someone who matters.

---

## 2. The v2 curve (story v2, implemented)

38 steps (8 new). The full-range swing is from −5 to +5, with 16 sign changes and no flat stretch.

| # | Step | Beat | Int. | Emotion | Built by |
|---|---|---|---:|---|---|
| 1 | a1_dark_stone | Supper with the family, Captain Bram's honey cakes and sums; the stone dies on the window | +2 | warmth, then a chill | |
| 2 | a1_first_glyph | First glyph; Idra's hands shake, fingers grey | +3 | wonder | Codex, VFX |
| 3 | a1_hesks_ember | "The stubborn part. Stubborn lasts." | +2 | tenderness | |
| 4 | a1_wolf_at_dusk | A wolf has a stagborn fawn pinned; you step between them | −2 | fear, first triumph | Codex |
| 5 | **a1_thistle** 🆕 | Free the fawn; "NOT sleeping in the house." / "It's sleeping in the house." | +4 | wonder, belonging, laughter | Codex, VFX |
| 6 | a1_staff_yard | Maren's arm story; Wren knocks you flat twice | +3 | fun, a mentor's honesty | Codex |
| 7 | **a1_kindling** 🆕 | Kindling Night: lanterns for the dead; Bram's "for friends up north"; a lantern for nobody; Thistle eats one | +4 | warmest night of childhood | C9, Codex, VFX |
| 8 | a1_blessing_eve | "I carve anyway." | +1 | nerves | |
| 9 | a1_blessing | The ring lights (Idra sits down hard at the edge) | **+5** | triumph | C9, VFX |
| 10 | a1_after_blessing | "Bad news." Wren: "You glow now. Insufferable." Wren joins. | +2 | joy with an edge | |
| 11 | a2_three_letters | Apprenticeship | +2 | pride | |
| 12 | a2_dark_road | Bram: "Report to me. Every stone. I keep the ledger." | +1 | duty (**betrayal planted**) | |
| 13 | **a2_stagborn_road** 🆕 | The herd walks the old ward-line at dawn; free Thistle or keep it | **+5** | awe, bittersweet choice | C9, Codex, VFX |
| 14 | a2_greenhollow | Gilda's barn; "the Captain's patrol checked it last week" | −3 | shock | VFX |
| 15 | a2_first_ashsight | The replay; **a watcher with a shuttered lantern, no face** | +1 | eerie wonder | Codex, VFX |
| 16 | a2_duskbriar | Corin: "a list comes with the crystal, neat hand, like a clerk's" | −1 | pity | |
| 17 | a2_thief_truth | Idra coughs and her lantern dims with her | −2 | unease | VFX |
| 18 | a3_silverford | "Irritatingly clean." | +2 | comedy | |
| 19 | a3_sunstone_oil | "Pay the lamp-lighter first." | +3 | kindness | |
| 20 | a3_council | The King asks *you* | 0 | weight | |
| 21 | a3_scar_front | The violet line crawls; Bram: "write down every stone" | −2 | dread | VFX |
| 22 | a3_fallen_heart | The cold Elder Stone; the herd fled (Thistle limping, or screaming at the window) | −3 | dread | VFX |
| 23 | **a3_idra_secret** 🆕 | **TWIST.** Idra collapses. Ashsight at the Miller's Stone: she has fed Ashford's heart with her own ember for 30 years | −4 | gut-punch | Codex, VFX |
| 24 | **a3_kindling_return** 🆕 | The last good night: father vs Maren at staves, Thistle eats Maren's hat, "the Guard's gone to Greenhollow" | +3 | borrowed time | Codex, VFX |
| 25 | **a3_ring_falls** 🆕 | The ring goes dark mid-song. Maren holds the heart-stone by hand and dies; her ember turns the ring gold | **−5** | terror, grief | C9, Codex, VFX |
| 26 | **a3_the_ledger** 🆕 | **BETRAYAL.** The ash shows a Guard key and a voice counting "nine, forty-one, sixty": Bram. He sold *your* reports | **−5** | betrayal, guilt | Codex, VFX |
| 27 | **a4_dark_night** 🆕 | **Dark night.** Wren walks out into the rain. Maren's voice from the stone: "Staff up." You stand up | −4 | despair, one spark | Codex, VFX |
| 28 | a4_glade_trial | **Comeback.** Wren: "Still angry. Still coming." Thistle and the Warden bow together | +3 | reunion, awe | C9, Codex, VFX |
| 29 | a4_greyseam | "Bad singing. Good sign." Harrok's mother asks for the stone | +2 | gruff warmth | VFX |
| 30 | a4_highwatch | Rowan asks after Maren ("I'll ask her myself"), then dies at the gate | −4 | gentle grief | C9, Codex, VFX |
| 31 | a4_crownstead | Old ash under new: young Bram pulls Hollin's Reach's line; Tamsin is his sister | −2 | understanding | VFX |
| 32 | a4_elden | Snikkit, then "it's your turn to be held" | +3 | slapstick, belonging | VFX |
| 33 | a4_five_hearts | "Hums like a hive." Wren: "Especially the grumpy ones." | +4 | hard-won hope | VFX |
| 34 | a5_rifts_edge | Tamsin: "He did the sum. I did the burying." | −2 | anger meets grief | |
| 35 | a5_turn_the_tide | Every callback comes over the ridge | +4 | rally | C9, Codex, VFX |
| 36 | a5_scarbound | "It's a troll now, too. A worse one." | −3 | fear, then fury | Codex, VFX |
| 37 | a5_seal | The mouth wants a living ember; your choices decide who pays | **+5** | sacrifice, catharsis | C9, Codex, VFX |
| 38 | a5_homecoming | Kindling Night a year on; the heart-stone: "Not bad. Not good. Not bad." | +3 | bittersweet home | C9, VFX |

```
 +5 |                 *       *                                               *
 +4 |         *   *                                                   *   *
 +3 |   *       *                         *         *       *       *           *
 +2 | *   *             * *             *                     *
 +1 |               *       *     *
 0  |                                       *
 -1 |                               *
 -2 |       *                         *       *                   *     *
 -3 |                           *               *                           *
 -4 |                                             *       *     *
 -5 |                                                 * *
      I                   II             III                 IV             V
```

### Act by act
| Act | Shape | Peak | Trough |
|---|---|---|---|
| I, Hearth and Stone | Climbs through warmth: family, a pet, a best friend, a festival, then the Blessing | +5 Blessing | −2 wolf |
| II, Ash on the Wind | Awe (the herd) and a choice, then a mystery with a faceless watcher | +5 herd crossing | −3 barn |
| III, Relics and Rot | Comedy and politics, dread, the twist, one last good night, then the double gut-punch | +3 oil, Kindling | **−5 Maren, −5 Bram** |
| IV, The Five Hearts | Dark night, then the comeback (Wren returns), gentle grief (Rowan), then hope | +4 five hearts | −4 vigil, Rowan |
| V, The Ashen Scar | Anger meets grief, rally, fear, then sacrifice and catharsis, then home | +5 seal | −3 troll |

---

## 3. The devices

### Early warmth, so the losses hurt
- **Family:** supper with Captain Bram at the table; father on Kindling Night ("Snored like a millstone"); mother and father arguing over the fawn; the homecoming mirrors both.
- **Mentor:** Maren (the arm story, drill-yard jokes, "Not bad. Not good. Not bad."). Her death in Act III is the loss that the whole second half answers.
- **Friend:** **Wren Coldbrook** (new supporting cast; she is the design's companion #1, joining as the first follower).
- **Pet or animal bond:** **Thistle**, a stagborn fawn you save from the Act I wolf. It is the player's first bonded beast and becomes a Stagborn Wardwalker in the retinue design.

### Rising wonder
First glyph (Act I), then Thistle's glowing antler-buds (Act I), then the Blessing (Act I), then the herd walking the ward-line at dawn (Act II), then the Warden bowing (Act IV).

### The twist: Idra has been dying on purpose (Act III, `a3_idra_secret`)
Ashsight at the Miller's Stone shows thirty years of Idra giving her own warmth to Ashford's heart. It recontextualizes Act I:
- "My hands are slow tonight" in a1_first_glyph;
- the grey fingers ("stone dust") in idra_grey;
- Idra sitting down hard at the Blessing (the ring drank from her);
- the cough that dims her lantern in a2_thief_truth;
- her finale offer, "I'd like the view", which now carries thirty years behind it.

### The betrayal: Captain Bram Hollis (Act III, `a3_the_ledger`)
It is earned through a foreshadowing chain. Every link is a line the player has already seen:

| Where | Plant |
|---|---|
| a1_dark_stone | "I count them at night, like sheep. Never once helped me sleep." |
| a1_kindling | His lantern "for friends up north... Ones I couldn't count to in time." |
| a2_dark_road | "Report to me. Every stone you light, every one that's failing. I keep the ledger." |
| a2_greenhollow | "The Captain's patrol checked it last week." |
| a2_first_ashsight | A watcher with a shuttered lantern; the ash gives no face |
| a2_duskbriar | Corin: the list comes "in a neat hand, like a clerk's" |
| a3_scar_front | "Write down every stone you pass... The ledger's all I've got." |
| a3_kindling_return | "Sent the Guard to Greenhollow. Just me and the honey cakes tonight." |
| **a3_the_ledger** | The ash: a Guard key, "nine, forty-one, sixty", and the watcher lifts his lantern |
| a4_crownstead | Older ash: young Bram pulled Hollin's Reach's line; Tamsin is his sister |

What makes it hurt is that it goes through *the player*. Bram sold *your* reports: "Best ledger I ever had." Wren's "You told him" in the dark night lands because it is partly true.

### Dark night, then comeback (`a4_dark_night`, then `a4_glade_trial`)
Rain, night, alone at the gold stone. Maren's ember speaks through Ember Legacy, first in her Act I line ("Staff up. You block with the wood, not your face"), then with a joke ("Idra said that first, didn't she? Thief."), then with absolution ("And he chose. Not you."). Idra reframes the loss: "She gave. First one in two hundred years. That's the answer." Maren's death is the story's proof that the fix works. Wren comes back at the Glade: "Still angry. Still coming."

### The sacrifice, run by Ember Legacy (`a5_seal`)
"All of them" pours in every ember the player helped lay:
- Hesk and Maren (always);
- Rowan, if his radial card went to the **stone** (the N3 3-card choice);
- Harrok's mother, if you said "Stronger clan";
- the Stagborn herd walking the lines, if you **freed Thistle**;
- the stones with nobody, if you hung **a lantern for nobody** on Kindling Night (a hidden side action).

When those are short, the mouth "wants one living ember", and your choices decide who walks in:

| Priority | Condition | Who pays | Ending flag |
|---|---|---|---|
| 1 | Rowan in the stone + Harrok ally + Thistle freed + a lantern for nobody | **Nobody.** The Kindled Dawn (hidden best ending) | `r1.ending.kindled` |
| 2 | You spared Bram | Bram: "Nine guards. Forty-one stones. Sixty miles. One of me. That sum, I can do." | `r1.ending.bram` |
| 3 | You pardoned Tamsin | Tamsin: "Tell my brother the sum came out even." | `r1.ending.tamsin` |
| 4 | Otherwise, or "Then rest, Idra" | Idra: "I was going anyway, love. Now I get to go somewhere useful." | `r1.ending.idra` |

Every ending is bittersweet: Maren and Rowan are lanterns in every one. The Kindled Dawn costs nobody *else*, and Idra hangs a lantern "for the ones with nobody".

### Ashsight reveals that recontextualize
| Reveal | Makes you re-see |
|---|---|
| a2_first_ashsight: the faceless watcher | a3_the_ledger turns the same watcher around: Bram |
| a3_idra_secret: Idra feeding the stone | a1_first_glyph, a1_blessing, a2_thief_truth |
| a3_the_ledger: Bram counting | a1_dark_stone's sums, a2_dark_road's ledger, a3_kindling_return's "Guard's away" |
| a4_crownstead: old ash, young Bram | a1_kindling's "friends up north", and Tamsin's whole grievance |

### Humour between the heavy beats
Humour sits right beside each heavy beat:
- Thistle eats lanterns (Act I, Act III), then "get that stag off my roof" (Act V);
- Wren: "I'm exactly your size", "Insufferable", "Especially the grumpy ones", "a worse one";
- father vs Maren at staves, and "He blocks with his face";
- Maren's ember calling Idra a thief *during the vigil*;
- Idra's tea (Acts II and V);
- plus the v1 bits: Odrin's sections, Snikkit and Harrok.

### Branches that pay off (callbacks)
| Choice | Pays off in |
|---|---|
| **thistle_bond** (free / keep), Act II | Idra's Glade line (limping with the herd, or screaming at the window); carrying Idra home; Wren's Kindling line; Wren leaving in the rain; the Warden trial (grown Thistle beside you, or fawn Thistle facing it down); the finale allies (the herd charge, or Thistle refusing to leave); the Kindled Dawn gate; mother's last line |
| **bram_fate** (chains / spare), Act III | Tamsin's first words about her brother; Bram hauling stone among the allies; **Bram walks into the mouth** (if spared); the lanterns and the Scar voice |
| **tamsin_fate** (arrest / pardon), Act V | **Tamsin walks into the mouth** (if pardoned and Bram isn't there) |
| rowan_ember (stone / heir / lance), Act IV | Rowan in the stone is one of the Kindled Dawn's embers |
| harrok_pact (ally / alone), Act IV | Harrok's mother's ember; the war-horns; the Kindled Dawn |
| corin_fate (jail / free / informant), Act II | Corin's late warning in the raid (informant); Corin among the allies in three versions |
| Hidden: a lantern for nobody, Act I | The Kindled Dawn, 25 hours of play later |

---

## 4. Staging: who builds each key beat

**C9** = cutscene shot list, **Codex** = unique animation, **VFX** = effect work. Music cues come from `AUDIO_R1.md`. Three cues don't exist yet and are marked *missing* in `r1_registry.json` → `music`: `r1_kindling`, `r1_lament` and `r1_finale`. Each has a fallback.

| Beat | Music | Camera | Animation / VFX | Silence, weather, time | C9 | Codex | VFX |
|---|---|---|---|---|:-:|:-:|:-:|
| First glyph | r1_night | over the shoulder, push in on the finger | kneel-trace; Idra's shaking hand; stroke trail, gold flare | no music on the first stroke; dusk | | ✓ | ✓ |
| Thistle freed | r1_village_day | antler-bud close-up; wide on the parents at the door | fawn follow and nuzzle; blue antler glow | night | | ✓ | ✓ |
| Kindling Night (I) | r1_kindling* | slow crane up the ring as lanterns rise | lantern hang; shoulder-ride; Thistle chewing | first frost, night | ✓ | ✓ | ✓ |
| Blessing | r1_village_day | existing shot list; hold on Idra sitting down hard | element motes, Vale-wide flare | one beat of silence; dusk | ✓ | | ✓ |
| Herd crossing | r1_forest_glade | mist, the herd in silhouette on the ward-line | herd walk (X3); the line lights under each hoof | 3 s of only a bellow; dawn mist | ✓ | ✓ | ✓ |
| Idra's secret | r1_lament* | Ashsight replays the Act I carve from a new angle | Idra collapse (unique); a gold thread from her chest to the stone | the Act I rune hum alone, then cut; night rain | | ✓ | ✓ |
| Kindling Night (III) | r1_kindling* | mirror the Act I crane shot exactly | father vs Maren staff bout | first frost, night | | ✓ | ✓ |
| Maren's last stand | r1_lament* | handheld fight, then a silhouette on the heart-stone | one-armed stone hold (unique); every light snuffs, `r1_ward_break`; gold ember sinks | **hard cut to silence** until the ember sinks; night | ✓ | ✓ | ✓ |
| The ledger | silence | the watcher's lantern lifts to his face | Bram seated, won't stand (unique idle); sepia ghost of the pin pull | dawn, ash-grey fog | | ✓ | ✓ |
| The longest night | r1_lament* | static wide, tiny figure; push-in only when Maren speaks | kneel in rain; stand up with the staff (unique) | rain only until her first line; heavy rain, night | | ✓ | ✓ |
| Warden and Thistle | r1_boss_warden | Warden and Thistle in one frame at the stone | Warden bow (X3); grown or fawn Thistle | sun through mist, morning | ✓ | ✓ | ✓ |
| Rowan's ember | r1_highwatch_keep | Rowan against the battlement | wounded sit; ember rises; snow stops mid-air | **the wind stops**; dusk snow | ✓ | ✓ | ✓ |
| Crownstead old ash | silence | two ghost layers, new over old | sepia old-ash ghost variant (L11) | afternoon | | | ✓ |
| Walk it home | r1_finale* | a 2 s hero shot per ally on the ridge | horn, goblin shriek, herd charge | dawn | ✓ | ✓ | ✓ |
| The seal | r1_finale* | variant per ending | walk-into-the-light per sacrificer; herd charge (Kindled) | **all sound drops**, then birdsong; dawn | ✓ | ✓ | ✓ |
| Homecoming | r1_kindling* | golden-hour walk, then the Kindling lanterns (the Act I mirror) | lanterns; the heart-stone's gold hum | golden hour into night | ✓ | | ✓ |

\* = missing cue; C12 plays the registry fallback until L17 sources it.

**New C9 cutscenes:** `herd_crossing` and `maren_last_stand`, plus four variants of `finale_seal` (idra / bram / tamsin / kindled) and the lanterns in `region_complete`.

**New Codex animations:**
- Idra's collapse and the carry pose;
- Maren's one-armed stone hold;
- Bram's seated idle;
- the rain kneel and stand-up;
- the fawn's follow and nuzzle, and a grown-Thistle variant;
- the walk-into-the-light for Idra, Bram and Tamsin;
- the herd charge.

---

## 5. Risks and open questions
- **Parents never die.** They are WorldSim people (`parents.json`), and killing them would fight the life-sim. The story's losses are Maren, Rowan and one of Idra, Bram or Tamsin.
- **The Staff Yard passes to Wren** (`r1.a3.maren_gone`). The companion quest "The Yard's Last Lesson" (RETINUE §2.8) should become a posthumous quest: Maren's old Runeward debt.
- **Name clash for the cloud:** the retinue design has a companion *Tamsin Reedwhistle*, and the story has *Tamsin Reeve*. Recommend renaming the companion (for example, *Tavi Reedwhistle*).
- **Bram in the retinue:** after the story, a spared Bram is a grudge-free veteran recruit, if he survives. A chained Bram can be pardoned through the Moot.
