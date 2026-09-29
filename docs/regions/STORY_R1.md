# The Stones Are Dimming: Region 1 main quest

This is package **L14**, rewritten in **story v2** to be an emotional rollercoaster. The curve, the diagnosis of v1 and the staging per beat are in `EMOTION_MAP_R1.md`.

- **Data:** `kingdom/data/region1/quests/r1_main.json` (38 steps, each with `staging`).
- **Dialogue:** `kingdom/data/region1/dialogue/r1_act1..5.json` (236 nodes, 281 lines).
- **Schema:** `kingdom/data/region1/quests/README.md`.
- **Cast:** `CAST_R1.md`.

The quest lints clean with `tools_qa/region1/lint_quests.gd` (0 errors, 0 warnings). Autoplay finishes the quest in all 10,368 choice combinations and shows every one of the 281 lines.

## The idea
Every runestone in the Vale glows because someone's **ember** rests in it: the stubborn part of a person who chose to keep watch after death.
- The five **Elder Stones** are the network's hearts. Their embers are two hundred years old.
- Nobody has given a new ember in generations. First the Crown made it a noble's right, then the Church called it heathen, and then people simply stopped.
- So the stones are dimming. **No villain is doing it**, but people make it worse out of grief:
  - A Guard captain who once did the sum and left a village outside the ward.
  - His sister, whose village it was.
- The fix is the Vale remembering how to give. Maren proves it first, and it costs her life.

**Tone:** a warm, sunny storybook that makes you love people before it costs you any of them. Every heavy beat is set beside a light one: Thistle eating lanterns, Wren's mouth, Idra's tea. Nobody is a chosen one: Idra, the best carver alive, had no Blessing at all.

**Mechanics as story:**
- **Wardwright** is how you care for the dead's light.
- **Ashsight** is how the ash testifies, and in v2 it makes you re-see old scenes.
- The **Scar Tide** is what grows where care runs out.
- **Ember Legacy** is the answer: Maren's ember is the first new one in two hundred years, and at the finale your earlier ember choices decide who else has to pay.

Each mechanic is taught in its own scene and used again in at least two acts (the lint checks this):

