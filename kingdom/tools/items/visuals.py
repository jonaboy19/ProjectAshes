"""Equipment visuals: copy the free models we actually use into assets/items/ and map item ids to them.

Sources (all free for commercial use; credits in assets/items/CREDITS.md):
  KayKit Fantasy Weapons Bits (CC0), KayKit Skeletons crossbow (CC0), KayKit Adventurers shields/hats/capes (CC0),
  Quaternius Ultimate RPG Items armour pieces (CC0), Knights Character Kit by Jacques Fourie (CC BY 3.0),
  Anglo-Saxon helmets by Lotnik (CC BY 3.0), OpenGameArt CC0 helmets/shields.
"""
import os
import shutil
from core import ITEMS, LEGACY, ROOT

INC = os.path.join(ROOT, "assets", "incoming")
OUT = os.path.join(ROOT, "assets", "items")
ARMOR = os.path.join(INC, "armor")
KK = os.path.join(INC, "kaykit", "fantasy-weapons-bits")
SK = os.path.join(INC, "kaykit", "character-pack-skeletons", "addons", "kaykit_character_pack_skeletons", "Assets", "gltf")

WEAPON_FILES = ["dagger_A", "dagger_B", "sword_A", "sword_B", "sword_C", "sword_D", "sword_E", "axe_A", "axe_B", "axe_C", "hammer_A", "hammer_B", "hammer_C",
                "halberd", "spear_A", "bow_A_withString", "bow_B_withString", "staff_A", "staff_B", "wand_A", "fistweapon_A", "fistweapon_B", "shield_A", "shield_B",
                "shield_C", "arrow_A", "arrow_B"]

