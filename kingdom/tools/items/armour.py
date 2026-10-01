"""Armour sets (light / medium / heavy / robes), sect robes and accessories (rings, amulets, talismans)."""
from core import add, craft, TIERS, LEGACY

F = "armour"
SLOTS = ["head", "body", "hands", "legs", "feet", "cloak"]
BASE = {"head": 2.0, "body": 5.0, "hands": 1.0, "legs": 3.0, "feet": 1.5, "cloak": 1.0}
LVL_OFF = {"head": 1, "body": 3, "hands": 0, "legs": 2, "feet": 0, "cloak": 1}
DUR = {"head": 90, "body": 130, "hands": 90, "legs": 110, "feet": 110, "cloak": 80}
MAGIC = {"head": 1, "body": 3, "hands": 1, "legs": 2, "feet": 1, "cloak": 2}
CLS = {"robe": dict(mult=0.45, load=0.05, dur=0.7, speed=0.0), "light": dict(mult=1.0, load=0.15, dur=0.9, speed=0.0),
       "medium": dict(mult=1.6, load=0.4, dur=1.1, speed=-0.004), "heavy": dict(mult=2.3, load=0.75, dur=1.3, speed=-0.008)}
BOOT_SPEED = {"robe": 0.02, "light": 0.03, "medium": 0.0, "heavy": -0.01}
TRARITY = [0, 0, 1, 1, 2, 3, 3]
# units of main material per slot
UNITS = {"head": 2, "body": 5, "hands": 2, "legs": 4, "feet": 2, "cloak": 3}