| Mechanic | Taught | Used |
|---|---|---|
| Wardwright (N1) | Act I, the Miller's Stone (the Ward glyph); Act IV, Crownstead (routing) | II, III, IV, V |
| Ember Legacy (N3) | Act I, "Whose Light"; Act IV, Sir Rowan's choice (the 3-card radial) | I (Kindling), III (Idra, Maren), IV (vigil, hubs), V (the seal) |
| Ashsight (N4) | Act II, the Pennick farm | II, III (Idra's secret, the ledger), IV (Crownstead, two ash layers) |
| Scar Tide (N2) | Act III, Greenhollow's south fields | IV, V |

## Act I: Hearth and Stone (Ashford, age 8 to 12)
1. **Supper.** Supper with your family and Captain Bram Hollis, your father's old captain. He brings honey cakes and counts his stones "like sheep". The Miller's Stone dies on the window glass.
2. **The first glyph.** Idra's hands are "slow tonight" and her fingers grey ("stone dust"), so she teaches yours. The stone hums back ("Rudely, but it counts"). It holds old Hesk: "The stubborn part. Stubborn lasts."
3. **The wolf.** At the ring edge a wolf has a **stagborn fawn** pinned in the brambles. You get between them, and Maren Coldbrook shouts at your feet.
4. **Thistle.** The fawn follows you home. Mother: "It is NOT sleeping in the house." Father: "It's sleeping in the house." Its name is **Thistle**.
5. **The Staff Yard.** Maren's arm story ("Forty people slept that night. Fair trade."). Her niece **Wren** knocks you flat twice: "I'm exactly your size. Friends?"
6. **Kindling Night.** Lanterns for everyone who rests in a stone. Father's is for grandfather ("Snored like a millstone"). Bram hangs his last, "for friends up north... ones I couldn't count to in time." Idra: the stones with nobody just get the dark. *(Hidden side action: hang one for nobody.)* Thistle eats a lantern.
7. **The Blessing.** Every stone lights, and Idra sits down hard at the edge. "A stone clearing its throat before bad news." Wren: "You glow now. Insufferable. I'm coming on every road." **Wren joins.**

**Teaches:** move, look, talk, interact, carve, fight, block, dodge, eat, sleep, map (the L16 prompts, unchanged, on the same steps); the first glyph (N1); embers (N3). The first glyph is still step 2, so the "first glyph in 20 minutes" onboarding metric (C8) is untouched.

## Act II: Ash on the Wind (the Vale, age 12 to 15)
1. **Apprenticeship.** Pick the Guild, Highwatch or the Runeward. Idra still needs you on the roads.
2. **The ledger.** Bram does the sum (nine guards, forty-one stones, sixty miles), then: "**Report to me.** Every stone you light, every one that's failing. I keep the ledger."
3. **The herd.** At dawn the **Stagborn herd** walks the old ward-line across the road, and the line glows under their hooves. Thistle takes three steps toward them and looks back. **Choice:** *"Go on. Go home."* or *"Stay with me."*
4. **Gilda's farm.** The Pennick barn burns; "the Captain's patrol checked that stone last week."
5. **Ashsight.** Idra teaches it ("Fire remembers."). A hooded cutter, and at the edge of the memory **a second figure with a shuttered lantern. No face.**
6. **Corin.** Corin Vesk, sixteen, cuts stones for scar-crystal: "A list comes with the crystal... neat hand, like a clerk's." Jail him, free him, or make him your informant. "They're dying on their own!"
7. **The cough.** Idra coughs, and her lantern dims while she does. "Tea went down the wrong way."

## Act III: Relics and Rot, then Kindling Night
1. **Silverford.** Odrin's licence ("Irritatingly clean") and his ledgers: the stones are *empty*. Imra's sunstone oil.
2. **The Council.** King Aldric asks *you*: accept the Dawn relics, refuse them, or borrow one.
3. **The Scar.** It reaches Greenhollow; burn it or harvest it. Bram: "Write down every stone you pass."
4. **The Glade.** The herd has fled; Thistle is either limping with them or screaming at Idra's window. The Elder Stone is cold: "It's everyone's fault. That's the good news."
5. **Twist: Grey Fingers.** Idra collapses on the Glade path and you carry her home. Ashsight at the Miller's Stone shows thirty years of ash: **Idra, every night, palm on the stone, giving her own ember to keep Ashford's heart lit.** You see the night of your first glyph (her hands shook) and your Blessing (the ring drank from her). "Everyone can mend it. I just started early." "Everybody's dying, love. I'm just doing it on purpose."
6. **The last good night.** Ashford lights Kindling early this year, "for Idra", mirroring Act I. Father and Maren fight with staves ("He blocks with his face"). Thistle eats Maren's hat. Bram: "Sent the Guard to Greenhollow. Just me and the honey cakes."
7. **Staff up.** Mid-song, every stone in the ring goes out. Rift wolves come in. **Maren holds the heart-stone lit by hand** while you hold them off her. Her last words: "Hm. Not bad. Not good. Not bad... Fair trade. Better than fair... Tell her... staff up." Her ember sinks in and **the ring burns gold: the first new ember in two hundred years.**
8. **Betrayal: The Ledger.** Ashsight at the cut line shows a Guard's key, a pin pulled, and a voice counting "nine, forty-one, sixty". The watcher from the Pennick farm lifts his lantern: **Captain Hollis.**
   - "The Crown only redraws lines for places that scream. So I made the Vale scream."
   - He sold **your reports**, failing stones first: "Best ledger I ever had. One dark night, I told them. Then the wolves came."
   - **Choice:** chains ("The King decides") or "Go. Live with that sum." Either way: "That's crueller than chains... Thank you."

## Act IV: The Five Hearts
1. **The Longest Night (the dark night of the soul).** Wren: "You told him. Every stone." She walks out into the rain. You kneel alone at the gold stone, and **Maren speaks from it** (Ember Legacy):
   - "Staff up. You block with the wood, not your face."
   - "Idra said that first, didn't she? Thief."
   - "And he chose. Not you. Everything is bigger than you. Get up anyway."

   Idra: "She gave. First one in two hundred years. That's the answer." She gives you **Maren's staff**.
2. **The Glade (the comeback).** Wren is back: "Still angry. Still coming." Tire the Antlered Warden and carve Bless. Then either **grown Thistle** steps out of the herd to stand beside you (freed), or **fawn Thistle** faces the Warden down (kept). The Warden bows.
3. **The other four hearts, in any order:**
   - **Greyseam:** Harrok ("Bad singing. Good sign."). As an ally, he tells you his mother asked to rest in the stone: "She was always stronger clan."
   - **Highwatch:** Rowan sees Maren's staff: "Tell her I want a rematch." "She died." "...Then I'll ask her myself. Sooner than I'd like." He dies at the gate, and you place his ember with the 3-card radial.
   - **Crownstead:** the relic is a leash. The ash has **two layers**. Tamsin's cart sits on top. Underneath is older ash: **a young Lieutenant Bram pulling the pin on Hollin's Reach's line**, and a woman on his arm: "Bram, they're our neighbours!" Tamsin is his sister. You route a line to Kingsreach.
   - **The Elden Road:** Snikkit's "lonely shiny", and the ancestor stone: "It's your turn to be held."
4. **Five hearts beating.** "Hums like a hive." Wren: "Every spark. Especially the grumpy ones."

## Act V: The Ashen Scar (finale)
1. **Tamsin.** "He did the sum. I did the burying." Forty graves, one winter. Arrest or pardon her; either way she gives you the anchor stone.
2. **Walk it home.** Allies come over the ridge according to your choices:
   - Tuskridge horns, or Snikkit's goblins;
   - the Stagborn herd with Thistle at its head, or Thistle refusing to leave your side;
   - Corin, in three versions;
   - Bram hauling stone and not meeting your eyes, if spared;
   - Wren always: "Miss me? Don't answer that."
3. **The troll.** "It was a troll, once." "It's a troll now, too. A worse one."
4. **The seal.** Idra offers her ember ("I've been practising for thirty years").
   - **"Then rest, Idra."** She goes: "Maren's saving me a seat. She'll cheat at staves."
   - **"No. All of them."** Every ember you helped lay pours in along the ward-lines. If they are enough, the mouth shuts. If not, it "wants one living ember", and who walks in depends on you (see *Endings*).
5. **Homecoming, Kindling Night a year on.**
   - "Sit. Eat." ("And get that stag off my roof.")
   - New lanterns at the ring.
   - Idra retires if she lived ("The tea, regrettably, is also yours").
   - Wren runs the Staff Yard ("twelve new strays").
   - A voice on the wind from the Scar.
   - The heart-stone, in Maren's voice: **"Staff up, lantern-holder. ...Hm. Not bad. Not good. Not bad."**

   **Region 1 complete** (`r1.complete`).

## Endings
| Ending | How | Who pays | Last lantern | Scar voice |
|---|---|---|---|---|
| **The Kindled Dawn** (hidden, `r1.ending.kindled`) | "All of them" + Rowan's ember in the **stone** + Harrok **ally** + Thistle **freed** + a **lantern for nobody** (Act I side action) | nobody else | "Idra hangs a third, for the ones with nobody" | "The whole Vale humming" |
| **One of Me** (`r1.ending.bram`) | "All of them", Kindled not met, Bram **spared** | Bram | "One nobody signs. Everybody knows whose." | "nine, forty-one, sixty, one. Even, at last." |
| **Debt Paid** (`r1.ending.tamsin`) | "All of them", Kindled not met, Bram chained, Tamsin **pardoned** | Tamsin | "Tamsin Reeve, of Hollin's Reach" | "Tell Hollin's Reach I'm home." |
| **On Watch** (`r1.ending.idra`) | "Then rest, Idra", or "All of them" with nobody else to step in | Idra | "Idra Vell, who'd hate the fuss" | "The tea is terrible here too." |

Maren and Rowan are lanterns in every ending: the cost always stands. The line priority lives in `r1_act5.json` → `seal_count`.

## Branches and what they change
| Choice (registry group) | Options | Pays off in |
|---|---|---|
| `thistle_bond` 🆕 | freed / kept | 7 callbacks (Glade, carrying Idra, Kindling, the rain, the Warden, the allies, mother); a Kindled gate |
| `apprenticeship` | Guild / Highwatch / Runeward | Captain, Odrin and Rowan greet you differently; rep |
| `corin_fate` | jail / free / informant | a late warning in the raid (informant); Tamsin knows; three ally versions |
| `relic_policy` | accept / refuse / borrow | Lucan's Crownstead scene; Church and Crown rep |
| `scar_answer` | burn / harvest | Gilda; crystal in your pack |
| `harrok_pact` | ally / alone | Harrok's mother's ember; war-horns; a Kindled gate |
| `rowan_ember` | stone / heir / lance (N3 radial) | Highwatch's voice, Tobin or the lance; a Kindled gate |
| `snikkit_deal` | trade / force | goblins at the finale |
| `bram_fate` 🆕 | chains / spare | Tamsin's words; Bram among the allies; **Bram walks into the mouth** |
| `tamsin_fate` | arrest / pardon | **Tamsin walks into the mouth** (if Bram can't) |
| `the_seal` | all of them / Idra rests | who pays (see *Endings*) |
| (hidden) `r1.a1.lantern_nobody` | Act I side action | a Kindled gate |

## Beats that need cutscenes (for C9)
The ids are in `r1_registry.json` under `cutscenes`, and the quest emits `["cutscene", id]` at these moments. Keep every cutscene short, skippable and in the sunny storybook look. Every step's `staging` also names the music, camera, silence, weather and time of day.

| Id | Trigger | Shot list seed | Length |
|---|---|---|---|
| `blessing` | `a1_blessing` starts | 1) Dusk; the ring and villagers with lanterns. 2) The child in the centre; Idra at the edge. 3) The stones light one by one, then all at once. 4) Wide: stones flare across the Vale. 5) Mother's face. 6) *New:* a 1 s insert of Idra sitting down hard (the twist's seed; don't linger). | 25–35 s |
| `herd_crossing` 🆕 | `a2_stagborn_road` starts | 1) Dawn mist on the road; Wren's hand on your arm. 2) Stagborn silhouettes in single file. 3) Low shot: the ward-line lights under each hoof. 4) Thistle's ears turn; it takes three steps. 5) It looks back at you (hand-off to the choice). 3 s of only a bellow, no music. | 15 s |
| `maren_last_stand` 🆕 | the 5th rift wolf at the ring dies | 1) Hard silence. Maren kneels at the dark heart-stone, one palm flat. 2) Close: frost climbing her sleeve. 3) Her face: "Not bad." 4) The ember rises and hesitates; it doesn't leave, but sinks. 5) The ring blooms gold, stone by stone; lanterns relight themselves. 6) Wide: the villagers come out of their doors. Music (lament) returns on 5. | 30 s |
| `elder_relight` | each Elder Stone relit (5×) | As before, with per-site variants. *New Glade variant:* the Warden and Thistle (grown or fawn) together in one frame. | 10–15 s |
| `rowan_ember` | Rowan's ember choice made | 1) Rowan against the battlement, smiling. 2) The ember rises. 3) It goes to the chosen card. 4) The north wind stops; snowflakes hang in the air. | 12 s |
| `finale_seal` | `a5_seal` sealed | 1) The mouth roars violet. 2) **Variant per ending:** *idra:* palm on the anchor, a wink, light. *bram:* he walks in counting under his breath and never looks back. *tamsin:* she drops her pack and doesn't look at anyone. *kindled:* the herd charges down the lines, an orc-mother's ember roars up from Greyseam, a small lantern flares, and five hearts pulse at once. 3) The mouth shrinks. 4) The glimpse: an ember-red sky, a bloom-violet forest. 5) All sound drops, then birdsong. | 40–60 s |
| `region_complete` | `a5_homecoming` done | 1) Walk home at golden hour. 2) Family at the door. 3) *New:* Kindling Night a year on, the Act I crane shot mirrored, with the new lanterns (per ending). 4) The heart-stone hums gold as you pass. 5) The "Region 1 complete" card. | 25 s |

