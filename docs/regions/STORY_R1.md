# The Stones Are Dimming: Region 1 main quest

Package **L14**. The data is `kingdom/data/region1/quests/r1_main.json` (30 steps) with dialogue in `kingdom/data/region1/dialogue/r1_act1..5.json` (134 nodes, 158 lines). The schema is in `kingdom/data/region1/quests/README.md`, and the cast in `CAST_R1.md`. It lints clean with `tools_qa/region1/lint_quests.gd`, and autoplay finishes the quest in all 2,592 choice combinations.

## The idea
Every runestone in the Vale glows because someone's **ember** rests in it: the stubborn part of a person who chose to keep watch after death. The five **Elder Stones** are the network's hearts. Their embers are two hundred years old, and nobody has given a new one in generations. First the Crown made ember-laying a noble's right, then the Church called it heathen, and then people simply stopped. The Legion carved harder and called it repair.

So the stones are dimming, and **no villain is doing it**. The Ashen Hand's saboteurs only push stones that were already failing, for scar-crystal paid by a woman whose village the Crown left outside the ward. The Church's relics really work, on a leash. The fix isn't a sword. It's the Vale remembering how to give. The finale says it out loud: not one hero's ember, all of them.

**Tone:** warm, sunny storybook with real costs. Maren's arm, Rowan's death, forty graves at Hollin's Reach and Idra's offer at the mouth. Every loss is met with humour or tenderness, never despair. There's no chosen one: Idra, the best carver alive, had no Blessing at all.

**Mechanics as story:** Wardwright (carving and routing) is how you care for the dead's light. Ashsight is how the ash testifies. The Scar Tide is what grows where care runs out. Ember Legacy is the answer. Each mechanic is taught in its own scene and used again in at least two acts (the lint checks this):

| Mechanic | Taught | Used |
|---|---|---|
| Wardwright (N1) | Act I, the Miller's Stone (the Ward glyph); Act IV, Crownstead (routing ward-lines) | II, III, IV, V |
| Ember Legacy (N3) | Act I, "Whose Light" (what embers are); Act IV, Sir Rowan's choice (the 3-card radial) | III, IV, V |
| Ashsight (N4) | Act II, the burned Pennick farm | II, IV |
| Scar Tide (N2) | Act III, Greenhollow's south fields (burn it or harvest it) | IV, V |

## Act I: Hearth and Stone (Ashford, age 8 to 12)
At supper the Miller's Stone goes out. Your mother tells you to stay in; of course you go. Warden Idra Vell is glaring at the dark stone and hands you the lantern. Her hands are slow tonight, so she teaches yours: palm flat, down, across, up, don't lift. The stone hums back ("Rudely, but it counts"). It holds old Hesk the miller: "The stubborn part. Stubborn lasts."

Idra sends you home because something is pacing the ring edge. It's a lone wolf, the safe first fight, and a one-armed woman shouting about your feet. Maren Coldbrook takes you on at the Old Mill Staff Yard. Ask about her arm and you learn the price of holding a stone lit by hand. Years pass. On the eve of twelve, Idra admits the ring gave her nothing at her own Blessing: "I carve anyway." At the Blessing every stone in the ring lights at once, and so does every stone in the Vale. "A stone clearing its throat before bad news."

**Teaches:** move, look, talk, interact, carve, fight, block, dodge, eat, sleep, map (L16 prompts); the first glyph (N1); embers (N3).

## Act II: Ash on the Wind (the Vale, age 12 to 15)
Three letters offer an apprenticeship with the Guild, Highwatch or the Runeward. Whichever you pick, Idra still needs you on the roads, and gives you a chisel. Captain Hollis does the sum (nine guards, forty-one stones, sixty miles) and sends you to relight two stones on the Greenhollow road. Then Gilda Pennick's barn burns: boars with purple eyes came through a gap in a stone she checked last week.

Idra teaches **Ashsight** in the ash beside the broken stone ("Fire remembers."). Grey figures replay a hooded cutter taking the glyph out clean, then running north-east. The ember trail leads into Duskbriar and the Ashen Hand. The cutter is Corin Vesk, sixteen, paid in scar-crystal from "a buyer at the Edge". His mother eats because of it. You choose his fate: jail, freedom, or informant. He also says the line that turns the story: "They're dying on their own!" Idra: "Then he's a thief who tells the truth. That frightens me more than a liar would."

