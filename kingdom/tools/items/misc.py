"""Manuals and scrolls, lore, keys, quest items, trade goods, furniture, seeds/crops, feed, tack, uniques."""
import json
import os
from core import add, craft, DATA, LEGACY

F = "misc"

TREES = {  # tree -> (display, soul paths)
    "swordsmanship": ("Swordsmanship", ["blade"]), "fist_palm": ("Fist and Palm", ["warden"]), "fire": ("Fire Arts", ["scholar"]),
    "water": ("Water Arts", ["tide"]), "wind": ("Wind Arts", ["hunt"]), "earth": ("Earth Arts", ["warden"]), "lightning": ("Lightning Arts", ["scholar"]),
    "qi": ("Qi Arts", ["scholar", "tide"]), "shadow": ("Shadow Arts", ["wanderer"]), "iaido": ("Iaido", ["blade"]), "command": ("Command", ["warden"]),
    "crafting": ("Craft Lore", ["forge"]), "farming": ("Husbandry", ["harvest"]),
}
TIER_REALM = {1: ("mortal", 1), 2: ("qi_condensation", 3), 3: ("foundation", 10), 4: ("core", 18), 5: ("nascent_soul", 28)}
TIER_NAME = {1: "Primer", 2: "Practices", 3: "Forms", 4: "Mysteries", 5: "Canon"}
TIER_PRICE = {1: 40, 2: 130, 3: 400, 4: 1200, 5: 3400}
TIER_TINT = {1: "#d8c8a0", 2: "#a8d8a0", 3: "#80b0f0", 4: "#c090f0", 5: "#ffc860"}
SECTS_BY_TREE = {"swordsmanship": ["ninefold_sword_pavilion", "royal_ember_academy", "greywatch_spear_hall"], "fist_palm": ["iron_lotus_monastery", "ashford_staff_yard"],
                 "fire": ["royal_ember_academy", "dawnflame_seminary", "hall_of_four_currents"], "water": ["hall_of_four_currents"], "wind": ["windstep_lodge", "hall_of_four_currents"],
                 "earth": ["anvil_brotherhood"], "lightning": ["hall_of_four_currents"], "qi": ["ninefold_sword_pavilion", "iron_lotus_monastery", "verdant_oath_sanctuary"],
                 "shadow": ["hollow_moon_school"], "iaido": ["hollow_moon_school", "ninefold_sword_pavilion"], "command": ["royal_ember_academy", "greywatch_spear_hall"],
                 "crafting": ["anvil_brotherhood"], "farming": ["verdant_oath_sanctuary"]}

CROPS = {}          # crop item id -> {days, seasons, winter_hardy, asset}
MANUALS = []        # data for tests


def build():
    manuals()
    scrolls()
    lore_and_keys()
    trade_goods()
    furniture()
    seeds_and_feed()
    tack()


def manuals():
    with open(os.path.join(DATA, "skills", "index.json")) as f:
        idx = json.load(f)
    for tree in idx["trees"]:
        with open(os.path.join(DATA, "skills", tree + ".json")) as f:
            d = json.load(f)
        by_tier = {}
        for t in d["techniques"]:
            by_tier.setdefault(t["tier"], []).append(t["id"])
        disp, paths = TREES[tree]
        for tier, teaches in sorted(by_tier.items()):
            iid = "manual_%s_t%d" % (tree, tier)
            realm, rlv = TIER_REALM[tier]
            add(iid, "%s %s" % (disp, TIER_NAME[tier]), "manual", F, price=TIER_PRICE[tier], stack=1, weight=0.6, rarity=min(3, tier - 1 if tier > 1 else 0) if tier < 4 else 3,
                level=max(1, rlv), desc="A written course in %s for a practitioner at the %s stage. Reading it teaches: %s." % (disp.lower(), realm.replace("_", " "), ", ".join(x.replace("_", " ") for x in teaches)),
                tint=TIER_TINT[tier], glyph="fam:book", type="manual", manual_tree=tree, path=paths, realm=realm, realm_level=rlv, tier=tier, teaches=teaches,
                sects=SECTS_BY_TREE.get(tree, []), consumable=False, req_level=max(1, rlv))
            MANUALS.append(iid)
    with open(os.path.join(DATA, "skills", "manuals.json")) as f:
        mj = json.load(f)
    for m in mj["manuals"]:
        add(m["id"], m["name"], "manual", F, price=180 if m.get("grant") else 2400, stack=1, weight=0.5, rarity=1 if m.get("grant") else 3, level=3 if m.get("grant") else 20,
            desc=m["desc"] + " " + m["where"], tint="#e8d8a8", glyph="fam:book", type="manual", teaches=m["teaches"], realm="mortal" if m.get("grant") else "qi_condensation",
            realm_level=1 if m.get("grant") else 3, grant=bool(m.get("grant")), unique=not m.get("grant"))
        MANUALS.append(m["id"])


