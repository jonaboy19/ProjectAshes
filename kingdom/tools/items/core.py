"""Shared registry for the Region 1 item generator (tools/items/build.py).

Everything is data: add() registers an item, craft() a recipe. Crafted items may leave
price=None and get it derived from their recipe inputs (price_of), so prices stay
consistent with materials by construction.
"""
import json
import os
import collections

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")

with open(os.path.join(DATA, "items.json")) as f:
    LEGACY = json.load(f)

with open(os.path.join(DATA, "recipes.json")) as f:
    LEGACY_RECIPES = json.load(f)

# gathering_items.gd registers these at runtime; recipes may use them as inputs.
GATHERED = {
    "venison": 5, "rabbit_meat": 3, "pork": 4, "perch": 2, "trout": 4, "pike": 7, "emberfin": 30,
    "mushroom": 2, "wild_berries": 1, "healing_herb": 3, "deer_hide": 9, "fox_pelt": 10, "boar_tusk": 7,
}

ITEMS = collections.OrderedDict()     # id -> props (no underscore keys in output)
FILE_OF = {}                          # id -> data/items/<file>.json
ICON = {}                             # id -> (glyph name, tint hex)
RECIPES = []
SALVAGE = []
RECIPE_OUT = {}                       # output item -> recipe (first wins)
SKILL_LEVEL_CAP = 10

RARITY_NAMES = ["common", "uncommon", "rare", "epic", "legendary"]


def exists(item_id):
    return item_id in ITEMS or item_id in LEGACY or item_id in GATHERED


def add(item_id, name, cat, file, price=None, stack=20, weight=0.3, rarity=0, level=1,
        desc="", tint="#e8e0d0", glyph=None, **extra):
    """Register an item. Existing (legacy) ids are never overwritten; they are only noted for recipes."""
    if item_id in LEGACY or item_id in GATHERED:
        return None
    if item_id in ITEMS:
        raise ValueError("duplicate item id %s" % item_id)
    d = collections.OrderedDict()
    d["name"] = name
    d["category"] = cat
    if price is not None:
        d["price"] = int(price)
    d["max_stack_size"] = int(stack)
    d["weight"] = round(float(weight), 2)
    d["rarity"] = int(rarity)
    d["level"] = int(level)
    if desc:
        d["description"] = desc
    for k, v in extra.items():
        if v is not None:
            d[k] = v
    d["tint"] = tint
    ITEMS[item_id] = d
    FILE_OF[item_id] = file
    if glyph:
        ICON[item_id] = (glyph, tint)
    return d


