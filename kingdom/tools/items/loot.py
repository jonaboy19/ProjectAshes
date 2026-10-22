"""Loot tables by danger tier (1..5) and theme, and per-species monster drops."""
from core import ITEMS, LEGACY, GATHERED, price_of
import shops

# danger tier -> (level window lo, hi, max rarity, rolls, gold)
TIER = {1: (1, 14, 1, (1, 2), (2, 14)), 2: (8, 26, 2, (1, 3), (8, 45)), 3: (20, 40, 2, (2, 3), (25, 120)),
        4: (34, 52, 3, (2, 4), (70, 300)), 5: (46, 60, 3, (3, 5), (180, 900))}
RW = {0: 100.0, 1: 40.0, 2: 12.0, 3: 3.5, 4: 0.3}


def ids(**kw):
    return shops.where(**kw)


def lv(i):
    return shops.lvl(i)


def pool(idlist, tier, weight=1.0, cnt=(1, 1), window=None, raw=None):
    lo, hi, rmax, _r, _g = TIER[tier]
    if window:
        lo, hi = window
    out = []
    for i in idlist:
        if i not in ITEMS and i not in LEGACY and i not in GATHERED:
            continue
        l = lv(i)
        r = shops.rar(i)
        if l > hi or l < lo - 14 or r > rmax:
            continue
        # prefer items near the tier's level window
        fit = 1.0 if l >= lo else max(0.15, 1.0 - (lo - l) / 14.0)
        w = RW.get(r, 1.0) * weight * fit
        stack = shops.info(i).get("max_stack_size", 1)
        c = cnt
        if stack >= 20 and cnt == (1, 1):
            c = (1, 3)
        out.append([i, round(w, 2), c[0], c[1]])
    return out