# set key, display, class, tier index (for colour/rarity), lo, hi, power, rlevel, main material item, second material,
# pieces {slot: word}, blurb
SETS = [
    # light
    ("hide", "Padded Hide", "light", 0, 1, 7, 0.6, 1, "rabbit_pelt", "sinew", dict(head="cap", body="vest", hands="gloves", legs="leggings", feet="boots", cloak="cloak"), "Hide stitched over padding. Better than a shirt."),
    ("leather", "Leather", "light", 1, 4, 14, 1.0, 1, "leather", "linen_thread", dict(head="cap", body="jerkin", hands="gloves", legs="leggings", feet="boots", cloak="cloak"), "Boiled leather, sturdy and quiet."),
    ("hardened", "Hardened Leather", "light", 2, 12, 24, 1.45, 4, "hardened_leather", "linen_thread", dict(head="cap", body="cuirass", hands="gloves", legs="leggings", feet="boots", cloak="cloak"), "Waxed and boiled until it rings. Scouts and caravan guards wear it."),
    ("studded", "Studded Leather", "light", 3, 22, 34, 1.95, 5, "hardened_leather", "iron_ingot", dict(head="cap", body="jacket", hands="gloves", legs="leggings", feet="boots", cloak="cloak"), "Hardened leather set with iron studs."),
    ("bearhide", "Bearhide", "light", 4, 32, 44, 2.6, 7, "hardened_leather", "bear_pelt", dict(head="hood", body="coat", hands="gloves", legs="leggings", feet="boots", cloak="mantle"), "Thick bearhide lined with fur. Hunters of the north swear by it."),
    ("wyvernhide", "Wyvernscale Leather", "light", 5, 42, 54, 3.4, 9, "wyvern_leather", "wyvern_scale", dict(head="hood", body="cuirass", hands="gloves", legs="leggings", feet="boots", cloak="mantle"), "Scaled wyvern leather, light and proof against steel."),
    ("riftstalker", "Rift-Stalker", "light", 6, 52, 60, 4.4, 10, "wyvern_leather", "rift_silk_thread", dict(head="hood", body="coat", hands="gloves", legs="leggings", feet="boots", cloak="shroud"), "Leather stitched with Rift thread. It drinks the light."),
    # medium
    ("bronzescale", "Bronze Scale", "medium", 1, 6, 16, 0.8, 3, "bronze_ingot", "sinew", dict(head="helm", body="hauberk", hands="gauntlets", legs="chausses", feet="boots", cloak="cloak"), "Overlapping bronze scales on a leather backing."),
    ("chain", "Iron Mail", "medium", 2, 12, 26, 1.0, 4, "iron_ingot", "leather", dict(head="coif", body="hauberk", hands="mail_mitts", legs="chausses", feet="boots", cloak="cloak"), "Riveted iron rings. Every guard captain owns one."),
    ("steelmail", "Steel Mail", "medium", 3, 24, 38, 1.4, 6, "steel_ingot", "hardened_leather", dict(head="coif", body="hauberk", hands="mail_mitts", legs="chausses", feet="boots", cloak="cloak"), "Fine steel rings over a padded gambeson."),
    ("lamellar", "Fine Steel Lamellar", "medium", 4, 34, 47, 1.85, 7, "fine_steel_ingot", "silk_cloth", dict(head="helm", body="lamellar", hands="gauntlets", legs="chausses", feet="boots", cloak="cloak"), "Laced plates of fine steel that move like cloth."),
    ("spiritscale", "Spirit-Iron Scale", "medium", 5, 44, 55, 2.5, 9, "spirit_iron_ingot", "wyvern_leather", dict(head="helm", body="hauberk", hands="gauntlets", legs="chausses", feet="boots", cloak="cloak"), "Scales of spirit-iron that hum against a cultivator's skin."),
    ("riftscale", "Rift-Crystal Scale", "medium", 6, 52, 60, 3.3, 10, "rift_crystal_ingot", "wyvern_leather", dict(head="helm", body="hauberk", hands="gauntlets", legs="chausses", feet="boots", cloak="cloak"), "Crystal scales that never catch the light the same way twice."),
    # heavy
    ("bronzeplate", "Bronze Cuirass", "heavy", 1, 8, 18, 0.8, 4, "bronze_ingot", "sinew", dict(head="helm", body="cuirass", hands="gauntlets", legs="greaves", feet="sabatons", cloak="cape"), "Heavy bronze plates. Old fashioned, still effective."),
    ("iron", "Iron Plate", "heavy", 2, 14, 28, 1.0, 5, "iron_ingot", "leather", dict(head="helm", body="cuirass", hands="gauntlets", legs="greaves", feet="sabatons", cloak="cape"), "Riveted iron plate. Slow, loud and hard to kill."),
    ("steelplate", "Steel Plate", "heavy", 3, 26, 40, 1.4, 6, "steel_ingot", "hardened_leather", dict(head="helm", body="cuirass", hands="gauntlets", legs="greaves", feet="sabatons", cloak="cape"), "Blued steel plate, articulated at every joint."),
    ("knight", "Knight's Plate", "heavy", 4, 36, 48, 1.85, 8, "fine_steel_ingot", "hardened_leather", dict(head="helm", body="cuirass", hands="gauntlets", legs="greaves", feet="sabatons", cloak="mantle"), "A full harness of fine steel, made for the Crown's knights."),
    ("spiritplate", "Spirit-Iron Plate", "heavy", 5, 46, 56, 2.5, 9, "spirit_iron_ingot", "wyvern_leather", dict(head="helm", body="cuirass", hands="gauntlets", legs="greaves", feet="sabatons", cloak="mantle"), "Plate that flows with the wearer's qi."),
    ("riftplate", "Rift-Crystal Plate", "heavy", 6, 54, 60, 3.3, 10, "rift_crystal_ingot", "wyvern_leather", dict(head="helm", body="cuirass", hands="gauntlets", legs="greaves", feet="sabatons", cloak="mantle"), "Crystal plate from the deepest forges. The Rift is in every joint."),
    # robes
    ("linen", "Peasant Linen", "robe", 0, 1, 7, 0.6, 1, "cloth", "linen_thread", dict(head="hood", body="robe", hands="mitts", legs="leggings", feet="slippers", cloak="cloak"), "Plain undyed linen."),
    ("wool", "Acolyte Wool", "robe", 1, 5, 14, 0.8, 2, "felt", "wool_thread", dict(head="hood", body="robe", hands="mitts", legs="leggings", feet="slippers", cloak="cloak"), "Heavy wool, warm in a cold hall."),
    ("adept", "Adept's", "robe", 2, 12, 24, 1.0, 3, "linen_cloth", "silk_thread", dict(head="hat", body="robe", hands="gloves", legs="leggings", feet="slippers", cloak="mantle"), "Linen trimmed with silk and worked with a student's first wards."),
    ("enchanter", "Enchanter's Spidersilk", "robe", 3, 22, 34, 1.4, 5, "spidersilk_cloth", "silk_thread", dict(head="hat", body="robe", hands="gloves", legs="leggings", feet="slippers", cloak="mantle"), "Spidersilk: light, strong and quick to take an enchantment."),
    ("sage", "Sage's Silk", "robe", 4, 32, 44, 1.85, 7, "silk_cloth", "silk_thread", dict(head="hat", body="robe", hands="gloves", legs="leggings", feet="slippers", cloak="mantle"), "Layers of fine silk embroidered with concentration sigils."),
    ("spiritsilk", "Spirit-Silk", "robe", 5, 42, 54, 2.5, 9, "spirit_silk", "silk_thread", dict(head="hat", body="robe", hands="gloves", legs="leggings", feet="slippers", cloak="mantle"), "Cloth that holds qi. Cultivators wear it to train."),
    ("riftweave", "Riftweave", "robe", 6, 52, 60, 3.3, 10, "riftweave_cloth", "rift_silk_thread", dict(head="hat", body="robe", hands="gloves", legs="leggings", feet="slippers", cloak="shroud"), "Robes woven from Rift thread; the hem is always slightly elsewhere."),
]

