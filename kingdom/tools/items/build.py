#!/usr/bin/env python3
"""Generates the Region 1 item set.

  python3 tools/items/build.py            (from kingdom/)

Writes data/items/*.json (+ index.json), data/recipes/*.json, data/items/shops.json, loot.json, sets.json,
crops.json, visuals.json, assets/ui/icons/items/<id>.svg and copies the equipment models to assets/items/.
Legacy ids in data/items.json and data/recipes.json are never touched.
"""
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import core  # noqa: E402
from core import ITEMS, FILE_OF, RECIPES, ICON, DATA, ROOT, save_json  # noqa: E402
import glyphs, materials, weapons, armour, food, alchemy, tools, misc, pathmanuals, uniques, shops, loot, visuals  # noqa: E402

GI_ROOT = os.path.join(ROOT, "assets", "incoming", "game-icons", "icons", "000000", "transparent", "1x1")
ICON_DIR = os.path.join(ROOT, "assets", "ui", "icons", "items")



LEGACY_PATCH = {
    "iron_dagger": {"level": 12, "req_level": 12, "weapon_type": "dagger", "type": "dagger", "dmg_type": "pierce", "reach": 0.8, "weight": 1.0, "tier": 2, "material": "iron", "tint": "#c4cad4", "affinity": ["shadow", "swordsmanship"], "path": ["blade"], "crit": 0.08},
    "iron_sword": {"level": 14, "req_level": 14, "weapon_type": "sword", "type": "sword", "dmg_type": "slash", "reach": 1.2, "weight": 3.1, "tier": 2, "material": "iron", "tint": "#c4cad4", "affinity": ["swordsmanship"], "path": ["blade"]},
    "iron_helm": {"level": 15, "req_level": 15, "armour_class": "heavy", "set": "iron", "set_name": "Iron Plate", "type": "head_armour", "tier": 2, "material": "iron", "tint": "#c4cad4", "armour_load": 0.45, "weight": 2.0},
    "leather_cap": {"level": 4, "req_level": 4, "armour_class": "light", "set": "leather", "set_name": "Leather", "type": "head_armour", "tier": 1, "tint": "#a9763c", "armour_load": 0.09, "weight": 0.9},
    "leather_jerkin": {"level": 7, "req_level": 7, "armour_class": "light", "set": "leather", "set_name": "Leather", "type": "body_armour", "tier": 1, "tint": "#a9763c", "armour_load": 0.15, "weight": 3.2},
    "leather_gloves": {"level": 4, "req_level": 4, "armour_class": "light", "set": "leather", "set_name": "Leather", "type": "hands_armour", "tier": 1, "tint": "#a9763c", "armour_load": 0.09, "weight": 0.4},
    "leather_boots": {"level": 5, "req_level": 5, "armour_class": "light", "set": "leather", "set_name": "Leather", "type": "feet_armour", "tier": 1, "tint": "#a9763c", "armour_load": 0.09, "weight": 1.0},
    "copper_ring": {"level": 3, "req_level": 3, "type": "ring", "tint": "#d9885a", "weight": 0.05},
    "belt_pouch": {"level": 2, "req_level": 1, "type": "belt", "tint": "#b08850", "weight": 0.4},
    "wooden_shield": {"level": 2, "req_level": 2, "weapon_type": "shield", "shield_type": "shield", "block": 0.18, "type": "shield", "tier": 0, "material": "wooden", "tint": "#c9a26b", "weight": 3.4, "affinity": ["earth"], "path": ["warden"]},
    "hammer": {"level": 12, "type": "tool", "tool_tier": 2, "tool_power": 1.3, "tint": "#c4cad4", "weight": 3.0},
    "pickaxe": {"level": 12, "type": "tool", "tool_tier": 2, "tool_power": 1.3, "tint": "#c4cad4", "weight": 3.4},
    "wood_axe": {"level": 12, "type": "tool", "tool_tier": 2, "tool_power": 1.3, "tint": "#c4cad4", "weight": 2.8},
    "heirloom_blade": {"level": 10, "rarity": 2, "weapon_type": "sword", "type": "sword", "tint": "#e0c070", "unique": True, "weight": 2.8},
    "heirloom_hammer": {"level": 8, "rarity": 2, "type": "tool", "tint": "#e0c070", "unique": True, "tool_tier": 3, "tool_power": 1.5},
    "heirloom_knife": {"level": 6, "rarity": 2, "weapon_type": "dagger", "type": "dagger", "tint": "#e0c070", "unique": True, "crit": 0.1},
    "heirloom_lantern": {"level": 6, "rarity": 2, "type": "talisman", "tint": "#e0c070", "unique": True},
    "heirloom_purse": {"level": 6, "rarity": 2, "type": "talisman", "tint": "#e0c070", "unique": True},
    "heirloom_sickle": {"level": 6, "rarity": 2, "type": "talisman", "tint": "#e0c070", "unique": True},
    "maren_staff": {"level": 14, "rarity": 2, "weapon_type": "staff", "type": "staff", "tint": "#d8c8a0", "unique": True, "two_handed": True, "magic": 10},
    "rowan_lance": {"level": 16, "rarity": 2, "weapon_type": "spear", "type": "spear", "tint": "#d8c8a0", "unique": True, "reach": 2.2},
    # legacy food: spoilage and raw flags
    "bread": {"spoil_hours": 120, "spoils_into": "spoiled_food", "type": "baked", "cooked": True},
    "apple": {"spoil_hours": 300, "spoils_into": "spoiled_food", "type": "produce"},
    "stew": {"spoil_hours": 72, "spoils_into": "spoiled_food", "type": "dish", "cooked": True},
    "cheese": {"spoil_hours": 600, "spoils_into": "spoiled_food", "type": "produce"},
    "wolf_meat": {"spoil_hours": 36, "spoils_into": "spoiled_food", "type": "raw_meat", "raw": True},
    "grilled_fish": {"spoil_hours": 72, "spoils_into": "spoiled_food", "type": "dish"},
    "venison_roast": {"spoil_hours": 96, "spoils_into": "spoiled_food", "type": "dish"},
    "berry_pie": {"spoil_hours": 96, "spoils_into": "spoiled_food", "type": "baked"},
    "mushroom_soup": {"spoil_hours": 72, "spoils_into": "spoiled_food", "type": "dish"},
    "egg": {"spoil_hours": 240, "spoils_into": "spoiled_food", "type": "produce"},
    "turnip": {"spoil_hours": 400, "spoils_into": "spoiled_food", "type": "produce"},
    "cabbage": {"spoil_hours": 240, "spoils_into": "spoiled_food", "type": "produce"},
    "ale": {"type": "drink", "drink": True},
    "venison": {"spoil_hours": 48, "spoils_into": "spoiled_food", "type": "raw_meat", "raw": True},
    "rabbit_meat": {"spoil_hours": 36, "spoils_into": "spoiled_food", "type": "raw_meat", "raw": True},
    "pork": {"spoil_hours": 48, "spoils_into": "spoiled_food", "type": "raw_meat", "raw": True},
    "perch": {"spoil_hours": 30, "spoils_into": "spoiled_food", "type": "raw_meat", "raw": True},
    "trout": {"spoil_hours": 30, "spoils_into": "spoiled_food", "type": "raw_meat", "raw": True},
    "pike": {"spoil_hours": 30, "spoils_into": "spoiled_food", "type": "raw_meat", "raw": True},
    "mushroom": {"spoil_hours": 120, "spoils_into": "spoiled_food", "type": "produce"},
    "wild_berries": {"spoil_hours": 70, "spoils_into": "spoiled_food", "type": "produce"},
    "healing_herb": {"type": "herb", "level": 1},
    "iron_ingot": {"type": "ingot", "tint": "#c4cad4", "level": 12, "weight": 2.0},
    "copper_ingot": {"type": "ingot", "tint": "#d9885a", "level": 1, "weight": 1.8},
    "iron_ore": {"type": "ore", "level": 8}, "copper_ore": {"type": "ore", "level": 1}, "coal": {"type": "fuel", "level": 1},
    "scar_crystal": {"rarity": 2, "level": 16, "type": "crystal"}, "scarbloom": {"rarity": 1, "level": 12, "type": "herb"},
    "leather": {"type": "leather", "level": 1}, "plank": {"type": "timber"}, "log": {"type": "timber"},
    "saddle": {"type": "tack", "mount_slot": "saddle", "level": 6},
}


