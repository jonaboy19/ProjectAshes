"""Quest lines for tools/towns/gen_town.py: three chained quests per town, drawn from five templates per slot and shaped by the
settlement's archetype, its trade kits, its size and its threat. Only objective types the town kit wires by itself are used
(goto, collect, deliver, talk_to, investigate, choose, kill: scripts/world/town_kit/town_hub.gd), so every line completes headless.

  slot A  an errand or an order      haul | standing order | two loads | long carry | winter table
  slot B  a small mystery            theft | witness | sabotage | contraband | taint
  slot C  the local threat           edge | tracks | intel | two waves | bait

Towns of one archetype take different templates (their rank among the towns of that archetype rotates the table), the
givers differ between slots, the objective order differs between templates (talk first, parallel stages, two stashes, a hand-over
somewhere else), and the stakes, goods, clues and threat sign come from per-archetype and per-species tables.
"""
import math

from town_text import THREAT_NAMES

# --------------------------------------------------------------------------------------------- goods (items that exist in data/items)
# per archetype: (item id, display name, count, stash prop, stash label, pick-up line). All ids are in data/items.json or data/items/*.json.
GOODS = {
    "farming": [("wheat", "sacks of wheat", 4, "sack", "Wheat sacks", "You shoulder four sacks of wheat from the pile."),
                ("barley", "sacks of barley", 4, "sack", "Barley sacks", "You tie four sacks of barley and swing them up."),
                ("flour", "sacks of flour", 3, "sack", "Flour sacks", "You carry three sacks of fresh flour out of the dust.")],
    "pastoral": [("wool", "fleeces", 4, "sack", "Fleece bundles", "You tie four fleeces into a bundle."),
                 ("cheese", "cheese wheels", 3, "crate", "Cheese wheels", "You lift three wheels from the cool shelf."),
                 ("butter", "crocks of butter", 3, "crate", "Butter crocks", "You stack three crocks in a carry-crate.")],
    "craft": [("cloth", "bolts of cloth", 3, "crate", "Bolts of cloth", "You lift three bolts of undyed cloth from the rack."),
              ("linen", "bolts of linen", 3, "crate", "Linen bolts", "You take three bolts of pale linen."),
              ("dye_red", "pots of red dye", 2, "crate", "Dye pots", "You wrap two pots of madder red in sacking.")],
    "mining": [("iron_ore", "lumps of iron ore", 4, "stone", "Ore pile", "You fill a sack with four lumps of good ore."),
               ("coal", "sacks of coal", 4, "sack", "Coal sacks", "You fill a sack with four lumps of hard coal."),
               ("stone", "cut blocks", 4, "stone", "Cut blocks", "You drag four trimmed blocks onto the barrow.")],
    "fortress": [("iron_ingot", "iron ingots", 3, "crate", "Ingot crate", "You lift three ingots from the stores crate."),
                 ("leather", "rolls of harness leather", 3, "crate", "Leather rolls", "You take three rolls of harness leather."),
                 ("plank", "planks", 4, "crate", "Plank stack", "You shoulder four planks of seasoned timber.")],
    "hunting": [("hides", "dry hides", 4, "sack", "Drying hides", "You roll four dry hides into a bundle."),
                ("venison", "cuts of venison", 3, "sack", "Hung venison", "You take three cuts of hung venison."),
                ("fur_bundle", "fur bundles", 3, "sack", "Fur bundles", "You tie three bundles of winter fur.")],
    "religious": [("firewood", "split logs", 4, "crate", "Woodpile", "You carry four split logs from the woodpile."),
                  ("candle", "candles", 4, "crate", "Candle box", "You take four tapers from the chandlery box."),
                  ("healing_herb", "bundles of herbs", 4, "sack", "Herb racks", "You gather four dry bundles of herbs.")],
    "merchant": [("cloth", "bolts of sample cloth", 3, "crate", "Sample bolts", "You take three sample bolts from the stage crate."),
                 ("salt_sack", "sacks of salt", 2, "sack", "Salt sacks", "You heave two sacks of salt onto your shoulder."),
                 ("plank", "crated planks", 4, "crate", "Crated planks", "You carry four planks from the staging yard.")],
    "scholarly": [("coal", "sacks of kiln coal", 4, "sack", "Coal sacks", "You fill a sack with four lumps of kiln coal."),
                  ("sand", "sacks of fine sand", 4, "sack", "Sand sacks", "You scoop four measures of pale sand."),
                  ("glass", "glass blanks", 3, "crate", "Glass blanks", "You lift three cooled blanks from the annealing rack.")],
    "criminal": [("hides", "raw hides", 4, "sack", "Raw hides", "You bundle four raw hides, and wish you had not."),
                 ("rope", "coils of rope", 3, "sack", "Coiled rope", "You loop three coils over your shoulder."),
                 ("lamp_oil", "jars of lamp oil", 2, "crate", "Oil jars", "You wrap two jars of lamp oil in straw.")],
    "fishing": [("flax", "bundles of flax", 4, "sack", "Flax bales", "You bind four bundles of flax for the nets."),
                ("salt_sack", "sacks of salt", 2, "sack", "Salt sacks", "You heave two sacks of salt from the pan shed."),
                ("fish", "baskets of fish", 3, "sack", "Fish baskets", "You fill three baskets with good fish."),
                ("rope", "coils of rope", 3, "sack", "Rope coils", "You carry three coils of tarred rope.")],
    "royal": [("cloth", "bolts of banner cloth", 3, "crate", "Banner cloth", "You take three bolts of banner cloth."),
              ("candle", "hall candles", 4, "crate", "Hall candles", "You gather four tall candles from the chandlery."),
              ("ale", "casks of ale", 2, "crate", "Ale casks", "You roll two small casks onto the barrow.")],
}