PIECE_NAME = {"cap": "Cap", "hood": "Hood", "vest": "Vest", "jerkin": "Jerkin", "gloves": "Gloves", "leggings": "Leggings", "boots": "Boots",
              "cloak": "Cloak", "cuirass": "Cuirass", "jacket": "Jacket", "coat": "Coat", "mantle": "Mantle", "shroud": "Shroud", "helm": "Helm",
              "hauberk": "Hauberk", "gauntlets": "Gauntlets", "chausses": "Chausses", "coif": "Coif", "mail_mitts": "Mail Mitts",
              "lamellar": "Lamellar", "greaves": "Greaves", "sabatons": "Sabatons", "cape": "Cape", "robe": "Robe", "mitts": "Mitts",
              "slippers": "Slippers", "hat": "Hat"}
SLOT_ICON = {"head": {"light": "helm_leather", "medium": "helm", "heavy": "helm", "robe": "helm_cloth"},
             "body": {"light": "chest_leather", "medium": "chest_mail", "heavy": "chest_plate", "robe": "chest_cloth"},
             "hands": {"light": "gloves", "medium": "gloves", "heavy": "gloves", "robe": "gloves_cloth"},
             "legs": {"light": "legs_leather", "medium": "legs_heavy", "heavy": "legs_heavy", "robe": "legs_cloth"},
             "feet": {"light": "boots", "medium": "boots", "heavy": "boots", "robe": "boots_cloth"},
             "cloak": {"light": "cloak", "medium": "cloak", "heavy": "cloak", "robe": "cloak"}}
SET_SLOT_KEY = {"head": "head", "body": "body", "hands": "hands", "legs": "legs", "feet": "feet", "cloak": "cloak"}
SETS_OUT = {}

TREE_FOR_CLASS = {"robe": ["fire", "water", "wind", "lightning", "qi"], "light": ["shadow", "wind"], "medium": ["swordsmanship"], "heavy": ["earth", "command"]}
PATH_FOR_CLASS = {"robe": ["scholar", "tide"], "light": ["hunt", "wanderer"], "medium": ["blade"], "heavy": ["warden"]}


