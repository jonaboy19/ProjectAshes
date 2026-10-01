"""Named epic and legendary items: loot and boss rewards only, never sold, never crafted."""
from core import add

F = "uniques"


def u(iid, name, slot, fam, tint, level, rarity, price, desc, bonus_desc="", tier=5, stack=1, **stats):
    return add(iid, name, "gear", F, price=price, stack=1, weight=stats.pop("weight", 3.0), rarity=rarity, level=level, desc=desc, tint=tint, glyph="fam:" + fam, slot=slot,
               durability=stats.pop("durability", 400), req_level=level, unique=True, tier=tier, bonus_desc=bonus_desc or None, type=stats.pop("type", "unique"), **stats)


def build():
    tower_relics()
    # legendary (rarity 4)
    u("oathblade_of_caldrenn", "Oathblade of Caldrenn", "main_hand", "sword", "#ffe090", 45, 4, 7200,
      "The coronation sword of the first king, lost at Kingsreach in the burning. Its steel is etched with every oath sworn on it.",
      "Hits against the oath-broken (bandits, raiders, orcs at war) deal +25% damage.", damage=46, speed=0.03, crit=0.1, reach=1.3, weapon_type="sword", dmg_type="slash",
      two_handed=False, affinity=["swordsmanship"], path=["blade", "warden"], weight=2.8)
    u("emberglass_longbow", "Emberglass Longbow", "main_hand", "longbow", "#ff9a4a", 48, 4, 7800,
      "A bow of black yew strung with spider silk and set with a sliver of Emberglass Mere's sunset-coloured glass.",
      "Arrows ignite on release; burning deals 6 damage per second for 3 seconds.", damage=40, speed=0.0, crit=0.14, reach=36.0, weapon_type="longbow", dmg_type="pierce",
      ranged=True, ammo="arrow", two_handed=True, affinity=["wind", "fire"], path=["hunt"], weight=1.4)
    u("wyrmbane_spear", "Wyrmbane", "main_hand", "spear", "#8ae8c8", 55, 4, 9200,
      "A spear drawn from spirit-iron and the fang of a wyvern that killed a company of knights, forged by the man whose company it was.",
      "Deals +35% damage to wyverns and other flyers; pins them to the ground.", damage=58, speed=0.0, reach=2.3, weapon_type="spear", dmg_type="pierce", affinity=["swordsmanship"],
      path=["warden", "hunt"], weight=3.0, armour_pierce=0.2)
    u("staff_of_the_quiet_star", "Staff of the Quiet Star", "main_hand", "staff", "#c8a8ff", 58, 4, 9800,
      "Ash-white wood and a captured star-fragment. Mages who hold it say the world goes very quiet and very clear.",
      "Spells cost 15% less qi; every tenth spell is free.", damage=8, magic=84, speed=0.02, reach=1.7, weapon_type="staff", dmg_type="magic", two_handed=True, qi_regen=1.2,
      affinity=["fire", "water", "wind", "earth", "lightning", "qi"], path=["scholar"], weight=2.0)
    u("gauntlets_of_the_iron_lotus", "Gauntlets of the Iron Lotus", "main_hand", "fist", "#ffc870", 50, 4, 8600,
      "Worn by eleven abbots and never once cleaned. The knuckles are dimpled from ten thousand bricks.",
      "Every third strike releases a shockwave (+40% damage, knockback).", damage=44, speed=0.06, reach=0.6, weapon_type="fist", dmg_type="blunt", crit=0.1, affinity=["fist_palm"],
      path=["warden"], weight=2.2, armour=6)
    u("aegis_of_ashford", "Aegis of Ashford", "off_hand", "tower", "#9fe8d6", 52, 4, 9000,
      "The founders' shield, carried out of the burning town. Its face is scored with the ward-runes of the first stones.",
      "Blocks are free of stamina cost; blocked damage reflects 20% as holy fire.", armour=40, speed=-0.04, block=0.5, weapon_type="shield", shield_type="tower", affinity=["earth"], path=["warden"], weight=6.0)
    u("mantle_of_ash", "Mantle of Ash", "cloak", "cloak", "#a09890", 50, 4, 7400,
      "A grey cloak woven from the ash the Ghosts leave behind. It drifts even in still air.",
      "Once per minute, the first lethal hit leaves you at 1 health and wreathed in ash (enemies lose you).", armour=16, resist=30, qi_regen=0.5, speed=0.03, stealth=0.2, path=["wanderer"], weight=0.6)
    u("crown_of_embers", "Crown of Embers", "head", "helm", "#ff7a3a", 56, 4, 9600,
      "An iron circlet that glows like a banked fire. Whoever wears it cannot be made cold.",
      "Immune to frost; fire spells cast +30% stronger.", armour=20, magic=28, resist=36, max_health=50, path=["scholar"], armour_load=0.3, weight=1.2)
    u("ring_of_the_first_flame", "Ring of the First Flame", "ring", "ring", "#ff9a4a", 55, 4, 8400,
      "A band of red gold from the hearth of the first fire in the valley.", "Warmth flows back into you: 2 health per second out of combat.", damage=7, magic=16, max_health=40, qi_regen=0.6, weight=0.05)
    u("amulet_of_the_sleeping_ward", "Amulet of the Sleeping Ward", "amulet", "amulet", "#9fe8d6", 57, 4, 9400,
      "Carved from a fragment of the great runestone at Ashford. It sleeps until you are in danger.",
      "When health falls below 25%, a ward erupts, absorbing the next 150 damage (once per hour).", max_health=130, armour=12, resist=24, weight=0.1)
    u("rift_warden_plate", "Rift-Warden's Breastplate", "body", "chest_plate", "#c79bff", 58, 4, 9800,
      "Plate cut from a single rift-crystal slab, the last piece of the Wardens' last harness.",
      "Damage from rift-touched creatures reduced by 30%.", armour=88, resist=40, max_health=90, speed=-0.02, armour_load=0.8, armour_class="heavy", weight=7.5, set="rift_warden")
    u("seers_shroud", "Seer's Shroud", "body", "chest_cloth", "#e8c8ff", 56, 4, 9000,
      "A robe that remembers being worn by ghosts. It is always slightly cold.",
      "You can see ash-memories without the Ashsight; spells cost 10% less qi.", armour=16, magic=70, resist=50, qi_regen=1.0, armour_class="robe", armour_load=0.05, weight=0.8)

    # epic (rarity 3), named uniques for Region 1
    u("greywatch_longspear", "Greywatch Longspear", "main_hand", "spear", "#dfe6f2", 34, 3, 2600, "Issued only to Hall Captains of Greywatch; the haft is wound with grey cord.",
      damage=32, reach=2.2, weapon_type="spear", dmg_type="pierce", affinity=["swordsmanship", "command"], path=["warden"], weight=2.8, tier=4)
    u("duskbriar_hunting_bow", "Duskbriar Hunting Bow", "main_hand", "longbow", "#8a7058", 30, 3, 2200, "Ironwood and deer sinew; built by a hunter who never missed a wolf.",
      damage=30, crit=0.1, reach=32.0, weapon_type="longbow", dmg_type="pierce", ranged=True, ammo="arrow", two_handed=True, affinity=["wind"], path=["hunt"], weight=1.5, tier=4)
    u("stormcaller_wand", "Stormcaller Wand", "main_hand", "wand", "#fff070", 40, 3, 3400, "A copper wand wrapped in lightning-struck yew. It smells of rain.",
      damage=5, magic=38, speed=0.02, reach=0.7, weapon_type="wand", dmg_type="magic", affinity=["lightning"], path=["scholar"], weight=0.4, tier=5)
    u("bonecleaver_of_tuskridge", "Bonecleaver of Tuskridge", "main_hand", "battleaxe", "#e0d8b0", 38, 3, 3000, "The Tuskridge chief's axe: steel head, orc tusk haft-rings, too many notches to count.",
      damage=46, speed=-0.04, reach=1.5, weapon_type="battleaxe", dmg_type="slash", two_handed=True, affinity=["earth"], path=["warden"], weight=6.6, tier=4)
    u("riftpiercer", "Riftpiercer", "main_hand", "dagger", "#c79bff", 54, 3, 5200, "A dagger whose edge is pure rift-crystal. It slips through armour like water through a net.",
      damage=38, speed=0.05, crit=0.22, reach=0.9, weapon_type="dagger", dmg_type="pierce", armour_pierce=0.4, affinity=["shadow"], path=["wanderer"], weight=0.8, tier=6)
    u("hearthkeepers_hammer", "Hearthkeeper's Hammer", "main_hand", "warhammer", "#ffb870", 36, 3, 2800, "Forged by a dozen Ashford smiths for the village champion; burns with a quiet warmth.",
      damage=44, speed=-0.05, reach=1.3, weapon_type="warhammer", dmg_type="blunt", two_handed=True, forge_quality=0.1, affinity=["earth"], path=["forge", "warden"], weight=6.0, tier=4)
    u("silent_reed_sabre", "Silent Reed Sabre", "main_hand", "sabre", "#cfd8f0", 32, 3, 2600, "Hollow Moon school steel. Sheathing it makes no sound.",
      damage=30, speed=0.04, crit=0.14, reach=1.2, weapon_type="sabre", dmg_type="slash", affinity=["iaido", "shadow"], path=["blade"], weight=2.0, tier=4)
    u("wolfmothers_charm", "Wolf-Mother's Charm", "trinket", "talisman", "#8fd0ff", 26, 3, 1800, "Carved from the fang of the pack-mother of Duskbriar. Wolves see you as kin.",
      speed=0.06, max_health=30, stealth=0.15, weight=0.1, tier=4)
    u("kingsreach_signet", "Kingsreach Signet", "ring", "ring", "#ffd65c", 30, 3, 2400, "A noble's signet; the wax seal it makes opens doors and ledgers.",
      armour=4, max_health=25, charm=0.2, weight=0.05, tier=4)
    u("troll_hide_cloak", "Troll-Hide Cloak", "cloak", "cloak", "#6f8a66", 32, 3, 2000, "Whole troll hide, tanned green-grey. The wearer knits slowly while resting.",
      armour=10, resist=14, regen=0.5, max_health=40, weight=2.0, tier=4)
    u("scarbloom_circlet", "Scarbloom Circlet", "head", "helm_cloth", "#c79bff", 28, 3, 2000, "Woven scar-flowers that never wilt; the Rift's touch in every petal.",
      armour=6, magic=16, resist=16, weight=0.3, armour_class="robe", tier=4)


