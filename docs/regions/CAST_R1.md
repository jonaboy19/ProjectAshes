# Region 1 cast: "The Stones Are Dimming"

The 12 named characters of the main quest (package L14, story v2: see `EMOTION_MAP_R1.md`), plus two new supporting characters, Wren and Thistle. Speaker ids are the keys in `kingdom/data/region1/quests/cast.json`; the lint (`tools_qa/region1/lint_quests.gd`) fails if one of them never speaks. Names follow `docs/regions/OWNER_DECISIONS.md` (poster names on screen, data ids kept). No romance is written for any of them; courtship stays with the life-sim systems and their owner rules.

Voice rules for everyone: lines of 120 characters or fewer, one idea per line, no speeches. Each voice below has one tic you can hear in a single line.

| # | Id | Name | Role | First scene |
|---|---|---|---|---|
| 1 | `mother` | Your mother (procedural name) | Home | Act I, dusk: "Stay in tonight, love." |
| 2 | `father` | Your father (procedural name) | Home, ex-Guard spear | Act I, supper: "He's had five, sprout." |
| 3 | `maren_coldbrook` | Maren Coldbrook | Staff teacher, Old Mill Staff Yard; **dies Act III** | Act I, the wolf at the ring edge |
| 4 | `bram_hollis` | Captain Bram Hollis | Ashford Guard Captain; **the betrayer** | Act I, supper, with honey cakes |
| 5 | `idra_vell` | Warden Idra Vell | Runeward stone-keeper, quest giver | Act I, the Miller's Stone |
| 6 | `odrin_thale` | Guildmaster Odrin Thale | Masons' and Runecarvers' Guild, Silverford | Act III, "Section Four" |
| 7 | `rowan_ashby` | Sir Rowan Ashby | Knight-captain, Order of the Highwatch | Act IV, "Without the Knees" |
| 8 | `lucan` | Envoy Lucan | Envoy of the Dawn Throne (Aurelis Patriarchate) | Act III, the Council |
| 9 | `harrok_ashmaw` | Harrok Ashmaw | Chief of the Tuskridge exiles (orc) | Act IV, Greyseam Mine |
| 10 | `snikkit` | Snikkit the Twice-Bitten | Leader of the Mossfang Warren (goblin) | Act IV, the Elden Road |
| 11 | `imra_solvane` | Imra Solvane | Solkar caravan mistress (tease) | Act III, Silverford market |
| 12 | `tamsin_reeve` | Tamsin Reeve | Quartermaster, Rift's Edge Camp | Act V, "Edge Rules" |

Supporting speakers (not in the 12): **Wren Coldbrook** (best friend, first companion), **Thistle** (stagborn fawn, first bonded beast), Corin Vesk (Ashen Hand cutter, 16), Gilda Pennick (Greenhollow farmer), King Aldric III, the ancestor stones (Ember Legacy voices), the narrator.

---

### 1. Your mother
Warm and practical; she worries in lists ("Coat on. Back the moment she says so. And don't touch anything."). Her pride leaks out sideways, never as a speech. She opens the quest by telling you to stay in, and closes it by telling you to sit and eat. Her Blessing reaction changes with your element; the "no Blessing" line is the proudest one on purpose.
**Voice:** short imperatives, then one soft line.

### 2. Your father
An old Guard spear-carrier who served under Captain Hollis, with a dry, understated humour ("Nearly dropped my spear. Don't tell the Captain."). He jokes when he's moved. He wins the fawn argument ("It's sleeping in the house."), hangs grandfather's lantern on Kindling Night ("Snored like a millstone"), and loses to Maren at staves every year. At the homecoming he admits the Miller's Stone never sang for him. In the Bram ending, Bram's last words are for him: "Tell your father I was a good captain, once. He'll know when."
**Voice:** deadpan, calls you "sprout" while you're small.

### 3. Maren Coldbrook
A one-armed veteran who teaches village children to fight with a quarterstaff behind the old mill. She was a Runeward officer. In the Long Dark she held a failing stone lit with her own warmth until dawn, and the stone took her arm "as payment. Forty people slept that night. Fair trade." She is the first adult who tells you the truth about cost. She teaches block and roll ("Everything is bigger than you."). Her niece Wren is her other stray.

**Arc (v2):** she is the mentor whose loss the second half answers.
- On Kindling Night in Act III, when the ring line is cut, she holds Ashford's heart-stone lit by hand again, with her one good arm, while you hold off the rift wolves. She dies there: "Forty slept, last time. Whole village tonight. Fair trade. Better than fair."
- Her ember stays and turns the ring gold: the first new ember in two hundred years, and the story's proof that the fix is giving.
- In the Act IV vigil her voice from the stone gets you back on your feet, and she leaves you her staff.
- She has the last line of the region: "Staff up, lantern-holder. ...Hm. Not bad. Not good. Not bad."