def build():
    for (key, disp, cls, t, lo, hi, power, rl, main, second, pieces, blurb) in SETS:
        c = CLS[cls]
        ids = []
        for slot in SLOTS:
            word = pieces[slot]
            item_id = "%s_%s" % (key, word)
            ids.append(item_id)
            if item_id in LEGACY:
                continue
            name = "%s %s" % (disp, PIECE_NAME[word])
            arm = max(1, int(round(BASE[slot] * c["mult"] * power)))
            lvl = min(hi, lo + LVL_OFF[slot])
            speed = BOOT_SPEED[cls] if slot == "feet" else (c["speed"] * (2 if slot == "body" else 1) if cls in ("medium", "heavy") else 0.0)
            ex = {}
            if cls == "robe":
                ex["magic"] = max(1, int(round(MAGIC[slot] * power * 1.6)))
                ex["resist"] = max(1, int(round(MAGIC[slot] * power * 0.8)))
            elif slot == "cloak":
                ex["resist"] = max(1, int(round(power * 2)))
            ex["armour_load"] = round(c["load"] * (1.0 if slot in ("body", "legs") else 0.6), 2)
            rarity = TRARITY[t] if power >= 1.0 or cls != "light" else 0
            if key in ("hide", "linen"):
                rarity = 0
            dur = int(round(DUR[slot] * c["dur"] * (0.7 + 0.3 * power * 1.3)))
            add(item_id, name, "gear", F, price=None, stack=1, weight=round({"head": 1.2, "body": 4.0, "hands": 0.5, "legs": 2.2, "feet": 1.2, "cloak": 0.8}[slot] * (0.35 if cls == "robe" else 0.8 if cls == "light" else 1.3 if cls == "medium" else 1.8), 2),
                rarity=rarity, level=lvl, desc="%s %s" % (blurb, "" if slot != "cloak" else "Worn over the armour."), tint=TIERS[t].color if cls != "light" and cls != "robe" else
                {"hide": "#c9a97a", "leather": "#a9763c", "hardened": "#8b5a32", "studded": "#7a5230", "bearhide": "#6b4a34", "wyvernhide": "#c58a3c", "riftstalker": "#7a5ab0",
                 "linen": "#eadfc4", "wool": "#c8c0b0", "adept": "#7c9ac8", "enchanter": "#b8c8e8", "sage": "#d8b0e0", "spiritsilk": "#9ff0dc", "riftweave": "#a985f0"}[key],
                glyph="fam:" + SLOT_ICON[slot][cls], slot=slot if slot != "cloak" else "cloak", armour=arm, speed=round(speed, 3), durability=dur, req_level=lvl,
                armour_class=cls, set=key, set_name=disp, material=key, tier=t, affinity=TREE_FOR_CLASS[cls], path=PATH_FOR_CLASS[cls], type=slot + "_armour", **ex)
            # recipe
            n = UNITS[slot]
            if cls == "light":
                ins = [(main, max(1, n - (1 if slot == "body" else 0)) if slot != "cloak" else 2)]
                if second == "wool_thread" or second == "linen_thread":
                    ins.append((second, 2))
                elif second in ("rivets",):
                    ins.append((second, 6 if slot == "body" else 3))
                else:
                    ins.append((second, 1))
                skill, stn = "leatherwork", "workbench"
            elif cls == "robe":
                ins = [(main, max(1, n - 1) if slot != "cloak" else 2), (second, 2 if slot in ("body", "legs") else 1)]
                skill, stn = "tailoring", "workbench" if t < 2 else "loom"
            else:
                ins = [(main, n if slot != "cloak" else 2)]
                if slot != "cloak":
                    ins.append((second, 1 if slot in ("head", "hands", "feet") else 2))
                else:
                    ins = [("cloth" if t < 3 else "linen_cloth", 2), (main, 1)]
                skill, stn = ("smithing", "anvil") if slot != "cloak" else ("tailoring", "workbench")
            rr = max(1, min(10, rl + (1 if slot == "body" else 0) - (1 if slot in ("hands", "cloak", "feet", "head") else 0)))
            craft(item_id, skill, stn, rr, ins, xp=8 + 6 * rr + 2 * n)
        SETS_OUT[key] = {"name": disp, "class": cls, "pieces": ids, "level": lo,
                         "bonuses": set_bonuses(cls, power, t)}

    sect_robes()
    accessories()


