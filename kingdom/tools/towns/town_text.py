"""Text and tables for tools/towns/gen_town.py: name pools, role catalogue (job, lines, work), archetype kits (workers, quest themes).
Tone: Region 1 (docs/regions/CAST_R1.md, WORLD_R1.md): dry, terse, practical; one idea per line; lines of 120 characters or fewer.
Every role has two greetings and two rumours; the generator picks from them with a seeded RNG, so the output is deterministic."""

# --------------------------------------------------------------------------------------------- names

FIRST = """Aldous Alys Amice Ansel Arden Aubrey Barda Basil Bartle Bede Bessa Bettany Blythe Brannoc Brida Brock Bryony Cade Calder
Cecily Cedric Clem Colm Corbin Cordell Cressa Dacey Dael Dalla Dane Darby Dena Derwin Dolan Dorrit Drystan Duff Eadric Eda Edlin
Elbert Elfrida Elka Elwin Emmet Enid Eorl Erwin Esmer Evelyn Fenn Fenna Ferris Fiske Flora Folke Freya Fulk Garth Gavin Gerda
Gethin Gisla Godric Greta Gunnar Gwen Hadley Hale Halla Hamo Hanne Hardy Hartley Hazel Hedda Helm Henna Hewitt Hilde Hugh Idony
Ingram Isolt Jaren Jessa Jory Joss Kell Kelda Kendra Kestrel Kit Lanny Larkin Leif Leofric Letty Lind Linnet Lorne Lowen Lyle
Mabyn Madoc Mags Maeve Marden Mellor Merrin Milo Mora Morwen Nan Neville Nial Nolan Norah Odell Olwen Orrin Osric Oswin Otto
Pagan Parsley Pernel Piers Poppy Quill Quinn Radley Rafe Reda Reeve Rhosyn Rolf Rook Rosamund Rowena Rulf Rye Sabin Sander Seren
Sidony Silas Sitha Sorrel Stannis Sunniva Tabby Talbot Tegan Tess Tobin Torin Tuck Una Uther Vance Vera Wadsworth Wat Wendel
Wilda Wolfram Wystan Yarrow Yorick Zeb""".split()

SURNAMES = """Applegarth Ashby Aylward Barrow Bellamy Bexley Birkett Blackmore Bramble Brindle Brook Buckley Burrow Calloway Carver Chandler
Charnock Clay Coldwell Combe Cooper Copley Cragg Crowther Dalby Dane Dobbin Dunmow Eastman Elder Farrow Fellows Fletcher Forrest
Fothergill Gaunt Garland Gilbey Goodrich Graye Greaves Hallam Harker Hartwell Hatch Hawker Hazelden Heron Hollis Holloway Hopper
Hornby Hurst Ingleby Jessop Keld Kemble Kettle Kirby Lambert Larkspur Lathom Ledger Lockwood Lovell Lyle Marlowe Mattock Merrow
Middleton Mossop Netherby Nettle Newlyn Oakes Orchard Overton Pargeter Pashley Peverell Pickering Plover Quarry Radcliffe Rawlin
Redfern Rimmer Rudge Rushton Sallow Sedge Selby Shaw Sheaf Skerrit Slater Sparrow Spindle Stannard Stoker Strand Sumner Swale
Tallis Tanner Tarrant Thackeray Thorpe Tilley Tolliver Trevor Tupper Tyndall Underhill Upton Vickery Wainwright Wakeley Warrender
Wetherby Whitlock Wicker Wilmot Winslow Woolcott Wrenn Wythe Yardley Yoxall""".split()

ARCH_SURNAMES = {
    "farming": "Furrow Harrow Haywood Seedley Barleycorn Stooks".split(),
    "pastoral": "Fleece Shearer Crook Flockton Lambkin Tupman".split(),
    "craft": "Madder Woad Tenter Fuller Shuttle Loomis".split(),
    "mining": "Coalhill Pitman Shaftoe Ironside Lodestone Seam".split(),
    "fortress": "Pikeman Bulwark Garrison Shieldwall Spearman Rampart".split(),
    "hunting": "Fletchley Snare Hartshorn Fernley Antler Tracker".split(),
    "religious": "Vesper Lauds Candlemas Tithing Almoner Chantry".split(),
    "merchant": "Coinwright Scales Tollman Tradewell Bargain Mercer".split(),
    "scholarly": "Inkwell Quillon Lensley Glassman Lantern Vellum".split(),
    "criminal": "Shadwell Cutpurse Nimble Quiet Fenwick Sly".split(),
    "fishing": "Netley Gullet Saltmarsh Wherry Keel Brine".split(),
    "royal": "Crownley Heraldson Banner Standard Sceptre Tabard".split(),
}