def scrolls():
    S = [("scroll_ember_orb", "Scroll of Ember Orb", 1, "fire_ember_orb", "#ff8a3a"), ("scroll_flame_wave", "Scroll of Flame Wave", 2, "fire_flame_wave", "#ff6a2a"),
         ("scroll_water_whip", "Scroll of Water Whip", 1, "water_whip", "#6ab4ff"), ("scroll_ice_lance", "Scroll of Ice Lance", 2, "water_ice_lance", "#a8e0ff"),
         ("scroll_wind_blade", "Scroll of Wind Blade", 1, "wind_blade", "#b8f0d8"), ("scroll_gale_burst", "Scroll of Gale Burst", 2, "wind_gale_burst", "#98e8c8"),
         ("scroll_stone_bullet", "Scroll of Stone Bullet", 1, "earth_stone_bullet", "#c8a868"), ("scroll_earth_spike", "Scroll of Earth Spike", 2, "earth_spike", "#b89858"),
         ("scroll_spark", "Scroll of Spark", 1, "lightning_spark", "#fff070"), ("scroll_chain_lightning", "Scroll of Chain Lightning", 2, "lightning_chain", "#ffe040"),
         ("scroll_qi_bolt", "Scroll of Qi Bolt", 2, "qi_bolt", "#ffe890"), ("scroll_shuriken", "Scroll of Shadow Shuriken", 1, "shadow_shuriken", "#8a7ac8"),
         ("scroll_smoke", "Scroll of Shadow Smoke", 2, "shadow_smoke", "#6a5aa8")]
    for iid, nm, tier, tech, tint in S:
        add(iid, nm, "manual", F, price=[0, 55, 160][tier], stack=5, weight=0.1, rarity=tier, level=[1, 6, 16][tier], desc="One cast of a technique, written out. The paper burns away when read.",
            tint=tint, glyph="fam:scroll", type="scroll", casts=tech, single_use=True, tier=tier)
    add("scroll_recall", "Scroll of Recall", "manual", F, price=120, stack=5, weight=0.1, rarity=2, level=14, desc="Read it in the wild and be carried to the last hearth you rested at.", tint="#b8d8ff", glyph="fam:scroll", type="scroll", effect="recall", single_use=True)
    add("scroll_ward", "Scroll of Warding", "manual", F, price=90, stack=5, weight=0.1, rarity=1, level=10, desc="Draws a ward-circle on the ground. Beasts will not cross it for an hour.", tint="#a8e0a8", glyph="fam:scroll", type="scroll", effect="ward", single_use=True)
    add("scroll_identify", "Scroll of Sight", "manual", F, price=70, stack=5, weight=0.1, rarity=1, level=8, desc="Reveals hidden traps and marks on the nearest landmark.", tint="#f0e0a0", glyph="fam:scroll", type="scroll", effect="reveal", single_use=True)