def glyph_index():
    idx = {}
    for author in sorted(os.listdir(GI_ROOT)):
        d = os.path.join(GI_ROOT, author)
        for fn in os.listdir(d):
            if fn.endswith(".svg"):
                idx.setdefault(fn[:-4], os.path.join(d, fn))
    return idx


def lighten(hexc, min_l=0.6):
    h = hexc.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    if lum < min_l:
        k = (min_l - lum) / (1 - lum) if lum < 1 else 0
        r, g, b = [int(c + (255 - c) * k) for c in (r, g, b)]
    return "#%02x%02x%02x" % (r, g, b)


def resolve_icons():
    gi = glyph_index()
    counters = collections.Counter()
    missing = set()
    chosen = {}
    for iid in ITEMS:
        spec = ICON.get(iid)
        if not spec:
            continue
        g, tint = spec
        if g.startswith("fam:"):
            fam = g[4:]
            lst = glyphs.FAM[fam]
            name = lst[counters[fam] % len(lst)]
            counters[fam] += 1
        else:
            name = g
        if name not in gi:
            missing.add(name)
            continue
        chosen[iid] = (name, tint)
    if missing:
        print("MISSING GLYPHS:", sorted(missing))
    os.makedirs(ICON_DIR, exist_ok=True)
    n = 0
    for iid, (name, tint) in chosen.items():
        dst = os.path.join(ICON_DIR, iid + ".svg")
        if os.path.exists(dst) and not os.path.exists(dst + ".gen"):
            # never overwrite hand-made legacy icons; ours are tracked with a marker file list
            if iid in core.LEGACY:
                continue
        svg = open(gi[name]).read()
        svg = svg.replace('fill="#000"', 'fill="%s"' % lighten(tint))
        if 'fill="' not in svg:
            svg = svg.replace("<path ", '<path fill="%s" ' % lighten(tint), 1)
        with open(dst, "w") as f:
            f.write(svg)
        n += 1
    return chosen, n