TRAITS = """stubborn hardworking superstitious practical dry-humoured protective gloomy wise slow-to-anger restless kind patient dusty
gruff honest proud warm gossipy smooth calculating jovial nosy disciplined fair tired sharp-eyed quiet dutiful eager chatty
brave gentle sharp-tongued bold imaginative hungry shy observant soft-hearted curious fearless wistful tart solitary unflappable
serene stern pompous careful thrifty cheerful grumbling generous suspicious loyal sly hot-tempered meticulous forgetful
earnest cautious blunt sentimental weather-wise early-riser night-owl fond-of-puns deaf-when-convenient""".split()

# --------------------------------------------------------------------------------------------- roles
# role -> job (WorldSim index: 0 farmer, 1 blacksmith, 2 merchant, 3 guard, 4 laborer, 5 woodcutter), schedule kind,
# two greetings, two rumours. Schedule kinds: day (work), night (night watch), shop (shop hours), early (bakers), inn (late shift), kid, elder.

ROLES = {
    # keepers of the forced lots
    "innkeeper": (2, "inn", ["Sit anywhere that is not wet. The wet ones are the regulars.", "Ale is fair, stew is hot, and I do not do credit."],
                  ["Travellers say the stones are dimmer on the east road. I water the ale, not the news.", "Somebody paid in old coin last night. Very old. Nobody knew the king on it."]),
    "blacksmith": (1, "day", ["Mind the anvil. It has opinions.", "Bring iron or bring coin. Preferably iron."],
                   ["Hinges, hooks, wolf-bells. That is what sells now.", "Good steel is dear. Bad steel is dearer, the day it breaks."]),
    "shopkeeper": (2, "shop", ["Everything has a price. Some of it is even written down.", "Take your time. Touch nothing you cannot afford."],
                   ["Candles are short this month. The wax comes late, and so does the honest news.", "Sold three lanterns today. People are afraid of the dark again."]),
    "baker": (2, "early", ["Bread is at dawn. After dawn it is a rumour.", "Mind the flour. It gets everywhere, opinions included."],
              ["The oven runs hot because the town runs hungry.", "Half the loaves go to the watch. The rest go to whoever asks nicely."]),
    "herbalist": (2, "shop", ["Sit. Tongue out. No, the other way.", "If it hurts it is working. If it does not hurt, you overpaid."],
                  ["Fever in two households. Nothing the stones can mend.", "Fewer wild herbs past the last waymark this year. The hedges are bare."]),
    "guard captain": (3, "day", ["State your business and keep your hands where I can see them.", "Quiet town. Good. Do not make it noisy."],
                      ["Nine spears for the whole wall. I count them like sheep.", "{Threat} sign at the edge again. I wrote it in the ledger. Nobody reads the ledger."]),
    "guard": (3, "day", ["Move along. Or stay, but stay quiet.", "Evening. Stones are lit, gate is shut, I am cold."],
              ["Heard something past the hedge last night. Whatever it was, it was not honest.", "Captain says it is nothing. Captain also says that about rain."]),
    # the town's own
    "reeve": (2, "reeve", ["Reeve here. Yes, it is as dull as it sounds. Ask anyway.", "Tithe day is never early and always too soon."],
              ["The tally does not add up, and I have added it four times.", "Strangers stop here more than they used to. Not all of them buy anything."]),
    "elder": (4, "elder", ["Sit by me. My knees insist.", "You are somebody's grandchild. I can tell by the walk."],
              ["When I was young the stones sang at dusk. Now they hum, like someone ill.", "I remember the Long Dark. Nobody asks. Nobody wants the answer."]),
    "child": (4, "kid", ["Are you a soldier? You look like a soldier.", "I am not lost. I am exploring."],
              ["I saw a light in the hedge last night. Do not tell Mum.", "Our dog knows something and will not say what."]),
    "farmer": (0, "day", ["Mud is honest. Walk on it.", "Rain tomorrow. My knee says so."],
               ["Violet at the field edge, only a little. I am told it is the light.", "Crows are thick this year. They knew about the harvest before I did."]),
    "woodcutter": (5, "day", ["Timber! Well, soon. Stand back.", "Quiet work, wood. I like the quiet."],
                   ["Trees past the ward-line grow wrong. Too straight. Too quiet.", "Found a stump cut clean with no axe mark. I left it be."]),
    "laborer": (4, "day", ["Day work, day pay. What is it?", "My back says no. My purse says yes."],
                ["Hands wanted everywhere and nobody pays for hands.", "Someone is hiring after dark. I did not ask for whom."]),
    "carter": (4, "day", ["Road is long, axle is short.", "Hold the mule. He is not as bad as he looks."],
               ["Fewer carts on the road, more trouble at the verge.", "Toll at the ford has gone up. So has my temper."]),
    "miller": (4, "day", ["Mind the sails, mind your hat.", "Grain in, flour out. Everything else is chatter."],
               ["The wheel ran backward for a minute this week. I did not touch it.", "Flour weighs light lately. The scales are honest. I checked."]),
    # trade roles
    "shepherd": (0, "day", ["Quiet, lad. Not you. The dog.", "Wool does not shear itself. More is the pity."],
                 ["Sheep go missing near the old barrow. The shepherds do not look for them.", "Counted forty, home came thirty-nine. The dog looks guilty."]),
    "dairymaid": (0, "early", ["Mind the pail, it is still warm.", "Cows first, people second. Ask the cows."],
                  ["The spotted cow keeps to the verge. She knows which stones are dark.", "Milk soured overnight in two houses. The cellar is cold. It is not the cellar."]),
    "cheesemaker": (2, "day", ["Smell that? That is patience, aged.", "Taste first. Argue after."],
                    ["Wheels go west to Kingsreach and come back as complaints.", "A wheel went missing off the cool shelf. Whole wheel. Heavy thief."]),
    "wool buyer": (2, "shop", ["Fleece by the stone, gossip free.", "Show me the staple. I can read a fleece like a ledger."],
                   ["Prices are down. The wolves are bolder past the downs.", "Carters are late. Carters are always late. This is later."]),
    "dyer": (4, "day", ["Do not shake my hand. You will be blue until Tuesday.", "Mind the vat. It looks like water. It is not."],
             ["The stream ran red on dye day. Children upstream think it is an omen. We let them.", "A bolt of good blue went missing. The thief is easy to spot: the man not wearing it."]),
    "weaver": (4, "day", ["Hush. I am counting threads.", "Warp, weft, patience. Two out of three will do."],
               ["A good cloth outlasts a bad king. I have the cloth.", "Shuttle went missing off the loom. Nobody takes a shuttle. Someone did."]),
    "cloth merchant": (2, "shop", ["Feel that. Go on. That is a week of someone's life.", "Colour holds if you wash it cold and talk to it kindly."],
                       ["Silverford pays double for the good batch and then complains.", "Bolts are short at the count. The count was right when they left."]),
    "miner": (4, "day", ["Mind the lamp. Mind the roof. Mind me.", "Coal dust never leaves. Not the lungs, not the stew."],
              ["The north shaft is shut again. The foreman says the roof. The miners say not.", "Something knocks back when you knock on the deep face."]),
    "ore sorter": (4, "day", ["Good ore rings. Bad ore thuds. Everything else is lies.", "Sort it or carry it. Not both."],
                   ["Seams are thinner. The carts are still full of waste.", "Two sacks went out unmarked last week. Somebody is skimming the pile."]),
    "smelter": (1, "day", ["Stand back from the heat. It does not like being looked at.", "Ore in, iron out, patience in between."],
                ["The furnace burned blue yesterday. Nothing I fed it burns blue.", "Charcoal price is up and the iron price is not. Do the sum."]),
    "quarryman": (4, "day", ["Stone does not care how your morning went.", "Mind the cut face. It remembers being mountain."],
                  ["A good block takes three weeks to cut and a day to crack.", "The deep face hums at night. Not the stones. The rock."]),
    "fisher": (4, "dawn", ["Fish bite at dawn and at the worst moment.", "Lines down by first light, or do not bother."],
               ["The shoals have gone deep. The old fishers say the water has a second bottom.", "Found a net cut clean, not torn. Cut."]),
    "net mender": (4, "day", ["Hold this. No, higher. There.", "A net is promises with holes in. I mend the holes."],
                   ["Nets come back torn in places no fish reaches.", "Rope is dear and getting dearer. Cut a net, you cut a wage."]),
    "boatwright": (1, "day", ["If it floats, I built it. If it sank, somebody else did.", "Pitch, plank and promises. In that order."],
                   ["Black oak for the keel. It never leaks and it never comes back.", "Somebody asked me for a boat with no name. I built it. I did not ask."]),
    "salter": (4, "day", ["Lick the wall if you doubt me.", "Salt keeps. People, less so."],
               ["A pinch of salt on the doorstep keeps small dark things out. Also the neighbours.", "Pans ran short this month. Somebody is selling our salt as theirs."]),
    "hunter": (5, "dawn", ["Keep your voice down. The wood listens.", "Boots soft, bow ready, mouth shut."],
               ["Wolves came at noon last week. Noon. They have learned the stones are tired.", "A white hart in the north wood. We do not shoot the white hart."]),
    "trapper": (5, "dawn", ["Mind the snare by the gate. It is not for you.", "Furs by the dozen, questions by none."],
                ["A trapper went north in autumn and came back without his dogs.", "Found traps sprung, empty, and tracks too big to be a bear."]),
    "tanner": (4, "day", ["You smell it before you see it. That is the trade.", "Good leather needs oak bark, time and a strong stomach."],
               ["Wind from the west and the town can breathe. From the east we hold our noses together.", "Wolf pelts sell high this season. So do the people who bring them."]),
    "charcoal burner": (4, "day", ["Smoke on the moor after dusk is ours. If it is smoke you cannot smell, it is not.", "Do not breathe near the kiln. Or do. I am not your mother."],
                        ["The far kiln was cold when I woke. No fire, no ash, no scorch on the ground.", "Somebody is cutting beyond the ward. The forests are thinner every year."]),
    "glasswright": (1, "day", ["Red glass, hot and honest. Mind the heat.", "Do not breathe on it. It is thinking."],
                    ["The crystal hums when the stones dim. I am not saying it means anything.", "A Solkar trader wanted a window for a desert temple. The reddest thing I ever made."]),
    "lamp-maker": (1, "day", ["A lamp is only a promise to come home. Buy two.", "Oil, wick, glass. The glass is the hard part."],
                   ["Night fishing needs light and silence. Most of us manage the first.", "Lanterns on the pier brought the boats home. Mostly."]),
    "scribe": (2, "shop", ["Ink is cheaper than blood. Sign here.", "If it is not written down, it did not happen."],
               ["The ledgers say one thing. The cellars say another. I am only the scribe.", "Somebody asked me to change a date. I wrote it down that they asked."]),
    "trader": (2, "shop", ["Everything is for sale. Even this sentence.", "Come, come. Prices are only the start of a conversation."],
               ["Caravans bring spice from the south and leave with wool. Mostly.", "A buyer offered gold for road maps. I said they were free. He did not believe me."]),
    "weigh-master": (2, "shop", ["Scales never lie. Thumbs do.", "Weight, then price, then argument. In that order."],
                     ["A short weight turned up at the market. The scales are honest. The thumbs, not so.", "Every cart is heavier going out than coming in, and nobody can say why."]),
    "soldier": (3, "day", ["Eyes front. Mouth shut. Spear up.", "Off duty at dusk. Do not ask before."],
                ["Sergeant says the north pass is quiet. Sergeant also says silence is a tactic.", "Recruits keep coming. Fewer keep staying."]),
    "drillmaster": (3, "day", ["Feet apart. No, the other apart.", "Shoulders back. The spear is not a walking stick."],
                    ["The Order sent forty recruits. Thirty stayed. Twenty hold a line.", "Wolves test the line first. Men test it second. Both fail the same way."]),
    "armourer": (1, "day", ["Steel is honest. People are not. Show me your blade.", "Mail mends, bones do not."],
                 ["A knight's armour mended eleven times. He will not buy new. Says it remembers his knees.", "Steel from the south comes dear. The price is a crime."]),
    "stablehand": (4, "dawn", ["Mind the grey. He bites.", "Horses know the road to the pass. They will not go past the last banner."],
                   ["A rider came through at night, banner under his cloak. Horse was lathered.", "The chargers will not graze the east paddock. Nothing wrong there. I checked."]),
    "beekeeper": (0, "day", ["Hold still. If one lands, it is deciding about you.", "Never swat. Bow. They notice manners."],
                  ["Wild bees nest in the old tower. Nobody wants that honey.", "Candles burn longer if you hum while you pour. Nobody knows why."]),
    "spinner": (4, "day", ["Mind the wool. It sticks to everything, opinions especially.", "Spin clockwise on a good day and anticlockwise on a bad one."],
                ["A good thread is worth more than a good sword in winter.", "Thread went short at the guild count. A whole spool. Nobody found it."]),
    "chaplain": (2, "temple", ["Peace on your road. Mind the step, it is older than the faith.", "The stones are not our rivals. Ask the envoys."],
                 ["Fewer come to the vigil. More come to the stones. I count both.", "Somebody left a lantern on the shrine at dusk. Nobody will say who."]),
    "pilgrim guide": (4, "day", ["The road east is shut. The road west is long. Choose.", "Pilgrims eat first. Questions come after soup."],
                      ["Queues at the ditch grow daily. We feed them. Nobody asked us to.", "A rider crossed at night with a sunlit banner under his cloak."]),
}