def tower_relics():
    """tower_relic_<tower>_<floor>: first-clear relics of the towers (scripts/world/towers/tower_data.gd relic()). Same stats as
    that function; the tower agent may rename them at grant time."""
    SLOTS = ["Crown", "Sigil", "Band", "Seal", "Charm", "Fetish"]
    stats = ["max_health", "damage", "armour", "stamina_regen"]
    for tid, floors, lo, hi in [("ashfall_spire", 20, 5, 60)]:
        for n in range(1, floors + 1):
            stat = stats[(n - 1) % 4]
            val = {"max_health": 6.0 + 2.0 * n, "damage": 1.0 + 0.6 * n, "armour": 1.0 + 0.5 * n, "stamina_regen": 0.04 + 0.01 * n}[stat]
            lvl = int(round(lo + (hi - lo) * (n - 1) / (floors - 1)))
            add("tower_relic_%s_%d" % (tid, n), "Spire Relic %d (%s)" % (n, SLOTS[(n - 1) % len(SLOTS)]), "gear", F, price=int(300 + 120 * n), stack=1, weight=0.2,
                rarity=2 if n < 10 else 3, level=lvl, desc="Taken from the guardian of floor %d. Its bonus lasts as long as you carry it." % n, tint="#c79bff", glyph="fam:talisman",
                slot="trinket", durability=500, req_level=1, unique=True, type="relic", tier=min(6, 1 + n // 4), **{stat: round(val, 2)})