def lore_and_keys():
    L = [("lore_ashford_chronicle", "The Ashford Chronicle", "A village history, kept by the mill and three generations of clerks.", 1, 0),
         ("lore_out_of_the_ashes", "Out of the Ashes", "The founders' tale: how the first families came to the valley.", 4, 1),
         ("lore_herbalists_almanac", "The Herbalist's Almanac", "Seasons, herbs and their uses, with sketches of the dangerous ones.", 3, 0),
         ("lore_monster_field_guide", "Field Guide to Beasts of the Vale", "Wolves, trolls, wyverns and what to do about each.", 6, 1),
         ("lore_smiths_primer", "A Smith's Primer", "Alloys, heats and a dozen ways to ruin a blade.", 5, 0),
         ("lore_sect_customs", "Sect Customs of the Five Schools", "Etiquette, hierarchy and the things one doesn't say in a hall.", 10, 1),
         ("lore_rift_survey", "Survey of the Rift Wound", "Measured notes on where the Rift leaks and what comes through.", 20, 2),
         ("lore_kingsreach_laws", "The Laws of Caldrenn", "Crown statutes on trade, travel and killing.", 8, 1),
         ("lore_cultivators_diary", "A Cultivator's Diary", "Loose pages from someone who reached the Core and left little else.", 18, 2),
         ("lore_tuskridge_songs", "Songs of the Tuskridge", "Transcribed orc war-songs with the tuning marks.", 12, 1),
         ("lore_runestone_notes", "Notes on the Runestones", "A wardwright's working notebook.", 14, 2),
         ("lore_cookbook", "The Travelling Cook", "Recipes from four regions and their rumoured side-effects.", 4, 0)]
    for iid, nm, desc, lv, r in L:
        add(iid, nm, "lore", F, price=20 + lv * 6, stack=1, weight=0.6, rarity=r, level=lv, desc=desc, tint="#d8c8a0", glyph="fam:book", type="lore", readable=True)
    K = [("key_iron", "Iron Key", "#c4cad4", "An iron key of no particular make.", 1), ("key_brass", "Brass Key", "#d8b860", "Small and ornate; belongs to a strongbox.", 3),
         ("key_rusted", "Rusted Key", "#a8684a", "Flaking orange. One more turn might snap it.", 1), ("key_crypt", "Crypt Key", "#8a8a98", "Black iron, cold to touch.", 10),
         ("key_warren", "Warren Gate Key", "#9a7a4a", "Crudely carved from bone and iron; goblin handiwork.", 6),
         ("key_tower_bronze", "Bronze Tower Key", "#d9a15a", "Opens the first seal of a tower.", 12), ("key_tower_silver", "Silver Tower Key", "#e6ebf4", "Opens the second seal of a tower.", 26),
         ("key_tower_gold", "Gold Tower Key", "#ffd65c", "Opens the third seal of a tower.", 40), ("key_captains", "Captain's Key", "#b8a060", "Opens the armoury at a garrison.", 15),
         ("key_master", "Guild Master Key", "#ffe090", "Opens any guild strongroom in Caldrenn.", 30), ("key_rift", "Rift-Crystal Key", "#c79bff", "It turns in locks that aren't there.", 50)]
    for iid, nm, tint, desc, lv in K:
        add(iid, nm, "key", F, price=0, stack=5, weight=0.1, rarity=0 if lv < 10 else 2 if lv < 40 else 3, level=lv, desc=desc, tint=tint, glyph="fam:key", type="key", quest_item=True)
    Q = [("sealed_letter", "Sealed Letter", "A letter under wax. Not yours to open.", 1), ("royal_writ", "Royal Writ", "Stamped with the Caldrenn crown. Doors open.", 20),
         ("bounty_notice", "Bounty Notice", "A reward poster, torn from a notice board.", 1), ("old_map_fragment", "Old Map Fragment", "A corner of a map; the rest is out there.", 8),
         ("treasure_map", "Treasure Map", "An X on a hillside. There is always an X.", 12), ("guild_badge", "Adventurer Guild Badge", "Pewter badge with a rank stamped on the back.", 1),
         ("messenger_satchel", "Messenger's Satchel", "Leather satchel sealed at the clasp.", 3), ("stolen_goods", "Bundle of Stolen Goods", "Someone will pay to have this back.", 4),
         ("bandit_ledger", "Bandit Ledger", "Names, routes and sums, in a bad hand.", 6), ("ward_stone_fragment", "Ward-Stone Fragment", "A chip of runestone that still tingles.", 8),
         ("lost_locket", "Lost Locket", "A silver locket with a child's hair inside.", 2), ("smuggler_manifest", "Smuggler's Manifest", "A list of crates and who paid to lose them.", 10),
         ("ash_relic", "Ashbound Relic", "Warm, grey, and heavier than it should be.", 14), ("ember_relic", "Ember Relic", "A hand-sized ember-glass token that hums.", 22),
         ("tribal_token", "Tuskridge Token", "An orc clan token; shows a peaceful visitor.", 6), ("goblin_warmap", "Goblin War-Map", "Scratched on hide. Marks the raid routes.", 7),
         ("holy_relic_finger", "Saint's Knucklebone", "A reliquary knucklebone in a silver cage.", 16), ("sect_invitation", "Sect Invitation", "Cream paper, gilt edge. A school wants you.", 5),
         ("rift_sample_jar", "Rift Sample Jar", "Sealed glass with something that looks at you.", 20)]
    for iid, nm, desc, lv in Q:
        add(iid, nm, "quest", F, price=0, stack=5, weight=0.2, rarity=1 if lv > 10 else 0, level=lv, desc=desc, tint="#f0b85a", glyph="fam:letter" if "letter" in iid or "map" in iid or "notice" in iid or "writ" in iid or "manifest" in iid or "ledger" in iid or "invitation" in iid or "warmap" in iid else "fam:misc", type="quest", quest_item=True)