## Act III: Relics and Rot (Silverford, Kingsreach, Greenhollow, the Stagborn Glade)
In Silverford, Guildmaster Odrin Thale tests your unlicensed hands with an Alarm glyph ("Irritatingly clean"). His ledgers prove it: repairs triple every year, and none of them hold. The stones aren't broken; they're empty. Imra Solvane of the Solkar caravan gives you sunstone oil, because in the south fire takes the purple back.

At the Council of Wardens, Envoy Lucan of the Dawn Throne offers relics that "shine without anyone's dead inside them", at the price of chapels and a tithe. King Aldric asks *you*. You can accept, refuse, or borrow one for Greenhollow with no tithe. Then the **Scar Tide** reaches Greenhollow's fields. You can burn it back cell by cell, or fill your pack with crystal while the edge keeps crawling; the valley remembers which.

The Stagborn herd flees its Glade. There the Elder Stone lies cold ("It didn't fall. It went cold, and the ground let go of it."). Idra tells the truth about the five hearts: "It's everyone's fault. That's the good news. Everyone can mend it."

## Act IV: The Five Hearts (the Elder Stones)
**The Glade** comes first. The Antlered Warden must be tired out, not killed. Then you carve Bless while it watches, and it lowers its antlers to the stone. The other four hearts can be done **in any order**:
- **Greyseam Mine:** Tuskridge orcs mine the deep seam because the Crown bars them ("Rock does not read."). Violet has welled up out of the rock. Answer Harrok's "Strong blood" with "Stronger clan" and he holds your torch. Burn the seam, then relight.
- **Highwatch Keep:** you hold the north gate with Sir Rowan against rift wolves from Grimfen Pass. One gets under his shield. Seventy winters: "I'd like to keep watch. Without the knees." This is where the **Ember Legacy** choice is taught: his ember goes to the stone, to his squire Tobin, or to his lance. If it goes to the stone, Highwatch greets you ever after.
- **Crownstead:** Lucan's relic is dimming (or never came), because "a relic is a leash". He helps you read the ash: a cart, and a woman's voice saying "The Edge pays on delivery." The heart is healthy but its line is cut, so you **route a new ward-line** to Kingsreach (N1 routing is taught here).
- **The Elden Road:** Snikkit has "borrowed" the keystone because "shiny was lonely". Trade your lantern for it, or take it. The stone speaks as your family's founder: "Now it's your turn to be held." With Ember Legacy (L10) it speaks as **your own previous character**.

With five hearts beating, "the whole Vale hums like a hive in summer." You route three lines toward the Edge.

## Act V: The Ashen Scar (finale)
At Rift's Edge Camp, Tamsin Reeve admits everything. The Crown pulled the lines back from Hollin's Reach and left forty graves in one winter, "so I let the dark pay, for once." Arrest or pardon; either way she gives you the anchor stone. You ward the anchor and **walk the tide home** cell by cell. Allies arrive according to your earlier choices: Tuskridge war-horns, Snikkit's goblins pointing out the purple, or the Runeward crews singing badly.

At the mouth the **Scarbound Troll** stands up out of the violet ("It was a troll, once."). With it down, the mouth still wants an ember. Idra offers hers: "I'm old, I'm ready, and frankly I'd like the view." You choose:
- **"Then rest, Idra."** She seals it. Her voice joins the stones, and the Scar stone greets you: "The tea is terrible here too."
- **"No. All of them."** The ward-lines you routed carry every heart in the Vale to the mouth: "Miller, knight, grandmother. Stand aside, Warden. We've got this one." Idra lives, retires, and leaves you her chisel (and her tea).

As the mouth closes you glimpse a red sky raining fire and a violet forest breathing light (the Ember and Bloom Rifts). Home in Ashford your mother says "Sit. Eat." Your father admits the Miller's Stone never sang for him, and Hesk's stone greets the little lantern-holder: "Go on, then. Live. We've got the road." **Region 1 complete** (`r1.complete`). The seal is held "for now", by borrowed light. Your first ancestor's ember can later rest in the Scar stone (the post-game hook for Ember Legacy).