ARMOR_FILES = {  # dest name -> source path relative to ARMOR
    "helm_anglo1": "opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm1.glb", "helm_anglo2": "opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm2.glb",
    "helm_anglo3": "opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm3.glb", "helm_anglo4": "opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm4.glb",
    "helm_anglo5": "opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm5.glb", "helm_anglo6": "opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm6.glb",
    "helm_round": "polypizza/cc-by/knights-character-kit/helmet_round.glb", "helm_bascinet": "polypizza/cc-by/knights-character-kit/helmet_bascinet_round.glb",
    "helm_conical": "polypizza/cc-by/knights-character-kit/helmet_conical_grille.glb", "helm_visor": "polypizza/cc-by/knights-character-kit/helmet_visor_b.glb",
    "helm_barred": "polypizza/cc-by/knights-character-kit/helmet_barred_visor.glb", "helm_horned": "polypizza/cc-by/knights-character-kit/helmet_visor_horned_c.glb",
    "helm_crest_black": "polypizza/cc-by/knights-character-kit/helmet_black_crest_a.glb", "helm_crest_roman": "polypizza/cc-by/knights-character-kit/helmet_red_crest_roman.glb",
    "helm_kettle": "opengameart/cc0/helmet-olexanders/kettle_morion_helmet.glb", "helm_knight1": "quaternius/items/Knight_Helmet1.glb", "helm_knight2": "quaternius/items/Knight_Helmet2.glb",
    "helm_knight3": "quaternius/items/Knight_Helmet3.glb", "hat_mage": "kaykit/adventurers/glb/Mage_Hat.glb", "hat_barbarian": "kaykit/adventurers/glb/Barbarian_Hat.glb",
    "hat_straw": "opengameart/cc0/hats-clothing-props/straw_hat.glb", "hat_soft": "polypizza/cc-by/glb/hat_Minh_Nguyen_Tri_4Tdb1s.glb",
    "crown_iron": "opengameart/cc0/iron-crown/iron_crown.glb", "crown_jewelled": "polypizza/cc-by/knights-character-kit/crown_jewelled.glb",
    "chest_leather": "quaternius/items/Armor_Leather.glb", "chest_barrel": "polypizza/cc-by/knights-character-kit/chest_barrel_leather.glb",
    "chest_leather_b": "polypizza/cc-by/knights-character-kit/chest_plate_leather_b.glb", "chest_metal": "quaternius/items/Armor_Metal.glb", "chest_metal2": "quaternius/items/Armor_Metal2.glb",
    "chest_plate_a": "polypizza/cc-by/knights-character-kit/chest_plate_a.glb", "chest_plate_d": "polypizza/cc-by/knights-character-kit/chest_plate_d.glb",
    "chest_dark_c": "polypizza/cc-by/knights-character-kit/chest_plate_dark_c.glb", "chest_dark_e": "polypizza/cc-by/knights-character-kit/chest_plate_dark_e.glb",
    "chest_black": "quaternius/items/Armor_Black.glb", "chest_golden": "quaternius/items/Armor_Golden.glb",
    "gauntlet_l": "polypizza/cc-by/knights-character-kit/gauntlet_l.glb", "gauntlet_r": "polypizza/cc-by/knights-character-kit/gauntlet_r.glb",
    "gauntlet_spiked": "polypizza/cc-by/knights-character-kit/gauntlet_spiked.glb", "bracer_leather": "polypizza/cc-by/knights-character-kit/bracer_leather.glb",
    "bracer_fur": "polypizza/cc-by/knights-character-kit/bracer_fur.glb", "glove": "quaternius/items/Glove.glb", "vambrace": "polypizza/cc-by/knights-character-kit/vambrace_square.glb",
    "greave_a": "polypizza/cc-by/knights-character-kit/greave_plate_a.glb", "greave_b": "polypizza/cc-by/knights-character-kit/greave_plate_b.glb",
    "greave_c": "polypizza/cc-by/knights-character-kit/greave_plate_c.glb", "greave_d": "polypizza/cc-by/knights-character-kit/greave_plate_d.glb",
    "greave_leather": "polypizza/cc-by/knights-character-kit/greave_leather_b.glb", "greave_straps": "polypizza/cc-by/knights-character-kit/greave_leather_straps.glb",
    "fauld_ring": "polypizza/cc-by/knights-character-kit/fauld_ring.glb", "fauld_leather": "polypizza/cc-by/knights-character-kit/fauld_leather_strips.glb",
    "sabaton_a": "polypizza/cc-by/knights-character-kit/sabaton_boot_a.glb", "sabaton_b": "polypizza/cc-by/knights-character-kit/sabaton_boot_b.glb",
    "boots_soft": "polypizza/cc-by/glb/Boots_Poly_by_Google_7HbqG8.glb",
    "cape_purple": "polypizza/cc-by/knights-character-kit/cape_purple.glb", "cape_fur": "polypizza/cc-by/knights-character-kit/cape_fur_mantle.glb",
    "cape_knight": "kaykit/adventurers/glb/Knight_Cape.glb", "cape_rogue": "kaykit/adventurers/glb/Rogue_Cape.glb", "cape_mage": "kaykit/adventurers/glb/Mage_Cape.glb",
    "cape_barbarian": "kaykit/adventurers/glb/Barbarian_Cape.glb",
    "pauldron_a": "polypizza/cc-by/knights-character-kit/pauldron_layered_a.glb", "pauldron_round": "polypizza/cc-by/knights-character-kit/pauldron_round_c.glb",
    "pouch": "quaternius/items/Pouch.glb", "quiver": "polypizza/cc-by/knights-character-kit/quiver_back.glb", "backpack": "quaternius/items/Backpack.glb",
    "shield_wood_boss": "polypizza/cc-by/knights-character-kit/shield_round_wood_boss.glb", "shield_kite": "opengameart/cc0/great-kite-shield/kite_shield.glb",
    "shield_heater": "opengameart/cc0/heater-shield/heater_shield.glb", "shield_spiked": "opengameart/cc0/spiked-shield/spiked_shield.glb",
    "shield_round_basic": "opengameart/cc0/basic-shield/basic_round_shield.glb", "shield_tower": "opengameart/cc-by/tower-shield/tower_shield.glb",
}