def extra_ui_icons():
    """Slot and category icons the inventory needs for the new slots (white, like the other gm icons)."""
    gi = glyph_index()
    gm = os.path.join(ROOT, "assets", "ui", "icons", "gm")
    for name, glyph in [("slot_cloak", "cloak"), ("slot_ring", "ring"), ("slot_amulet", "necklace"), ("cat_tools", "anvil")]:
        svg = open(gi[glyph]).read().replace('fill="#000"', 'fill="#fff"')
        with open(os.path.join(gm, name + ".svg"), "w") as f:
            f.write(svg)


def out_items():
    by_file = collections.OrderedDict()
    for iid, d in ITEMS.items():
        by_file.setdefault(FILE_OF[iid], collections.OrderedDict())[iid] = d
    index = []
    for fname, items in by_file.items():
        save_json(os.path.join(DATA, "items", fname + ".json"), items)
        index.append(fname)
    return index


def out_recipes():
    by_skill = collections.OrderedDict()
    for r in RECIPES:
        by_skill.setdefault(r["skill"], []).append(r)
    files = []
    for sk, lst in by_skill.items():
        save_json(os.path.join(DATA, "recipes", sk + ".json"), {"recipes": lst}, indent=None)
        files.append(sk)
    return files


def make_salvage():
    """Scrap returns for crafted gear: ~45% of the raw materials (at least one), at the matching station."""
    out = []
    for r in RECIPES:
        item = r["output"]["item"]
        info = ITEMS.get(item)
        if not info or info.get("category") != "gear" or info.get("unique") or info.get("no_craft"):
            continue
        ys = []
        for inp in r["inputs"]:
            base = inp["item"].split("|")[0]
            n = int(inp["count"] * 0.45)
            if n < 1:
                continue
            ys.append({"item": base, "count": n})
        if not ys:
            ys.append({"item": r["inputs"][0]["item"].split("|")[0], "count": 1})
        sk = r["skill"]
        out.append({"item": item, "yield": ys, "skill": sk, "stations": ["anvil"] if sk in ("smithing", "jewelry") else ["workbench"],
                    "level": max(1, r["level"] - 1), "xp": max(2, r["xp"] // 4)})
    return out


def main():
    materials.build()
    weapons.build()
    armour.build()
    food.build()
    alchemy.build()
    tools.build()
    misc.build()
    pathmanuals.build()
    uniques.build()
    core.resolve_prices()
    bad = core.check_inputs()
    if bad:
        print("UNRESOLVED INPUTS:", bad[:40])
        raise SystemExit(1)
    shops.build()
    shop_out = {"tiers": {"1": {"name": "village", "level_cap": shops.CAP[1]}, "2": {"name": "town", "level_cap": shops.CAP[2]}, "3": {"name": "city", "level_cap": shops.CAP[3]}},
                "shops": shops.SHOPS, "settlements": shops.SETTLEMENTS, "identity": shops.IDENT}
    loot_out = loot.build()

    # clean previous generated data
    for sub in ("items", "recipes"):
        d = os.path.join(DATA, sub)
        if os.path.isdir(d):
            for fn in os.listdir(d):
                if fn.endswith(".json"):
                    os.remove(os.path.join(d, fn))
    index = out_items()
    rfiles = out_recipes()
    salv = make_salvage()
    recipes_meta = {
        "skills": {
            "baking": {"name": "Baking", "verb": "Bake", "tag": "crafted"}, "brewing": {"name": "Brewing", "verb": "Brew", "tag": "crafted"},
            "tailoring": {"name": "Tailoring", "verb": "Sew", "tag": "crafted"}, "jewelry": {"name": "Jewelry", "verb": "Set", "tag": "crafted"},
            "fletching": {"name": "Fletching", "verb": "Fletch", "tag": "crafted"}, "masonry": {"name": "Masonry", "verb": "Dress", "tag": "crafted"},
        },
        "stations": {
            "oven": {"name": "Oven", "skills": ["baking", "cooking"]}, "brew_vat": {"name": "Brew Vat", "skills": ["brewing"]},
            "loom": {"name": "Loom", "skills": ["tailoring"]}, "jeweler_bench": {"name": "Jeweller's Bench", "skills": ["jewelry"]},
        },
        "station_skill_adds": {"hearth": ["baking", "brewing"], "anvil": ["jewelry", "masonry"], "workbench": ["tailoring", "fletching", "masonry"]},
        "files": rfiles,
    }
    save_json(os.path.join(DATA, "recipes", "meta.json"), recipes_meta, indent=1)
    save_json(os.path.join(DATA, "recipes", "salvage.json"), {"salvage": salv})
    save_json(os.path.join(DATA, "items", "index.json"), {"files": index, "extras": ["shops", "loot", "sets", "crops", "visuals", "legacy_patch"]}, indent=1)
    save_json(os.path.join(DATA, "items", "legacy_patch.json"), LEGACY_PATCH)
    save_json(os.path.join(DATA, "items", "shops.json"), shop_out)
    save_json(os.path.join(DATA, "items", "loot.json"), loot_out)
    save_json(os.path.join(DATA, "items", "sets.json"), armour.SETS_OUT)
    misc.dump_crops(os.path.join(DATA, "items", "crops.json"))
    visuals.copy_assets()
    vis = visuals.build_visuals()
    save_json(os.path.join(DATA, "items", "visuals.json"), vis)
    with open(os.path.join(ROOT, "assets", "items", "CREDITS.md"), "w") as f:
        f.write(visuals.CREDITS)
    chosen, nicons = resolve_icons()
    extra_ui_icons()
    # report
    cats = collections.Counter(d["category"] for d in ITEMS.values())
    print("items:", len(ITEMS), dict(cats))
    print("recipes:", len(RECIPES), "salvage:", len(salv), "shops:", len(shops.SHOPS), "visuals:", len(vis), "icons:", nicons)
    print("loot themes:", len(loot_out["themes"]), "monsters:", len(loot_out["monsters"]))


if __name__ == "__main__":
    main()