# per trade kit (data/world/town_identity.json "kits"): goods that belong to that trade. They come before the archetype's own goods.
KIT_GOODS = {
    "wagons": [("plank", "planks of ash", 4, "crate", "Plank stack", "You shoulder four planks of seasoned ash."),
               ("iron_ingot", "bars of rim iron", 3, "crate", "Rim iron", "You lift three bars of rim iron.")],
    "quarry": [("stone", "cut blocks", 4, "stone", "Cut blocks", "You drag four trimmed blocks onto the barrow.")],
    "kilns": [("charcoal", "sacks of charcoal", 4, "sack", "Charcoal sacks", "You fill a sack with four lumps of charcoal."),
              ("firewood", "split logs", 4, "crate", "Woodpile", "You carry four split logs from the stack.")],
    "salt": [("salt_sack", "sacks of salt", 2, "sack", "Salt sacks", "You heave two sacks of salt from the pan shed."),
             ("fish", "baskets of fish", 3, "sack", "Fish baskets", "You fill three baskets with good fish.")],
    "boats": [("plank", "planks", 4, "crate", "Plank stack", "You shoulder four planks of boat timber."),
              ("rope", "coils of rope", 3, "sack", "Rope coils", "You carry three coils of tarred rope.")],
    "ferry": [("rope", "coils of rope", 3, "sack", "Rope coils", "You carry three coils of tarred rope."),
              ("plank", "planks", 4, "crate", "Plank stack", "You shoulder four planks of landing timber.")],
    "reeds": [("flax", "bundles of flax", 4, "sack", "Reed bundles", "You bind four bundles of cut reed and flax."),
              ("rope", "coils of rope", 3, "sack", "Rope coils", "You carry three coils of rope.")],
    "smokehouse": [("smoked_fish", "smoked fish", 4, "sack", "Smoke racks", "You lift four smoked fish from the rack."),
                   ("salt_sack", "sacks of salt", 2, "sack", "Salt sacks", "You heave two sacks of salt.")],
    "tannery": [("hides", "raw hides", 4, "sack", "Raw hides", "You bundle four raw hides."),
                ("leather", "rolls of leather", 3, "crate", "Leather rolls", "You take three rolls of cured leather.")],
    "glass": [("sand", "sacks of fine sand", 4, "sack", "Sand sacks", "You scoop four measures of pale sand."),
              ("glass", "glass blanks", 3, "crate", "Glass blanks", "You lift three cooled blanks from the annealing rack.")],
    "lanterns": [("lamp_oil", "jars of lamp oil", 2, "crate", "Oil jars", "You wrap two jars of lamp oil in straw."),
                 ("glass", "glass blanks", 3, "crate", "Glass blanks", "You lift three cooled blanks from the rack.")],
    "candles": [("candle", "candles", 4, "crate", "Candle box", "You take four tapers from the chandlery box.")],
    "bees": [("honey_barrel", "honey barrels", 2, "crate", "Honey barrels", "You roll two small honey barrels onto the barrow.")],
    "forge_smoke": [("coal", "sacks of coal", 4, "sack", "Coal sacks", "You fill a sack with four lumps of hard coal."),
                    ("iron_ore", "lumps of iron ore", 4, "stone", "Ore pile", "You fill a sack with four lumps of ore.")],
    "dairy": [("cheese", "cheese wheels", 3, "crate", "Cheese wheels", "You lift three wheels from the cool shelf."),
              ("butter", "crocks of butter", 3, "crate", "Butter crocks", "You stack three crocks in a carry-crate."),
              ("milk", "pails of milk", 3, "crate", "Milk pails", "You lift three pails of milk.")],
    "wool": [("wool", "fleeces", 4, "sack", "Fleece bundles", "You tie four fleeces into a bundle.")],
    "dyers": [("dye_red", "pots of red dye", 2, "crate", "Dye pots", "You wrap two pots of madder red in sacking."),
              ("dye_blue", "pots of woad blue", 2, "crate", "Dye pots", "You wrap two pots of woad blue in sacking."),
              ("cloth", "bolts of cloth", 3, "crate", "Bolts of cloth", "You lift three bolts of undyed cloth from the rack.")],
    "mills": [("flour", "sacks of flour", 3, "sack", "Flour sacks", "You carry three sacks of fresh flour out of the dust."),
              ("wheat", "sacks of wheat", 4, "sack", "Wheat sacks", "You shoulder four sacks of wheat from the pile.")],
    "granary": [("wheat", "sacks of wheat", 4, "sack", "Seed wheat", "You shoulder four sacks of wheat from the bin."),
                ("barley", "sacks of barley", 4, "sack", "Barley sacks", "You tie four sacks of barley and swing them up.")],
    "caravan": [("salt_sack", "sacks of salt", 2, "sack", "Salt sacks", "You heave two sacks of salt onto your shoulder."),
                ("cloth", "bolts of sample cloth", 3, "crate", "Sample bolts", "You take three sample bolts from the stage crate.")],
    "barracks": [("iron_ingot", "iron ingots", 3, "crate", "Ingot crate", "You lift three ingots from the stores crate."),
                 ("leather", "rolls of harness leather", 3, "crate", "Leather rolls", "You take three rolls of harness leather.")],
    "stables": [("leather", "rolls of harness leather", 3, "crate", "Leather rolls", "You take three rolls of harness leather."),
                ("barley", "sacks of feed barley", 4, "sack", "Feed sacks", "You swing four sacks of feed barley onto your shoulder.")],
    "hunters": [("venison", "cuts of venison", 3, "sack", "Hung venison", "You take three cuts of hung venison."),
                ("hides", "dry hides", 4, "sack", "Drying hides", "You roll four dry hides into a bundle."),
                ("fur_bundle", "fur bundles", 3, "sack", "Fur bundles", "You tie three bundles of winter fur.")],
    "herbs": [("healing_herb", "bundles of herbs", 4, "sack", "Herb racks", "You gather four dry bundles of herbs.")],
    "big_fields": [("wheat", "sacks of wheat", 4, "sack", "Wheat sacks", "You shoulder four sacks of wheat."),
                   ("barley", "sacks of barley", 4, "sack", "Barley sacks", "You tie four sacks of barley and swing them up.")],
    "great_oak": [("firewood", "split logs", 4, "crate", "Woodpile", "You carry four split logs from the oak-wood stack.")],
}

# gifts the giver adds to a quest's pay now and then: item id -> count
GIFTS = {"farming": ["bread", 2], "pastoral": ["cheese", 1], "craft": ["linen", 1], "mining": ["ale", 1], "fortress": ["bandage", 2],
         "hunting": ["venison", 1], "religious": ["candle", 2], "merchant": ["salt", 1], "scholarly": ["lamp_oil", 1],
         "criminal": ["ale", 1], "fishing": ["smoked_fish", 2], "royal": ["bread", 2]}

# --------------------------------------------------------------------------------------------- stakes (why it matters now)
STAKES = {
    "farming": ["before the rain turns the lane to soup", "before the tithe collector counts the barns", "before the harvest fair"],
    "pastoral": ["before the buyers come up the drove road", "before the fair opens on the green", "before the first frost"],
    "craft": ["before the guild inspector arrives", "before the festival orders are due", "before the dye vats cool"],
    "mining": ["before the next shift goes down", "before the carters leave for the forges", "before the foreman files his tally"],
    "fortress": ["before the next muster", "before the road officer rides through", "before the watch changes at dusk"],
    "hunting": ["before the cold sets in for good", "before the pelt buyers come through", "before the next hunt goes out"],
    "religious": ["before the vigil", "before the pilgrims arrive for the feast", "before the shrine's lamp burns low"],
    "merchant": ["before the caravan rolls at dawn", "before the guild audit", "before the roads turn bad"],
    "scholarly": ["before the next firing", "before the Academy's visitor arrives", "before the night work begins"],
    "criminal": ["before anyone asks", "before the next cart goes through", "before the pass closes"],
    "fishing": ["before the tide turns", "before the boats go out", "before the weather breaks"],
    "royal": ["before the Council sits", "before the tourney heats begin", "before the great market opens"],
}