def trade_goods():
    G = [("grain", "Sack of Grain", 4, "grain", "#e0c880", "Threshed and sacked. The staple of every market.", 40, 1.5),
         ("fish", "Barrel of Fish", 7, "fish", "#a8b8c8", "Salted fish in brine.", 20, 4.0),
         ("wood", "Bundle of Timber", 3, "log", "#b98a54", "Cut and corded for the carts.", 30, 3.0),
         ("ore", "Cart-Load of Ore", 8, "ore", "#9aa0a8", "Mixed ore from the Greyseam, sorted by weight.", 20, 6.0),
         ("iron", "Bar Iron", 22, "ingot", "#c4cad4", "Bundled bar iron, the smith's staple.", 20, 5.0),
         ("pottery", "Crate of Pottery", 10, "barrel", "#c4905c", "Jugs, bowls and platters packed in straw.", 10, 4.0)]
    for iid, nm, p, fam, tint, desc, stack, w in G:
        add(iid, nm, "material", F, price=p, stack=stack, weight=w, rarity=0, level=1, desc=desc, tint=tint, glyph="fam:" + fam, type="trade_good", trade_good=True)
    TG = [("salt_sack", "Sack of Rock Salt", 12, "powder", "#f4f4f4", "Mined salt for the preserving season.", 1, 0, 2.5),
          ("spice_chest", "Chest of Spices", 120, "chest", "#e8842a", "Pepper, cinnamon and cloves in sealed tins.", 14, 2, 3.0),
          ("silk_crate", "Crate of Silk", 160, "chest", "#f8ecf0", "Shenlu silk, packed with cedar.", 16, 2, 4.0),
          ("wine_cask", "Cask of Wine", 55, "barrel", "#7a1a2a", "A sealed cask, a hundred cups.", 8, 1, 8.0),
          ("fur_bundle", "Bundle of Furs", 36, "hide", "#d8c8a8", "Fox, marten and rabbit tied in pairs.", 6, 1, 3.0),
          ("amber_beads", "Amber Beads", 48, "gem", "#e8a030", "Strung Seirune amber.", 10, 1, 0.3),
          ("glassware_crate", "Crate of Glassware", 70, "barrel", "#d8f0f4", "Bottles and cups; handle with care.", 12, 1, 5.0),
          ("candle_box", "Box of Candles", 14, "furniture_light", "#f6e9b8", "Fifty tallow candles.", 1, 0, 2.0),
          ("soap_bars", "Bars of Soap", 8, "powder", "#e8e8d8", "Lye and tallow; town folk buy them by the dozen.", 1, 0, 1.0),
          ("perfume_flask", "Flask of Perfume", 65, "vial", "#f0c0e0", "Rose and musk.", 14, 1, 0.2),
          ("book_crate", "Crate of Books", 90, "book", "#d8c8a0", "Copied texts in leather covers.", 10, 1, 6.0),
          ("jewel_casket", "Jewellery Casket", 280, "chest", "#ffd65c", "Gold and stones in a locked box. Keep it close.", 24, 2, 2.0),
          ("steel_bars", "Bundle of Steel Bars", 60, "ingot", "#dfe6f2", "Uniform bars from a town furnace.", 18, 1, 6.0),
          ("armour_crate", "Crate of Armour", 140, "chest", "#c4cad4", "Mixed mail and plate for the garrison.", 14, 1, 10.0),
          ("honey_barrel", "Barrel of Honey", 50, "barrel", "#f0b830", "Dark heather honey in a sealed keg.", 4, 1, 7.0),
          ("tea_chest", "Chest of Tea", 75, "chest", "#88b860", "Shenlu tea in lead-lined paper.", 10, 1, 3.0),
          ("dye_bolt_crate", "Crate of Dyed Cloth", 80, "cloth", "#c4424a", "Bright bolts: madder, woad and weld.", 8, 1, 4.0),
          ("rice_sack", "Sack of Rice", 16, "grain", "#f4f0e0", "Imported from the south and east.", 10, 0, 2.0),
          ("cheese_crate", "Crate of Mountain Cheese", 46, "cheese", "#e8c468", "Waxed wheels from Stonehollow.", 8, 1, 4.0),
          ("smoked_meat_crate", "Crate of Smoked Meat", 40, "meat", "#c86a54", "Ham and bacon for the army quartermaster.", 6, 1, 4.0)]
    for iid, nm, p, fam, tint, desc, lv, r, w in TG:
        add(iid, nm, "material", F, price=p, stack=10, weight=w, rarity=r, level=lv, desc=desc, tint=tint, glyph="fam:" + fam, type="trade_good", trade_good=True)