def set_bonuses(cls, power, t):
    p = power
    if cls == "robe":
        return {"3": {"magic": round(2 * p, 1)}, "5": {"magic": round(4 * p, 1), "qi_regen": round(0.25 * p, 2)}, "6": {"magic": round(7 * p, 1), "qi_regen": round(0.5 * p, 2), "resist": round(4 * p, 1)}}
    if cls == "light":
        return {"3": {"speed": 0.01}, "5": {"speed": 0.02, "crit": 0.02 + 0.005 * t}, "6": {"speed": 0.03, "crit": 0.05 + 0.01 * t, "max_stamina": round(6 * p, 1)}}
    if cls == "medium":
        return {"3": {"armour": round(1.0 * p, 1)}, "5": {"armour": round(2.5 * p, 1), "max_health": round(6 * p, 1)}, "6": {"armour": round(5 * p, 1), "max_health": round(12 * p, 1), "block": 0.03}}
    return {"3": {"armour": round(2.0 * p, 1)}, "5": {"armour": round(5 * p, 1), "max_health": round(10 * p, 1)}, "6": {"armour": round(9 * p, 1), "max_health": round(22 * p, 1), "block": 0.05}}


# --------------------------------------------------------------------------------------------------------
SECTS = [
    ("royal_ember_academy", "Ember Academy", "#d8552a", ["Cadet", "Kindled", "Flame Senior"], "fire"),
    ("ninefold_sword_pavilion", "Ninefold Pavilion", "#d9dde6", ["Outer Disciple", "Inner Disciple", "Core Disciple"], "swordsmanship"),
    ("iron_lotus_monastery", "Iron Lotus", "#e8a24c", ["Novice", "Brother", "Lotus Warden"], "fist_palm"),
    ("hall_of_four_currents", "Four Currents", "#58a8d8", ["Pupil", "Adept", "Current-Master"], "water"),
    ("dawnflame_seminary", "Dawnflame", "#f0c850", ["Acolyte", "Brightblade", "Dawn Paladin"], "fire"),
    ("greywatch_spear_hall", "Greywatch Spear Hall", "#8a9098", ["Recruit", "Spearman", "Hall Captain"], "swordsmanship"),
    ("ashford_staff_yard", "Ashford Staff Yard", "#b89a68", ["Yard Pupil", "Staff Bearer", "Yard Master"], "fist_palm"),
    ("hollow_moon_school", "Hollow Moon", "#9a88d8", ["Shade", "Moon Blade", "Night Master"], "shadow"),
    ("verdant_oath_sanctuary", "Verdant Oath", "#68b868", ["Sprout", "Oathkeeper", "Grove Elder"], "qi"),
    ("windstep_lodge", "Windstep Lodge", "#a8e0d0", ["Runner", "Rider", "Wind-Warden"], "wind"),
    ("anvil_brotherhood", "Anvil Brotherhood", "#c08050", ["Apprentice", "Journeyman", "Anvil-Master"], "earth"),
]
RANK_LVL = [8, 22, 38]
RANK_POWER = [0.8, 1.45, 2.4]


def sect_robes():
    for sid, disp, col, ranks, tree in SECTS:
        short = sid
        for r, rank in enumerate(ranks):
            iid = "sectrobe_%s_%d" % (sid, r + 1)
            lvl = RANK_LVL[r]
            pw = RANK_POWER[r]
            add(iid, "%s %s Robe" % (disp, rank), "gear", F, price=int(60 * (2.6 ** r)), stack=1, weight=1.4, rarity=min(3, r + 1), level=lvl,
                desc="The %s robe of %s, issued at the gate. Wearing it in the hall says who you answer to." % (rank.lower(), disp), tint=col, glyph="fam:chest_cloth",
                slot="body", armour=max(1, int(round(5 * 0.6 * pw))), speed=0.0, durability=int(120 * (1 + 0.3 * r)), req_level=lvl, magic=int(round(3 * pw * 1.4)),
                qi_regen=round(0.15 * pw, 2), armour_class="robe", sect=sid, sect_rank=r + 1, set="sect_" + sid, set_name=disp, tier=r + 1, affinity=[tree],
                path=["scholar", "blade"] if tree == "swordsmanship" else ["scholar"], type="sect_robe", armour_load=0.05, no_craft=True)
        sash = "sectsash_%s" % sid
        add(sash, "%s Sash" % disp, "gear", F, price=90, stack=1, weight=0.2, rarity=1, level=10, desc="A coloured sash that marks a disciple of %s." % disp,
            tint=col, glyph="fam:talisman", slot="trinket", speed=0.01, qi_regen=0.1, durability=150, req_level=10, sect=sid, set="sect_" + sid, set_name=disp, type="sect_token",
            affinity=[tree])
        SETS_OUT["sect_" + sid] = {"name": disp, "class": "robe", "pieces": ["sectrobe_%s_%d" % (sid, r + 1) for r in range(3)] + [sash], "level": 8,
                                   "bonuses": {"2": {"qi_regen": 0.2}}}