# --------------------------------------------------------------------------------------------- archetypes
# workers: [(role, weight)]  authority: the town's reeve-like title; extra lot: types a village of this identity gets beyond the minimum

ARCHS = {
    "farming": {"workers": [("farmer", 4), ("miller", 1), ("carter", 1), ("shepherd", 1), ("woodcutter", 1)], "authority": "reeve", "threat": ["wolf"],
                "works": "the mill yard", "item": ["wheat", "wheat", 4], "stash": ["sack", "Wheat sacks", "You shoulder four sacks of wheat from the pile."],
                "deliver_role": "baker", "thing": "a few sacks of milled flour", "theft": ["sack", "tracks", "ledger"], "suspect": ["carter", "laborer"],
                "a_title": "Wheat for the Bakehouse", "b_title": "Light on the Scales", "c_title": "Wolves at the Millrace"},
    "pastoral": {"workers": [("shepherd", 3), ("dairymaid", 2), ("cheesemaker", 1), ("wool buyer", 1), ("carter", 1)], "authority": "reeve", "threat": ["wolf"],
                 "works": "the fold", "item": ["wool", "wool", 4], "stash": ["sack", "Fleece bundles", "You tie four fleeces into a bundle."],
                 "deliver_role": "wool buyer", "thing": "two cheese wheels", "theft": ["crate", "tracks", "ledger"], "suspect": ["carter", "laborer"],
                 "a_title": "Fleece for the Buyer", "b_title": "A Wheel Short", "c_title": "Wolves on the Downs"},
    "craft": {"workers": [("dyer", 3), ("weaver", 2), ("cloth merchant", 1), ("carter", 1), ("laborer", 1)], "authority": "reeve", "threat": ["giant_wasp"],
              "works": "the dye works", "item": ["cloth", "cloth", 3], "stash": ["crate", "Bolts of cloth", "You lift three bolts of undyed cloth from the rack."],
              "deliver_role": "dyer", "thing": "a bolt of good blue", "theft": ["ledger", "tracks", "lock"], "suspect": ["carter", "weaver", "laborer"],
              "a_title": "Cloth for the Vats", "b_title": "The Missing Bolt", "c_title": "Wasps in the Drying Meadow"},
    "mining": {"workers": [("miner", 4), ("ore sorter", 1), ("smelter", 1), ("carter", 1), ("laborer", 1)], "authority": "yard-boss", "threat": ["ghoul", "wolf"],
               "works": "the ore yard", "item": ["iron_ore", "iron ore", 4], "stash": ["stone", "Ore pile", "You fill a sack with four lumps of good ore."],
               "deliver_role": "smelter", "thing": "a few marked ore sacks", "theft": ["sack", "tracks", "lock"], "suspect": ["carter", "ore sorter", "laborer"],
               "a_title": "Ore for the Furnace", "b_title": "Skimmed from the Pile", "c_title": "Something in the Spoil Heap"},
    "fortress": {"workers": [("soldier", 3), ("armourer", 1), ("stablehand", 1), ("drillmaster", 1), ("carter", 1)], "authority": "watch-commander", "threat": ["wolf"],
                 "works": "the drill yard", "item": ["iron_ingot", "iron ingots", 3], "stash": ["crate", "Ingot crate", "You lift three ingots from the stores crate."],
                 "deliver_role": "armourer", "thing": "a set of spear heads", "theft": ["lock", "tracks", "ledger"], "suspect": ["stablehand", "carter", "laborer"],
                 "a_title": "Iron for the Armoury", "b_title": "Short of Spear Heads", "c_title": "Wolves at the Line"},
    "hunting": {"workers": [("hunter", 3), ("trapper", 1), ("tanner", 1), ("woodcutter", 1), ("carter", 1)], "authority": "huntmaster", "threat": ["wolf"],
                "works": "the lodge yard", "item": ["hides", "hides", 4], "stash": ["sack", "Drying hides", "You roll four dry hides into a bundle."],
                "deliver_role": "tanner", "thing": "a bundle of prime pelts", "theft": ["tracks", "lock", "sack"], "suspect": ["trapper", "carter", "laborer"],
                "a_title": "Hides for the Tanner", "b_title": "Pelts Gone from the Rack", "c_title": "A Den Too Close"},
    "religious": {"workers": [("chaplain", 1), ("beekeeper", 1), ("farmer", 2), ("pilgrim guide", 1), ("laborer", 1)], "authority": "chaplain", "threat": ["wolf"],
                  "works": "the shrine garden", "item": ["firewood", "firewood", 4], "stash": ["crate", "Woodpile", "You carry four split logs from the woodpile."],
                  "deliver_role": "chaplain", "thing": "the shrine's offering bowl", "theft": ["tracks", "lock", "ledger"], "suspect": ["pilgrim guide", "laborer"],
                  "a_title": "Wood for the Vigil", "b_title": "The Empty Bowl", "c_title": "Wolves Along the Pilgrim Road"},
    "merchant": {"workers": [("trader", 2), ("weigh-master", 1), ("scribe", 1), ("carter", 2), ("laborer", 1)], "authority": "factor", "threat": ["wolf"],
                 "works": "the weigh yard", "item": ["cloth", "cloth", 3], "stash": ["crate", "Sample bolts", "You take three sample bolts from the stage crate."],
                 "deliver_role": "trader", "thing": "a sealed contract case", "theft": ["ledger", "lock", "tracks"], "suspect": ["scribe", "carter", "laborer"],
                 "a_title": "Samples for the Caravan", "b_title": "The Light Weight", "c_title": "Wolves on the Staging Road"},
    "scholarly": {"workers": [("glasswright", 1), ("scribe", 1), ("lamp-maker", 1), ("laborer", 2), ("carter", 1)], "authority": "reeve", "threat": ["wolf"],
                  "works": "the kiln yard", "item": ["coal", "coal", 4], "stash": ["sack", "Coal sacks", "You fill a sack with four lumps of kiln coal."],
                  "deliver_role": "glasswright", "thing": "a case of finished glass", "theft": ["crate", "tracks", "lock"], "suspect": ["scribe", "carter", "laborer"],
                  "a_title": "Coal for the Kiln", "b_title": "A Case Gone Cold", "c_title": "Something at the Edge of the Light"},
    "criminal": {"workers": [("trapper", 2), ("tanner", 2), ("trader", 1), ("carter", 1), ("laborer", 1)], "authority": "headman", "threat": ["wolf"],
                 "works": "the skin yard", "item": ["hides", "hides", 4], "stash": ["sack", "Raw hides", "You bundle four raw hides, and wish you had not."],
                 "deliver_role": "tanner", "thing": "a bag of coin", "theft": ["lock", "tracks", "ledger"], "suspect": ["trader", "carter", "laborer"],
                 "a_title": "Hides, No Questions", "b_title": "Light Fingers", "c_title": "Teeth Below the Pass"},
    "fishing": {"workers": [("fisher", 4), ("net mender", 1), ("boatwright", 1), ("salter", 1), ("carter", 1)], "authority": "harbourmaster", "threat": ["bog_toad"],
                "works": "the drying racks", "item": ["flax", "flax", 4], "stash": ["sack", "Flax bales", "You bind four bundles of flax for the nets."],
                "deliver_role": "net mender", "thing": "a coil of good rope", "theft": ["tracks", "lock", "sack"], "suspect": ["carter", "fisher", "salter"],
                "a_title": "Flax for the Nets", "b_title": "Cut Lines", "c_title": "Toads in the Reeds"},
    "royal": {"workers": [("household knight", 2), ("trader", 2), ("carter", 1), ("laborer", 1), ("falconer", 1)], "authority": "chamberlain", "threat": ["wolf"],
              "works": "the Tourney Lists", "item": ["cloth", "cloth", 3], "stash": ["crate", "Banner cloth", "You take three bolts of banner cloth."],
              "deliver_role": "court scribe", "thing": "a sealed letter", "theft": ["ledger", "lock", "tracks"], "suspect": ["courtier", "treasury clerk", "carter", "laborer"],
              "a_title": "Cloth for the Banners", "b_title": "A Letter Gone Astray", "c_title": "Wolves at the Court Road"},
}