def furniture():
    # id, name, fam, comfort, station inputs, level, tint, desc
    FU = [("chair_plain", "Plain Chair", "furniture_chair", 1, [("plank", 3)], 1, "#b98a54", "Four legs and a back."),
          ("stool", "Stool", "furniture_chair", 1, [("plank", 1)], 1, "#b98a54", "Three legs, one virtue."),
          ("chair_carved", "Carved Chair", "furniture_chair", 3, [("oak_plank", 3), ("linen_thread", 2)], 4, "#9a6a3a", "Oak with a carved back."),
          ("armchair", "Padded Armchair", "furniture_chair", 5, [("oak_plank", 3), ("wool", 4), ("leather", 2)], 6, "#7a4a2a", "Deep and comfortable."),
          ("table_plain", "Plain Table", "furniture_table", 1, [("plank", 5)], 1, "#b98a54", "Scrubbed pine."),
          ("table_oak", "Oak Table", "furniture_table", 3, [("oak_plank", 6), ("iron_nails", 8)], 4, "#9a6a3a", "Heavy oak for big meals."),
          ("table_round", "Round Table", "furniture_table", 4, [("oak_plank", 8), ("iron_nails", 12)], 6, "#8a5a2a", "No head of the table."),
          ("desk", "Writing Desk", "furniture_table", 3, [("oak_plank", 5), ("hinges", 2)], 5, "#8a5a2a", "With a slanted top and an inkwell."),
          ("bed_straw", "Straw Bed", "furniture_bed", 1, [("plank", 4), ("thatch", 6)], 1, "#c8b070", "A sack of straw on a frame."),
          ("bed_wool", "Wool Bed", "furniture_bed", 3, [("oak_plank", 5), ("wool", 6), ("linen_cloth", 2)], 4, "#d8d0c0", "Wool mattress and linen sheets."),
          ("bed_feather", "Feather Bed", "furniture_bed", 6, [("oak_plank", 6), ("goose_feather", 30), ("linen_cloth", 3)], 7, "#f4f1e8", "Goose-down. You will sleep like the dead."),
          ("cupboard", "Cupboard", "furniture_storage", 2, [("plank", 6), ("hinges", 2)], 2, "#b98a54", "Shelves behind doors."),
          ("wardrobe", "Wardrobe", "furniture_storage", 3, [("oak_plank", 8), ("hinges", 4)], 5, "#8a5a2a", "Hangs a whole wardrobe."),
          ("bookshelf", "Bookshelf", "furniture_storage", 2, [("oak_plank", 6)], 3, "#9a6a3a", "Five shelves."),
          ("chest_wood", "Wooden Chest", "furniture_storage", 1, [("plank", 4), ("hinges", 2)], 2, "#b98a54", "Stores a household's valuables."),
          ("chest_iron_banded", "Iron-Banded Chest", "furniture_storage", 2, [("oak_plank", 4), ("iron_ingot", 2), ("hinges", 2)], 5, "#7a7a82", "Locks with a key; thieves give up."),
          ("barrel_storage", "Barrel", "barrel", 0, [("plank", 4), ("iron_nails", 6)], 2, "#9a6a3a", "Holds ale, grain or secrets."),
          ("weapon_rack", "Weapon Rack", "furniture_storage", 1, [("plank", 4), ("iron_nails", 4)], 2, "#8a5a2a", "Displays and stores weapons."),
          ("armour_stand", "Armour Stand", "furniture_storage", 2, [("oak_plank", 3), ("iron_ingot", 1)], 4, "#7a7a82", "A wooden torso for your harness."),
          ("rug_wool", "Wool Rug", "furniture_decor", 2, [("wool_thread", 10), ("dye_red", 1)], 3, "#c4424a", "Red wool with a border of black."),
          ("rug_fur", "Bearskin Rug", "furniture_decor", 4, [("bear_pelt", 1), ("tannin", 1)], 6, "#6b4a34", "Head and all."),
          ("candle_holder", "Candle Holder", "furniture_light", 1, [("iron_ingot", 1), ("candle", 2)], 2, "#c4cad4", "Lights a room."),
          ("chandelier", "Iron Chandelier", "furniture_light", 4, [("iron_ingot", 3), ("candle", 8)], 6, "#c4cad4", "Hangs from a beam."),
          ("lamp_oil_standing", "Standing Oil Lamp", "furniture_light", 3, [("bronze_ingot", 2), ("glass", 1), ("lamp_oil", 1)], 5, "#d8b860", "A warm steady light."),
          ("painting_landscape", "Landscape Painting", "furniture_decor", 4, [("linen_cloth", 1), ("plank", 2), ("dye_blue", 1), ("dye_green", 1)], 5, "#a8c8e8", "The Vale in oils."),
          ("banner_house", "House Banner", "furniture_decor", 2, [("linen_cloth", 2), ("dye_red", 1), ("plank", 1)], 3, "#c4424a", "Hangs your colours."),
          ("trophy_wolf", "Wolf Trophy", "furniture_decor", 2, [("wolf_pelt", 1), ("wolf_fang", 2), ("plank", 1)], 3, "#8a8a8a", "A warning to the living."),
          ("trophy_boar", "Boar Trophy", "furniture_decor", 2, [("boar_hide", 1), ("boar_tusk_fine", 2), ("plank", 1)], 4, "#8b6a4c", "Tusks and scowl."),
          ("vase_clay", "Clay Vase", "furniture_decor", 1, [("clay", 3)], 2, "#c4905c", "Holds wildflowers."),
          ("vase_porcelain", "Porcelain Vase", "furniture_decor", 4, [("clay", 4), ("quartz", 1), ("dye_blue", 1)], 6, "#e8f0ff", "Thin, white, blue-glazed."),
          ("mirror_polished", "Polished Mirror", "furniture_decor", 4, [("silver_ingot", 1), ("glass", 1), ("oak_plank", 1)], 6, "#e8eef8", "A little vain, a little useful."),
          ("hearth_rug", "Hearth Cushion", "furniture_decor", 2, [("wool", 4), ("linen_cloth", 1)], 2, "#d8c8b0", "For the dog and for you."),
          ("bath_tub", "Wooden Bath Tub", "furniture_decor", 4, [("oak_plank", 6), ("iron_nails", 12), ("tallow", 1)], 5, "#9a6a3a", "Hot water, occasionally."),
          ("flower_box", "Flower Box", "furniture_decor", 1, [("plank", 2), ("clay", 1)], 1, "#b98a54", "Window-ledge flowers."),
          ("statue_marble", "Marble Statue", "furniture_decor", 5, [("marble", 4)], 8, "#f3f0ea", "A figure of some forgotten saint."),
          ("sect_banner", "Sect Banner", "furniture_decor", 3, [("silk_cloth", 1), ("plank", 1), ("dye_black", 1)], 6, "#d9dde6", "Shows a school's mark.")]
    for iid, nm, fam, comfort, ins, rl, tint, desc in FU:
        add(iid, nm, "furniture", F, price=None, stack=1, weight=6.0 if comfort >= 3 else 3.0, rarity=0 if comfort < 4 else 1, level=rl * 4, desc=desc, tint=tint, glyph="fam:" + fam,
            type="furniture", furniture=True, comfort=comfort, placeable=True)
        craft(iid, "carpentry", "workbench", rl, ins, xp=8 + 4 * rl)