# --------------------------------------------------------------------------------------------- the threat
LORE = {
    "wolf": {"sign": "tracks too big for a dog and fences torn outward", "sound": "howling closer every night", "where": "the tree line", "hunt": "thin the pack out"},
    "corrupted_wolf": {"sign": "tracks that change halfway across the mud", "sound": "a howl with something wrong in it", "where": "the burnt ground", "hunt": "put down the tainted pack"},
    "bog_toad": {"sign": "slime trails through flattened reeds", "sound": "croaking that stops when anyone comes near", "where": "the reed edge", "hunt": "clear the reed beds"},
    "ghoul": {"sign": "scratches in the spoil and frost where no frost should be", "sound": "knocking from where nothing lives", "where": "the old workings", "hunt": "lay them to rest"},
    "giant_wasp": {"sign": "paper nests under the eaves and stung livestock", "sound": "a drone that carries across the yards", "where": "the sheds past the last house", "hunt": "burn them out"},
}
OUTSKIRT_CLUES = {
    "wolf": [("tracks", "Large prints", "Prints too big for a dog, heading for the tree line."),
             ("bones", "Gnawed bones", "A dragged carcass. Teeth marks, not knife marks."),
             ("rag", "Torn fence", "A rail splintered outward, wool snagged on the edge.")],
    "corrupted_wolf": [("tracks", "Wrong prints", "Prints that start as a wolf's and end as something else."),
                       ("bones", "Blackened bones", "Bones with a tarry stain that does not wash off."),
                       ("scorch", "Scorched grass", "A ring of burnt grass where nothing living walked.")],
    "bog_toad": [("tracks", "Slime trail", "A glistening trail through flattened reeds, wide as a hand."),
                 ("bones", "Picked bones", "Fish bones heaped at the water's edge, unnaturally clean."),
                 ("rag", "Chewed net", "A net dragged half out of the water and chewed through.")],
    "ghoul": [("scorch", "Cold ground", "Frost on a patch of ground, out of season, in the shape of a body."),
              ("bones", "Scattered bones", "Bones and a rusted buckle dug up and scattered."),
              ("tracks", "Dragged marks", "Two deep furrows, as if something heavy was hauled by its heels.")],
    "giant_wasp": [("scorch", "Burnt comb", "A paper nest, half burned, the ash still warm."),
                   ("bones", "Husked carcass", "A dead rat, hollow, with a neat round hole in it."),
                   ("rag", "Stung glove", "A glove stained at the fingertips and swollen with something yellow.")],
}
BAIT = {"wolf": ("venison", "cuts of venison", 3, "sack", "Hung venison", "You take three cuts of hung venison for bait."),
        "corrupted_wolf": ("venison", "cuts of venison", 3, "sack", "Hung venison", "You take three cuts of hung venison for bait."),
        "bog_toad": ("fish", "baskets of fish", 3, "sack", "Fish baskets", "You fill three baskets with fish for bait."),
        "ghoul": ("lamp_oil", "jars of lamp oil", 2, "crate", "Oil jars", "You wrap two jars of lamp oil in straw."),
        "giant_wasp": ("lamp_oil", "jars of lamp oil", 2, "crate", "Oil jars", "You wrap two jars of lamp oil in straw.")}

# --------------------------------------------------------------------------------------------- clues of the small mysteries
CLUES = {
    "farming": [("sack", "Slit sack", "A sack by the door has been slit and sewn back up. It is lighter than it should be."),
                ("tracks", "Muddy prints", "Boot prints, one heel worn down, coming and going. They stop where the lane meets {works}."),
                ("ledger", "Altered count", "Someone re-inked a line of the count. The ink is newer than the page.")],
    "pastoral": [("sack", "Half-emptied sack", "A fleece sack half emptied behind the fold, the mouth re-tied in a hurry."),
                 ("tracks", "Hoof and boot", "Hoof prints mixed with boot prints. The animals were walked, not driven."),
                 ("lock", "Cut gate rope", "The gate rope is cut, not frayed. The edge is clean.")],
    "craft": [("rag", "Dyed rag", "A rag stained with a colour the shop does not mix. The stain is fresh."),
              ("lock", "Forced hasp", "The hasp was prised off and set back almost straight. The lock only looks shut."),
              ("ledger", "Altered count", "Someone re-inked a line of the count. The ink is newer than the page.")],
    "mining": [("stone", "Moved marker", "A survey stone sits a hand's width from its mark. The old socket is clean."),
               ("scorch", "Scorched prop", "A pit prop charred at the foot. Someone lit a small fire and stamped it out."),
               ("lock", "Cut chain", "A chain cut clean with a good tool and wrapped to look whole.")],
    "fortress": [("lock", "Oiled lock", "The armoury hasp was oiled before it was forced. Someone knew the lock."),
                 ("tracks", "Nailed boots", "Nailed boots, too clean for a recruit's. They stop at the drill-yard gate."),
                 ("ledger", "Altered roll", "One name on the roll is rubbed out and written over. Both names are in the same hand.")],
    "hunting": [("bones", "Skinning pile", "Pelt scraps and bones heaped behind the lodge. Fresh. Someone skins where we do not."),
                ("tracks", "Boot prints", "Boot prints, one heel worn down, coming and going. They stop at {works}."),
                ("lock", "Cut snare wire", "Snare wire cut with shears, not snapped.")],
    "religious": [("scorch", "Cold candle stub", "A candle stub on the sill, burned to the stump and doused with a thumb."),
                  ("ledger", "Offering ledger", "The offering count has two hands in it. One is the almoner's. The other is trying to be."),
                  ("rag", "Torn cloak", "A scrap of a pilgrim's cloak, caught on a nail far from the pilgrim road.")],
    "merchant": [("ledger", "Altered count", "Someone re-inked a line of the count. The ink is newer than the page."),
                 ("lock", "Forced hasp", "The hasp was prised off and set back almost straight. The lock only looks shut."),
                 ("sack", "Resealed sack", "A seal pressed twice in the same wax. The second press is crooked.")],
    "scholarly": [("scorch", "Scorched floor", "A circle of scorch on the kiln-yard stone, too neat for an accident."),
                  ("crate", "Opened crate", "A crate lid nailed back crooked. The nails are bright."),
                  ("ledger", "Altered log", "The kiln log skips an hour. It is the hour the glass vanished in.")],
    "criminal": [("lock", "Picked lock", "The lock is clean and oiled. A lock picked well looks better than one that is not."),
                 ("tracks", "Soft prints", "Prints in soft mud, shoes with the heels cut down. Someone who does not want to be followed."),
                 ("rag", "Dropped glove", "A good glove, left where nobody who owned it would drop it.")],
    "fishing": [("sack", "Salt-crusted sack", "A sack by the racks, crusted white, slit and loosely tied."),
                ("tracks", "Wet prints", "Wet prints, bare feet, from the water to the sheds and back."),
                ("rag", "Cut net", "A net cut clean, not torn. The cut edge is still wet.")],
    "royal": [("ledger", "Altered roll", "One line of the household roll was re-inked. The ink is newer than the page."),
              ("lock", "Opened case", "The case lock is whole. The seal inside is not."),
              ("rag", "Torn livery", "A scrap of livery thread caught on the stair, the wrong colour for any house in the keep.")],
}

# --------------------------------------------------------------------------------------------- the tables that pick templates
A_FOR = {"farming": ["haul", "order", "carry", "two"], "pastoral": ["two", "haul", "table", "order"], "craft": ["order", "two", "haul", "carry"],
         "mining": ["haul", "two", "carry", "order"], "fortress": ["order", "carry", "haul", "two"], "hunting": ["table", "haul", "two", "carry"],
         "religious": ["table", "order", "carry", "haul"], "merchant": ["two", "carry", "order", "haul"], "scholarly": ["order", "haul", "table", "two"],
         "criminal": ["carry", "two", "order", "table"], "fishing": ["two", "haul", "carry", "table"], "royal": ["carry", "order", "table", "two"]}
B_FOR = {"farming": ["theft", "taint", "witness"], "pastoral": ["witness", "taint", "theft"], "craft": ["sabotage", "theft", "witness"],
         "mining": ["sabotage", "witness", "theft"], "fortress": ["sabotage", "witness", "contraband"], "hunting": ["contraband", "witness", "theft"],
         "religious": ["taint", "witness", "theft"], "merchant": ["contraband", "sabotage", "theft"], "scholarly": ["sabotage", "witness", "theft"],
         "criminal": ["contraband", "theft", "witness"], "fishing": ["contraband", "taint", "theft"], "royal": ["witness", "theft", "contraband"]}