THREAT_NAMES = {"wolf": ("wolf", "wolves"), "giant_wasp": ("giant wasp", "giant wasps"), "ghoul": ("ghoul", "ghouls"), "bog_toad": ("bog toad", "bog toads"),
                "corrupted_wolf": ("corrupted wolf", "corrupted wolves")}

# --------------------------------------------------------------------------------------------- relationship opinions
# kind -> (default value, [opinion templates with {o} the other's first name])
RELATIONS = {
    "family": (20, ["{o} is blood. That settles most arguments and starts the rest.", "{o} and I share a roof and a temper. Mostly the temper."]),
    "friend": (15, ["{o} is good company and better at keeping quiet.", "I would trust {o} with a purse. A small one."]),
    "colleague": (10, ["{o} works hard and talks harder.", "{o} knows the trade. I will say that for {o}."]),
    "mentor": (20, ["{o} will be good, with a little less hurry.", "I teach {o} what I was taught. Slower, though."]),
    "rival": (-5, ["{o} undercuts me. I forgive {o}. Mostly.", "{o} has opinions about my prices. I have opinions about {o}."]),
    "debtor": (-8, ["{o} owes me and keeps promising. Promises are not coin.", "{o} will pay at harvest. I have heard which harvest."]),
    "neighbour": (5, ["{o} lives next door and hears everything I do.", "{o} keeps a tidy yard and an untidy mouth."]),
}