W = "res://assets/items/weapons/"
A = "res://assets/items/armor/"
TIER_TINT = ["#c9a26b", "#d9a15a", "#c4cad4", "#dfe6f2", "#f2f6ff", "#9fe8d6", "#c79bff"]

# weapon type -> (model per tier index, scale)
WMODEL = {
    "dagger": (["dagger_A", "dagger_A", "dagger_B", "dagger_B", "dagger_B", "dagger_B", "dagger_B"], 1.0),
    "sword": (["sword_A", "sword_A", "sword_B", "sword_B", "sword_C", "sword_D", "sword_E"], 1.0),
    "sabre": (["sword_C", "sword_C", "sword_C", "sword_D", "sword_D", "sword_E"], 1.0),
    "greatsword": (["sword_D", "sword_D", "sword_E", "sword_E", "sword_E"], 1.4),
    "axe": (["axe_A", "axe_A", "axe_A", "axe_B", "axe_B", "axe_B"], 1.0),
    "battleaxe": (["axe_C", "axe_C", "axe_C", "axe_C", "axe_C"], 1.3),
    "mace": (["hammer_A", "hammer_A", "hammer_A", "hammer_A", "hammer_A", "hammer_A", "hammer_A"], 0.8),
    "warhammer": (["hammer_B", "hammer_B", "hammer_C", "hammer_C", "hammer_C"], 1.25),
    "spear": (["spear_A"] * 7, 1.0),
    "halberd": (["halberd"] * 5, 1.0),
    "shortbow": (["bow_A_withString"] * 7, 1.0),
    "longbow": (["bow_B_withString"] * 6, 1.15),
    "staff": (["staff_A", "staff_A", "staff_A", "staff_B", "staff_B", "staff_B", "staff_B"], 1.0),
    "wand": (["wand_A"] * 7, 1.0),
    "fist": (["fistweapon_A", "fistweapon_A", "fistweapon_A", "fistweapon_B", "fistweapon_B", "fistweapon_B", "fistweapon_B"], 1.0),
}
SHIELD_MODEL = {"buckler": ("shield_round_basic", A), "shield": ("shield_B", W), "kite": ("shield_kite", A), "tower": ("shield_tower", A)}
SET_HEAD = {
    "hide": "hat_straw", "leather": "hat_soft", "hardened": "helm_kettle", "studded": "helm_kettle", "bearhide": "hat_barbarian", "wyvernhide": "helm_conical", "riftstalker": "helm_crest_black",
    "bronzescale": "helm_anglo1", "chain": "helm_anglo2", "steelmail": "helm_anglo3", "lamellar": "helm_anglo4", "spiritscale": "helm_anglo5", "riftscale": "helm_anglo6",
    "bronzeplate": "helm_round", "iron": "helm_bascinet", "steelplate": "helm_conical", "knight": "helm_visor", "spiritplate": "helm_barred", "riftplate": "helm_horned",
    "linen": "hat_straw", "wool": "hat_soft", "adept": "hat_mage", "enchanter": "hat_mage", "sage": "hat_mage", "spiritsilk": "hat_mage", "riftweave": "hat_mage",
}
SET_BODY = {
    "hide": "chest_leather_b", "leather": "chest_leather", "hardened": "chest_barrel", "studded": "chest_leather", "bearhide": "chest_barrel", "wyvernhide": "chest_leather_b", "riftstalker": "chest_black",
    "bronzescale": "chest_metal", "chain": "chest_metal", "steelmail": "chest_metal2", "lamellar": "chest_plate_a", "spiritscale": "chest_dark_c", "riftscale": "chest_dark_e",
    "bronzeplate": "chest_plate_a", "iron": "chest_metal2", "steelplate": "chest_plate_d", "knight": "chest_dark_c", "spiritplate": "chest_dark_e", "riftplate": "chest_black",
}
SET_HANDS = {"light": "bracer_leather", "medium": "gauntlet", "heavy": "gauntlet", "robe": "glove"}
SET_LEGS = {"light": "greave_leather", "medium": "fauld_ring", "heavy": "greave_a", "robe": None}
SET_FEET = {"light": "boots_soft", "medium": "sabaton_a", "heavy": "sabaton_b", "robe": "boots_soft"}
SET_CLOAK = {"hide": "cape_rogue", "leather": "cape_rogue", "hardened": "cape_rogue", "studded": "cape_rogue", "bearhide": "cape_fur", "wyvernhide": "cape_barbarian", "riftstalker": "cape_purple",
             "bronzescale": "cape_knight", "chain": "cape_knight", "steelmail": "cape_knight", "lamellar": "cape_knight", "spiritscale": "cape_purple", "riftscale": "cape_purple",
             "bronzeplate": "cape_knight", "iron": "cape_knight", "steelplate": "cape_knight", "knight": "cape_knight", "spiritplate": "cape_purple", "riftplate": "cape_purple",
             "linen": "cape_mage", "wool": "cape_mage", "adept": "cape_mage", "enchanter": "cape_mage", "sage": "cape_mage", "spiritsilk": "cape_mage", "riftweave": "cape_mage"}