## Branches and what they change
| Choice (registry group) | Options | Pays off in |
|---|---|---|
| `apprenticeship` | Guild / Highwatch / Runeward | Captain, Odrin and Rowan greet you differently; rep |
| `corin_fate` | jail / free / informant | Tamsin knows you were told (informant) |
| `relic_policy` | accept / refuse / borrow | Lucan's Crownstead scene; rep with Church and Crown |
| `scar_answer` | burn / harvest | Gilda's reaction; crystal in your pack |
| `harrok_pact` | ally / alone | Harrok's line after the relight; orcs at the finale |
| `rowan_ember` | stone / heir / lance (N3 radial) | Highwatch's voice, Tobin, or the heirloom lance |
| `snikkit_deal` | trade / force | goblins at the finale |
| `tamsin_fate` | arrest / pardon | rep; she fights beside you (pardon) |
| `the_seal` | Idra rests / all of them | the Scar stone's voice, or Idra retires |

## Beats that need cutscenes (for C9)
The ids are in `r1_registry.json` under `cutscenes`, and the quest emits `["cutscene", id]` actions at these moments. C9 writes shot lists for `cutscene_player.gd`. Keep each one short and skippable, and in the sunny storybook look.

| Id | Trigger | Beats (shot list seed) | Length |
|---|---|---|---|
| `blessing` | `a1_blessing` starts (age 12) | 1) Dusk; the Ashford ring and villagers with lanterns. 2) The child steps into the centre and Idra watches from the edge. 3) The stones light one by one, then all together; element-coloured motes rise (none: a still, quiet glow, held on the child's raised chin). 4) Wide: stones flare all across the Vale, as far as the horizon. 5) Mother's face. | 25–35 s |
| `elder_relight` | each Elder Stone relit (5×; the Glade version includes the Warden bowing) | 1) Close on the carved glyph; the stroke trail burns in. 2) Light runs down into the ground. 3) Aerial: ward-lines race along the roads to nearby stones, which light in a chain. 4) The map layer pulses. Reuse with per-site variants (Glade: antlers; Greyseam: miners' lamps; Highwatch: the banner lifts; Crownstead: the line to Kingsreach; Elden: the ancestor's face in the glow). | 10–15 s |
| `rowan_ember` | Rowan's ember choice made | 1) Rowan at rest against the battlement, smiling. 2) An ember rises from his chest. 3) It goes to the chosen card: into the stone (gold glow), into Tobin's hand, or into the lance. 4) The north wind stills. | 12 s |
| `finale_seal` | `a5_seal` sealed | 1) The mouth roars violet. 2a) Idra walks in, sets her palm on the anchor and turns to wink, then light. 2b) Or ward-lines converge from five directions; ember-figures (miller, knight, founder, strangers) stand shoulder to shoulder. 3) The mouth shrinks. 4) The glimpse beyond it: an ember-red sky raining fire, and a bloom-violet forest breathing light. 5) Silence, then birdsong. | 40–60 s |
| `region_complete` | `a5_homecoming` done | 1) Walking home down the lit road at golden hour. 2) Family at the door. 3) The Miller's Stone hums as you pass. 4) The "Region 1 complete" card, then back to free play. | 20 s |

The birth cutscene already exists (`cinematic/birth_cutscene.gd`), which brings the region to the four cutscenes the plan requires.

Also scripted but not cutscenes (C6/C7 wiring):
- **Ashsight at the Pennick farm** (Act II) and **at Crownstead** (Act IV) should inject a real raid or sabotage event into `ash_memory` (L11), so the replay uses the normal ghost pipeline. The `ash_vision` and `crownstead_vision` narrator lines are the captions.
- **The Scarbound Troll rises** (`troll_rises`) is an in-engine boss intro (X6).

## Hand-off notes
- **C7 (quest runtime wiring):** see `HOOKS_FOR_CLOUD.md` (Story quest section) for the event mapping from Wardlines, the Scar Tide, Ashsight, combat and areas.
- **C0/C1:** places marked `c0`/`c1` in `r1_registry.json` need to exist. Proposed positions are given there.
- **C8:** Act I is the onboarding. `a1_first_glyph` sets `r1.a1.first_glyph` for the "first glyph in 20 minutes" metric, and `a1_hesks_ember` spawns the one safe wolf at the ring edge.
- **L15 side quests** reuse the schema and registry. Add places and choice groups there, never rename ids.
- **Not written:** the voice-over and the romance/courtship lines (the owner's rule: traditional male–female courtship, handled by the life-sim systems, not this quest).