# accessories ---------------------------------------------------------------------------------------------------
THEMES = [
    ("vigor", "Vigor", "max_health", [8, 18, 34, 55], "Its wearer shrugs off a little more harm."),
    ("swiftness", "Swiftness", "speed", [0.02, 0.035, 0.05, 0.07], "Feet feel lighter."),
    ("warding", "Warding", "armour", [2, 4, 7, 11], "A faint shimmer turns glancing blows."),
    ("might", "Might", "damage", [1, 3, 5, 8], "Hits land a little harder."),
    ("focus", "Focus", "magic", [3, 6, 11, 18], "Magicules gather more easily around it."),
    ("breath", "Breath", "stamina_regen", [0.05, 0.1, 0.16, 0.24], "Stamina returns faster."),
    ("qi", "Qi", "qi_regen", [0.15, 0.3, 0.55, 0.9], "Qi settles to its wearer's pace."),
]
ACC_TIERS = [  # name, ingot, gem, level, rarity, tint, recipe level
    ("Silver", "silver_ingot", "garnet", 14, 1, "#e6ebf4", 3),
    ("Gold", "gold_ingot", "sapphire", 28, 2, "#ffd65c", 5),
    ("Spirit-Jade", "spirit_iron_ingot", "spirit_jade", 42, 3, "#6fe0a0", 8),
    ("Rift-Crystal", "rift_crystal_ingot", "rift_crystal", 54, 3, "#c79bff", 10),
]