**Voice:** drill-yard commands and gallows humour; she never pities herself. Her signature line, "Not bad. Not good. Not bad.", is used exactly three times: when you meet, when she dies, and at the end.

### 4. Captain Bram Hollis
He runs Ashford's Guard, with nine guards for forty-one stones and sixty miles of road. He isn't cynical, just tired, and he does the sums out loud so you understand why he can't send anyone. He is your father's old captain and a regular at your supper table, with honey cakes. He gives the first repair job and the first Scar warning. "If you smell smoke, run to the guardhouse. Not toward the smoke. Toward me."

**Arc (v2): the betrayal.**
- *History:* twenty years ago, as a young lieutenant, he obeyed the Crown and pulled the ward-line from his own village, Hollin's Reach ("Nine guards. I did the sum."). Forty people died that winter, among them his sister Tamsin's neighbours. He has hung a lantern "for friends up north" every Kindling Night since.
- *Motive:* he came to believe the Crown only redraws lines for places that scream.
- *The betrayal:* he asked you to report every stone, sold that list to the Ashen Hand (failing stones first), and on Kindling Night in Act III sent the Guard away so the ring line could be cut. "One dark night, I told them. Just one. Then the wolves came." Maren died.
- *The reveal:* Ashsight shows his key and his counting.
- *Fate:* chains, or "Go. Live with that sum."
- *If spared:* he hauls stone at the finale without meeting your eyes, and may walk into the Rift mouth: "Nine guards. Forty-one stones. Sixty miles. One of me. That sum, I can do."

**Voice:** arithmetic as a love language, and later as a confession. He never lies once he's caught.

### 5. Warden Idra Vell
The Vale's last full Wardwright, in her sixties, with fingertips gone grey from carving. The ring gave her nothing at her own Blessing; she carves anyway. Carving is a craft, not a gift, and she is the story's thesis in person. She teaches the first glyph, explains embers, teaches Ashsight and walks you to the Rift mouth. At the end she offers her own ember to seal it.

**Arc (v2): the twist.**
- The grey fingers aren't stone dust. For thirty years she has fed Ashford's heart-stone with her own ember, alone and without asking anyone.
- That is why her hands were "slow tonight" at your first glyph, why she sat down hard at your Blessing, and why her lantern dims when she coughs.
- It comes out in Act III when she collapses on the Glade path and Ashsight at the Miller's Stone shows you. "Everyone can mend it. I just started early." "I'm just doing it on purpose."
- Maren's ember takes over the ring, so Idra can stop.
- At the mouth, "I've been practising for thirty years." Whether she pays depends on you (see `STORY_R1.md`, *Endings*). If she lives, she retires and leaves you her chisel and her terrible tea.
**Voice:** quiet imperatives, dry wit, "Hm." She never wastes a word.

### 6. Guildmaster Odrin Thale
Master of the Masons' and Runecarvers' Guild in Silverford. He is proud, precise and legalistic, citing the Charter by section ("Section four: only Guild hands carve."). He is not a villain: a careless glyph really can split a stone. His ledgers hold the first hard evidence that the stones are empty, not broken. He licenses you after a clean Alarm glyph ("Irritatingly clean.").
**Voice:** formal clauses, fees and sections; secretly frightened that nobody listens to a mason.

### 7. Sir Rowan Ashby
Knight-captain of Highwatch Keep, seventy winters old, cheerful, and fond of talking to the north wind. Knight-path players are his squire. He holds the north gate with you against rift wolves from Grimfen Pass, takes a wound under the shield, and asks you to carry his ember. That is where the Ember Legacy choice is taught: the stone, his squire Tobin, or his old lance. If he rests in the stone, Highwatch greets you afterwards ("Mind the step. It's icy."), and his ember is one of the four that make the hidden Kindled Dawn possible. In v2 he recognises Maren's staff: "She beat me at staves in '31. Tell her I want a rematch." "She died." "...Then I'll ask her myself. Sooner than I'd like."
**Voice:** jovial and a little poetic; calls you "young blade"; jokes about his knees until the end.