# --------------------------------------------------------------------------------------------- more roles and lines (town_roles.py)
from town_roles import EXTRA, NEW_ROLES, KIT_ROLES, ROLE_WORK  # noqa: E402,F401

for _role, (_g, _r) in EXTRA.items():
    _job, _kind, _greet, _rum = ROLES[_role]
    ROLES[_role] = (_job, _kind, list(_greet) + list(_g), list(_rum) + list(_r))
ROLES.update(NEW_ROLES)

# Where an identity's work happens: the first of the town's trade kits that has a place name here (else the archetype's own `works`).
WORKS_BY_KIT = {
    "quarry": "the quarry yard", "kilns": "the kilns", "wagons": "the wagon yard", "ferry": "the ferry landing", "boats": "the boat slip",
    "reeds": "the reed landing", "hunters": "the lodge yard", "caravan": "the caravan stage", "smokehouse": "the smokehouse yard",
    "bees": "the apiary", "candles": "the apiary", "forge_smoke": "the ore yard", "tannery": "the tannery yard", "ravens": "the raven tower yard",
    "glass": "the glass kiln", "lanterns": "the lamp pier", "salt": "the salt pans", "mills": "the mill yard", "dairy": "the dairy yard",
    "dyers": "the dye works", "guild": "the guild hall steps", "fair_green": "the fair green", "wool": "the fold", "stables": "the stable yard",
    "barracks": "the spear hall yard", "watch": "the watch post", "great_oak": "the great oak", "big_fields": "the south meadow", "herbs": "the herb walk",
}
