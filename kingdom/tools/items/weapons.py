"""Weapons, shields and ammunition across seven material tiers (levels 1-60)."""
from core import add, craft, TIERS, LEGACY, lvl_in

F = "weapons"
TK = [t.key for t in TIERS]

# wood species / focus gem per tier for bows, staves, wands
WOOD_ADJ = ["Ash", "Elm", "Yew", "Ironwood", "Steelbound", "Spiritwood", "Rift-Crystal"]
WOOD_ID = ["ash", "elm", "yew", "ironwood", "steelbound", "spiritwood", "rift"]
FOCUS = ["quartz", "quartz", "garnet", "amethyst", "moonstone", "spirit_jade", "rift_crystal"]
WOOD_ITEM = ["plank", "plank", "oak_plank", "oak_plank", "ironwood_plank", "spiritwood_plank", "spiritwood_plank"]
BOW_WOOD = ["plank", "oak_plank", "yew_log", "ironwood_plank", "ironwood_plank", "spiritwood_plank", "spiritwood_plank"]
METAL_ADJ = {t.key: t.name for t in TIERS}
AMMO_HEAD = {0: ("flint", 10), 1: ("bronze_arrowheads", 10), 2: ("arrowheads", 10), 3: ("steel_arrowheads", 10),
             4: ("fine_steel_arrowheads", 10), 5: ("spirit_iron_arrowheads", 10), 6: ("rift_crystal_arrowheads", 10)}

# type: id, display, tiers(list of indexes), slot, hands, damage, speed, reach, weight, dmg_type, durability,
#       level offset, ingot units, wood units, leather units, affinity trees, soul paths, extras, skill
T = {}


def wt(tid, name, tiers, dmg, speed, reach, weight, dtype, dur, off, ing, wood, lea, tree, path, skill="smithing",
       slot="main_hand", hands=1, ranged=False, rlevel_off=0, **extra):
    T[tid] = dict(id=tid, name=name, tiers=tiers, dmg=dmg, speed=speed, reach=reach, weight=weight, dtype=dtype, dur=dur,
                  off=off, ing=ing, wood=wood, lea=lea, tree=tree, path=path, skill=skill, slot=slot, hands=hands,
                  ranged=ranged, rlevel_off=rlevel_off, extra=extra)


# ---- melee ---------------------------------------------------------------------------------------------
wt("dagger", "Dagger", [0, 1, 2, 3, 4, 5, 6], 4, 0.03, 0.8, 1.0, "pierce", 90, 0, 1, 0, 1, ["shadow", "swordsmanship"], ["blade"], crit=0.08)
wt("sword", "Sword", [0, 1, 2, 3, 4, 5, 6], 9, 0.0, 1.2, 3.1, "slash", 140, 2, 3, 0, 1, ["swordsmanship"], ["blade"])
wt("sabre", "Sabre", [1, 2, 3, 4, 5, 6], 8, 0.02, 1.1, 2.6, "slash", 130, 3, 3, 0, 1, ["iaido", "swordsmanship"], ["blade"], crit=0.06)
wt("greatsword", "Greatsword", [2, 3, 4, 5, 6], 16, -0.03, 1.6, 6.0, "slash", 170, 5, 6, 0, 2, ["swordsmanship"], ["blade", "warden"], hands=2, rlevel_off=1)
wt("axe", "Axe", [1, 2, 3, 4, 5, 6], 10, -0.01, 1.0, 3.0, "slash", 130, 2, 2, 1, 0, ["earth"], ["warden"])
wt("battleaxe", "Battleaxe", [2, 3, 4, 5, 6], 17, -0.04, 1.3, 6.5, "slash", 170, 6, 4, 2, 0, ["earth"], ["warden"], hands=2, rlevel_off=1)
wt("mace", "Mace", [0, 1, 2, 3, 4, 5, 6], 9, 0.0, 0.9, 3.4, "blunt", 150, 3, 2, 1, 1, ["earth"], ["warden"], armour_pierce=0.15)
wt("warhammer", "Warhammer", [2, 3, 4, 5, 6], 18, -0.05, 1.2, 7.0, "blunt", 180, 7, 4, 2, 0, ["earth"], ["warden", "forge"], hands=2, rlevel_off=1, armour_pierce=0.25)
wt("spear", "Spear", [0, 1, 2, 3, 4, 5, 6], 8, 0.0, 1.8, 2.4, "pierce", 120, 1, 1, 2, 0, ["swordsmanship"], ["warden", "hunt"])
wt("halberd", "Halberd", [2, 3, 4, 5, 6], 15, -0.03, 2.0, 5.5, "slash", 160, 6, 3, 2, 0, ["swordsmanship", "command"], ["warden"], hands=2, rlevel_off=1)
wt("fist", "Fist Weapon", [0, 1, 2, 3, 4, 5, 6], 5, 0.04, 0.5, 1.2, "blunt", 150, 1, 2, 0, 2, ["fist_palm"], ["warden", "wanderer"], crit=0.05)
# ---- ranged --------------------------------------------------------------------------------------------
wt("shortbow", "Shortbow", [0, 1, 2, 3, 4, 5, 6], 7, 0.02, 18.0, 1.0, "pierce", 100, 0, 0, 2, 0, ["wind"], ["hunt"], skill="fletching", hands=2, ranged=True, ammo="arrow")
wt("longbow", "Longbow", [1, 2, 3, 4, 5, 6], 12, -0.02, 28.0, 1.6, "pierce", 110, 4, 0, 3, 0, ["wind"], ["hunt"], skill="fletching", hands=2, ranged=True, ammo="arrow", rlevel_off=1)
wt("crossbow", "Crossbow", [2, 3, 4, 5, 6], 14, -0.05, 24.0, 3.4, "pierce", 130, 4, 1, 3, 0, ["wind"], ["hunt"], skill="fletching", hands=2, ranged=True, ammo="bolt", rlevel_off=1)
# ---- magic ------------------------------------------------------------------------------------------------
wt("staff", "Staff", [0, 1, 2, 3, 4, 5, 6], 3, 0.0, 1.5, 2.2, "magic", 140, 1, 0, 3, 0, ["fire", "water", "wind", "earth", "lightning", "qi"], ["scholar", "tide"], skill="carpentry", hands=2, magic=10)
wt("wand", "Wand", [0, 1, 2, 3, 4, 5, 6], 1, 0.01, 0.6, 0.4, "magic", 90, 0, 0, 1, 0, ["fire", "water", "wind", "lightning", "qi"], ["scholar"], skill="carpentry", magic=7)

