"""Tools (gathering and crafting), adventuring gear and consumable supplies."""
from core import add, craft, TIERS, LEGACY

F = "tools"
# tool tiers map to core TIERS but the lowest is stone/flint
TOOL_T = [(0, "Flint", "flint", "#9aa0a8"), (1, "Bronze", "bronze", "#d9a15a"), (2, "Iron", "iron", "#c4cad4"),
          (3, "Steel", "steel", "#dfe6f2"), (4, "Fine Steel", "finesteel", "#f2f6ff"), (5, "Spirit-Iron", "spiritiron", "#9fe8d6")]
POWER = [1.0, 1.15, 1.3, 1.5, 1.75, 2.1]
RL = [1, 2, 3, 5, 7, 9]
LV = [1, 6, 12, 24, 34, 44]
RAR = [0, 0, 0, 1, 2, 3]

# word, display, skill, desc, tiers, ingot units, wood units, damage, recipe skill, glyph fam, weight, legacy iron id
TOOLS = [
    ("felling_axe", "Felling Axe", "woodcutting", "Fells trees faster and yields more timber.", [0, 1, 2, 3, 4, 5], 2, 1, 5, "smithing", "tool_axe", 2.8, "wood_axe"),
    ("pickaxe", "Pickaxe", "mining", "Bites rock. Better tools get more from every vein.", [0, 1, 2, 3, 4, 5], 2, 1, 4, "smithing", "tool_pick", 3.4, "pickaxe"),
    ("smithing_hammer", "Smithing Hammer", "smithing", "Carry one and your smithing improves faster.", [1, 2, 3, 4, 5], 1, 1, 3, "smithing", "hammer", 3.0, "hammer"),
    ("sickle", "Sickle", "farming", "Cuts grain and herbs clean; a little extra every harvest.", [0, 1, 2, 3, 4], 1, 1, 2, "smithing", "sickle", 0.8, None),
    ("shovel", "Shovel", "digging", "Digs clay, sand and furrows.", [0, 1, 2, 3, 4], 1, 1, 3, "smithing", "shovel", 2.4, None),
    ("saw", "Hand Saw", "carpentry", "Clean cuts: carpentry improves faster.", [1, 2, 3, 4], 1, 1, 2, "smithing", "saw", 1.2, None),
    ("chisel", "Mason's Chisel", "masonry", "Dresses stone and carves runes.", [1, 2, 3, 4], 1, 1, 2, "smithing", "chisel", 0.8, None),
    ("skinning_knife", "Skinning Knife", "skinning", "Takes hides and meat from kills without spoiling them.", [0, 1, 2, 3, 4], 1, 1, 3, "smithing", "dagger", 0.6, None),
]
TOOL_PRICE_NOTE = {}