def craft(out, skill, stations, level, inputs, count=1, xp=None, time=None, rid=None, name=None):
    """inputs: list of (item_spec, n). Output price is derived later if the item has none."""
    if isinstance(stations, str):
        stations = [stations]
    if stations == ["loom"]:
        stations = ["loom", "workbench"]
    if level > SKILL_LEVEL_CAP:
        level = SKILL_LEVEL_CAP
    rid = rid or out
    r = collections.OrderedDict()
    r["id"] = rid
    if name:
        r["name"] = name
    r["skill"] = skill
    r["stations"] = stations
    r["level"] = int(level)
    r["xp"] = int(xp if xp is not None else 4 + 3 * level + 2 * sum(n for _, n in inputs) // 2)
    r["time"] = round(time if time is not None else 1.0 + 0.25 * level + 0.15 * len(inputs), 1)
    r["inputs"] = [{"item": i, "count": int(n)} for i, n in inputs]
    r["output"] = {"item": out, "count": int(count)}
    for x in RECIPES:
        if x["id"] == rid:
            raise ValueError("duplicate recipe %s" % rid)
    RECIPES.append(r)
    if out not in RECIPE_OUT:
        RECIPE_OUT[out] = r
    return r


def raw_price(item_id):
    if item_id in LEGACY and "price" in LEGACY[item_id]:
        return LEGACY[item_id]["price"]
    if item_id in GATHERED:
        return GATHERED[item_id]
    return None


def price_of(item_id, _depth=0):
    p = raw_price(item_id)
    if p is not None:
        return p
    d = ITEMS.get(item_id)
    if d is None:
        raise KeyError("unknown item %s" % item_id)
    if "price" in d:
        return d["price"]
    r = RECIPE_OUT.get(item_id)
    if r is None or _depth > 12:
        raise KeyError("item %s has no price and no recipe" % item_id)
    cost = 0.0
    for inp in r["inputs"]:
        alts = inp["item"].split("|")
        cost += price_of(alts[0], _depth + 1) * inp["count"]
    markup = MARKUP.get(r["skill"], 1.12)
    labour = 1 + r["level"] * 0.6
    p = max(1, int(round((cost * markup + labour) / max(1, r["output"]["count"]))))
    d["price"] = p
    return p


MARKUP = {"smithing": 1.14, "carpentry": 1.15, "tailoring": 1.15, "leatherwork": 1.14, "cooking": 1.25,
          "baking": 1.25, "brewing": 1.3, "alchemy": 1.35, "jewelry": 1.3, "fletching": 1.15, "masonry": 1.12}


def resolve_prices():
    for i in list(ITEMS):
        price_of(i)


def check_inputs():
    bad = []
    for r in RECIPES:
        for inp in r["inputs"]:
            for alt in inp["item"].split("|"):
                if not exists(alt):
                    bad.append((r["id"], alt))
        if not exists(r["output"]["item"]):
            bad.append((r["id"], r["output"]["item"]))
    return bad


# ---------------------------------------------------------------------------------------
# tiers shared by weapons / armour / tools

class Tier:
    def __init__(self, key, name, lo, hi, dmg, dur, rarity, ingot, wood, leather, cloth, rlevel, color):
        self.key = key
        self.name = name
        self.lo = lo
        self.hi = hi
        self.dmg = dmg
        self.dur = dur
        self.rarity = rarity
        self.ingot = ingot
        self.wood = wood
        self.leather = leather
        self.cloth = cloth
        self.rlevel = rlevel      # base mastery (recipe) level 1..10
        self.color = color


TIERS = [
    Tier("wooden", "Wooden", 1, 8, 0.55, 0.6, 0, "plank", "plank", "leather", "cloth", 1, "#c9a26b"),
    Tier("bronze", "Bronze", 6, 16, 0.8, 0.85, 0, "bronze_ingot", "plank", "leather", "cloth", 2, "#d9a15a"),
    Tier("iron", "Iron", 12, 26, 1.0, 1.0, 1, "iron_ingot", "oak_plank", "leather", "cloth", 3, "#c4cad4"),
    Tier("steel", "Steel", 24, 38, 1.4, 1.3, 1, "steel_ingot", "oak_plank", "hardened_leather", "linen_cloth", 5, "#dfe6f2"),
    Tier("finesteel", "Fine Steel", 34, 47, 1.85, 1.6, 2, "fine_steel_ingot", "ironwood_plank", "hardened_leather", "silk_cloth", 7, "#f2f6ff"),
    Tier("spiritiron", "Spirit-Iron", 44, 55, 2.5, 2.0, 3, "spirit_iron_ingot", "ironwood_plank", "wyvern_leather", "spirit_silk", 9, "#9fe8d6"),
    Tier("rift", "Rift-Crystal", 52, 60, 3.3, 2.4, 3, "rift_crystal_ingot", "spiritwood_plank", "wyvern_leather", "riftweave_cloth", 10, "#c79bff"),
]


def lvl_in(tier, frac):
    """Level inside a tier's window, frac 0..1."""
    return int(round(tier.lo + (tier.hi - tier.lo) * frac))


def save_json(path, obj, indent=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=indent, ensure_ascii=False, separators=(",", ":") if indent is None else None)
        f.write("\n")