def seeds_and_feed():
    W = "SPRING SUMMER AUTUMN WINTER".split()
    C = [("wheat", 4, [], False, "farm/crop_wheat"), ("barley", 4, ["SPRING", "SUMMER"], False, "farm/crop_wheat"), ("cabbage", 5, [], False, "farm/crop_cabbage"),
         ("turnip", 4, W, True, "farm/crop_cabbage"), ("flax", 5, ["SPRING", "SUMMER"], False, ""), ("hops", 6, ["SUMMER"], False, ""),
         ("carrot", 4, ["SPRING", "SUMMER", "AUTUMN"], False, "farm/crop_cabbage"), ("onion", 5, ["SPRING", "SUMMER"], False, "farm/crop_cabbage"),
         ("leek", 5, ["SPRING", "AUTUMN", "WINTER"], True, "farm/crop_cabbage"), ("peas", 3, ["SPRING"], False, "farm/crop_cabbage"),
         ("broad_beans", 4, ["SPRING", "AUTUMN"], False, "farm/crop_cabbage"), ("beetroot", 4, ["SPRING", "SUMMER", "AUTUMN"], False, "farm/crop_cabbage"),
         ("radish", 2, ["SPRING", "SUMMER", "AUTUMN"], False, "farm/crop_cabbage"), ("parsnip", 6, ["SPRING", "AUTUMN"], True, "farm/crop_cabbage"),
         ("pumpkin", 7, ["SUMMER"], False, "farm/crop_cabbage"), ("oats", 4, ["SPRING", "SUMMER"], False, "farm/crop_wheat"),
         ("rye", 5, ["AUTUMN", "WINTER"], True, "farm/crop_wheat"), ("garlic_bulb", 5, ["AUTUMN"], True, "farm/crop_cabbage"),
         ("healing_herb", 3, ["SPRING", "SUMMER", "AUTUMN"], False, ""), ("sunroot", 5, ["SUMMER"], False, ""), ("thyme", 3, ["SPRING", "SUMMER"], False, ""),
         ("sage", 3, ["SPRING", "SUMMER"], False, ""), ("parsley", 3, ["SPRING", "SUMMER", "AUTUMN"], False, ""), ("nettle", 2, ["SPRING", "SUMMER", "AUTUMN"], False, "")]
    names = {"wheat": "Wheat", "barley": "Barley", "cabbage": "Cabbage", "turnip": "Turnip", "flax": "Flax", "hops": "Hop", "carrot": "Carrot", "onion": "Onion", "leek": "Leek",
             "peas": "Pea", "broad_beans": "Broad Bean", "beetroot": "Beetroot", "radish": "Radish", "parsnip": "Parsnip", "pumpkin": "Pumpkin", "oats": "Oat", "rye": "Rye",
             "garlic_bulb": "Garlic", "healing_herb": "Healing Herb", "sunroot": "Sunroot", "thyme": "Thyme", "sage": "Sage", "parsley": "Parsley", "nettle": "Nettle"}
    for crop, days, seasons, hardy, asset in C:
        CROPS[crop] = {"days": days, "seasons": seasons, "winter_hardy": hardy, "asset": asset}
        add("seed_" + crop, "%s Seeds" % names[crop], "seed", F, price=max(1, days // 2 + (1 if crop in ("pumpkin", "hops", "flax") else 0)), stack=40, weight=0.02, rarity=0, level=1,
            desc="A paper twist of seed. Plant in %s." % (", ".join(s.lower() for s in seasons) if seasons else "any season"), tint="#c8b070", glyph="fam:seed", type="seed", plants=crop)
    FD = [("hay_bale", "Bale of Hay", 3, "Dry hay for cattle, sheep and horses.", 10, "#d8c870", 6.0), ("chicken_feed", "Chicken Feed", 2, "Cracked grain and scraps.", 30, "#e0c880", 0.5),
          ("pig_slop", "Bucket of Slop", 1, "Kitchen waste, turnips and whey.", 10, "#a89868", 2.0), ("horse_oats", "Horse Oats", 3, "Crimped oats in a nosebag.", 20, "#e0d4a0", 1.0),
          ("salt_lick", "Salt Lick", 6, "A block of rock salt for livestock.", 5, "#f4f4f4", 2.0), ("fodder_mix", "Winter Fodder Mix", 5, "Hay, turnip and chaff bound in a cake.", 10, "#b8a860", 3.0),
          ("horse_treat", "Horse Treat", 2, "Oats rolled in honey. Horses adore you.", 20, "#e8c070", 0.1)]
    for iid, nm, p, desc, stack, tint, w in FD:
        add(iid, nm, "feed", F, price=p, stack=stack, weight=w, rarity=0, level=1, desc=desc, tint=tint, glyph="fam:sack_food", type="feed", feed=True)


def tack():
    T = [("bridle", "Leather Bridle", "tack", "bridle", [("leather", 2), ("iron_nails", 4)], 3, 0, "Bit, reins and headstall."),
         ("saddlebags", "Saddlebags", "tack", "bags", [("leather", 3), ("iron_nails", 6)], 3, 0, "Doubles what your horse carries (+12 slots)."),
         ("horse_blanket", "Horse Blanket", "tack", "blanket", [("wool", 4), ("linen_thread", 2)], 2, 0, "Keeps a horse warm in winter."),
         ("saddle_fine", "Fine Riding Saddle", "tack", "saddle", [("hardened_leather", 3), ("oak_plank", 2), ("steel_ingot", 1), ("silk_thread", 2)], 6, 1, "Padded, stitched and balanced. Horses tire slower under it."),
         ("stirrups_steel", "Steel Stirrups", "tack", "stirrups", [("steel_ingot", 1)], 5, 1, "Quiet, strong, well shaped."),
         ("cart_harness", "Cart Harness", "tack", "harness", [("leather", 4), ("rope", 2), ("iron_nails", 6)], 4, 0, "Draws a cart behind any willing beast."),
         ("barding_leather", "Leather Barding", "tack", "barding", [("hardened_leather", 6), ("rivets", 20)], 6, 1, "Protective leather panels for a warhorse."),
         ("barding_chain", "Mail Barding", "tack", "barding", [("steel_ingot", 8), ("hardened_leather", 2)], 8, 2, "Chain mail for a warhorse."),
         ("barding_plate", "Plate Barding", "tack", "barding", [("fine_steel_ingot", 10), ("hardened_leather", 4)], 10, 3, "Knightly plate for a destrier."),
         ("horseshoes_steel", "Steel Horseshoes", "tack", "shoes", [("steel_ingot", 1)], 5, 1, "Four steel shoes: faster, longer."),
         ("hoof_pick", "Hoof Pick", "tack", "tool", [("iron_ingot", 1)], 2, 0, "Keeps hooves clean.")]
    for iid, nm, cat, ms, ins, rl, r, desc in T:
        add(iid, nm, cat, F, price=None, stack=1 if ms not in ("shoes", "tool") else 4, weight=3.0, rarity=r, level=rl * 4, desc=desc, tint="#9c6a3f", glyph="fam:tack", type="tack", mount_slot=ms)
        craft(iid, "leatherwork" if ms not in ("shoes", "tool", "stirrups") else "smithing", "workbench" if ms not in ("shoes", "tool", "stirrups") else "anvil", rl, ins, xp=10 + 5 * rl)
    # mount items (livestock as goods)
    for iid, nm, p, r, lv, desc, speed in [("horse_riding", "Riding Horse", 180, 0, 6, "A sound riding horse.", 1.0), ("horse_draft", "Draft Horse", 140, 0, 4, "Slow and immensely strong.", 0.7),
                                           ("horse_courser", "Courser", 420, 1, 20, "Fast, bred for the capital's riders.", 1.35), ("horse_destrier", "Destrier", 800, 2, 34, "A warhorse trained to the charge.", 1.25),
                                           ("donkey", "Donkey", 60, 0, 1, "Stubborn and sure-footed.", 0.6)]:
        add(iid, nm, "tack", F, price=p, stack=1, weight=0.0, rarity=r, level=lv, desc=desc, tint="#9c6a3f", glyph="fam:tack", type="mount", mount=True, mount_speed=speed)


def dump_crops(path):
    with open(path, "w") as f:
        json.dump(CROPS, f, indent=1)