def build():
    for (word, disp, skill, desc, tiers, ing, wood, dmg, rskill, fam, wt, legacy) in TOOLS:
        for t in tiers:
            ti, nm, key, tint = TOOL_T[t]
            iid = "%s_%s" % (key, word)
            if t == 2 and legacy:
                iid = legacy
            if iid in LEGACY:
                continue
            name = "%s %s" % (nm, disp)
            add(iid, name, "tool", F, price=None, stack=1, weight=wt, rarity=RAR[t], level=LV[t], desc=desc, tint=tint, glyph="fam:" + fam,
                slot="main_hand", damage=dmg + t, tool=skill, tool_tier=t, tool_power=POWER[t], durability=int(140 * (0.6 + 0.4 * POWER[t] * 1.2)),
                req_level=LV[t] if t > 2 else 1, type="tool")
            if t == 0:
                ins = [("flint", 2), ("plank", 1), ("sinew", 1)]
                sk, stn = "carpentry", "workbench"
            else:
                ins = [(TOOL_ING[t], ing), ("plank" if t < 3 else "oak_plank", wood)]
                sk, stn = "smithing", "anvil"
            craft(iid, sk, stn, RL[t], ins, xp=8 + 5 * RL[t])

    # fishing rods: wood species
    RODS = [("whittled_rod", "Whittled Rod", 0, 1, "A bent stick and a line. Everyone starts here.", [("plank", 1), ("sinew", 2), ("flint", 1)], 1),
            ("yew_rod", "Yew Fishing Rod", 1, 10, "A springy rod with a reel of waxed line.", [("yew_log", 1), ("bowstring", 1), ("iron_nails", 4)], 3),
            ("ironwood_rod", "Ironwood Fishing Rod", 2, 26, "Hauls pike and salmon without complaint.", [("ironwood_plank", 1), ("silk_thread", 2), ("steel_ingot", 1)], 6),
            ("spirit_rod", "Spiritwood Fishing Rod", 3, 44, "The line hums. Even spirit fish bite.", [("spiritwood_plank", 1), ("spirit_silk", 1), ("spirit_iron_ingot", 1)], 9)]
    for (iid, nm, t, lv, desc, ins, rl) in RODS:
        add(iid, nm, "tool", F, price=None, stack=1, weight=0.9, rarity=RAR[t + 1] if t else 0, level=lv, desc=desc, tint=["#c9a26b", "#c4885b", "#8a7058", "#a8f0c8"][t],
            glyph="fam:rod", slot="main_hand", damage=1, tool="fishing", tool_tier=t, tool_power=[1.0, 1.25, 1.6, 2.1][t], durability=120 + 40 * t, req_level=lv, type="tool")
        craft(iid, "fletching", "workbench", rl, ins, xp=10 + 5 * rl)
    # mortars
    for (iid, nm, t, lv, desc, ins, rl) in [
            ("clay_mortar", "Clay Mortar & Pestle", 0, 1, "Grinds herbs to paste.", [("clay", 3), ("firewood", 1)], 1),
            ("bronze_mortar", "Bronze Mortar & Pestle", 1, 8, "A sturdy alchemist's set.", [("bronze_ingot", 2)], 3),
            ("steel_mortar", "Steel Mortar & Pestle", 2, 24, "Doesn't taint what it grinds.", [("steel_ingot", 2), ("quartz", 1)], 5),
            ("jade_mortar", "Spirit-Jade Mortar & Pestle", 3, 42, "Carved from spirit jade; potions come out potent.", [("spirit_jade", 2), ("spirit_iron_ingot", 1)], 9)]:
        add(iid, nm, "tool", F, price=None, stack=1, weight=1.5, rarity=[0, 0, 1, 3][t], level=lv, desc=desc, tint=["#c4905c", "#d9a15a", "#dfe6f2", "#6fe0a0"][t],
            glyph="fam:powder", tool="alchemy", tool_tier=t, tool_power=[1.0, 1.2, 1.5, 2.0][t], type="tool", durability=200)
        craft(iid, "smithing" if t else "masonry", "anvil" if t else "workbench", rl, ins, xp=10 + 5 * rl)

    # ---- adventuring kit -------------------------------------------------------------------------------------------------
    def kit(iid, nm, price, fam, tint, desc, lv=1, weight=0.5, stack=10, rarity=0, **kw):
        return add(iid, nm, "tool", F, price=price, stack=stack, weight=weight, rarity=rarity, level=lv, desc=desc, tint=tint, glyph="fam:" + fam, type="kit", **kw)

    kit("torch", "Torch", None, "furniture_light", "#ffb050", "Pitch-soaked and good for an hour of light.", 1, 0.4, 20, light_hours=1.0)
    kit("lantern", "Iron Lantern", None, "furniture_light", "#ffd070", "Horn panes and a wick; burns lamp oil for many hours.", 4, 1.0, 1, light_hours=12.0, slot="trinket", durability=200)
    kit("tinderbox", "Tinderbox", None, "misc", "#b89a70", "Flint, steel and char-cloth. Fire anywhere dry.", 1, 0.3, 5, tool="firemaking")
    kit("waterskin", "Waterskin", None, "sack_food", "#b08850", "A leather skin of clean water. Four drinks.", 1, 0.6, 5, drinks=4)
    kit("bedroll", "Bedroll", None, "misc", "#8a6a4a", "A roll of blanket. Sleep outdoors without the worst of it.", 2, 1.2, 1, rest_bonus=0.25)
    kit("tent_kit", "Travel Tent", None, "misc", "#b89a70", "Oiled canvas and stakes; two sleepers.", 6, 4.0, 1, rest_bonus=0.6)
    kit("compass", "Brass Compass", 40, "misc", "#d8b860", "Keeps north even when the stars hide.", 12, 0.2, 1, rarity=1)
    kit("spyglass", "Spyglass", 60, "misc", "#c8a060", "Reveals far landmarks on the map.", 16, 0.4, 1, rarity=1)
    kit("lockpicks", "Lockpicks", None, "key", "#c4cad4", "A roll of bent wires. Open a lock if you know how.", 6, 0.1, 10, tool="lockpicking", pick_uses=6)
    kit("grappling_hook", "Grappling Hook", None, "rope", "#9aa0a8", "Hook and rope for walls and ledges.", 10, 2.0, 1)
    kit("hunting_horn", "Hunting Horn", None, "misc", "#e8d8b0", "Calls dogs, hounds and help.", 4, 0.7, 1)
    kit("worm_bait", "Tin of Worms", 1, "misc", "#b8603a", "Fish cannot refuse them.", 1, 0.1, 40, bait=1.0)
    kit("fine_bait", "Fine Fishing Bait", 6, "misc", "#e8c070", "Dough, cheese and honey.", 8, 0.1, 40, bait=1.6)
    kit("glowfly_lure", "Glowfly Lure", 18, "misc", "#a8f0a0", "Night fishing; draws emberfin and rare fish.", 16, 0.1, 20, bait=2.4, rarity=1)
    kit("caltrops", "Caltrops", None, "nails", "#9aa0a8", "Scatter behind you; pursuers slow.", 8, 0.5, 10)
    kit("mapcase", "Map Case", None, "sack_food", "#b08850", "Waxed tube for maps and orders.", 2, 0.3, 1)
    kit("cooking_pot", "Iron Cooking Pot", None, "soup", "#6a6a72", "A portable pot: cooks at any campfire.", 3, 2.5, 1)
    kit("parchment_blank", "Blank Parchment", None, "scroll", "#f0e8c8", "Scraped and smoothed. Ready for ink.", 1, 0.05, 40)
    kit("ink", "Bottle of Ink", None, "vial", "#2a2a40", "Oak-gall ink.", 1, 0.2, 20)
    kit("quill", "Goose Quill", None, "feather", "#f4f1e8", "A writing quill.", 1, 0.02, 20)
    craft("torch", "carpentry", "workbench", 1, [("log", 1), ("resin", 1), ("wool", 1)], count=3, xp=3)
    craft("lantern", "smithing", "anvil", 3, [("iron_ingot", 1), ("glass", 1), ("hinges", 1)], xp=16)
    craft("tinderbox", "carpentry", "workbench", 1, [("flint", 1), ("scrap_iron", 1), ("plank", 1)], xp=4)
    craft("waterskin", "leatherwork", "workbench", 1, [("leather", 1), ("tallow", 1)], xp=6)
    craft("bedroll", "tailoring", "workbench", 1, [("wool", 3), ("leather", 1)], xp=8)
    craft("tent_kit", "tailoring", "workbench", 3, [("waxed_cloth", 3), ("plank", 2), ("rope", 2)], xp=18)
    craft("lockpicks", "smithing", "anvil", 3, [("iron_ingot", 1)], xp=10)
    craft("grappling_hook", "smithing", "anvil", 3, [("iron_ingot", 2), ("rope", 1)], xp=14)
    craft("hunting_horn", "carpentry", "workbench", 2, [("goat_hide", 1), ("plank", 1), ("sinew", 1)], xp=8)
    craft("caltrops", "smithing", "anvil", 2, [("iron_nails", 12)], count=3, xp=8)
    craft("mapcase", "leatherwork", "workbench", 1, [("leather", 1), ("wax", 1)], xp=5)
    craft("cooking_pot", "smithing", "anvil", 2, [("iron_ingot", 2)], xp=10)
    craft("parchment_blank", "tailoring", "workbench", 1, [("goat_hide|hides", 1), ("ash", 1)], count=3, xp=3)
    craft("ink", "alchemy", ["alchemy_table"], 1, [("bark", 2), ("ash", 1), ("empty_vial", 1)], xp=4)
    craft("quill", "fletching", "workbench", 1, [("goose_feather", 2)], xp=2)


TOOL_ING = {0: "flint", 1: "bronze_ingot", 2: "iron_ingot", 3: "steel_ingot", 4: "fine_steel_ingot", 5: "spirit_iron_ingot"}
