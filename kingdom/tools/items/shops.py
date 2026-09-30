"""Shop definitions: what each kind of merchant stocks at each settlement tier (1 village, 2 town, 3 city)."""
from core import ITEMS, LEGACY, GATHERED, price_of, raw_price

# item level caps for shop tier 1/2/3 and max rarity
CAP = {1: 14, 2: 34, 3: 56}
RMAX = {1: 1, 2: 2, 3: 3}


def info(i):
    if i in ITEMS:
        return ITEMS[i]
    return LEGACY.get(i, {})


def lvl(i):
    d = info(i)
    if "level" in d:
        return d["level"]
    return 1


def rar(i):
    return info(i).get("rarity", 0)


def all_ids():
    return list(LEGACY.keys()) + [g for g in GATHERED if g not in LEGACY] + list(ITEMS.keys())


def usable(i):
    return i not in ("food", "gear") and not info(i).get("unique") and not info(i).get("quest_item") and not info(i).get("spoiled")


def where(**kw):
    """Select ids by category / type / slot / name-contains. Values may be lists."""
    out = []
    for i in all_ids():
        if not usable(i):
            continue
        d = info(i)
        ok = True
        for k, v in kw.items():
            vals = v if isinstance(v, (list, tuple, set)) else [v]
            if k == "id_in":
                ok = i in vals
            elif k == "id_prefix":
                ok = any(i.startswith(x) for x in vals)
            elif k == "set":
                ok = d.get("set") in vals
            elif k == "not_type":
                ok = d.get("type") not in vals
            else:
                ok = d.get(k) in vals
            if not ok:
                break
        if ok:
            out.append(i)
    return out