C_FOR = {"farming": ["edge", "tracks", "intel"], "pastoral": ["tracks", "bait", "edge"], "craft": ["edge", "intel", "bait"],
         "mining": ["tracks", "waves", "edge"], "fortress": ["waves", "intel", "edge"], "hunting": ["intel", "tracks", "waves"],
         "religious": ["edge", "bait", "tracks"], "merchant": ["intel", "edge", "waves"], "scholarly": ["tracks", "bait", "intel"],
         "criminal": ["intel", "tracks", "edge"], "fishing": ["bait", "tracks", "edge"], "royal": ["waves", "intel", "tracks"]}
# who a good is for: the roles that use it (the first one the town has receives it)
USERS = {
    "wheat": ["baker", "miller"], "flour": ["baker"], "barley": ["innkeeper", "stablehand", "baker"], "wool": ["spinner", "weaver", "wool buyer"],
    "cheese": ["cheesemaker", "innkeeper", "shopkeeper"], "butter": ["baker", "innkeeper", "shopkeeper"], "milk": ["cheesemaker", "dairymaid", "baker"],
    "cloth": ["weaver", "dyer", "cloth merchant", "trader", "court scribe"], "linen": ["weaver", "cloth merchant", "dyer"], "dye_red": ["dyer"], "dye_blue": ["dyer"],
    "iron_ore": ["smelter", "blacksmith"], "coal": ["smelter", "blacksmith", "glasswright"], "stone": ["mason", "quarryman"], "charcoal": ["blacksmith", "smelter"],
    "iron_ingot": ["blacksmith", "armourer", "wheelwright"], "leather": ["armourer", "stablehand", "tanner"], "plank": ["boatwright", "wheelwright", "mason", "armourer"],
    "hides": ["tanner"], "venison": ["innkeeper", "baker"], "fur_bundle": ["tanner", "trader"], "firewood": ["innkeeper", "baker", "blacksmith"],
    "candle": ["chaplain", "chandler"], "healing_herb": ["herbalist", "herbwife", "chaplain"], "salt_sack": ["salter", "innkeeper", "baker"],
    "sand": ["glasswright"], "glass": ["glasswright", "lamp-maker"], "rope": ["boatwright", "net mender", "rope-maker", "ferryman"],
    "lamp_oil": ["lamp-maker", "innkeeper"], "flax": ["net mender", "rope-maker", "weaver"], "fish": ["smoker", "innkeeper", "salter"],
    "smoked_fish": ["innkeeper", "shopkeeper"], "honey_barrel": ["chandler", "innkeeper", "baker"], "ale": ["innkeeper"],
}
HUNTER_ROLES = ["guard captain", "huntmaster", "hunter", "watch-commander", "soldier", "guard"]
WITNESS_ROLES = ["child", "elder", "innkeeper", "guard", "net mender", "stablehand"]


# --------------------------------------------------------------------------------------------- helpers

def first_of(n):
    return n.split(" ")[0]


def slug(s):
    import re
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


class Ctx:
    """What a template knows about its town."""

    def __init__(self, tid, name, arch, kit, kind, people, doc, species, fy, rng, rank, authority, landmark, town_scale):
        self.tid, self.name, self.arch, self.kit, self.kind = tid, name, arch, kit, kind
        self.people, self.doc, self.species, self.fy, self.rng, self.rank = people, doc, species, fy, rng, rank
        self.by_id = {p["id"]: p for p in people}
        self.authority_role = authority
        self.giver = next(p for p in people if p["role"] == authority)
        self.landmark = landmark
        self.scale = town_scale
        self.sing, self.plur = THREAT_NAMES.get(species, (species, species + "s"))
        self.lore = LORE[species]
        self.works_id = "%s_works" % tid
        self.outskirts = "%s_outskirts" % tid
        self.works = kit["works"]
        self.lots = {r["btype"]: r["bid"] for r in doc["lots"]["required"]}
        self.clues, self.stashes = [], []
        self.stakes = STAKES[arch][rank % len(STAKES[arch])]
        kits = (doc.get("identity") or {}).get("kits") or []
        self.kit_goods = []
        for k in kits:
            for g in KIT_GOODS.get(k, []):
                if g not in self.kit_goods:
                    self.kit_goods.append(g)
        self.goods = self.kit_goods + [g for g in GOODS[arch] if g[0] not in [x[0] for x in self.kit_goods]]

    def person(self, roles, avoid=(), fallback_roles=("shopkeeper", "baker", "innkeeper")):
        for rl in (roles, list(fallback_roles)):
            c = [p for p in self.people if p["role"] in rl and p["id"] not in avoid and (p["role"] != "child" or "child" in rl)]
            if c:
                return self.rng.choice(c)
        c = [p for p in self.people if p["role"] not in ("child", "elder") and p["id"] not in avoid]
        return self.rng.choice(c)

    def recv_for(self, item, avoid=()):
        """Who takes this good: a resident whose role uses it, else the archetype's usual receiver, else a keeper."""
        return self.person(USERS.get(item, []) + [self.kit["deliver_role"]], avoid)

    def good(self, k):
        """The k-th good of this town: its own trade's goods first (rotating with the town's rank), then the archetype's."""
        return self.goods[(k + self.rank % max(1, len(self.kit_goods))) % len(self.goods)]

    def at_works(self, avoid=()):
        """Residents whose work is the settlement's works site (the people at the far end of a carry)."""
        c = [p for p in self.people if p["work"] == self.works_id and p["role"] != "child" and p["id"] not in avoid]
        return c

    def gold(self, base):
        return int(round(base * self.scale))

    def reward(self, gold, rep, rel, label, days=60, giver=None, gift=False):
        g = giver or self.giver
        r = {"gold": self.gold(gold), "rep": {self.tid: rep}, "relationship": [{"npc": g["id"], "label": label, "value": rel, "days": days}]}
        if gift:
            item, n = GIFTS[self.arch]
            r["items"] = {item: n}
        return r

    def spot(self, k):
        """A building door for a clue or stash: the town's own buildings, then a home."""
        order = []
        for t in ("general_shop", "smithy", "tavern", "bakery", "healer", "guard_post"):
            if t in self.lots:
                order.append((self.lots[t], [[1.4, 0.8], [-1.4, 0.8], [1.4, -0.8]][k % 3]))
        order.append((self.works_id, [-1.6, 0.6]))
        homes = max(1, int(self.doc["lots"].get("homes", 1)))
        order.append(("%s_house_%d" % (self.tid, (1 + k) % homes + 1), [1.2, 0.8]))
        return order[(k + self.rank) % len(order)]

    def add_clue(self, key, prop, target, note, where=None, k=0):
        b = where or self.spot(k)
        c = {"id": "%s/clue/%s" % (self.tid, key), "target": target, "note": note.format(works=self.works, thing=self.sing), "prop": prop, "h": 0.0}
        if isinstance(b, dict):
            c.update(b)
        else:
            c["building"], c["at"] = b[0], b[1]
        self.clues.append(c)
        return c["id"]

    def out_clue(self, key, k, prop, target, note):
        """A clue near the outskirts place: around its (settlement-relative) point, nudged to dry ground by the kit."""
        oc = self.doc["places"][2]["at"]
        a = math.tau * (k / 3.0) + 0.9
        at = [round(oc[0] + 9.0 * math.cos(a)), round(oc[1] + 9.0 * math.sin(a))]
        return self.add_clue(key, prop, target, note, where={"anchor": "town", "at": at, "dry": True})

    def stash(self, key, good, quest, stage, where=None, k=0):
        item, nm, n, prop, label, say = good
        c = {"id": "%s/stash/%s" % (self.tid, key), "item": item, "count": n, "quest": quest, "stage": stage, "target": label, "say": say, "prop": prop}
        if where == "works" or where is None:
            c.update({"anchor": "landmark", "at": [-4.0 + 2.0 * k, round(self.fy - 4.0, 1)]})
        else:
            c.update({"building": where[0], "at": where[1]})
        self.stashes.append(c)


