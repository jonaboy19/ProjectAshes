"""Alchemy: potions, remedies, cultivation pills, elixirs, coatings, bombs, and repair goods."""
from core import add, craft

F = "alchemy"
AT = ["alchemy_table"]


def pot(i, name, fam, tint, desc, lvl, rarity=0, heal=None, buff=None, cures=None, stack=10, weight=0.25, kind="potion", **kw):
    ex = dict(kw)
    if buff:
        ex["buff_name"], ex["buff_stat"], ex["buff_value"], ex["buff_hours"] = buff
    return add(i, name, "healing", F, price=None, stack=stack, weight=weight, rarity=rarity, level=lvl, desc=desc, tint=tint,
               glyph="fam:" + fam, heal=heal, cures=cures, type=kind, **ex)


def brew(out, level, inputs, count=1, xp=None, time=None, rid=None):
    return craft(out, "alchemy", AT, level, inputs, count=count, xp=xp, time=time, rid=rid)


def build():
    V = ("empty_vial", 1)
    # ---- healing -------------------------------------------------------------------------------------
    pot("minor_healing_potion", "Minor Healing Potion", "potion", "#ff6a6a", "Red, sweet and quick. Closes scrapes.", 1, heal=40)
    pot("healing_potion", "Healing Potion", "potion", "#ff4a5a", "A proper draught; mends most cuts in a breath.", 10, 1, heal=90)
    pot("greater_healing_potion", "Greater Healing Potion", "potion", "#ff2a4a", "Dense, bright red. Even deep wounds knit.", 24, 1, heal=160)
    pot("superior_healing_potion", "Superior Healing Potion", "potion", "#e01a4a", "Brewed by master alchemists; wounds close as you watch.", 38, 2, heal=260)
    pot("grand_healing_potion", "Grand Healing Potion", "potion", "#c8104a", "A sect-grade restorative. Drink it and the fight starts again.", 52, 3, heal=400)
    brew("minor_healing_potion", 1, [("healing_herb", 2), V], xp=8)
    brew("healing_potion", 3, [("healing_herb", 3), ("yarrow", 1), ("sunroot", 1), V], xp=16)
    brew("greater_healing_potion", 5, [("healing_herb", 4), ("yarrow", 2), ("bloodmoss", 2), V], xp=30)
    brew("superior_healing_potion", 7, [("bloodmoss", 3), ("troll_blood", 1), ("spirit_ginseng", 1), V], xp=56, time=3.2)
    brew("grand_healing_potion", 9, [("troll_blood", 2), ("spirit_ginseng", 1), ("qi_blossom", 1), V], xp=90, time=4.0)
    # stamina / qi
    pot("greater_stamina_draught", "Greater Stamina Draught", "potion", "#ffd05a", "Tart and strong. Breath comes easily for hours.", 14, 1, heal=10, buff=("Second wind+", "stamina_regen", 0.9, 3))
    pot("endurance_tonic", "Endurance Tonic", "potion", "#f0b040", "Sunroot and honey. You do not tire for half a day.", 22, 1, buff=("Endurance", "max_stamina", 30, 6))
    brew("greater_stamina_draught", 4, [("sunroot", 2), ("wild_berries", 3), ("honey_jar", 1), V], xp=22)
    brew("endurance_tonic", 6, [("sunroot", 3), ("honey_jar", 1), ("ashroot", 1), V], xp=34)
    for k, (nm, lv, r, q, herbs, tint) in enumerate([
            ("Lesser Qi Draught", 8, 0, 40, [("moonpetal", 1), ("frostmint", 1)], "#8fd0ff"),
            ("Qi Draught", 20, 1, 110, [("qi_blossom", 1), ("frostmint", 2)], "#6fb4ff"),
            ("Greater Qi Draught", 36, 2, 260, [("qi_blossom", 2), ("spirit_ginseng", 1)], "#4f8cff"),
            ("Supreme Qi Draught", 52, 3, 520, [("qi_blossom", 3), ("jade_lotus", 1), ("spirit_stone_lesser", 1)], "#8a70ff")]):
        iid = ["qi_draught_lesser", "qi_draught", "qi_draught_greater", "qi_draught_supreme"][k]
        pot(iid, nm, "potion", tint, "Restores qi. Bitter, cold, faintly luminous.", lv, r, qi_restore=q)
        brew(iid, [3, 5, 8, 10][k], herbs + [V], xp=[14, 30, 60, 100][k])
    # ---- injury cures (RAInjuries types) -----------------------------------------------------------------------------
    pot("styptic_powder", "Styptic Powder", "vial", "#f0e8d8", "Puffball and yarrow: stops a deep cut bleeding at once.", 2, cures="deep_cut", heal=8, stack=20, kind="remedy")
    pot("ribwort_balm", "Ribwort Balm", "vial", "#b8d890", "Cooling balm for bruised ribs.", 2, cures="bruised_ribs", heal=5, stack=20, kind="remedy")
    pot("magicule_tonic", "Magicule Soothing Tonic", "vial", "#b8c8f0", "Cools a burned channel.", 6, cures="magicule_burn", stack=10, kind="remedy")
    pot("soul_calm_draught", "Soul-Calm Draught", "vial", "#d8c8f8", "Quiet tea for a tired soul.", 12, 1, cures="soul_fatigue", stack=10, kind="remedy")
    pot("bonesetting_paste", "Bonesetting Paste", "vial", "#e8d8b0", "Plaster and comfrey for knitting bone. Needs a splint.", 14, 1, cures="broken_arm", heal=10, stack=10, kind="remedy")
    pot("meridian_pill", "Meridian-Mending Pill", "pill", "#f0d888", "Reknits torn meridians. Sect physicians dispense it.", 26, 2, cures="torn_meridian", stack=5, kind="pill")
    pot("core_mending_elixir", "Core-Mending Elixir", "potion", "#ffb870", "Brewed from a beast core and spirit herbs. The last hope for a fractured core.", 42, 3, cures="fractured_core", stack=3, kind="elixir")
    brew("styptic_powder", 2, [("puffball", 2), ("yarrow", 1)], count=2, xp=8)
    brew("ribwort_balm", 2, [("nettle", 2), ("tallow", 1), ("frostmint", 1)], count=2, xp=8)
    brew("magicule_tonic", 4, [("frostmint", 2), ("moonpetal", 1), V], xp=16)
    brew("soul_calm_draught", 5, [("moonpetal", 2), ("ghostcap", 1), ("honey_jar", 1), V], xp=26)
    brew("bonesetting_paste", 5, [("willow_bark", 2), ("bone_dust", 1), ("tallow", 1), V], xp=28)
    brew("meridian_pill", 8, [("spirit_ginseng", 1), ("bone_dust", 1), ("qi_blossom", 1), ("lesser_core", 1)], xp=60, time=3.2)
    brew("core_mending_elixir", 10, [("beast_core", 1), ("spirit_ginseng", 2), ("jade_lotus", 1), V], xp=130, time=5.0)
    # antidotes / resists
    pot("antivenom", "Antivenom", "vial", "#8ac860", "Serpent's tongue and cool clay. Draws venom out.", 10, 1, cures="poison", heal=10, stack=10, kind="remedy")
    pot("fever_cure", "Feverfew Tincture", "vial", "#c8e6b0", "Bitter tincture that breaks a fever.", 3, cures="fever", heal=5, stack=10, kind="remedy")
    pot("purge_draught", "Purging Draught", "vial", "#a8b850", "Violent but effective: clears poison and spoiled food.", 6, cures="poison", stack=10, kind="remedy")
    pot("burn_salve", "Burn Salve", "vial", "#f0c890", "Tallow, nettle and aloe-like sap.", 4, heal=30, cures="burn", stack=10, kind="remedy")
    pot("frostbite_salve", "Frostbite Salve", "vial", "#f0a8a0", "Warming ointment of emberleaf and lard.", 6, heal=25, cures="frostbite", stack=10, kind="remedy")
    brew("antivenom", 5, [("serpent_tongue", 2), ("clay", 1), V], xp=26)
    brew("fever_cure", 2, [("feverfew", 3), ("willow_bark", 1), V], xp=10)
    brew("purge_draught", 3, [("hemlock", 1), ("salt", 2), ("nettle", 2), V], xp=16) if False else brew("purge_draught", 3, [("ghostcap", 1), ("salt", 2), ("nettle", 2), V], xp=16)
    brew("burn_salve", 2, [("tallow", 2), ("nettle", 1), ("healing_herb", 1)], count=2, xp=10)
    brew("frostbite_salve", 3, [("emberleaf", 2), ("lard", 1), ("wax", 1)], count=2, xp=14)
    # ---- buff potions -------------------------------------------------------------------------------------------------
    B = [("strength_draught", "Strength Draught", "potion", "#ff9a4a", "Bear claw and red herbs: your arm feels twice as sure.", 8, 0, ("Stronger", "damage", 3, 3), [("bear_claw", 1), ("redcap", 2), V], 4),
         ("fleetfoot_potion", "Fleetfoot Potion", "potion", "#8ae8c8", "Bright green and gone in a swallow; you run like the wind.", 10, 0, ("Fleetfoot", "speed", 0.08, 3), [("windgrass_placeholder", 1)], 4),
         ("stoneskin_potion", "Stoneskin Potion", "potion", "#b8a880", "Gritty and heavy. Skin becomes stone.", 14, 1, ("Stoneskin", "armour", 6, 3), [("ashroot", 2), ("bone_dust", 1), V], 5),
         ("night_eye_potion", "Night-Eye Potion", "potion", "#2a3a68", "Moonpetal steeped in dark wine. The dark turns grey.", 10, 1, ("Night eyes", "night_vision", 1, 6), [("moonpetal", 2), ("red_wine", 1), V], 5),
         ("shadow_draught", "Shadow Draught", "potion", "#3a2a58", "Nightshade and ghostcap. Feet fall softly.", 16, 1, ("Shadow-step", "stealth", 0.25, 3), [("nightshade", 1), ("ghostcap", 1), V], 6),
         ("fire_ward_potion", "Fire Ward Potion", "potion", "#ff8a4a", "Frost and ember in one flask. Flames go round you.", 16, 1, ("Fire ward", "resist", 8, 4), [("frostmint", 2), ("ember_blossom", 1), V], 6),
         ("frost_ward_potion", "Frost Ward Potion", "potion", "#8ac8ff", "Hot ginger and emberleaf. Cold cannot bite.", 12, 0, ("Frost ward", "resist", 6, 4), [("emberleaf", 2), ("ginger", 1), V], 5),
         ("focus_potion", "Focus Potion", "potion", "#c8a8ff", "Clarity in a bottle. Spells come cleaner.", 18, 1, ("Focused", "magic", 8, 3), [("moonpetal", 1), ("frostmint", 1), ("quartz", 1), V], 6),
         ("luck_draught", "Four-Leaf Draught", "potion", "#6ad08a", "It smells of clover and small miracles.", 20, 2, ("Lucky", "luck", 0.15, 3), [("qi_blossom", 1), ("honey_jar", 1), ("moonstone", 1), V], 7),
         ("vigour_potion", "Vigour Potion", "potion", "#ff7a7a", "Raises your vitality for the day.", 20, 1, ("Vigorous", "max_health", 40, 6), [("bloodmoss", 2), ("sunroot", 2), ("honey_jar", 1), V], 6)]
    for (iid, nm, fam, tint, desc, lv, r, buff, ins, rl) in B:
        pot(iid, nm, fam, tint, desc, lv, r, buff=buff)
        if iid == "fleetfoot_potion":
            ins = [("sunroot", 2), ("frostmint", 1), ("goose_feather", 2), V]
        brew(iid, rl, ins, xp=14 + 5 * rl)
    # ---- elixirs: long buffs ---------------------------------------------------------------------------------------------
    E = [("elixir_might", "Elixir of Might", "#ff8a3a", "Deep amber. Your blows land like a blacksmith's.", 26, 2, ("Might", "damage", 6, 12), [("troll_blood", 1), ("bear_claw", 2), ("sunroot", 2), V], 8),
         ("elixir_iron_skin", "Elixir of Iron Skin", "#b8c0d0", "Silvery and thick. Edges slide off you.", 28, 2, ("Iron skin", "armour", 10, 12), [("troll_hide", 1), ("ashroot", 2), ("silver_ore", 1), V], 8),
         ("elixir_swiftness", "Elixir of Swiftness", "#8ae8d8", "Clear with a green glint.", 30, 2, ("Swift", "speed", 0.1, 12), [("goose_feather", 4), ("frostmint", 2), ("essence_wind", 1), V], 8),
         ("elixir_clarity", "Elixir of Clarity", "#c8a8ff", "Violet and cool; the world goes sharp-edged.", 32, 2, ("Clear", "magic", 14, 12), [("moonstone", 1), ("moonpetal", 2), ("essence_water", 1), V], 8),
         ("elixir_vitality", "Elixir of Vitality", "#ff6a7a", "Thick red-gold. You feel twenty years younger.", 34, 2, ("Vital", "max_health", 80, 12), [("troll_blood", 1), ("spirit_ginseng", 1), ("honey_jar", 2), V], 9),
         ("elixir_qi_flow", "Elixir of Flowing Qi", "#6fb4ff", "Sky blue. Your dantian hums.", 40, 3, ("Flowing qi", "qi_regen", 1.0, 12), [("qi_blossom", 2), ("jade_lotus", 1), ("lesser_core", 1), V], 9),
         ("elixir_dragon_blood", "Dragonblood Elixir", "#ff3a2a", "Wyvern venom cut with spirit-herb; no one agrees how anyone survives it.", 50, 3, ("Dragon-blooded", "damage", 12, 12), [("wyvern_venom_gland", 1), ("beast_core", 1), ("spirit_ginseng", 2), V], 10)]
    for (iid, nm, tint, desc, lv, r, buff, ins, rl) in E:
        pot(iid, nm, "potion", tint, desc, lv, r, buff=buff, kind="elixir", stack=5)
        brew(iid, rl, ins, xp=40 + 8 * rl, time=3.5)
    # ---- cultivation pills (another agent owns scripts/realm/cultivation.gd; ids + realm + effect only) --------------------
    PILLS = [
        ("pill_qi_gathering", "Qi Gathering Pill", 5, 0, "mortal", "xp", 30, "#b8e0ff", [("moonpetal", 1), ("spirit_stone_lesser", 1)], 4),
        ("pill_qi_condensation", "Qi Condensation Pill", 12, 1, "qi_condensation", "xp", 90, "#8fd0ff", [("qi_blossom", 1), ("spirit_stone_lesser", 1), ("sunroot", 1)], 5),
        ("pill_foundation", "Foundation-Building Pill", 18, 2, "foundation", "breakthrough", 0.15, "#ffe8a0", [("spirit_ginseng", 1), ("lesser_core", 1), ("qi_blossom", 1)], 7),
        ("pill_foundation_nourish", "Foundation Nourishing Pill", 22, 1, "foundation", "xp", 240, "#ffd870", [("qi_blossom", 2), ("spirit_stone", 1), ("sunroot", 2)], 7),
        ("pill_core_formation", "Golden-Core Pill", 30, 2, "core", "breakthrough", 0.15, "#ffc85a", [("spirit_ginseng", 2), ("beast_core", 1), ("jade_lotus", 1)], 8),
        ("pill_core_nourish", "Core Nourishing Pill", 34, 2, "core", "xp", 600, "#ffb040", [("jade_lotus", 1), ("spirit_stone", 2), ("lesser_core", 1)], 8),
        ("pill_nascent_soul", "Nascent-Soul Pill", 42, 3, "nascent_soul", "breakthrough", 0.15, "#d8a8ff", [("spirit_ginseng", 3), ("beast_core", 1), ("jade_lotus", 2)], 9),
        ("pill_nascent_nourish", "Soul Nourishing Pill", 46, 3, "nascent_soul", "xp", 1400, "#c890ff", [("jade_lotus", 2), ("spirit_stone_greater", 1), ("beast_core", 1)], 9),
        ("pill_soul_transformation", "Soul-Transforming Pill", 50, 3, "soul_transformation", "breakthrough", 0.15, "#a8a0ff", [("spirit_ginseng", 4), ("greater_core", 1), ("jade_lotus", 3)], 10),
        ("pill_void_refinement", "Void-Refinement Pill", 58, 3, "void_refinement", "breakthrough", 0.12, "#8a80ff", [("rift_core", 1), ("greater_core", 1), ("jade_lotus", 3), ("spirit_stone_greater", 1)], 10),
    ]
    for (iid, nm, lv, r, realm, kind, val, tint, ins, rl) in PILLS:
        ex = {"cultivation_realm": realm, "pill_kind": kind}
        if kind == "xp":
            ex["cultivation_xp"] = val
            desc = "A refined pill that feeds cultivation in the %s realm." % realm.replace("_", " ")
        else:
            ex["breakthrough_bonus"] = val
            desc = "Taken before a breakthrough into %s; steadies the qi and improves the odds." % realm.replace("_", " ")
        pot(iid, nm, "pill", tint, desc, lv, r, stack=5, kind="pill", **ex)
        brew(iid, rl, ins + [("empty_vial", 1)] if False else ins, xp=30 + 9 * rl, time=3.0 + 0.3 * rl)
    for k, (iid, nm, lv, r, hp) in enumerate([("pill_body_temper_1", "Body-Tempering Pill", 8, 1, 2), ("pill_body_temper_2", "Marrow-Tempering Pill", 22, 2, 3),
                                              ("pill_body_temper_3", "Bone-Forging Pill", 38, 3, 4), ("pill_body_temper_4", "Nine-Turn Body Pill", 52, 3, 5)]):
        pot(iid, nm, "pill", ["#ffd0a8", "#ffb880", "#ff9a5a", "#ff7a3a"][k], "Permanently toughens the body: +%d maximum health (limited by realm)." % hp, lv, r, stack=5, kind="pill",
            permanent_stat="max_health", permanent_value=hp, pill_kind="tempering")
        brew(iid, [4, 6, 8, 10][k], [("bloodmoss", 2 + k), ("sunroot", 2), ([("bear_claw", 1)], [("troll_blood", 1)], [("troll_tooth", 1)], [("wyvern_fang", 1)])[k][0]] if False else
             [("bloodmoss", 2 + k), ("sunroot", 2), (["bear_claw", "troll_blood", "troll_tooth", "wyvern_fang"][k], 1)], xp=40 + 14 * k)
    pot("pill_clarity", "Clear-Mind Pill", "pill", "#e8f0ff", "Dispels distraction; improves the next meditation session.", 14, 1, stack=5, kind="pill", buff_name="Clear-mind", buff_stat="qi_regen", buff_value=0.5, buff_hours=6)
    brew("pill_clarity", 5, [("moonpetal", 2), ("frostmint", 1), ("spirit_stone_lesser", 1)], xp=30)
    # ---- coatings, oils, bombs ------------------------------------------------------------------------------------------------
    pot("blade_poison_weak", "Weak Blade Poison", "vial", "#7ab85a", "A poor man's poison: a few hours of sickness in whoever you cut.", 6, stack=10, kind="coating", coating="poison", coating_damage=2, coating_hits=10)
    pot("blade_poison", "Blade Poison", "vial", "#4a9a4a", "Nightshade and venom. Burns through the blood.", 14, 1, stack=10, kind="coating", coating="poison", coating_damage=5, coating_hits=10)
    pot("wyvern_venom_coat", "Wyvern-Venom Coating", "vial", "#7ac04c", "Dissolves armour as well as flesh.", 46, 3, stack=5, kind="coating", coating="poison", coating_damage=16, coating_hits=10)
    pot("fire_oil", "Fire Oil", "oil", "#ff8a3a", "Brush on a blade and it burns for a dozen hits.", 12, 1, stack=10, kind="coating", coating="fire", coating_damage=4, coating_hits=12)
    pot("holy_oil", "Blessed Oil", "oil", "#fff0a8", "Consecrated at the temple. Sears the undead.", 14, 1, stack=10, kind="coating", coating="holy", coating_damage=5, coating_hits=12)
    pot("frost_oil", "Frost Oil", "oil", "#a8e0ff", "Numbing oil; slows whoever you cut.", 16, 1, stack=10, kind="coating", coating="frost", coating_damage=4, coating_hits=12)
    brew("blade_poison_weak", 2, [("nightshade", 1), ("tallow", 1), V], xp=12)
    brew("blade_poison", 5, [("nightshade", 2), ("venom_sac", 1), V], xp=26)
    brew("wyvern_venom_coat", 9, [("wyvern_venom_gland", 1), ("nightshade", 2), V], xp=80)
    brew("fire_oil", 4, [("lamp_oil", 2), ("sulfur", 1), ("emberleaf", 1), V], xp=20)
    brew("holy_oil", 4, [("lamp_oil", 2), ("sage", 1), ("wax", 1), V], xp=20)
    brew("frost_oil", 5, [("lamp_oil", 2), ("frostmint", 2), V], xp=22)
    for (iid, nm, fam, tint, desc, lv, r, kw, ins, rl) in [
        ("alchemists_fire", "Alchemist's Fire", "bomb", "#ff7a2a", "Thrown flask of clinging fire.", 14, 1, dict(thrown=True, damage=18, dmg_type="fire", radius=3.0), [("sulfur", 2), ("saltpetre", 1), ("lamp_oil", 1), V], 5),
        ("frost_flask", "Frost Flask", "bomb", "#8ac8ff", "Shatters into a burst of killing cold.", 20, 1, dict(thrown=True, damage=16, dmg_type="frost", radius=3.0, slow=0.4), [("frostmint", 3), ("essence_water", 1), V], 6),
        ("smoke_bomb", "Smoke Bomb", "bomb", "#8a8a90", "A pellet of ash and saltpetre. Break line of sight and run.", 8, 0, dict(thrown=True, smoke=True, radius=4.0), [("ash", 2), ("saltpetre", 1), ("resin", 1)], 3),
        ("flash_powder", "Flash Powder", "bomb", "#f8f0a0", "A blinding flare.", 12, 1, dict(thrown=True, stun=2.0, radius=3.0), [("sulfur", 1), ("saltpetre", 1), ("quartz", 1)], 4),
        ("holy_water", "Holy Water", "vial", "#e8f4ff", "Blessed at the temple font. Burns the unquiet dead.", 10, 1, dict(thrown=True, damage=14, dmg_type="holy", undead_only=False), [("clean_water", 1), ("sage", 1), ("silver_ore", 1), V], 4),
        ("thunder_charm", "Thunder Charm", "bomb", "#fff070", "Paper charm that cracks like a lightning strike.", 30, 2, dict(thrown=True, damage=40, dmg_type="lightning", radius=3.5), [("essence_lightning", 1), ("sulfur", 1), ("parchment_blank", 1)], 8),
        ("rift_bomb", "Rift Bomb", "bomb", "#c79bff", "Crystal shard in a stoppered glass. Do not look directly.", 50, 3, dict(thrown=True, damage=90, dmg_type="rift", radius=4.5), [("rift_crystal", 1), ("rift_dust", 2), ("essence_fire", 1), V], 10)]:
        add(iid, nm, "healing", F, price=None, stack=10, weight=0.3, rarity=r, level=lv, desc=desc, tint=tint, glyph="fam:" + fam, type="thrown", **kw)
        brew(iid, rl, ins, xp=16 + 6 * rl)
    # repair goods
    for (iid, nm, desc, lv, r, frac, ins, rl, skill, stn) in [
        ("whetstone", "Whetstone", "A few strokes bring a blade back: repairs 25% of worn weapon durability.", 1, 0, 0.25, [("flint", 1), ("sand", 1)], 1, "masonry", "workbench"),
        ("repair_kit", "Repair Kit", "Rivets, rag, oil and needle in a roll. Restores 40% durability to worn gear.", 4, 0, 0.4, [("iron_ingot", 1), ("leather", 1), ("lamp_oil", 1)], 3, "smithing", "anvil"),
        ("master_repair_kit", "Master's Repair Kit", "Fine tools and flux. Restores 75% durability.", 22, 2, 0.75, [("steel_ingot", 2), ("hardened_leather", 1), ("quench_oil", 1), ("flux", 1)], 6, "smithing", "anvil")]:
        add(iid, nm, "healing", F, price=None, stack=10, weight=0.6, rarity=r, level=lv, desc=desc, tint="#c4cad4", glyph="fam:hammer", type="repair", repair_fraction=frac)
        craft(iid, skill, stn, rl, ins, xp=10 + 6 * rl)