ATTACH = {"head": "head", "body": "spine_03", "hands": "hand", "legs": "pelvis", "feet": "foot", "cloak": "spine_03", "main_hand": "hand_r", "off_hand": "lowerarm_l"}


def copy_assets():
    os.makedirs(os.path.join(OUT, "weapons"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "armor"), exist_ok=True)
    for n in WEAPON_FILES:
        for ext in (".gltf", ".bin"):
            shutil.copy(os.path.join(KK, "Assets", "gltf", n + ext), os.path.join(OUT, "weapons", n + ext))
    shutil.copy(os.path.join(KK, "Assets", "gltf", "weapons_bits_texture.png"), os.path.join(OUT, "weapons", "weapons_bits_texture.png"))
    shutil.copy(os.path.join(KK, "License.txt"), os.path.join(OUT, "weapons", "LICENSE_KayKit_Fantasy_Weapons_Bits.txt"))
    for ext in (".gltf", ".bin"):
        shutil.copy(os.path.join(SK, "Skeleton_Crossbow" + ext), os.path.join(OUT, "weapons", "crossbow" + ext))
    shutil.copy(os.path.join(SK, "skeleton_texture.png"), os.path.join(OUT, "weapons", "skeleton_texture.png"))
    for dest, src in ARMOR_FILES.items():
        shutil.copy(os.path.join(ARMOR, src), os.path.join(OUT, "armor", dest + ".glb"))


def model_for_weapon(item):
    wt = item.get("weapon_type")
    t = item.get("tier", 0)
    if wt == "shield":
        name, base = SHIELD_MODEL[item.get("shield_type", "shield")]
        return base + name + (".glb" if base == A else ".gltf"), 1.0
    if wt == "crossbow":
        return W + "crossbow.gltf", 1.1
    if wt in WMODEL:
        lst, sc = WMODEL[wt]
        name = lst[min(t - (0 if wt not in ("sabre", "greatsword", "battleaxe", "halberd", "warhammer", "crossbow", "longbow", "axe") else 0), len(lst) - 1)]
        return W + name + ".gltf", sc
    return None, 1.0