def accessories():
    # plain bands (no bonus beyond a little armour), cheap
    for k, (nm, ingot, gem, lvl, rar, tint, rl) in enumerate(ACC_TIERS):
        add("%s_band" % ("silver" if k == 0 else "gold" if k == 1 else "jade" if k == 2 else "rift"), "%s Band" % nm, "gear", F, price=None, stack=1, weight=0.05,
            rarity=max(0, rar - 1), level=lvl, desc="A plain %s ring." % nm.lower(), tint=tint, glyph="fam:ring", slot="ring", armour=1 + k, durability=200, req_level=lvl, type="ring", tier=k + 2)
        craft("%s_band" % ("silver" if k == 0 else "gold" if k == 1 else "jade" if k == 2 else "rift"), "jewelry", ["jeweler_bench", "anvil"], rl, [(ingot, 1)], xp=8 + 4 * rl)
    for tid, tname, stat, vals, blurb in THEMES:
        for k, (nm, ingot, gem, lvl, rar, tint, rl) in enumerate(ACC_TIERS):
            v = vals[k]
            ex = {stat: v}
            add("ring_%s_%d" % (tid, k + 1), "%s Ring of %s" % (nm, tname), "gear", F, price=None, stack=1, weight=0.05, rarity=rar, level=lvl,
                desc="%s %s" % (blurb, "Set with %s." % gem.replace("_", " ")), tint=tint, glyph="fam:ring", slot="ring", durability=200, req_level=lvl, type="ring", tier=k + 2, **ex)
            craft("ring_%s_%d" % (tid, k + 1), "jewelry", ["jeweler_bench", "anvil"], rl, [(ingot, 1), (gem, 1)], xp=14 + 5 * rl)
            add("amulet_%s_%d" % (tid, k + 1), "%s Amulet of %s" % (nm, tname), "gear", F, price=None, stack=1, weight=0.1, rarity=rar, level=lvl + 1,
                desc="%s %s" % (blurb, "A %s pendant on a cord." % gem.replace("_", " ")), tint=tint, glyph="fam:amulet", slot="amulet", durability=180, req_level=lvl + 1,
                type="amulet", tier=k + 2, **{stat: round(v * 1.4, 3) if isinstance(v, float) else int(round(v * 1.4))})
            craft("amulet_%s_%d" % (tid, k + 1), "jewelry", ["jeweler_bench", "anvil"], min(10, rl + 1), [(ingot, 1), (gem, 1), ("silk_thread" if k >= 1 else "linen_thread", 2)], xp=16 + 5 * rl)
    # talismans (trinket slot): mostly dropped / bought from temples and sect shops
    TAL = [
        ("talisman_wolf_fang", "Wolf-Fang Charm", 8, 0, "speed", 0.02, "A fang on a thong. Wolves hesitate.", {"wolf_fang": 1}),
        ("talisman_hearthstone", "Hearthstone Charm", 6, 0, "max_health", 8, "A warm river stone from an Ashford hearth.", None),
        ("talisman_lucky_coin", "Lucky Coin", 4, 0, "luck", 0.05, "Bent, old and somehow always heads.", None),
        ("talisman_ward_stone", "Ward-Stone Pendant", 14, 1, "armour", 3, "Carved at a runestone. A little of the ward rides with you.", None),
        ("talisman_bone_charm", "Bone Charm", 14, 1, "crit", 0.04, "Carved from a skeleton's knuckle. Grim luck.", None),
        ("talisman_hunters_token", "Hunter's Token", 16, 1, "damage", 2, "Given by the Ashford hunters' lodge.", None),
        ("talisman_healers_knot", "Healer's Knot", 20, 1, "heal_power", 0.15, "A knotted cord blessed at the temple.", None),
        ("talisman_scholars_seal", "Scholar's Seal", 24, 1, "qi_regen", 0.25, "Stamped wax on silk. Calms the breath.", None),
        ("talisman_moonpetal", "Moonpetal Locket", 26, 2, "stealth", 0.1, "Pressed petals in a silver locket.", None),
        ("talisman_ember_sigil", "Ember Sigil", 30, 2, "magic", 8, "A fire-sigil on brass. Warm to the touch.", None),
        ("talisman_troll_tooth", "Troll-Tooth Fetish", 32, 2, "max_health", 30, "Carried by those who want to keep what they have.", None),
        ("talisman_spirit_jade", "Spirit-Jade Talisman", 42, 3, "qi_regen", 0.6, "Carved jade humming with stored qi.", None),
        ("talisman_windstep", "Windstep Feather", 36, 2, "speed", 0.06, "A hawk's feather bound with red thread.", None),
        ("talisman_iron_lotus", "Iron Lotus Beads", 34, 2, "armour", 6, "Prayer beads the monks count while they fight.", None),
        ("talisman_rift_shard", "Rift-Shard Fetish", 52, 3, "damage", 7, "A shard that wants to cut.", None),
        ("talisman_wyvern_scale", "Wyvern-Scale Amulet", 48, 3, "resist", 10, "One scale, drilled and strung.", None),
    ]
    for (tid, nm, lvl, rar, stat, val, desc, _x) in TAL:
        add(tid, nm, "gear", F, price=None if False else int(12 * (2.3 ** (rar + lvl / 25.0))), stack=1, weight=0.1, rarity=rar, level=lvl, desc=desc,
            tint=["#e8e0d0", "#8fd0ff", "#ffd65c", "#c79bff"][rar], glyph="fam:talisman", slot="trinket", durability=160, req_level=lvl, type="talisman", **{stat: val})
    # belts/pouches (trinket)
    for tid, nm, lvl, rar, stat, val, desc in [
        ("pouch_herbalist", "Herbalist's Satchel", 8, 0, "heal_power", 0.08, "Small pockets for cuttings. Herbs keep better in it."),
        ("quiver_hunter", "Hunter's Quiver", 10, 0, "crit", 0.02, "Holds thirty arrows and a little luck."),
        ("pouch_alchemist", "Alchemist's Bandolier", 16, 1, "potion_power", 0.1, "Loops for vials."),
        ("belt_smith", "Smith's Apron-Belt", 12, 0, "forge_quality", 0.05, "Keeps the tools where your hand expects them."),
    ]:
        add(tid, nm, "gear", F, price=int(20 + lvl * 4), stack=1, weight=0.5, rarity=rar, level=lvl, desc=desc, tint="#b08850", glyph="fam:belt", slot="trinket",
            durability=140, req_level=lvl, type="belt", **{stat: val})