### 8. Envoy Lucan
The Dawn Throne's envoy in Kingsreach. He is gentle, sincere and full of sunrise imagery, says "friend" and means it. He offers relics that "shine without anyone's dead inside them", and they work, at the price of a chapel and a tithe. By Act IV he learns that "a relic is a leash": his Patriarch dims them when the tithe is late. He doesn't become a villain or a convert. He becomes an honest man who helps you read the ash at Crownstead.
**Voice:** warm, formal, hopeful; the most polite person in any room.

### 9. Harrok Ashmaw
Chief of the orc exiles of Tuskridge Hold. His clan mines the deep Greyseam seam because "Crown says: no orc picks in Crown rock. Rock does not read. Harrok's children eat." Answer his "Strong blood" with "Stronger clan" and Tuskridge comes down the scree roaring your name at the finale. As an ally he also tells you that his mother, who died in spring, broke orc custom and asked to rest in the Greyseam stone: "She was always stronger clan." Her ember roars at the Rift mouth in the Kindled Dawn.
**Voice:** short, blunt sentences; speaks of himself by name; dark, dry humour ("Bad singing. Good sign.").

### 10. Snikkit the Twice-Bitten
The goblin leader of the Mossfang Warren, close to becoming a hobgoblin. He "borrowed" the Elden Elder Stone's keystone because "shiny was lonely". Goblins see the violet Scar before humans do. Trade him your lantern and his eyes are yours at the finale; take the shard by force and "Snikkit remembers *everything*".
**Voice:** fast, third person, italic emphasis, never sits still.

### 11. Imra Solvane
A Solkar caravan mistress at Silverford market and the region's tease for the Solkar Dominion to the south. Her people fight their own Rift's creep with fire. She gives you sunstone oil, the tool that burns the Scar back, with "In Solkar we say: pay the lamp-lighter first."
**Voice:** merchant charm and sun proverbs; always one bargain ahead.

### 12. Tamsin Reeve
Quartermaster of Rift's Edge Camp and the Ashen Hand's paymaster. The Crown pulled the ward-lines back and left her village, Hollin's Reach, outside: forty graves in one winter. So she bought scar-crystal and paid boys like Corin to cut stones: "I let the dark pay, for once." She never apologises and never lies. She is **Bram Hollis's sister**: he pulled the line, and she did the burying. Arrest her or pardon her; either way she hands over the anchor stone ("Edge rules: pay your debts, even to Kings."). If she is pardoned and Bram isn't there, she walks into the Rift mouth: "Tell my brother the sum came out even."
**Voice:** gravel and grievance; "Edge rules"; the one antagonist whose argument the story doesn't dismiss.

---

## Supporting
- **Wren Coldbrook** (`wren_coldbrook`): Maren's niece and your best friend.
  - She knocks you flat at the Staff Yard ("I'm exactly your size. Friends?") and joins at the Blessing ("You glow now. Insufferable.").
  - After Maren dies, she blames you in the rain ("You told him. Every stone.") and walks out.
  - She comes back at the Glade: "Still angry. Still coming."
  - She runs the Staff Yard in the epilogue.
  - She is companion #1 in `docs/design/RETINUE_SETTLEMENT_ASCENSION.md` §2.8; her personal quest becomes posthumous.
  - **Voice:** quick, cheeky and competitive. Jokes first, feels second, apologises never, but comes back.
- **Thistle** (`thistle`): the stagborn fawn the Act I wolf was hunting. She follows you home and eats lanterns.
  - In Act II the herd crosses and you free her or keep her (`thistle_bond`), with seven callbacks.
  - Freed, she returns grown at the Glade and leads the herd down the ward-lines at the finale.
  - Kept, she faces down the Antlered Warden as a fawn and won't leave your side.
  - She is the player's first bonded beast (a Stagborn Wardwalker, twist T4). She never dies.
  - **Voice:** stage directions of small, offended, loyal animal noises.
- **Corin Vesk** (16): the saboteur you catch in Duskbriar. He is scared, defiant and too honest for the job. He says the line that drives the plot, "They're dying on their own!", and adds that "a list comes with the crystal, neat hand, like a clerk's" (Bram's). Jail him, free him, or make him your informant: an informant gets his warning to you an hour too late on Kindling Night, and Tamsin notices. All three versions return to fix stones at the finale.
- **Gilda Pennick**: the Greenhollow farmer whose barn burned. She is the story's ordinary person twice: after the raid, and again when the Scar reaches her fields ("Burn it or sell it, I don't care.").
- **King Aldric III**: measured and tired; asks the young carver what to do and means the question.
- **Ancestor stones** (`ancestor_stone`): Hesk the miller, Sir Rowan, the Elden Road founder, and, with Ember Legacy (L10), your own previous character. They are warm and fragmentary, and remember feelings better than facts.