The birth cutscene already exists (`cinematic/birth_cutscene.gd`).

**Scripted, not cutscenes** (C6/C7):
- Ashsight at the Pennick farm, the Miller's Stone (Idra's thirty years), the ring (the ledger) and Crownstead (two layers: new grey ghosts over old sepia ones) should inject events into `ash_memory` (L11) so the replays use the ghost pipeline. The narrator lines are the captions.
- The Scarbound Troll rising (`troll_rises`) is an in-engine boss intro (X6).

**Unique animations for Codex:**
- Idra's collapse and the carry pose;
- Maren's one-armed stone hold;
- Bram seated, refusing to stand;
- the rain kneel and stand-up with the staff;
- Thistle's follow and nuzzle (fawn and grown);
- the walk-into-the-light for Idra, Bram and Tamsin;
- the Stagborn herd charge;
- the father vs Maren staff bout.

The full per-beat table is in `EMOTION_MAP_R1.md` §4.

## Hand-off notes
- **C7:**
  - New spawn: `["spawn", "stagborn_fawn", "ashford_ring", 1]` in a1_hesks_ember. Thistle must never be a valid kill target.
  - New item: `maren_staff`.
  - New festival step: `kindling_night` in a1_kindling (autumn, during the childhood years). The Act III Kindling is lit "early, for Idra", so it never waits on the calendar: it needs only `enter_area ashford_ring`, staged at night.
  - `staging.music` names a registry cue. Missing cues (`r1_kindling`, `r1_lament`, `r1_finale`) have fallbacks in `r1_registry.json` → `music`.
- **C12 / L17:** source the three missing cues (briefs are in the registry).
- **C20 (retinue data addendum):**
  - Wren joins at `r1.a1.wren_joined` and leaves and returns in Act IV (`r1.a4.wren_left`, `r1.a4.wren_back`).
  - Thistle is the first bonded beast (`r1.a1.thistle_named`); `r1.thistle.freed` means she later runs with the herd as a Wardwalker.
  - Maren's death (`r1.a3.maren_gone`) hands the Staff Yard to Wren.
  - Name clash: *Tamsin Reedwhistle* (companion) vs *Tamsin Reeve*; see `EMOTION_MAP_R1.md` §5.
- **L15** side quests reuse the schema and registry. Add places and choice groups there, and never rename ids.
- **Not written:** the voice-over, and romance or courtship lines. Courtship stays with the life-sim systems (owner rule: traditional male–female pairs). Wren is written as a friend. Any courtship with her belongs to those systems.