def stock_for(i, scale=1.0):
    p = price_of(i) if (i in ITEMS or raw_price(i) is not None) else 5
    cat = info(i).get("category", "")
    if p <= 4:
        n, made = 24, 3.0
    elif p <= 15:
        n, made = 12, 1.5
    elif p <= 60:
        n, made = 6, 0.6
    elif p <= 250:
        n, made = 3, 0.0
    else:
        n, made = 2, 0.0
    n = max(1, int(round(n * scale)))
    imp = 0.0
    if cat in ("gear",) or (cat == "tool" and p > 30) or (made == 0.0):
        made = 0.0
        imp = round(n * 0.22, 2)
    else:
        made = round(min(made, n * 0.15 + 0.4) * scale, 2)
    if info(i).get("rarity", 0) >= 2:
        n = max(1, n // 2)
        imp = round(imp * 0.5, 2)
    return [i, n, made, imp]


SHOPS = {}


def shop(sid, name, blurb, rules, services=None, buys=None, min_tier=1, sect=None):
    """rules: list of (id list, min shop tier) - each id appears from that tier upward if its level/rarity allow."""
    tiers = {1: [], 2: [], 3: []}
    seen = {}
    for ids, t0 in rules:
        for i in ids:
            for t in (1, 2, 3):
                if t < t0:
                    continue
                if lvl(i) <= CAP[t] and rar(i) <= RMAX[t] + (1 if sect else 0) and i not in seen:
                    seen[i] = t
    for i, t in seen.items():
        tiers[t].append(stock_for(i, 1.0))
    for t in tiers:
        tiers[t].sort(key=lambda e: (lvl(e[0]), e[0]))
    SHOPS[sid] = {"name": name, "desc": blurb, "tiers": {str(t): tiers[t] for t in tiers}, "services": services or [], "buys": buys or [], "sect": sect}


def cat_ids(cat, **kw):
    return where(category=cat, **kw)


def build():
    foods_raw = where(type=["produce"])
    shop("general_store", "General Store", "A bit of everything: rope, candles, bedrolls and the things a traveller forgot.", [
        (where(id_in=["torch", "tinderbox", "waterskin", "bedroll", "rope", "candle", "worm_bait", "salt", "whetstone", "parchment_blank", "ink", "quill", "hardtack",
                     "trail_rations", "flint", "clay", "thatch", "log", "firewood", "bandage", "clean_water", "iron_nails", "mapcase", "hinges", "pottery_jug", "flax", "wool",
                     "lamp_oil", "glue", "wax", "lantern", "cooking_pot", "sand", "tallow", "charcoal"]), 1),
        (where(id_in=["tent_kit", "compass", "hunting_horn", "caltrops", "grappling_hook", "lockpicks", "fine_bait", "glowfly_lure", "spyglass", "empty_vial", "repair_kit"]), 2),
        (where(id_in=["flint_felling_axe", "flint_pickaxe", "flint_sickle", "flint_shovel", "bronze_felling_axe", "bronze_pickaxe", "bronze_sickle", "bronze_shovel", "wood_axe", "pickaxe", "hammer", "whittled_rod"]), 1)],
         services=["sell_anything_small"], buys=["material", "food", "tool"])
    shop("grocer", "Grocer", "Fresh from the farms: roots, fruit, grain, eggs, milk and cheese.", [
        (where(type=["produce"]) + where(id_in=["wheat", "barley", "flour", "egg", "cheese", "apple", "cabbage", "turnip", "wild_berries", "mushroom", "hops", "oats", "rye", "honey_jar", "milk", "butter", "salt"]), 1),
        (where(id_in=["rice", "tea_green", "tea_black", "pepper", "cinnamon", "ginger", "cloves", "saffron", "aged_cheese", "goat_cheese", "cream", "lard", "walnuts"]), 2)],
         buys=["food"])
    shop("butcher", "Butcher", "Meat, fish and what can be made from them.", [
        (where(type=["raw_meat"]) + where(id_in=["wolf_meat", "pork", "venison", "rabbit_meat", "perch", "trout", "pike", "raw_sausage", "lard", "salt", "jerky", "salted_fish", "smoked_fish", "cooking_salt_pork", "smoked_ham", "bacon", "sausages", "deer_hide", "hides"]), 1)],
         buys=["food", "hide"])
    shop("fishmonger", "Fishmonger", "River and lake fish, fresh and smoked, with bait and lines.", [
        (where(id_in=["perch", "trout", "pike", "carp", "eel", "salmon", "crayfish", "emberfin", "smoked_fish", "salted_fish", "fried_fish", "worm_bait", "fine_bait", "glowfly_lure", "whittled_rod", "yew_rod", "ironwood_rod", "fishing_net"]), 1)])
    shop("baker", "Baker", "Loaves, pies and sweet things from the oven.", [
        (where(type=["baked"]) + where(id_in=["bread", "berry_pie", "flour", "honey_jar", "butter", "egg", "hardtack", "yeast"]), 1)],
         buys=["food"])
    shop("tavern", "Tavern", "Hot meals, ale and a bed for the night.", [
        (where(type=["dish"]) + where(type=["drink"], not_type=["none"]) + where(id_in=["ale", "bread", "cheese", "stew", "grilled_fish", "venison_roast", "mushroom_soup", "berry_pie", "apple"]), 1),
        (where(type=["baked"]), 2)],
         services=["shared_room", "private_room", "meal", "gossip"], buys=["food"])
    smith_w = where(category="gear", type=["dagger", "sword", "sabre", "greatsword", "axe", "battleaxe", "mace", "warhammer", "spear", "halberd", "fist"])
    shop("blacksmith", "Blacksmith", "Blades, hammers, tools and bar metal, hot from the forge.", [
        (smith_w, 1),
        (where(category="tool", type=["tool"], slot=["main_hand"]) , 1),
        (where(id_in=["copper_ingot", "tin_ingot", "bronze_ingot", "iron_ingot", "steel_ingot", "fine_steel_ingot", "iron_nails", "hinges", "rivets", "horseshoe", "arrowheads", "coal", "iron_ore", "copper_ore", "tin_ore", "scrap_iron", "repair_kit", "whetstone", "lantern", "cooking_pot", "charcoal"]), 1),
        (where(id_in=["master_repair_kit", "silver_ingot", "flux", "quench_oil", "silver_ore"]), 2)],
         services=["repair", "sharpen"], buys=["gear", "ore", "material"])
    arm_w = where(category="gear", type=["head_armour", "body_armour", "hands_armour", "legs_armour", "feet_armour", "cloak_armour", "shield"])
    shop("armourer", "Armourer", "Mail, plate, helms and shields.", [
        ([i for i in arm_w if info(i).get("armour_class") in ("medium", "heavy") or info(i).get("type") == "shield" or i in ("iron_helm",)], 1),
        (where(id_in=["rivets", "leather", "hardened_leather", "steel_ingot", "fine_steel_ingot", "repair_kit", "master_repair_kit"]), 1)],
         services=["repair", "fit_armour"], buys=["gear"])
    shop("bowyer", "Bowyer & Fletcher", "Bows, crossbows, arrows and bolts.", [
        (where(category="gear", type=["shortbow", "longbow", "crossbow"]), 1),
        (where(category="ammo") + where(id_in=["arrowheads", "bowstring", "arrow_shafts", "goose_feather", "bronze_arrowheads", "steel_arrowheads", "quiver_hunter", "flint"]), 1)],
         services=["repair"], buys=["ammo"])
    shop("tailor", "Tailor", "Robes, cloaks, cloth and thread.", [
        ([i for i in arm_w if info(i).get("armour_class") == "robe" and info(i).get("slot") != "body" or info(i).get("armour_class") == "robe"], 1),
        (where(id_in=["cloth", "wool", "flax", "linen_thread", "wool_thread", "linen_cloth", "felt", "silk_cloth", "silk_thread", "silk_cocoon", "spidersilk_cloth", "waxed_cloth", "rope", "dye_red", "dye_blue", "dye_yellow", "dye_brown", "dye_black", "dye_green", "bedroll", "belt_pouch", "tent_kit"]), 1),
        (where(id_in=["rug_wool", "banner_house", "hearth_rug"]), 2)],
         services=["repair_cloth"], buys=["cloth", "material"])
    shop("leatherworker", "Leatherworker & Tanner", "Hides, leather and light armour; saddles and straps.", [
        ([i for i in arm_w if info(i).get("armour_class") == "light" or i.startswith("leather_")], 1),
        (where(id_in=["hides", "deer_hide", "fox_pelt", "wolf_pelt", "rabbit_pelt", "goat_hide", "boar_hide", "bear_pelt", "leather", "hardened_leather", "tannin", "tallow", "sinew", "fur_trim", "belt_pouch", "saddle", "bridle", "saddlebags", "horse_blanket", "waterskin", "mapcase", "quiver_hunter", "skinning_knife"]), 1),
        (where(id_in=["saddle_fine", "cart_harness", "barding_leather", "pouch_herbalist", "pouch_alchemist", "belt_smith"]), 2)],
         services=["repair_leather"], buys=["hide", "leather", "material"])
    shop("alchemist", "Alchemist", "Potions, remedies, herbs and the glass to mix them in.", [
        (where(category="healing", type=["potion", "remedy", "coating", "thrown", "repair"]) + where(type=["herb"]) + where(id_in=["empty_vial", "bandage", "healing_salve", "antidote", "stamina_draught", "healing_herb", "sulfur", "saltpetre", "quartz", "ash", "tallow", "lamp_oil", "wax", "clay_mortar", "bronze_mortar", "steel_mortar", "clean_water", "honey_jar"]), 1),
        (where(type=["pill", "elixir"]), 2),
        (where(type=["essence", "core"]), 3)],
         services=["brew_request"], buys=["healing", "herb", "monster_part"])
    shop("herbalist", "Herbalist", "A village healer's shelf: salves, simples and dried herbs.", [
        (where(id_in=["bandage", "healing_salve", "antidote", "minor_healing_potion", "styptic_powder", "ribwort_balm", "fever_cure", "burn_salve", "healing_herb", "feverfew", "nettle", "yarrow", "willow_bark", "puffball", "redcap", "thyme", "sage", "parsley", "bloodmoss", "sunroot", "frostmint", "emberleaf", "mushroom", "wild_berries", "honey_jar", "seed_healing_herb", "seed_thyme", "seed_sage", "seed_parsley", "seed_nettle", "stamina_draught", "empty_vial", "mint_tea", "healing_potion", "bonesetting_paste"]), 1)],
         services=["healing", "cure_injury"], buys=["healing", "herb"])
    shop("jeweller", "Jeweller", "Rings, amulets and cut stones.", [
        (where(category="gear", type=["ring", "amulet"]), 1),
        (where(id_in=["quartz", "garnet", "amethyst", "moonstone", "sapphire", "ruby", "ember_opal", "silver_ingot", "gold_ingot", "silver_ore", "gold_nugget", "copper_ring", "amber_beads", "silver_band", "gold_band"]), 1),
        (where(category="gear", type=["talisman"]), 2)],
         services=["appraise"], buys=["gem", "ring", "amulet", "ingot"], min_tier=2)
    shop("carpenter", "Carpenter & Lumberyard", "Timber, planks, shingles and furniture.", [
        (where(id_in=["log", "plank", "oak_log", "oak_plank", "yew_log", "ironwood_log", "ironwood_plank", "shingles", "bark", "resin", "iron_nails", "hinges", "glue", "rope", "thatch", "wood_axe", "flint_felling_axe", "bronze_felling_axe", "iron_saw", "bronze_saw", "hammer", "bowstring", "arrow_shafts"]), 1),
        (where(category="furniture"), 2)],
         services=["commission_furniture"], buys=["timber", "furniture"])
    shop("mason", "Mason & Quarry", "Stone, bricks, lime and glass.", [
        (where(id_in=["stone", "cut_stone", "clay", "brick", "roof_tile", "lime", "mortar", "sand", "limestone", "slate", "flint", "marble", "glass", "iron_nails", "rope", "bronze_chisel", "iron_chisel", "pickaxe", "bronze_pickaxe", "flint_pickaxe", "coal"]), 1)],
         buys=["mineral", "construction"])
    shop("miners_supply", "Miners' Supply", "Ores, coal and everything you take underground.", [
        (where(category="ore") + where(id_in=["coal", "pickaxe", "bronze_pickaxe", "steel_pickaxe", "flint_pickaxe", "torch", "lantern", "lamp_oil", "rope", "flint", "pasty", "hardtack", "spirit_stone_lesser", "quartz", "garnet", "sulfur", "saltpetre"]), 1)],
         buys=["ore", "gem"])
    shop("stable", "Stable & Tack", "Horses, saddles, feed and farriery.", [
        (where(category="tack") + where(category="feed") + where(id_in=["horseshoe", "horses", "hoof_pick", "horseshoes_steel", "saddle"]), 1)],
         services=["stabling", "farrier"], buys=["tack", "feed"])
    shop("farm_supply", "Farm Supply", "Seeds, feed and hand tools for the field.", [
        (where(category="seed") + where(category="feed") + where(id_in=["flint_sickle", "bronze_sickle", "iron_sickle", "steel_sickle", "flint_shovel", "bronze_shovel", "iron_shovel", "steel_shovel", "hay_bale", "wheat", "barley", "salt_lick", "rope"]), 1)],
         buys=["seed", "feed", "food"])
    shop("bookseller", "Bookseller & Scribe", "Primers, scrolls, almanacs and writing supplies.", [
        (where(category="lore") + where(id_in=["parchment_blank", "ink", "quill"]), 1),
        (where(category="manual", tier=[1, 2]) + where(type=["scroll"]), 2),
        (where(category="manual", tier=[3]), 3)],
         services=["read_aloud", "copy_text"], buys=["lore", "manual"], min_tier=2)
    shop("temple", "Temple", "Healing, blessing, holy water and small charms.", [
        (where(id_in=["holy_water", "holy_oil", "minor_healing_potion", "healing_potion", "bandage", "healing_salve", "antidote", "fever_cure", "antivenom", "candle", "candle_box", "talisman_ward_stone", "talisman_healers_knot", "talisman_hearthstone", "scroll_ward", "soul_calm_draught", "clean_water", "incense"]), 1),
        (where(id_in=["greater_healing_potion", "meridian_pill", "pill_clarity", "talisman_scholars_seal", "bonesetting_paste", "lore_sect_customs"]), 2)],
         services=["healing", "blessing", "cure_injury", "confession"], buys=["healing"])
    shop("adventurer_outfitter", "Adventurers' Outfitter", "What the guild sells to people who take contracts.", [
        (where(id_in=["minor_healing_potion", "healing_potion", "greater_healing_potion", "bandage", "torch", "lantern", "rope", "lockpicks", "tinderbox", "waterskin", "bedroll", "trail_rations", "jerky", "hardtack", "repair_kit", "whetstone", "caltrops",
                     "grappling_hook", "smoke_bomb", "alchemists_fire", "antidote", "antivenom", "stamina_draught", "greater_stamina_draught", "fire_oil", "blade_poison_weak", "old_map_fragment", "mapcase", "worm_bait", "compass", "spyglass", "hunting_horn", "tent_kit"]), 1),
        (where(id_in=["superior_healing_potion", "master_repair_kit", "flash_powder", "frost_flask", "qi_draught_lesser", "qi_draught", "stoneskin_potion", "strength_draught", "fleetfoot_potion", "night_eye_potion", "scroll_recall", "scroll_identify"]), 2)],
         services=["post_contracts", "repair"], buys=["monster_part", "healing"])
    shop("black_market", "Back-Alley Fence", "No questions, no receipts. Poisons, picks and other things.", [
        (where(id_in=["lockpicks", "caltrops", "smoke_bomb", "flash_powder", "blade_poison_weak", "blade_poison", "shadow_draught", "nightshade", "hemlock", "venom_sac", "spider_fang", "key_brass", "grappling_hook", "firewater", "stolen_goods", "scroll_shuriken", "scroll_smoke", "manual_shadow_t1", "manual_shadow_t2", "night_eye_potion", "luck_draught", "dagger", "iron_dagger"]), 2),
        (where(id_in=["wyvern_venom_coat", "rift_dust", "scar_ichor", "moonstone", "ruby", "spirit_jade"]), 3)],
         services=["fence_goods", "no_questions"], buys=["gear", "gem", "key", "quest"], min_tier=2)

    # sect shops: manuals for their trees, pills, robes, sashes
    import armour
    import misc
    for sid, disp, col, ranks, tree in armour.SECTS:
        trees = [t for t, ss in misc.SECTS_BY_TREE.items() if sid in ss]
        man = []
        for t in trees:
            man += [m for m in misc.MANUALS if m.startswith("manual_%s_t" % t)]
        robes = ["sectrobe_%s_%d" % (sid, r + 1) for r in range(3)] + ["sectsash_%s" % sid]
        pills = ["pill_qi_gathering", "pill_qi_condensation", "pill_foundation", "pill_foundation_nourish", "pill_body_temper_1", "pill_clarity", "qi_draught_lesser", "qi_draught",
                 "spirit_stone_lesser", "green_tea", "spirit_stone", "pill_core_formation", "pill_body_temper_2", "meridian_pill", "soul_calm_draught"]
        shop("sect_" + sid, "%s Hall Shop" % disp, "Sold to members and sponsored guests of %s." % disp, [
            ([m for m in man if info(m).get("tier", 1) <= 2], 1), ([m for m in man if info(m).get("tier", 1) == 3], 2), ([m for m in man if info(m).get("tier", 1) >= 4], 3),
            (robes[:1] + robes[3:], 1), (robes[1:2], 2), (robes[2:3], 3), (where(id_in=pills), 1)], services=["join_sect", "sect_quests", "training"], buys=["manual", "monster_part", "core"], sect=sid)

    # settlement assembly
    SETTLEMENTS.update({
        "hamlet": {"tier": 1, "shops": ["general_store", "grocer"]},
        "village": {"tier": 1, "shops": ["general_store", "grocer", "tavern", "herbalist", "blacksmith", "baker", "carpenter", "farm_supply"]},
        "frontier_town": {"tier": 2, "shops": ["general_store", "grocer", "butcher", "tavern", "herbalist", "blacksmith", "armourer", "bowyer", "leatherworker", "miners_supply", "adventurer_outfitter", "stable", "temple", "farm_supply", "baker"]},
        "town": {"tier": 2, "shops": ["general_store", "grocer", "butcher", "fishmonger", "baker", "tavern", "blacksmith", "armourer", "bowyer", "tailor", "leatherworker", "alchemist", "herbalist", "carpenter", "mason", "stable", "farm_supply", "temple", "jeweller", "bookseller", "adventurer_outfitter"]},
        "castle": {"tier": 3, "shops": ["general_store", "grocer", "butcher", "fishmonger", "baker", "tavern", "blacksmith", "armourer", "bowyer", "tailor", "leatherworker", "alchemist", "jeweller", "carpenter", "mason", "stable", "temple", "bookseller", "adventurer_outfitter", "black_market", "miners_supply", "farm_supply", "herbalist", "sect_royal_ember_academy", "sect_greywatch_spear_hall", "sect_ashford_staff_yard"]},
    })
    IDENT.update({"smithy": ["blacksmith", "armourer"], "market": ["general_store", "grocer", "tailor", "jeweller"], "tower": ["armourer", "bowyer"], "temple": ["temple", "herbalist"],
                  "library": ["bookseller", "alchemist"], "barracks": ["armourer", "bowyer", "blacksmith"], "wall": ["armourer"], "gate": ["adventurer_outfitter"]})


SETTLEMENTS = {}
IDENT = {}