# --------------------------------------------------------------------------------------------- objectives and stages

def goto(oid, place, text):
    return {"id": oid, "type": "goto", "place": place, "text": text}


def collect(oid, item, n, text):
    return {"id": oid, "type": "collect", "item": item, "count": n, "text": text}


def deliver(oid, item, n, to, text):
    return {"id": oid, "type": "deliver", "item": item, "count": n, "to": to, "text": text}


def talk(oid, npc, text):
    return {"id": oid, "type": "talk_to", "npc": npc, "text": text}


def investigate(oid, clue_ids, n, text):
    return {"id": oid, "type": "investigate", "clues": clue_ids, "count": n, "text": text}


def kill(oid, species, place, n, text):
    return {"id": oid, "type": "kill", "target": species, "place": place, "count": n, "text": text}


def stage(sid, title, mode, objs, end=False, rewards=None, branches=None):
    s = {"id": sid, "title": title, "mode": mode, "objectives": objs}
    if end:
        s["end"] = True
    if rewards:
        s["rewards"] = rewards
    if branches:
        s["branches"] = branches
    return s


def quest(c, qid, title, summary, giver, offer, stages, rewards=None, turn_in=None, requires=None):
    q = {"id": qid, "title": title, "summary": summary, "giver": {"npc": giver["id"], "name": giver["name"], "place": c.tid}}
    if requires:
        q["requires"] = requires
    q["offer_text"] = offer
    if turn_in:
        q["turn_in_text"] = turn_in
    q["stages"] = stages
    if rewards:
        q["rewards"] = rewards
    return q


def Q(s):
    return '"%s"' % s


def tc(s):
    """Title case that keeps the small words small: "the tree line" -> "the Tree Line"."""
    return " ".join(w if w in ("the", "at", "of", "and") else w.capitalize() for w in s.split())


# --------------------------------------------------------------------------------------------- slot A: errands and orders

def tv(c, options, salt=0):
    """A title variant: stable for the town, different between neighbours."""
    return options[(c.rank + sum(ord(ch) for ch in c.tid) + salt) % len(options)]


def a_haul(c, qid, requires):
    item, nm, n, prop, label, say = c.good(0)
    recv = c.recv_for(item, (c.giver["id"],))
    gf = first_of(c.giver["name"])
    title = "%s for the %s" % (tc(nm), tc(recv["role"]))
    c.stash("a", c.good(0), qid, "fetch")
    st = [stage("fetch", "Fetch the stock", "sequence", [goto("reach", c.works_id, "Go to %s" % c.works), collect("gather", item, n, "Take %d %s from the pile" % (n, nm))]),
          stage("deliver", "Take it to %s" % recv["name"], "all", [deliver("hand_over", item, n, recv["id"], "Hand the %s to %s" % (nm, recv["name"]))]),
          stage("report", "Tell %s" % gf, "all", [talk("report", c.giver["id"], "Tell %s it is done" % c.giver["name"])], end=True)]
    return quest(c, qid, title, "%s wants %d %s from %s taken to %s %s, and then a word." % (c.giver["name"], n, nm, c.works, recv["name"], c.stakes), c.giver,
                 Q("We need %s, and what is stacked at %s is the town's to take. Carry it to %s %s, then come and tell me." % (nm, c.works, recv["name"], c.stakes)),
                 st, c.reward(14, 3, 8, "Ran an errand for the town", 45, gift=c.rank % 2 == 0), Q("Good. That is one thing in %s that goes right." % c.name), requires)


def a_order(c, qid, requires):
    item, nm, n, prop, label, say = c.good(1)
    recv = c.recv_for(item, (c.giver["id"],))
    title = "%s on Order" % tc(nm)
    c.stash("a", c.good(1), qid, "gather")
    st = [stage("order", "Hear the order", "all", [talk("hear", recv["id"], "Hear what %s needs" % recv["name"])]),
          stage("gather", "Gather the stock", "all", [collect("gather", item, n, "Take %d %s from %s" % (n, nm, c.works))]),
          stage("deliver", "Fill the order", "all", [deliver("fill", item, n, recv["id"], "Hand the %s to %s" % (nm, recv["name"]))], end=True)]
    return quest(c, qid, title, "%s says %s has an order for %d %s that cannot wait. The stock is at %s, and the deadline is %s." % (c.giver["name"], recv["name"], n, nm, c.works, c.stakes), c.giver,
                 Q("%s has an order and nobody to fetch it. Hear %s out, then bring the goods from %s %s. I will vouch for you." % (recv["name"], first_of(recv["name"]), c.works, c.stakes)),
                 st, c.reward(16, 3, 8, "Filled a standing order", 45, gift=c.rank % 2 == 1), None, requires)


def a_two(c, qid, requires):
    g1, g2 = c.good(0), c.good(1)
    if g1[0] == g2[0]:
        g2 = next(g for g in c.goods if g[0] != g1[0])
    r1 = c.recv_for(g1[0], (c.giver["id"],))
    r2 = c.recv_for(g2[0], (c.giver["id"], r1["id"]))
    title = "%s and %s" % (tc(g1[1]), tc(g2[1]))
    c.stash("a1", g1, qid, "gather")
    c.stash("a2", g2, qid, "gather", where=c.spot(1), k=1)
    st = [stage("gather", "Gather both loads", "all", [collect("load1", g1[0], g1[2], "Take %d %s from %s" % (g1[2], g1[1], c.works)),
                                                      collect("load2", g2[0], g2[2], "Take %d %s from the second stack" % (g2[2], g2[1]))]),
          stage("deliver", "Deliver them", "all", [deliver("to1", g1[0], g1[2], r1["id"], "Hand the %s to %s" % (g1[1], r1["name"])),
                                                   deliver("to2", g2[0], g2[2], r2["id"], "Hand the %s to %s" % (g2[1], r2["name"]))]),
          stage("report", "Tell %s" % first_of(c.giver["name"]), "all", [talk("report", c.giver["id"], "Tell %s both are in" % c.giver["name"])], end=True)]
    return quest(c, qid, title, "Two loads wait in %s: %s for %s and %s for %s. %s wants them moved %s." % (c.name, g1[1], r1["name"], g2[1], r2["name"], c.giver["name"], c.stakes), c.giver,
                 Q("Two things are late and both are mine to answer for. %s waits on %s and %s on %s. Fetch them in any order, %s." % (r1["name"], g1[1], r2["name"], g2[1], c.stakes)),
                 st, c.reward(20, 4, 9, "Cleared two late loads", 60, gift=True), Q("Both in. I shall sleep tonight, which is rare."), requires)


