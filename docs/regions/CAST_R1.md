# Region 1 cast: "The Stones Are Dimming"

The 12 named characters of the main quest (package L14). Speaker ids are the keys in `kingdom/data/region1/quests/cast.json`; the lint (`tools_qa/region1/lint_quests.gd`) fails if one of them never speaks. Names follow `docs/regions/OWNER_DECISIONS.md` (poster names on screen, data ids kept). No romance is written for any of them; courtship stays with the life-sim systems and their owner rules.

Voice rules for everyone: lines of 120 characters or fewer, one idea per line, no speeches. Each voice below has one tic you can hear in a single line.

| # | Id | Name | Role | First scene |
|---|---|---|---|---|
| 1 | `mother` | Your mother (procedural name) | Home | Act I, dusk: "Stay in tonight, love." |
| 2 | `father` | Your father (procedural name) | Home, ex-Guard spear | Act I, after the Blessing |
| 3 | `maren_coldbrook` | Maren Coldbrook | Staff teacher, Old Mill Staff Yard | Act I, the wolf at the ring edge |
| 4 | `bram_hollis` | Captain Bram Hollis | Ashford Guard Captain | Act II, "Forty-One Stones" |
| 5 | `idra_vell` | Warden Idra Vell | Runeward stone-keeper, quest giver | Act I, the Miller's Stone |
| 6 | `odrin_thale` | Guildmaster Odrin Thale | Masons' and Runecarvers' Guild, Silverford | Act III, "Section Four" |
| 7 | `rowan_ashby` | Sir Rowan Ashby | Knight-captain, Order of the Highwatch | Act IV, "Without the Knees" |
| 8 | `lucan` | Envoy Lucan | Envoy of the Dawn Throne (Aurelis Patriarchate) | Act III, the Council |
| 9 | `harrok_ashmaw` | Harrok Ashmaw | Chief of the Tuskridge exiles (orc) | Act IV, Greyseam Mine |
| 10 | `snikkit` | Snikkit the Twice-Bitten | Leader of the Mossfang Warren (goblin) | Act IV, the Elden Road |
| 11 | `imra_solvane` | Imra Solvane | Solkar caravan mistress (tease) | Act III, Silverford market |
| 12 | `tamsin_reeve` | Tamsin Reeve | Quartermaster, Rift's Edge Camp | Act V, "Edge Rules" |

Supporting speakers (not in the 12): Corin Vesk (Ashen Hand cutter, 16), Gilda Pennick (Greenhollow farmer), King Aldric III, the ancestor stones (Ember Legacy voices), the narrator.

---

### 1. Your mother
Warm and practical; she worries in lists ("Coat on. Back the moment she says so. And don't touch anything."). Her pride leaks out sideways, never as a speech. She opens the quest by telling you to stay in, and closes it by telling you to sit and eat. Her Blessing reaction changes with your element; the "no Blessing" line is the proudest one on purpose.
**Voice:** short imperatives, then one soft line.

### 2. Your father
An old Guard spear-carrier with a dry, understated humour ("Nearly dropped my spear. Don't tell the Captain."). He jokes when he's moved. At the homecoming he admits the Miller's Stone never sang for him.
**Voice:** deadpan, calls you "sprout" while you're small.

### 3. Maren Coldbrook
A one-armed veteran who teaches village children to fight with a quarterstaff behind the old mill. She was a Runeward officer. In the Long Dark she held a failing stone lit with her own warmth until dawn, and the stone took her arm "as payment. Forty people slept that night. Fair trade." She is the first adult who tells you the truth about cost. She teaches block and roll ("Everything is bigger than you.").
**Voice:** drill-yard commands and gallows humour; she never pities herself.

### 4. Captain Bram Hollis
He runs Ashford's Guard, with nine guards for forty-one stones and sixty miles of road. He isn't cynical, just tired, and he does the sums out loud so you understand why he can't send anyone. He gives the first repair job and the first Scar warning. "If you smell smoke, run to the guardhouse. Not toward the smoke. Toward me."
**Voice:** arithmetic as a love language.

### 5. Warden Idra Vell
The Vale's last full Wardwright, in her sixties, with fingertips gone grey from carving. The ring gave her nothing at her own Blessing; she carves anyway. Carving is a craft, not a gift, and she is the story's thesis in person. She teaches the first glyph, explains embers, teaches Ashsight and walks you to the Rift mouth. At the end she offers her own ember to seal it. The player decides whether she rests there or whether "all of them" do it together, in which case she retires and leaves you her chisel and her terrible tea.
**Voice:** quiet imperatives, dry wit, "Hm." She never wastes a word.