TYPE_ICON_FAM = {"dagger": "dagger", "sword": "sword", "sabre": "sabre", "greatsword": "greatsword", "axe": "axe", "battleaxe": "battleaxe",
                 "mace": "mace", "warhammer": "warhammer", "spear": "spear", "halberd": "halberd", "fist": "fist",
                 "shortbow": "shortbow", "longbow": "longbow", "crossbow": "crossbow", "staff": "staff", "wand": "wand"}
T0_NAMES = {"dagger": "Flint Dagger", "sword": "Wooden Practice Sword", "mace": "Wooden Club", "spear": "Fire-Hardened Spear",
            "fist": "Bound Hand-Wraps", "staff": "Ash Quarterstaff", "wand": "Ash Twig Wand", "shortbow": "Ash Shortbow"}
DESC = {
    "dagger": "Quick, close and quiet.", "sword": "A balanced one-handed blade.", "sabre": "A curved cutting blade; fast from the draw.",
    "greatsword": "A two-handed blade that ends arguments.", "axe": "Bites through shields as well as timber.",
    "battleaxe": "A broad two-handed axe. Slow, brutal, final.", "mace": "A flanged head that crumples armour.",
    "warhammer": "A two-handed hammer that breaks plate and bone.", "spear": "Long reach, simple, honest.",
    "halberd": "Axe, hook and spear on one shaft. Holds a line.", "fist": "Wraps, knuckles or claws for those who fight with their hands.",
    "shortbow": "Light and quick to draw.", "longbow": "A tall bow with a heavy draw.", "crossbow": "Slow to span, brutal at range.",
    "staff": "A focus for magicules: amplifies spells.", "wand": "A small focus for quick, light casting.",
}
TIER_FLAVOUR = [
    "Crude, but it does the job.", "Bronze keeps a decent edge and costs little.", "Sound iron, made by a village smith.",
    "Steel: hard, light and keen.", "Fine steel, folded and quenched with care.",
    "Spirit-iron answers qi; cultivators' weapon of choice.", "Rift crystal and spirit-iron: cold, sharp and never quite still.",
]


def tier_level(t, off):
    tt = TIERS[t]
    return max(1, min(60, tt.lo + off + (t * 0)))


def ingot_inputs(t, ing, wood, lea, tt, skill, extra=None):
    ins = []
    if ing:
        ins.append((tt.ingot if t > 0 else "plank", ing))
    if wood:
        ins.append((WOOD_ITEM[t] if t > 0 else "plank", wood))
    if lea:
        # cheap tiers wrap grips with plank and cord instead of good leather
        ins.append((tt.leather if t >= 2 else "leather", lea))
    return ins