def a_carry(c, qid, requires):
    item, nm, n, prop, label, say = c.good(2)
    far = c.at_works((c.giver["id"],))
    recv = c.rng.choice(far) if far else c.person([c.kit["deliver_role"]], (c.giver["id"],))
    title = tv(c, ["A Long Carry", "Across Town", "Carry It Over"])
    c.stash("a", c.good(2), qid, "load", where=(c.giver["home"], [1.3, 0.9]))
    st = [stage("load", "Collect the stock", "all", [collect("load", item, n, "Take %d %s from outside %s's door" % (n, nm, first_of(c.giver["name"])))]),
          stage("carry", "Carry it across town", "sequence", [goto("cross", c.works_id, "Walk to %s" % c.works), deliver("drop", item, n, recv["id"], "Hand the %s to %s" % (nm, recv["name"]))], end=True)]
    return quest(c, qid, title, "%s wants %d %s carried from the far end of %s to %s at %s %s." % (c.giver["name"], n, nm, c.name, recv["name"], c.works, c.stakes), c.giver,
                 Q("The %s are by my door and %s is waiting at %s. It is a long walk and I have a bad knee. Take them over %s." % (nm, recv["name"], c.works, c.stakes)),
                 st, c.reward(15, 3, 7, "Carried the load across town", 45), None, requires)


def a_table(c, qid, requires):
    item, nm, n, prop, label, say = c.good(1)
    elder = c.person(["elder"], (c.giver["id"],))
    title = "A Table for %s" % first_of(elder["name"])
    c.stash("a", c.good(1), qid, "ask")
    st = [stage("ask", "Look after %s" % first_of(elder["name"]), "all", [talk("visit", elder["id"], "Visit %s and ask what is wanted" % elder["name"]),
                                                                          collect("gather", item, n, "Take %d %s from %s" % (n, nm, c.works))]),
          stage("bring", "Bring it", "all", [deliver("bring", item, n, elder["id"], "Hand the %s to %s" % (nm, elder["name"]))], end=True)]
    return quest(c, qid, title, "%s says %s is going short. %d %s and a visit would help, %s." % (c.giver["name"], elder["name"], n, nm, c.stakes), c.giver,
                 Q("%s will not ask, so I am asking for them. Go and see what is wanted, and bring %s %s. The stock at %s is the town's, and this is what it is for." % (elder["name"], nm, c.stakes, c.works)),
                 st, c.reward(10, 5, 14, "Looked after the old folk", 90, gift=True), Q("Thank you. It is the small things that keep a town."), requires)


# --------------------------------------------------------------------------------------------- slot B: small mysteries

def _clues3(c, k0=0):
    ids = []
    for k, (prop, target, note) in enumerate(CLUES[c.arch]):
        ids.append(c.add_clue("c%d" % (k + 1), prop, target, note, k=k + k0))
    return ids


def b_theft(c, qid, requires):
    thing = c.kit["thing"]
    suspect = c.person(c.kit["suspect"], (c.giver["id"],))
    sf = first_of(suspect["name"])
    gf = first_of(c.giver["name"])
    ids = _clues3(c)
    title = c.kit["b_title"]
    st = [stage("look", "Look for signs", "all", [investigate("clues", ids, 3, "Search the doors around town for signs")]),
          stage("question", "Ask %s" % sf, "all", [talk("question", suspect["id"], "Ask %s what they know" % suspect["name"])]),
          stage("decide", "Decide what to do", "all", [{"id": "verdict", "type": "choose", "npc": c.giver["id"], "options": [
              {"id": "report", "text": "Tell %s what you found" % gf, "say": "%s nods slowly. \"Then it is on the record.\"" % gf},
              {"id": "quiet", "text": "Take %s's quiet word and say nothing" % sf, "say": "%s presses a few coins into your hand. \"Good sense.\"" % sf}]}],
                branches={"report": "reported", "quiet": "hushed"}),
          stage("reported", "%s hears it" % gf, "all", [talk("told", c.giver["id"], "Tell %s who it was" % c.giver["name"])], end=True,
                rewards=c.reward(20, 6, 12, "Told the truth about the theft", 90)),
          stage("hushed", "Collect the hush money", "all", [talk("quiet", suspect["id"], "Collect %s's thanks" % sf)], end=True,
                rewards={"gold": c.gold(35), "rep": {c.tid: -6}, "relationship": [{"npc": c.giver["id"], "label": "Heard you looked the other way", "value": -12, "days": 90}]})]
    return quest(c, qid, title, "The stores of %s are missing %s. %s wants to know whether it is carelessness or a person." % (c.name, thing, c.giver["name"]), c.giver,
                 Q("I am missing %s from the stores and I have counted twice. Look around the doors in town. Someone was careless, or someone was not." % thing),
                 st, None, None, requires)


def b_witness(c, qid, requires):
    gv = c.person(["innkeeper", "shopkeeper"], (c.giver["id"],))
    wit = c.person(WITNESS_ROLES, (gv["id"], c.giver["id"]), ("elder", "child"))
    cul = c.person(c.kit["suspect"], (gv["id"], wit["id"], c.giver["id"]))
    wf, cf, gf = first_of(wit["name"]), first_of(cul["name"]), first_of(gv["name"])
    ids = _clues3(c, 1)
    title = tv(c, ["What %s Saw", "%s Will Not Say It Loud", "The Word of %s"]) % wf
    st = [stage("ask", "Hear %s out" % wf, "all", [talk("hear", wit["id"], "Ask %s what they saw" % wit["name"])]),
          stage("look", "Check the story", "all", [investigate("clues", ids, 2, "Find two signs that match what %s said" % wf)]),
          stage("decide", "Say what you will do", "all", [{"id": "verdict", "type": "choose", "npc": gv["id"], "options": [
              {"id": "name", "text": "Name %s to %s" % (cf, gf), "say": "%s goes quiet. \"I will deal with it. Openly.\"" % gf},
              {"id": "warn", "text": "Warn %s quietly and leave it" % cf, "say": "%s will owe you. You can see it in the shoulders." % cf}]}],
                branches={"name": "named", "warn": "warned"}),
          stage("named", "%s hears it" % gf, "all", [talk("told", gv["id"], "Tell %s it is settled" % gv["name"])], end=True,
                rewards=c.reward(18, 5, 12, "Named the culprit", 90, giver=gv)),
          stage("warned", "Let %s know" % cf, "all", [talk("warned", cul["id"], "Tell %s you kept it quiet" % cul["name"])], end=True,
                rewards={"gold": c.gold(25), "rep": {c.tid: -2}, "relationship": [{"npc": cul["id"], "label": "Kept quiet about it", "value": 15, "days": 120}]})]
    return quest(c, qid, title, "Something went wrong at night in %s, and %s says %s saw it. %s wants it checked before names are said." % (c.name, gv["name"], wit["name"], gv["name"]), gv,
                 Q("Somebody was in my place after dark. %s saw something and will not say it loud. Hear %s, then see if the story holds." % (wit["name"], wf)),
                 st, None, None, requires)