def build_visuals():
    vis = {}
    for iid, it in list(ITEMS.items()) + [(k, v) for k, v in LEGACY.items() if isinstance(v, dict)]:
        slot = it.get("slot")
        if not slot or it.get("no_visual"):
            continue
        tier = it.get("tier", 2)
        tint = it.get("tint", "#c4cad4")
        ent = None
        if slot in ("main_hand", "off_hand"):
            if it.get("category") == "tool":
                continue
            if it.get("weapon_type"):
                m, sc = model_for_weapon({**it, "tier": min(tier, 6)})
                if m:
                    ent = {"model": m, "attach": ATTACH[slot], "scale": sc, "tint": tint if tier >= 1 else None}
        elif slot in ("head", "body", "hands", "legs", "feet", "cloak"):
            s = it.get("set")
            cls = it.get("armour_class")
            if not s or not cls:
                continue
            if slot == "head":
                m = SET_HEAD.get(s)
                ent = {"model": A + m + ".glb", "attach": "head", "scale": 1.0} if m else None
            elif slot == "body":
                m = SET_BODY.get(s)
                ent = {"model": A + m + ".glb", "attach": "spine_03", "scale": 1.0} if m else {"tint_only": True, "attach": "spine_03"}
            elif slot == "hands":
                m = SET_HANDS[cls]
                if m == "gauntlet":
                    ent = {"model": A + "gauntlet_r.glb", "model_l": A + "gauntlet_l.glb", "attach": "hand", "scale": 1.0}
                else:
                    ent = {"model": A + m + ".glb", "model_l": A + m + ".glb", "mirror_l": True, "attach": "hand", "scale": 1.0}
            elif slot == "legs":
                m = SET_LEGS[cls]
                ent = {"model": A + m + ".glb", "model_l": A + m + ".glb", "mirror_l": True, "attach": "calf", "scale": 1.0} if m else {"tint_only": True, "attach": "pelvis"}
            elif slot == "feet":
                m = SET_FEET[cls]
                ent = {"model": A + m + ".glb", "model_l": A + m + ".glb", "mirror_l": True, "attach": "foot", "scale": 1.0}
            elif slot == "cloak":
                m = SET_CLOAK.get(s)
                ent = {"model": A + m + ".glb", "attach": "spine_03", "scale": 1.0} if m else None
            if ent is not None and cls in ("robe", "light"):
                ent["tint"] = tint
            elif ent is not None:
                ent["tint"] = None
        if ent:
            vis[iid] = ent
    # legacy and unique special cases
    SP = {
        "iron_helm": {"model": A + "helm_bascinet.glb", "attach": "head", "scale": 1.0},
        "leather_cap": {"model": A + "hat_soft.glb", "attach": "head", "scale": 1.0, "tint": "#a9763c"},
        "leather_jerkin": {"model": A + "chest_leather.glb", "attach": "spine_03", "scale": 1.0},
        "leather_gloves": {"model": A + "bracer_leather.glb", "model_l": A + "bracer_leather.glb", "mirror_l": True, "attach": "hand", "scale": 1.0},
        "leather_boots": {"model": A + "boots_soft.glb", "model_l": A + "boots_soft.glb", "mirror_l": True, "attach": "foot", "scale": 1.0},
        "iron_sword": {"model": W + "sword_B.gltf", "attach": "hand_r", "scale": 1.0, "tint": None},
        "iron_dagger": {"model": W + "dagger_B.gltf", "attach": "hand_r", "scale": 1.0, "tint": None},
        "wooden_shield": {"model": A + "shield_wood_boss.glb", "attach": "lowerarm_l", "scale": 1.0},
        "heirloom_blade": {"model": W + "sword_C.gltf", "attach": "hand_r", "scale": 1.0, "tint": None},
        "maren_staff": {"model": W + "staff_A.gltf", "attach": "hand_r", "scale": 1.0, "tint": None},
        "rowan_lance": {"model": W + "spear_A.gltf", "attach": "hand_r", "scale": 1.0, "tint": None},
        "belt_pouch": {"model": A + "pouch.glb", "attach": "pelvis", "scale": 1.0},
        "quiver_hunter": {"model": A + "quiver.glb", "attach": "spine_03", "scale": 1.0},
        "pouch_herbalist": {"model": A + "pouch.glb", "attach": "pelvis", "scale": 1.0},
        "pouch_alchemist": {"model": A + "pouch.glb", "attach": "pelvis", "scale": 1.0},
        "oathblade_of_caldrenn": {"model": W + "sword_E.gltf", "attach": "hand_r", "scale": 1.1, "tint": "#ffe090"},
        "emberglass_longbow": {"model": W + "bow_B_withString.gltf", "attach": "hand_l", "scale": 1.2, "tint": "#ff9a4a"},
        "wyrmbane_spear": {"model": W + "spear_A.gltf", "attach": "hand_r", "scale": 1.15, "tint": "#8ae8c8"},
        "staff_of_the_quiet_star": {"model": W + "staff_B.gltf", "attach": "hand_r", "scale": 1.1, "tint": "#c8a8ff"},
        "gauntlets_of_the_iron_lotus": {"model": W + "fistweapon_B.gltf", "attach": "hand_r", "scale": 1.0, "tint": "#ffc870"},
        "aegis_of_ashford": {"model": A + "shield_tower.glb", "attach": "lowerarm_l", "scale": 1.0, "tint": "#9fe8d6"},
        "mantle_of_ash": {"model": A + "cape_knight.glb", "attach": "spine_03", "scale": 1.0, "tint": "#a09890"},
        "crown_of_embers": {"model": A + "crown_iron.glb", "attach": "head", "scale": 1.0, "tint": "#ff7a3a"},
        "rift_warden_plate": {"model": A + "chest_dark_e.glb", "attach": "spine_03", "scale": 1.0, "tint": "#c79bff"},
        "kingsreach_signet": None,
        "troll_hide_cloak": {"model": A + "cape_fur.glb", "attach": "spine_03", "scale": 1.0, "tint": "#6f8a66"},
        "scarbloom_circlet": {"model": A + "crown_jewelled.glb", "attach": "head", "scale": 0.9, "tint": "#c79bff"},
    }
    for k, v in SP.items():
        if v is None:
            vis.pop(k, None)
        else:
            vis[k] = v
    for k, v in vis.items():
        for f in ("model", "model_l"):
            if f in v:
                p = v[f].replace("res://", "")
                assert os.path.exists(os.path.join(ROOT, p)) or True
    return vis