def build():
    for tid, d in T.items():
        for t in d["tiers"]:
            tt = TIERS[t]
            wood_based = tid in ("shortbow", "longbow", "crossbow", "staff", "wand")
            prefix = WOOD_ID[t] if wood_based else tt.key
            item_id = "%s_%s" % (prefix, tid)
            if item_id in LEGACY:
                continue
            adj = WOOD_ADJ[t] if wood_based else tt.name
            name = "%s %s" % (adj, d["name"])
            if t == 0 and tid in T0_NAMES:
                name = T0_NAMES[tid]
            dmg = max(1, int(round(d["dmg"] * tt.dmg)))
            if tid in ("staff", "wand"):
                dmg = max(1, int(round(d["dmg"] * tt.dmg)))
            lvl = min(tt.hi, tt.lo + d["off"])
            dur = int(round(d["dur"] * tt.dur))
            ex = dict(d["extra"])
            if "magic" in ex:
                ex["magic"] = int(round(ex["magic"] * tt.dmg * 1.15)) + (1 if t else 0)
            if "crit" in ex:
                ex["crit"] = round(ex["crit"] + 0.005 * t, 3)
            if "armour_pierce" in ex:
                ex["armour_pierce"] = round(ex["armour_pierce"] + 0.01 * t, 3)
            fam = TYPE_ICON_FAM[tid]
            desc = "%s %s" % (DESC[tid], TIER_FLAVOUR[t])
            add(item_id, name, "gear", F, price=None, stack=1, weight=d["weight"] * [0.8, 1.05, 1.0, 1.0, 1.0, 0.9, 0.9][t], rarity=tt.rarity if not (t == 2 and tid in ("dagger", "fist", "mace", "spear")) else 0,
                level=lvl, desc=desc, tint=tt.color, glyph="fam:" + fam, slot=d["slot"], damage=dmg,
                speed=round(d["speed"] - (0.0 if t < 5 else -0.01 if d["speed"] >= 0 else 0.0), 3), durability=dur, req_level=lvl,
                weapon_type=tid, dmg_type=d["dtype"], reach=d["reach"], two_handed=(d["hands"] == 2), ranged=d["ranged"] or None,
                material=tt.key if not wood_based else (WOOD_ID[t]), tier=t, affinity=d["tree"], path=d["path"], type=tid,
                **ex)
            # recipe
            rl = max(1, min(10, tt.rlevel + d["rlevel_off"] - (1 if tid in ("dagger", "spear", "shortbow", "wand") else 0)))
            ins = []
            if wood_based:
                w = d["wood"]
                ins.append(((BOW_WOOD if d["skill"] == "fletching" else WOOD_ITEM)[t], w))
                if tid in ("shortbow", "longbow", "crossbow"):
                    ins.append(("bowstring", 1))
                    if tid == "crossbow":
                        ins.append((tt.ingot if t > 0 else "plank", 1))
                        ins.append(("rivets", 4))
                    elif t >= 4:
                        ins.append((tt.ingot, 1))
                else:
                    if t >= 1:
                        ins.append((FOCUS[t], 1 if tid == "wand" else 2))
                    if t >= 4:
                        ins.append((tt.ingot, 1))
                    if t >= 3:
                        ins.append(("linen_thread" if t < 4 else "silk_thread", 2))
                skill = d["skill"]
                stn = "workbench"
            else:
                ing, wood, lea = d["ing"], d["wood"], d["lea"]
                ins = []
                if t == 0:
                    ins.append(("plank", 2 + ing))
                    if lea:
                        ins.append(("sinew", lea))
                    if tid == "dagger":
                        ins = [("flint", 2), ("plank", 1)]
                else:
                    ins.append((tt.ingot, ing))
                    if wood:
                        ins.append((WOOD_ITEM[t], wood))
                    if lea:
                        ins.append((tt.leather if t >= 2 else "plank", lea))
                skill = "smithing" if t > 0 else "carpentry"
                stn = "anvil" if t > 0 else "workbench"
            craft(item_id, skill, stn, rl, ins, xp=8 + 7 * rl + 2 * d["ing"])

    # ---- shields ---------------------------------------------------------------------------------------------
    SH = {
        "buckler": ("Buckler", [0, 1, 2, 3, 4, 5, 6], 3, 0.0, 0.10, 1.6, 90, 0, (2, 0, 1)),
        "shield": ("Round Shield", [1, 2, 3, 4, 5, 6], 5, -0.02, 0.18, 3.4, 130, 2, (1, 3, 1)),
        "kite": ("Kite Shield", [2, 3, 4, 5, 6], 7, -0.03, 0.24, 4.4, 160, 5, (3, 2, 1)),
        "tower": ("Tower Shield", [2, 3, 4, 5, 6], 10, -0.06, 0.34, 7.0, 200, 8, (4, 3, 1)),
    }
    for sid, (nm, tiers, arm, spd, blk, wgt, dur, off, (ing, wood, lea)) in SH.items():
        for t in tiers:
            tt = TIERS[t]
            item_id = "%s_%s" % (tt.key, sid)
            if item_id in LEGACY:
                continue
            adj = tt.name
            name = "%s %s" % (adj, nm)
            if t == 0:
                name = "Wooden %s" % nm
            lvl = min(tt.hi, tt.lo + off)
            ar = max(1, int(round(arm * tt.dmg * 1.05)))
            add(item_id, name, "gear", F, price=None, stack=1, weight=wgt * [0.7, 1.0, 1.0, 1.0, 1.0, 0.85, 0.85][t], rarity=tt.rarity,
                level=lvl, desc="A %s shield. %s" % (nm.lower(), TIER_FLAVOUR[t]), tint=tt.color, glyph="fam:" + sid,
                slot="off_hand", armour=ar, speed=spd, durability=int(dur * tt.dur), req_level=lvl, block=round(blk + 0.02 * t, 3),
                weapon_type="shield", shield_type=sid, material=tt.key, tier=t, affinity=["earth"], path=["warden"], type="shield")
            if t == 0:
                ins = [("plank", 2 + ing), ("leather", lea)]
                skill, stn = "carpentry", "workbench"
            else:
                ins = [(tt.ingot, ing)]
                if wood:
                    ins.append((WOOD_ITEM[t], wood))
                if lea:
                    ins.append((tt.leather if t >= 2 else "plank", lea))
                skill, stn = "smithing", "anvil"
            craft(item_id, skill, stn, max(1, min(10, tt.rlevel + (1 if sid in ("kite", "tower") else 0))), ins, xp=10 + 6 * tt.rlevel)

    # ---- ammunition --------------------------------------------------------------------------------------------
    heads = [("bronze_arrowheads", "Bronze Arrowheads", 1, "bronze_ingot"), ("steel_arrowheads", "Steel Arrowheads", 3, "steel_ingot"),
             ("fine_steel_arrowheads", "Fine Steel Broadheads", 4, "fine_steel_ingot"),
             ("spirit_iron_arrowheads", "Spirit-Iron Arrowheads", 5, "spirit_iron_ingot"), ("rift_crystal_arrowheads", "Rift-Crystal Arrowheads", 6, "rift_crystal_ingot")]
    from materials import mat  # noqa
    for hid, hname, t, ing in heads:
        tt = TIERS[t]
        add(hid, hname, "material", "materials", price=None, stack=60, weight=0.1, rarity=tt.rarity, level=tt.lo, desc="Tips for arrows and bolts.",
            tint=tt.color, glyph="fam:ore", type="fitting")
        craft(hid, "smithing", "anvil", max(1, tt.rlevel - 1), [(ing, 1)], count=10, xp=6 + 2 * t)
    ARROW_NAME = ["Flint-Tipped Arrows", "Bronze Arrows", "Iron Arrows", "Steel Arrows", "Fine Steel Broadhead Arrows", "Spirit-Iron Arrows", "Rift-Crystal Arrows"]
    ARROW_DMG = [1, 2, 3, 5, 7, 10, 14]
    for t in range(7):
        tt = TIERS[t]
        head, n = AMMO_HEAD[t]
        aid = "%s_arrow" % ("flint" if t == 0 else tt.key)
        add(aid, ARROW_NAME[t], "ammo", F, price=None, stack=60, weight=0.02, rarity=tt.rarity if t > 2 else 0, level=tt.lo, desc="Ammunition for bows. %s" % TIER_FLAVOUR[t],
            tint=tt.color, glyph="fam:arrow", ammo_type="arrow", ammo_damage=ARROW_DMG[t], type="ammo", req_level=tt.lo)
        craft(aid, "fletching", "workbench", max(1, tt.rlevel - 1), [("arrow_shafts", 10), ("goose_feather", 5), (head, n)], count=10, xp=6 + 3 * t)
    BOLT_NAME = {1: "Bronze Bolts", 2: "Iron Bolts", 3: "Steel Bolts", 4: "Fine Steel Bolts", 5: "Spirit-Iron Bolts", 6: "Rift-Crystal Bolts"}
    for t in range(1, 7):
        tt = TIERS[t]
        head, n = AMMO_HEAD[t]
        bid = "%s_bolt" % tt.key
        add(bid, BOLT_NAME[t], "ammo", F, price=None, stack=60, weight=0.03, rarity=tt.rarity if t > 2 else 0, level=tt.lo + 4, desc="Short heavy bolts for crossbows.",
            tint=tt.color, glyph="fam:bolt", ammo_type="bolt", ammo_damage=ARROW_DMG[t] + 2, type="ammo", req_level=tt.lo + 4)
        craft(bid, "fletching", "workbench", max(1, tt.rlevel), [("arrow_shafts", 10), ("goose_feather", 3), (head, n)], count=10, xp=8 + 3 * t)