def b_sabotage(c, qid, requires):
    rival = c.person(c.kit["suspect"], (c.giver["id"],))
    foreman = c.person([c.kit["deliver_role"]], (c.giver["id"], rival["id"]))
    rf, gf = first_of(rival["name"]), first_of(c.giver["name"])
    ids = _clues3(c, 2)
    title = tv(c, ["Someone Has Been at %s", "Moved in the Night at %s", "Tampered Work at %s"]) % tc(c.works)
    st = [stage("survey", "Survey the damage", "all", [investigate("clues", ids, 3, "Search around town for signs of tampering"),
                                                      talk("foreman", foreman["id"], "Hear %s's side of it" % foreman["name"])]),
          stage("decide", "Decide who to believe", "all", [{"id": "verdict", "type": "choose", "npc": c.giver["id"], "options": [
              {"id": "accuse", "text": "Tell %s it was %s" % (gf, rf), "say": "%s's jaw sets. \"I thought as much.\"" % gf},
              {"id": "cover", "text": "Tell %s it was an accident" % gf, "say": "%s breathes out. \"Then it was.\"" % gf}]}],
                branches={"accuse": "accused", "cover": "covered"}),
          stage("accused", "Face %s" % rf, "all", [talk("face", rival["id"], "Tell %s what you told %s" % (rival["name"], gf))], end=True,
                rewards=c.reward(22, 4, 10, "Found who tampered with the works", 90)),
          stage("covered", "Back to work", "all", [talk("calm", c.giver["id"], "Tell %s it is over" % c.giver["name"])], end=True,
                rewards={"gold": c.gold(12), "rep": {c.tid: 2}, "relationship": [{"npc": rival["id"], "label": "Took the blame off me", "value": 14, "days": 120}]})]
    return quest(c, qid, title, "Things at %s were moved, spoiled or broken in the night. %s wants to know if it was an accident or a person." % (c.works, c.giver["name"]), c.giver,
                 Q("Somebody has been at %s. Not a slip, I think. Walk the town, hear %s, and tell me what you make of it." % (c.works, foreman["name"])),
                 st, None, None, requires)


def b_contraband(c, qid, requires):
    tipster = c.person(["go-between", "trader", "trapper", "fisher", "innkeeper"], (c.giver["id"],))
    gv = c.person(["guard captain", "watch-commander", "huntmaster", "guard", "soldier"], (tipster["id"],))
    cul = c.person(c.kit["suspect"], (gv["id"], tipster["id"]))
    tf, gf = first_of(tipster["name"]), first_of(gv["name"])
    ids = [c.out_clue("o%d" % (k + 1), k, p, t, n) for k, (p, t, n) in enumerate(OUTSKIRT_CLUES[c.species][:2])]
    ids.append(c.add_clue("c3", CLUES[c.arch][0][0], CLUES[c.arch][0][1], CLUES[c.arch][0][2], k=3))
    title = tv(c, ["Quiet Goods", "Goods Without a Count", "A Cart at Night", "Off the Books"])
    st = [stage("tip", "Hear the tip", "all", [talk("tip", tipster["id"], "Hear what %s has to sell" % tipster["name"])]),
          stage("watch", "Watch the edge", "all", [goto("edge", c.outskirts, "Go to the edge of %s where the carts do not stop" % c.name)]),
          stage("find", "Find what was left", "all", [investigate("clues", ids, 2, "Find two signs of what passed through")]),
          stage("decide", "Decide what it is worth", "all", [{"id": "verdict", "type": "choose", "npc": gv["id"], "options": [
              {"id": "turn_in", "text": "Tell %s what you found" % gf, "say": "%s writes it down. \"This will matter.\"" % gf},
              {"id": "cut", "text": "Take %s's cut and forget the road" % tf, "say": "%s pays you without counting. \"Obliged.\"" % tf}]}],
                branches={"turn_in": "filed", "cut": "cut"}),
          stage("filed", "%s has it" % gf, "all", [talk("filed", gv["id"], "Tell %s who is behind it" % gv["name"])], end=True,
                rewards=c.reward(26, 6, 12, "Reported the contraband", 90, giver=gv)),
          stage("cut", "Take your share", "all", [talk("share", tipster["id"], "Collect your share from %s" % tipster["name"])], end=True,
                rewards={"gold": c.gold(45), "rep": {c.tid: -7}, "relationship": [{"npc": gv["id"], "label": "Heard you took a cut", "value": -14, "days": 90}]})]
    return quest(c, qid, title, "Goods are passing %s at night without a count. %s knows, and %s can show where it goes." % (c.name, gv["name"], tipster["name"]), gv,
                 Q("Goods come through at night and nobody counts them. %s says %s can point at the road. See what is left on it, then decide what it is worth." % (tipster["name"], tf)),
                 st, None, None, requires)


def b_taint(c, qid, requires):
    heal = c.person(["herbalist", "herbwife", "chaplain", "baker"], (c.giver["id"],))
    hf = first_of(heal["name"])
    ids = _clues3(c, 3)
    herb = ("healing_herb", "bundles of herbs", 3, "sack", "Herb bundles", "You pick three clean bundles of the healer's herbs.")
    title = tv(c, ["A Sour Turn", "Something in the Water", "The Sickness at the Door"])
    c.stash("b", herb, qid, "samples", where=c.spot(2), k=2)
    st = [stage("look", "Find the source", "all", [investigate("clues", ids, 3, "Look around town for what could have soured it")]),
          stage("samples", "Fetch the remedy", "all", [collect("herbs", herb[0], herb[2], "Take %d %s" % (herb[2], herb[1]))]),
          stage("deliver", "Bring it to %s" % hf, "all", [deliver("remedy", herb[0], herb[2], heal["id"], "Hand the herbs to %s" % heal["name"])]),
          stage("report", "Tell %s" % first_of(c.giver["name"]), "all", [talk("report", c.giver["id"], "Tell %s what you found" % c.giver["name"])], end=True)]
    return quest(c, qid, title, "Food and drink are turning in %s, and people are sick. %s needs the cause found and %s needs herbs." % (c.name, c.giver["name"], heal["name"]), c.giver,
                 Q("Milk, wells, stores, something is turning in this town. Find the source, then take %s the herbs they need. I do not want to say poison yet." % hf),
                 st, c.reward(22, 6, 12, "Helped when folk fell ill", 90, gift=True), Q("You have done more than you know. I will see this is not forgotten."), requires)


# --------------------------------------------------------------------------------------------- slot C: the threat

def _scout(c, avoid=()):
    """Someone who knows the edge of town: the watch, a hunter, else a carter or a farmer (never the quest's own giver)."""
    return c.person(HUNTER_ROLES, tuple(avoid) + (c.giver["id"],), ("carter", "farmer", "shepherd", "woodcutter", "fisher", "miner", "laborer"))


def _n_kill(c):
    return 3 if c.doc["kind"] in ("town", "frontier_town", "castle") else 2


def c_edge(c, qid, requires):
    n = _n_kill(c)
    gf = first_of(c.giver["name"])
    title = tv(c, ["%s at %s" % (tc(c.plur), tc(c.lore["where"])), "Thinning the %s" % tc(c.plur), "%s Near %s" % (tc(c.plur), c.name)])
    st = [stage("edge", "Go to the edge of town", "all", [goto("reach", c.outskirts, "Go to where the %s were seen" % c.plur)]),
          stage("hunt", "Thin them out", "all", [kill("hunt", c.species, c.outskirts, n, "Kill %d %s near %s" % (n, c.plur, c.name))]),
          stage("report", "Tell %s" % gf, "all", [talk("report", c.giver["id"], "Tell %s it is done" % c.giver["name"])], end=True)]
    return quest(c, qid, title, "%s sign has been found at the edge of %s: %s. %s wants %d of them dealt with." % (c.sing.capitalize(), c.name, c.lore["sign"], c.giver["name"], n), c.giver,
                 Q("The %s have come closer to %s each night: %s. Go to the edge and thin them out, before someone is hurt." % (c.plur, c.name, c.lore["sound"])),
                 st, c.reward(25, 5, 10, "Kept the %s from the edge" % c.plur, 60, gift=True), Q("Quieter already. I will sleep tonight. A little."), requires)