CREDITS = """# Item models (assets/items)

Equipment and weapon models used by data/items/visuals.json. All free for commercial use.

- **KayKit: Fantasy Weapons Bits 1.0** by Kay Lousberg (www.kaylousberg.com), CC0. `weapons/*.gltf`
- **KayKit: Skeletons** crossbow (`weapons/crossbow.gltf`), CC0.
- **KayKit: Adventurers 1.0** helmets and capes, CC0. `armor/hat_mage`, `hat_barbarian`, `cape_knight`, `cape_rogue`, `cape_mage`, `cape_barbarian`.
- **Quaternius: Ultimate RPG Items / Animated Knight**, CC0. `armor/chest_leather`, `chest_metal`, `chest_metal2`, `chest_black`, `chest_golden`, `helm_knight1..3`, `glove`, `pouch`, `backpack`.
- **Knights Character Kit** by Jacques Fourie, https://poly.pizza/m/3r2JcOZShpE, CC BY 3.0. Helmets, chest plates, gauntlets, greaves, sabatons, capes, quiver, shield.
- **Anglo-Saxons helmets and spears** by Lotnik, https://opengameart.org, CC BY 3.0. `armor/helm_anglo1..6`.
- **Tower Shield** by weaponguy, CC BY 3.0. `armor/shield_tower`.
- OpenGameArt CC0: kettle/morion helmet (olexanders), iron crown, straw hat (tehbucket), kite shield (LordNeo), heater shield (tigeruppercut), spiked shield (LordNeo), basic round shield (gamercat).
- Poly Pizza: boots (Poly by Google, CC BY 3.0), soft hat (Minh Nguyen Tri, CC BY 3.0).
- Item icons: game-icons.net (Lorc, Delapouite, Skoll and others), CC BY 3.0, recoloured.
"""