### 6. Guildmaster Odrin Thale
Master of the Masons' and Runecarvers' Guild in Silverford. He is proud, precise and legalistic, citing the Charter by section ("Section four: only Guild hands carve."). He is not a villain: a careless glyph really can split a stone. His ledgers hold the first hard evidence that the stones are empty, not broken. He licenses you after a clean Alarm glyph ("Irritatingly clean.").
**Voice:** formal clauses, fees and sections; secretly frightened that nobody listens to a mason.

### 7. Sir Rowan Ashby
Knight-captain of Highwatch Keep, seventy winters old, cheerful, and fond of talking to the north wind. Knight-path players are his squire. He holds the north gate with you against rift wolves from Grimfen Pass, takes a wound under the shield, and asks you to carry his ember. That is where the Ember Legacy choice is taught: the stone, his squire Tobin, or his old lance. If he rests in the stone, Highwatch greets you afterwards: "Mind the step. It's icy."
**Voice:** jovial and a little poetic; calls you "young blade"; jokes about his knees until the end.

### 8. Envoy Lucan
The Dawn Throne's envoy in Kingsreach. He is gentle, sincere and full of sunrise imagery, says "friend" and means it. He offers relics that "shine without anyone's dead inside them", and they work, at the price of a chapel and a tithe. By Act IV he learns that "a relic is a leash": his Patriarch dims them when the tithe is late. He doesn't become a villain or a convert. He becomes an honest man who helps you read the ash at Crownstead.
**Voice:** warm, formal, hopeful; the most polite person in any room.

### 9. Harrok Ashmaw
Chief of the orc exiles of Tuskridge Hold. His clan mines the deep Greyseam seam because "Crown says: no orc picks in Crown rock. Rock does not read. Harrok's children eat." Answer his "Strong blood" with "Stronger clan" and Tuskridge comes down the scree roaring your name at the finale.
**Voice:** short, blunt sentences; speaks of himself by name; dark, dry humour ("Bad singing. Good sign.").

### 10. Snikkit the Twice-Bitten
The goblin leader of the Mossfang Warren, close to becoming a hobgoblin. He "borrowed" the Elden Elder Stone's keystone because "shiny was lonely". Goblins see the violet Scar before humans do. Trade him your lantern and his eyes are yours at the finale; take the shard by force and "Snikkit remembers *everything*".
**Voice:** fast, third person, italic emphasis, never sits still.

### 11. Imra Solvane
A Solkar caravan mistress at Silverford market and the region's tease for the Solkar Dominion to the south. Her people fight their own Rift's creep with fire. She gives you sunstone oil, the tool that burns the Scar back, with "In Solkar we say: pay the lamp-lighter first."
**Voice:** merchant charm and sun proverbs; always one bargain ahead.

### 12. Tamsin Reeve
Quartermaster of Rift's Edge Camp and the Ashen Hand's paymaster. The Crown pulled the ward-lines back and left her village, Hollin's Reach, outside: forty graves in one winter. So she bought scar-crystal and paid boys like Corin to cut stones: "I let the dark pay, for once." She never apologises and never lies. Arrest her or pardon her; either way she hands over the anchor stone ("Edge rules: pay your debts, even to Kings.").
**Voice:** gravel and grievance; "Edge rules"; the one antagonist whose argument the story doesn't dismiss.

---

## Supporting
- **Corin Vesk** (16): the saboteur you catch in Duskbriar. He is scared, defiant and too honest for the job. He says the line that drives the plot: "They're dying on their own!" Jail him, free him, or make him your informant (Tamsin notices).
- **Gilda Pennick**: the Greenhollow farmer whose barn burned. She is the story's ordinary person twice: after the raid, and again when the Scar reaches her fields ("Burn it or sell it, I don't care.").
- **King Aldric III**: measured and tired; asks the young carver what to do and means the question.
- **Ancestor stones** (`ancestor_stone`): Hesk the miller, Sir Rowan, the Elden Road founder, and, with Ember Legacy (L10), your own previous character. They are warm and fragmentary, and remember feelings better than facts.