def c_tracks(c, qid, requires):
    n = _n_kill(c)
    gv = _scout(c)
    gf = first_of(gv["name"])
    ids = [c.out_clue("t%d" % (k + 1), k, p, t, nt) for k, (p, t, nt) in enumerate(OUTSKIRT_CLUES[c.species])]
    title = tv(c, ["Sign at %s" % tc(c.lore["where"]), "Prints Near %s" % c.name, "What Walks at %s" % tc(c.lore["where"])], 1)
    st = [stage("read", "Read the sign", "all", [investigate("sign", ids, 2, "Find two signs of the %s around the edge of %s" % (c.plur, c.name))]),
          stage("hunt", "Deal with them", "all", [kill("hunt", c.species, c.outskirts, n, "Kill %d %s near %s" % (n, c.plur, c.name))]),
          stage("report", "Tell %s" % gf, "all", [talk("report", gv["id"], "Tell %s what you found" % gv["name"])], end=True)]
    return quest(c, qid, title, "%s says something is out at the edge of %s: %s. Learn what it is, then put it down." % (gv["name"], c.name, c.lore["sign"]), gv,
                 Q("There is sign at %s: %s. I cannot tell how many, or how bold. Read it for me, and then put them down." % (c.lore["where"], c.lore["sign"])),
                 st, c.reward(27, 5, 11, "Read the sign and acted on it", 60, giver=gv), Q("Now we know what we are dealing with, and it is dealt with."), requires)


def c_intel(c, qid, requires):
    n = _n_kill(c)
    gv = c.giver
    scout = _scout(c)
    sf = first_of(scout["name"])
    title = tv(c, ["A Warning from %s" % sf, "%s Has Seen Something" % sf, "Word from %s" % sf], 2)
    st = [stage("hear", "Hear the warning", "all", [talk("warning", scout["id"], "Hear what %s has seen" % scout["name"])]),
          stage("edge", "Go and see", "all", [goto("reach", c.outskirts, "Go to %s" % c.lore["where"])]),
          stage("hunt", "Put them down", "all", [kill("hunt", c.species, c.outskirts, n, "Kill %d %s near %s" % (n, c.plur, c.name))]),
          stage("report", "Tell %s" % first_of(gv["name"]), "all", [talk("report", gv["id"], "Tell %s it is done" % gv["name"])], end=True)]
    return quest(c, qid, title, "%s has seen %s at the edge of %s, and %s wants someone to act before the town hears it from the %s." % (scout["name"], c.plur, c.name, gv["name"], c.plur), gv,
                 Q("%s has been out past the last house and does not like what they saw. Hear it, go and look, and %s." % (scout["name"], c.lore["hunt"])),
                 st, c.reward(28, 6, 11, "Acted on the warning", 60), Q("Good. Now the rest of the town can sleep."), requires)


def c_waves(c, qid, requires):
    n1, n2 = (2, 2) if c.doc["kind"] == "village" else (3, 2)
    gv = _scout(c)
    gf = first_of(gv["name"])
    title = tv(c, ["Two Nights of %s" % tc(c.plur), "%s in Waves" % tc(c.plur), "Breaking the %s" % tc(c.plur)], 3)
    st = [stage("first", "The first of them", "all", [kill("first", c.species, c.outskirts, n1, "Kill %d %s near %s" % (n1, c.plur, c.name))]),
          stage("word", "Report and listen", "all", [talk("word", gv["id"], "Tell %s the first are down" % gv["name"])]),
          stage("second", "The rest", "all", [kill("second", c.species, c.outskirts, n2, "Kill %d more %s at the edge" % (n2, c.plur))]),
          stage("done", "Tell %s" % gf, "all", [talk("done", gv["id"], "Tell %s the edge is clear" % gv["name"])], end=True)]
    return quest(c, qid, title, "The %s come in waves: %s. %s wants the first wave broken and then the second, with a word between them." % (c.plur, c.lore["sound"], gv["name"]), gv,
                 Q("It is not one pack, it is two nights of them, %s. Break the first and come and tell me. Then we finish it." % c.lore["sound"]),
                 st, c.reward(30, 6, 12, "Held the line against the %s" % c.plur, 60, giver=gv, gift=True), Q("That is two waves broken. I will not say it is over, but I will say it is quiet."), requires)


def c_bait(c, qid, requires):
    n = _n_kill(c)
    bait = BAIT[c.species]
    gv = _scout(c)
    title = tv(c, ["Bait at %s" % tc(c.lore["where"]), "A Smell for the %s" % tc(c.plur), "Setting the Lure"], 4)
    c.stash("c", bait, qid, "lure", where=c.spot(3), k=3)
    st = [stage("lure", "Get the bait", "all", [collect("bait", bait[0], bait[2], "Take %d %s" % (bait[2], bait[1]))]),
          stage("edge", "Set it out", "all", [goto("reach", c.outskirts, "Go to %s and set the bait" % c.lore["where"])]),
          stage("hunt", "Wait for them", "all", [kill("hunt", c.species, c.outskirts, n, "Kill %d %s that come for it" % (n, c.plur))]),
          stage("report", "Tell %s" % first_of(gv["name"]), "all", [talk("report", gv["id"], "Tell %s it worked" % gv["name"])], end=True)]
    return quest(c, qid, title, "%s wants the %s drawn out of %s with bait and put down at the edge of %s." % (gv["name"], c.plur, c.lore["where"], c.name), gv,
                 Q("They will not come to a trap but they will come to a smell. Take %s, set it at %s, and see what turns up." % (bait[1], c.lore["where"])),
                 st, c.reward(26, 5, 11, "Baited and dealt with the %s" % c.plur, 60, giver=gv), Q("Cunning. I should have thought of it myself."), requires)


TEMPLATES = {
    "A": {"haul": a_haul, "order": a_order, "two": a_two, "carry": a_carry, "table": a_table},
    "B": {"theft": b_theft, "witness": b_witness, "sabotage": b_sabotage, "contraband": b_contraband, "taint": b_taint},
    "C": {"edge": c_edge, "tracks": c_tracks, "intel": c_intel, "waves": c_waves, "bait": c_bait},
}


def build_line(c):
    """The town's three quests, in order: (quests, clues, stashes). Slot A's giver is the authority."""
    picks = [A_FOR[c.arch][c.rank % len(A_FOR[c.arch])], B_FOR[c.arch][c.rank % len(B_FOR[c.arch])], C_FOR[c.arch][c.rank % len(C_FOR[c.arch])]]
    out = []
    prev = None
    for slot, key in zip("ABC", picks):
        fn = TEMPLATES[slot][key]
        tmp_id = "tmp"
        q = fn(c, tmp_id, [prev] if prev else None)
        qid = "%s_%s" % (c.tid, slug(q["title"]))
        # stashes were created with a placeholder quest id: point them at the real one
        for s in c.stashes:
            if s["quest"] == tmp_id:
                s["quest"] = qid
        q["id"] = qid
        out.append(q)
        prev = qid
    return out, c.clues, c.stashes, picks