def build():
    weapons = ids(category="gear", type=["dagger", "sword", "sabre", "greatsword", "axe", "battleaxe", "mace", "warhammer", "spear", "halberd", "fist", "shortbow", "longbow", "crossbow", "staff", "wand"])
    armour = ids(category="gear", type=["head_armour", "body_armour", "hands_armour", "legs_armour", "feet_armour", "cloak_armour", "shield"])
    jewel = ids(category="gear", type=["ring", "amulet", "talisman", "belt"])
    potions = ids(category="healing", type=["potion", "remedy"])
    pills = ids(type=["pill", "elixir"])
    bombs = ids(type=["thrown", "coating"])
    food_cooked = ids(type=["dish", "baked", "preserved"])
    food_raw = ids(type=["produce"])
    drinks = ids(type=["drink"])
    herbs = ids(type=["herb"])
    ores = ids(category="ore") + ids(type=["mineral"])
    gems = ids(type=["gem"])
    ingots = ids(type=["ingot"])
    hides = ids(type=["hide", "leather"])
    cloth = ids(type=["cloth", "thread"])
    parts = ids(type=["monster_part"])
    cores = ids(type=["core", "essence"])
    spirit = ids(type=["spirit_stone"])
    ammo = ids(category="ammo")
    tools = ids(category="tool")
    manuals = ids(category="manual", type=["manual"]) + ids(type=["scroll"])
    scrolls = ids(type=["scroll"])
    lore = ids(category="lore")
    pm_dungeon = ids(power_source=["dungeon"])
    pm_any = ids(power_source=["dungeon", "teacher"]) + ids(power_source=["academy", "sect_hall"])
    keys = ids(category="key")
    kits = ids(type=["kit", "repair"])
    trade = ids(type=["trade_good"])
    timber = ids(type=["timber"])
    wood_ = ids(type=["fitting", "construction", "fuel", "craft_aid", "smith_aid", "container"])
    coins = ["scrap_iron"]

    THEMES = {}

    def theme(name, desc, parts_spec):
        THEMES[name] = {"desc": desc, "parts": parts_spec}

    theme("beast", "Animals and natural monsters: hides, fangs, meat.", [(ids(id_in=["wolf_fang", "boar_tusk", "boar_tusk_fine", "bear_claw", "bone_shard", "hornet_honey"]) + hides + ids(type=["raw_meat"]), 1.0, (1, 2)), (herbs, 0.1, (1, 2))])
    theme("humanoid", "Raiders and warbands: weapons, armour, rations, coin.", [(weapons, 0.35, (1, 1)), (armour, 0.3, (1, 1)), (food_cooked + drinks, 0.5, (1, 2)), (ammo, 0.4, (3, 12)), (potions, 0.35, (1, 1)), (ids(id_in=["scrap_iron", "goblin_tooth", "goblin_ear", "orc_tusk", "rope", "torch", "whetstone", "iron_nails"]), 0.6, (1, 3)), (keys, 0.06, (1, 1)), (gems, 0.05, (1, 1))])
    theme("undead", "The restless dead: bones, old steel, holy trinkets.", [(ids(id_in=["bone_shard", "bone_dust", "ghost_essence", "ash_residue", "ghostcap"]), 1.0, (1, 3)), (weapons, 0.25, (1, 1)), (armour, 0.2, (1, 1)), (jewel, 0.18, (1, 1)), (gems, 0.12, (1, 1)), (ids(id_in=["holy_water", "holy_oil", "candle"]), 0.15, (1, 2)), (keys, 0.08, (1, 1))])
    theme("rift", "Rift and Scar creatures: ichor, crystals and cores.", [(ids(id_in=["scar_ichor", "rift_dust", "scar_crystal", "scarbloom", "corrupted_fang", "rift_crystal"]), 1.0, (1, 2)), (cores, 0.5, (1, 1)), (gems, 0.2, (1, 1)), (spirit, 0.2, (1, 2)), (ids(id_in=["rift_silk_thread", "spirit_silk_cocoon", "spirit_iron_ore"]), 0.1, (1, 1))])
    theme("chest_common", "Ordinary chests, crates and sacks.", [(food_cooked + food_raw, 0.5, (1, 3)), (potions + ids(id_in=["bandage", "healing_salve", "antidote"]), 0.4, (1, 2)), (tools + kits, 0.25, (1, 1)), (hides + cloth + timber + wood_, 0.4, (1, 4)), (ores + ingots, 0.3, (1, 3)), (weapons, 0.12, (1, 1)), (armour, 0.12, (1, 1)), (gems, 0.05, (1, 1)), (drinks, 0.25, (1, 2))])
    theme("chest_military", "Garrison lockers and armouries.", [(weapons, 0.8, (1, 1)), (armour, 0.8, (1, 1)), (ammo, 0.6, (5, 20)), (kits, 0.4, (1, 2)), (potions, 0.4, (1, 2)), (ids(id_in=["trail_rations", "jerky", "hardtack"]), 0.4, (2, 6)), (ingots, 0.2, (1, 2))])
    theme("chest_arcane", "Mages' chests and sect caches.", [(manuals, 0.6, (1, 1)), (pm_any, 0.4, (1, 1)), (scrolls, 0.5, (1, 2)), (pills, 0.5, (1, 2)), (potions, 0.3, (1, 1)), (gems, 0.3, (1, 2)), (jewel, 0.3, (1, 1)), (cores, 0.25, (1, 1)), (spirit, 0.3, (1, 3)), (herbs, 0.2, (1, 3)), (lore, 0.12, (1, 1))])
    theme("chest_treasure", "Strongboxes with real money in them.", [(gems, 0.7, (1, 3)), (ingots, 0.4, (1, 2)), (jewel, 0.45, (1, 1)), (trade, 0.25, (1, 1)), (ids(id_in=["gold_nugget", "silver_ore"]), 0.4, (1, 4)), (lore, 0.1, (1, 1)), (weapons, 0.12, (1, 1)), (armour, 0.12, (1, 1)), (spirit, 0.15, (1, 2))])
    theme("dungeon_crypt", "Crypts: undead leavings and burial goods.", [(ids(id_in=["bone_shard", "bone_dust", "ghost_essence", "ghostcap", "candle"]), 0.7, (1, 3)), (jewel, 0.3, (1, 1)), (gems, 0.25, (1, 2)), (weapons, 0.25, (1, 1)), (armour, 0.25, (1, 1)), (manuals, 0.15, (1, 1)), (pm_dungeon, 0.18, (1, 1)), (keys, 0.12, (1, 1)), (ids(id_in=["holy_water", "holy_oil"]), 0.2, (1, 2)), (lore, 0.1, (1, 1))])
    theme("dungeon_cave", "Caves and mines: ores, gems, beast remains.", [(ores, 1.0, (1, 4)), (gems, 0.4, (1, 2)), (ingots, 0.15, (1, 2)), (parts + hides, 0.35, (1, 2)), (ids(id_in=["torch", "pasty", "pickaxe", "rope"]), 0.2, (1, 2)), (herbs, 0.15, (1, 3)), (spirit, 0.1, (1, 2))])
    theme("dungeon_ruin", "Ruins: old steel, lore and trinkets.", [(weapons, 0.35, (1, 1)), (armour, 0.35, (1, 1)), (jewel, 0.25, (1, 1)), (lore, 0.2, (1, 1)), (keys, 0.15, (1, 1)), (manuals, 0.15, (1, 1)), (pm_dungeon, 0.18, (1, 1)), (gems, 0.2, (1, 2)), (potions, 0.3, (1, 1)), (ids(id_in=["old_map_fragment", "treasure_map"]), 0.08, (1, 1))])
    theme("dungeon_warren", "Goblin warrens: scraps, stolen goods, raw meat.", [(ids(id_in=["scrap_iron", "goblin_tooth", "goblin_ear", "iron_nails", "rope", "torch", "goblin_warmap"]), 0.9, (1, 4)), (weapons, 0.25, (1, 1)), (armour, 0.15, (1, 1)), (food_cooked + drinks, 0.4, (1, 2)), (trade, 0.1, (1, 1)), (ids(id_in=["stolen_goods"]), 0.08, (1, 1)), (gems, 0.1, (1, 1))])
    theme("tower", "Tower floors: arcane treasure, cores and relics.", [(manuals, 0.5, (1, 1)), (pm_dungeon, 0.5, (1, 1)), (pills, 0.5, (1, 2)), (cores, 0.5, (1, 1)), (gems, 0.4, (1, 2)), (jewel, 0.4, (1, 1)), (weapons, 0.3, (1, 1)), (armour, 0.3, (1, 1)), (spirit, 0.4, (1, 3)), (herbs, 0.25, (1, 3)), (ingots, 0.15, (1, 2)), (lore, 0.1, (1, 1))])
    theme("boss", "Boss rewards: the best gear a tier can give.", [(weapons, 0.8, (1, 1)), (armour, 0.8, (1, 1)), (jewel, 0.5, (1, 1)), (pills, 0.3, (1, 1)), (cores, 0.5, (1, 1)), (gems, 0.4, (1, 2)), (manuals, 0.25, (1, 1)), (pm_dungeon, 0.3, (1, 1)), (ids(id_in=["beast_core", "lesser_core", "greater_core"]), 0.4, (1, 1))])
    theme("bandit_camp", "Bandit camps: loot from the road.", [(weapons, 0.4, (1, 1)), (armour, 0.3, (1, 1)), (food_cooked + drinks, 0.5, (1, 3)), (trade, 0.18, (1, 1)), (ids(id_in=["stolen_goods", "bandit_ledger", "lockpicks", "caltrops", "blade_poison_weak", "key_iron"]), 0.3, (1, 1)), (ammo, 0.4, (3, 10)), (potions, 0.3, (1, 1)), (gems, 0.1, (1, 1)), (jewel, 0.12, (1, 1))])
    theme("orc_camp", "Orc camps: tusks, rough steel, strong drink.", [(ids(id_in=["orc_tusk", "boar_hide", "bear_pelt", "iron_ore", "scrap_iron", "bear_meat", "pork", "tribal_token"]), 0.8, (1, 3)), (weapons, 0.35, (1, 1)), (armour, 0.25, (1, 1)), (drinks + food_cooked, 0.4, (1, 2)), (ids(id_in=["stout", "strong_ale", "kumis", "firewater"]), 0.2, (1, 3))])
    theme("ore_vein", "Mining nodes.", [(ores, 1.0, (1, 3)), (gems, 0.2, (1, 1))])
    theme("herb_patch", "Herb patches.", [(herbs, 1.0, (1, 3))])
    theme("village_home", "Houses, barns and larders.", [(food_cooked + food_raw, 0.8, (1, 3)), (tools, 0.15, (1, 1)), (cloth + hides, 0.25, (1, 3)), (drinks, 0.3, (1, 2)), (potions, 0.15, (1, 1))])

    out = {"tiers": {}, "themes": {}, "monsters": {}}
    for t, (lo, hi, rmax, rolls, gold) in TIER.items():
        out["tiers"][str(t)] = {"levels": [lo, hi], "max_rarity": rmax, "rolls": list(rolls), "gold": list(gold)}
    for name, th in THEMES.items():
        tabs = {}
        for t in TIER:
            entries = []
            merged = {}
            for (idl, wmul, cnt) in th["parts"]:
                for e in pool(idl, t, wmul, cnt):
                    if e[0] in merged:
                        merged[e[0]][1] = round(merged[e[0]][1] + e[1], 2)
                    else:
                        merged[e[0]] = e
            entries = sorted(merged.values(), key=lambda e: (-e[1], e[0]))
            # trim very long tails to keep files compact but varied
            kept = [e for e in entries if e[1] >= 0.35][:60]
            # path manuals are never trimmed away: every manual has to be findable (tests/test_path_sources.gd)
            kept += [[e[0], max(e[1], 0.5), e[2], e[3]] for e in entries if e[0].startswith("pm_") and e not in kept]
            entries = kept
            lo, hi, rmax, rolls, gold = TIER[t]
            mult = {"boss": 1.6, "tower": 1.3, "chest_treasure": 1.3, "chest_arcane": 1.1}.get(name, 1.0)
            tabs[str(t)] = {"rolls": [max(1, int(rolls[0] * mult)), max(1, int(round(rolls[1] * mult)))], "gold": [int(gold[0] * mult), int(gold[1] * mult)], "entries": entries}
            if name in ("ore_vein", "herb_patch", "beast"):
                tabs[str(t)]["gold"] = [0, 0]
            if name in ("boss", "tower") and t >= 4:
                uniq = [[i, 0.6 if ITEMS[i].get("rarity") == 3 else 0.12, 1, 1] for i in ITEMS if ITEMS[i].get("unique") and ITEMS[i].get("type") != "relic" and lo - 10 <= ITEMS[i].get("level", 1) <= hi + 4]
                tabs[str(t)]["entries"] += uniq
        out["themes"][name] = {"desc": th["desc"], "tiers": tabs}

    # species -> theme and guaranteed drops: [item, chance, min, max]
    M = {
        "wolf": ("beast", 1, [["wolf_pelt", 0.7, 1, 1], ["wolf_meat", 0.8, 1, 2], ["wolf_fang", 0.35, 1, 2], ["bone_shard", 0.1, 1, 1]]),
        "corrupted_wolf": ("rift", 2, [["wolf_pelt", 0.5, 1, 1], ["corrupted_fang", 0.5, 1, 2], ["scar_ichor", 0.3, 1, 1], ["minor_core", 0.08, 1, 1]]),
        "boar": ("beast", 1, [["pork", 0.9, 1, 2], ["boar_hide", 0.6, 1, 1], ["boar_tusk", 0.7, 1, 2], ["boar_tusk_fine", 0.1, 1, 1]]),
        "bear": ("beast", 2, [["bear_pelt", 0.85, 1, 1], ["bear_meat", 0.9, 1, 3], ["bear_claw", 0.6, 1, 3], ["tallow", 0.5, 1, 2], ["minor_core", 0.12, 1, 1]]),
        "troll": ("beast", 3, [["troll_hide", 0.7, 1, 1], ["troll_blood", 0.6, 1, 2], ["troll_tooth", 0.5, 1, 2], ["troll_meat", 0.6, 1, 2], ["lesser_core", 0.3, 1, 1], ["beast_core", 0.04, 1, 1]]),
        "wyvern": ("beast", 4, [["wyvern_hide", 0.7, 1, 2], ["wyvern_scale", 0.8, 2, 5], ["wyvern_fang", 0.5, 1, 2], ["wyvern_wing_membrane", 0.4, 1, 1], ["wyvern_venom_gland", 0.3, 1, 1], ["wyvern_meat", 0.5, 1, 2], ["beast_core", 0.25, 1, 1], ["greater_core", 0.03, 1, 1]]),
        "goblin": ("humanoid", 1, [["goblin_tooth", 0.6, 1, 2], ["goblin_ear", 0.5, 1, 1], ["scrap_iron", 0.5, 1, 2]]),
        "goblin_chief": ("humanoid", 2, [["goblin_tooth", 1.0, 2, 4], ["goblin_ear", 1.0, 1, 2], ["scrap_iron", 0.8, 2, 4], ["key_warren", 0.25, 1, 1], ["goblin_warmap", 0.3, 1, 1]]),
        "orc": ("orc_camp", 2, [["orc_tusk", 0.5, 1, 2], ["scrap_iron", 0.4, 1, 3], ["bear_meat", 0.1, 1, 1]]),
        "orc_chief": ("orc_camp", 3, [["orc_tusk", 1.0, 2, 4], ["tribal_token", 0.4, 1, 1], ["bonecleaver_of_tuskridge", 0.04, 1, 1], ["lesser_core", 0.15, 1, 1]]),
        "bandit": ("bandit_camp", 1, [["bandit_ledger", 0.05, 1, 1], ["lockpicks", 0.08, 1, 1]]),
        "bandit_leader": ("bandit_camp", 2, [["bandit_ledger", 0.4, 1, 1], ["key_iron", 0.3, 1, 1], ["stolen_goods", 0.4, 1, 1], ["lockpicks", 0.3, 1, 2]]),
        "skeleton": ("undead", 1, [["bone_shard", 0.9, 1, 3], ["bone_dust", 0.3, 1, 1], ["rusted_blade_dummy", 0.0, 1, 1]]),
        "ash_ghost": ("undead", 2, [["ghost_essence", 0.5, 1, 1], ["ash_residue", 0.8, 1, 3], ["ash_relic", 0.04, 1, 1]]),
        "giant_spider": ("beast", 2, [["spider_fang", 0.6, 1, 2], ["venom_sac", 0.4, 1, 1], ["spider_silk", 0.7, 1, 3]]),
        "scar_beast": ("rift", 3, [["scar_ichor", 0.7, 1, 2], ["scar_crystal", 0.4, 1, 1], ["rift_dust", 0.3, 1, 2], ["lesser_core", 0.2, 1, 1]]),
        "rift_creature": ("rift", 4, [["rift_dust", 0.8, 1, 3], ["rift_crystal", 0.5, 1, 2], ["rift_silk_thread", 0.2, 1, 1], ["beast_core", 0.2, 1, 1], ["rift_core", 0.02, 1, 1]]),
        "rabbit": ("beast", 1, [["rabbit_meat", 0.9, 1, 1], ["rabbit_pelt", 0.6, 1, 1]]),
        "deer": ("beast", 1, [["venison", 0.9, 1, 2], ["deer_hide", 0.8, 1, 1]]),
        "fox": ("beast", 1, [["fox_pelt", 0.8, 1, 1]]),
    }
    for sp, (th, t, drops) in M.items():
        drops = [d for d in drops if d[0] in ITEMS or d[0] in LEGACY or d[0] in GATHERED]
        out["monsters"][sp] = {"theme": th, "tier": t, "drops": drops}
    return out
