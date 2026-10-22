#!/usr/bin/env python3
"""Generates data/world/town_identity.json: the per-settlement VISUAL IDENTITY data (docs/design/VERTICAL_SLICE.md:
"you should recognise a settlement without reading its name").  Run from the kingdom dir:
    python3 tools/town_identity/gen_town_identity.py
Consumed by scripts/world/town_identity.gd (profile per town = archetype defaults + town overrides + terrain sense + size).

Vocabulary
  arch      visual archetype (maps to a realm identity of scripts/realm/settlements.gd IDENTITIES via `realm`)
  roof      house-variant mix (thatch / shingle / slate / red / tall): chooses WHICH shared house meshes a town uses, because
            the roof colour is baked into each house atlas (thatch: house_1/5/9, shingle: 2/6/10/13, slate: 3/7/11/12/16,
            red tile: 8/14/15).  `tint` (palette) then colours the whole instance (MultiMesh instance colour: no new draws).
  wall      stone | low | palisade | hedge | runestones | none
  layout    royal | radial | terraced | strung | loose | close | bank | lanes | campus | hold | green
  kits      named dressing bundles (KITS below): district prop specs + outskirts "yards" built by town_identity_view.gd
"""
import json, os

OUT = "data/world/town_identity.json"

PALETTES = {
    "neutral":    {"tint": "#FFFFFF", "desc": "unchanged (Kingsreach keeps the reference look)"},
    "honey":      {"tint": "#FFEBC0", "desc": "warm straw and honey plaster"},
    "whitewash":  {"tint": "#F2F6FF", "desc": "bright limewash"},
    "stone_grey": {"tint": "#D5DDE8", "desc": "cold grey masonry"},
    "ochre":      {"tint": "#FFE2A0", "desc": "ochre-washed plaster"},
    "terracotta": {"tint": "#FFD2BC", "desc": "baked clay and madder"},
    "umber":      {"tint": "#C4B5A2", "desc": "sooty brown, shabby"},
    "slate_cool": {"tint": "#CADBF6", "desc": "cool blue-grey, damp"},
    "moss":       {"tint": "#D6EDCB", "desc": "mossy green"},
    "sand":       {"tint": "#FFEDCC", "desc": "pale sand"},
    "cream_gold": {"tint": "#FFF3D2", "desc": "cream and gilt"},
    "ash":        {"tint": "#B5AEA6", "desc": "charcoal soot"},
    "amber":      {"tint": "#FFDB8C", "desc": "amber beeswax glow"},
    "rose":       {"tint": "#FFD8DA", "desc": "madder-dyed plaster"},
    "frost":      {"tint": "#E2ECFF", "desc": "cold blue-white"},
    "teal":       {"tint": "#CFEDE4", "desc": "sea-green wash"},
    "plum":       {"tint": "#EBD3F2", "desc": "dyer's violet"},
    "iron":       {"tint": "#BDB3AD", "desc": "rust-stained, ore dust"},
}

# ------------------------------------------------------------------ kits
def d(ids, n, r=1.2, frm="edge", face=False, solid=False, sc=1.0, **kw):
    """One district dressing spec: ids = [district kinds]."""
    e = {"in": ids, "id": None, "n": n, "r": r, "from": frm}
    if face: e["face"] = True
    if solid: e["solid"] = True
    if sc != 1.0: e["sc"] = sc
    e.update(kw)
    return e

def spec(ids, id_, n, r=1.2, frm="edge", face=False, solid=False, sc=1.0):
    e = d(ids, n, r, frm, face, solid, sc); e["id"] = id_; return e

ALL = ["market", "craft", "poor", "admin", "inn", "military"]
HOME = ["craft", "poor", "inn", "market"]
KITS = {
    # --- farming / pastoral
    "haystacks":  {"dress": [spec(["poor", "inn", "craft", "market"], "haystack", 0.28, 2.2, "yard", solid=True),
                             spec(["poor", "inn"], "hay", 0.2, 1.2, "yard")], "yards": [{"kind": "stacks", "n": 7}]},
    "granary":    {"yards": [{"kind": "granary", "n": 2}], "dress": [spec(["poor", "craft"], "sack_pile", 0.3, 1.0)]},
    "mills":      {"yards": [{"kind": "mills", "n": 3}]},
    "big_fields": {"yards": [{"kind": "fields", "n": 3}]},
    "pens":       {"yards": [{"kind": "pens", "n": 3}], "dress": [spec(["poor", "inn", "craft"], "fence", 0.5, 1.6, "yard"), spec(["poor", "inn"], "water_trough", 0.35, 1.3, "edge", face=True)]},
    "dairy":      {"dress": [spec(["poor", "inn", "craft"], "water_trough", 0.45, 1.3, "edge", face=True), spec(["poor", "inn"], "barrel_cluster", 0.4, 1.0), spec(["poor", "inn"], "fence", 0.4, 1.6, "yard")]},
    "brewery":    {"dress": [spec(["craft", "inn", "market"], "barrel_cluster", 0.7, 1.0), spec(["craft", "inn"], "cart", 0.12, 2.0, "yard", solid=True), spec(["inn", "craft"], "barrel", 0.5, 0.5)], "yards": [{"kind": "granary", "n": 1}]},
    "great_oak":  {"yards": [{"kind": "great_tree", "n": 1}]},
    "bees":       {"dress": [spec(["poor", "inn", "craft", "market"], "flower_bed", 0.45, 1.3, "yard"), spec(["market", "inn", "poor"], "basket_produce", 0.5, 0.5), spec(["poor", "inn"], "hay", 0.2, 1.2, "yard")]},
    "wool":       {"dress": [spec(["craft", "poor", "market"], "d:drying_rack", 0.45, 1.5, "yard", face=True), spec(["market", "inn"], "produce_table", 0.3, 1.1, "edge", face=True)], "yards": [{"kind": "pens", "n": 4}]},
    "fair_green": {"dress": [spec(["market", "inn"], "market_stall_green", 0.18, 2.7, "edge", face=True, solid=True), spec(["market", "inn"], "market_stall_red", 0.14, 2.7, "edge", face=True, solid=True), spec(["market", "admin"], "banner_pole", 0.7, 0.6, "edge", face=True)]},
    # --- mining / quarry / charcoal
    "mine":       {"dress": [spec(["craft", "poor"], "g:region/mine/mine_cart", 0.3, 1.2, "edge"), spec(["craft", "poor", "military"], "g:region/mine/ore_pile_iron", 0.35, 1.5, "yard"),
                             spec(["craft", "poor"], "g:region/mine/ore_pile_coal", 0.3, 1.5, "yard"), spec(["craft", "poor"], "g:region/mine/tunnel_support", 0.14, 1.6, "edge", face=True)],
                   "yards": [{"kind": "mine_yard", "n": 1}, {"kind": "spoil", "n": 4}]},
    "quarry":     {"dress": [spec(["craft", "poor", "market"], "g:region/nature/rock_slab", 0.4, 1.4, "yard"), spec(["craft", "poor"], "hand_cart", 0.35, 1.1, "edge"), spec(["craft"], "woodpile", 0.2, 1.7, "yard")],
                   "yards": [{"kind": "spoil", "n": 5, "mesh": "rock"}]},
    "kilns":      {"dress": [spec(["craft", "poor"], "woodpile", 0.6, 1.7, "yard"), spec(["craft", "poor", "military"], "g:region/ruins/campfire", 0.1, 1.3, "yard"), spec(["craft", "poor"], "g:region/mine/ore_pile_coal", 0.3, 1.5, "yard")],
                   "yards": [{"kind": "kilns", "n": 4}]},
    "forge_smoke": {"dress": [spec(["craft", "poor"], "anvil_stump", 0.2, 0.8, "edge"), spec(["craft", "poor"], "g:region/mine/ore_pile_iron", 0.2, 1.5, "yard")]},
    # --- merchant / crafts
    "stalls":     {"dress": [spec(["market", "inn", "admin"], "market_stall_red", 0.2, 2.7, "edge", face=True, solid=True), spec(["market", "inn"], "market_stall_green", 0.16, 2.7, "edge", face=True, solid=True),
                             spec(["market", "inn", "admin"], "produce_table", 0.3, 1.1, "edge", face=True), spec(["market", "inn", "craft"], "crate_stack", 0.4, 0.9), spec(["market", "inn", "admin"], "banner_pole", 0.55, 0.6, "edge", face=True)]},
    "guild":      {"dress": [spec(["market", "admin"], "banner_pole", 0.9, 0.6, "edge", face=True), spec(["market", "admin", "craft"], "g:notice_board", 0.2, 1.3, "edge", face=True, solid=True), spec(["market", "admin"], "signpost", 0.35, 0.9, "edge", face=True), spec(["market", "admin"], "street_lamp", 0.4, 0.6)]},
    "wagons":     {"dress": [spec(["market", "inn", "craft", "poor"], "covered_wagon", 0.16, 2.3, "yard", solid=True), spec(["market", "inn", "craft"], "cart", 0.26, 2.0, "yard", solid=True),
                             spec(["craft", "poor", "inn"], "hand_cart", 0.4, 1.1), spec(["craft", "poor"], "woodpile", 0.3, 1.7, "yard")], "yards": [{"kind": "wagon_park", "n": 4}]},
    "caravan":    {"dress": [spec(["market", "inn"], "g:region/road/caravan_wagon", 0.14, 4.4, "yard", solid=True), spec(["market", "inn"], "covered_wagon", 0.1, 2.3, "yard", solid=True),
                             spec(["inn", "market"], "hay", 0.3, 1.2, "yard"), spec(["market", "inn", "admin"], "banner_pole", 0.5, 0.6, "edge", face=True)],
                   "yards": [{"kind": "caravan_camp", "n": 1}, {"kind": "toll", "n": 1}]},
    "dyers":      {"dress": [spec(["craft", "market", "poor", "inn"], "d:drying_rack", 0.85, 1.5, "yard", face=True), spec(["craft", "poor", "market"], "d:laundry_line", 0.45, 2.4, "yard"),
                             spec(["craft", "market"], "barrel_cluster", 0.4, 1.0), spec(["market", "admin"], "banner_pole", 0.7, 0.6, "edge", face=True)]},
    "glass":      {"dress": [spec(["craft", "poor"], "g:region/ruins/campfire", 0.16, 1.3, "yard"), spec(["craft", "market", "admin"], "street_lamp", 0.55, 0.6), spec(["craft", "poor"], "crate_stack", 0.4, 0.9)],
                   "yards": [{"kind": "kilns", "n": 3}]},
    "tannery":    {"dress": [spec(["craft", "poor", "inn"], "d:drying_rack", 0.8, 1.5, "yard", face=True), spec(["craft", "poor"], "barrel", 0.6, 0.5), spec(["poor", "craft"], "d:laundry_line", 0.3, 2.4, "yard")]},
    # --- fortress / frontier
    "barracks":   {"dress": [spec(["military", "admin", "craft"], "weapon_rack", 0.35, 1.4, "edge", face=True, solid=True), spec(["military", "market"], "banner_pole", 0.7, 0.6, "edge", face=True),
                             spec(["military", "inn"], "g:region/road/checkpoint_barrier", 0.1, 2.2, "edge", face=True, solid=True), spec(["military", "craft"], "hay", 0.25, 1.2, "yard")]},
    "watch":      {"yards": [{"kind": "watch", "n": 3}], "dress": [spec(["military", "poor", "craft"], "weapon_rack", 0.2, 1.4, "edge", face=True, solid=True)]},
    "stables":    {"dress": [spec(["inn", "military", "craft"], "hay", 0.5, 1.2, "yard"), spec(["inn", "military"], "water_trough", 0.55, 1.3, "edge", face=True), spec(["inn", "military"], "g:horses/horse_cart", 0.1, 2.6, "yard", solid=True), spec(["inn", "military"], "fence", 0.55, 1.6, "edge", face=True)]},
    "ferry":      {"dress": [spec(["inn", "poor", "craft"], "g:rowboat", 0.18, 2.2, "yard", solid=True), spec(["inn", "craft", "poor"], "d:drying_rack", 0.25, 1.5, "yard"), spec(["military", "inn"], "barrel_cluster", 0.4, 1.0)], "yards": [{"kind": "waterfront", "n": 1}]},
    "hunters":    {"dress": [spec(["poor", "craft", "inn", "military"], "d:drying_rack", 0.6, 1.5, "yard", face=True), spec(["poor", "craft", "military"], "woodpile", 0.5, 1.7, "yard"), spec(["poor", "inn"], "g:region/ruins/campfire", 0.1, 1.3, "yard"), spec(["poor", "craft"], "g:region/ruins/bandit_tent", 0.1, 2.4, "yard")]},
    "smokehouse": {"dress": [spec(["craft", "poor", "inn"], "d:drying_rack", 0.9, 1.5, "yard", face=True), spec(["craft", "poor"], "woodpile", 0.5, 1.7, "yard"), spec(["craft", "poor"], "barrel_cluster", 0.4, 1.0)]},
    "ravens":     {"dress": [spec(["poor", "military", "craft"], "g:region/ruins/campfire", 0.1, 1.3, "yard"), spec(["poor", "craft"], "d:drying_rack", 0.4, 1.5, "yard")], "yards": [{"kind": "watch", "n": 1, "tall": True}]},
    # --- religious / scholarly
    "shrines":    {"dress": [spec(["admin", "market", "inn", "poor"], "g:region/road/wayshrine", 0.12, 1.3, "edge", face=True), spec(["admin", "market", "poor"], "flower_bed", 0.5, 1.3, "yard"), spec(["admin", "market"], "bench", 0.45, 1.0, "edge", face=True), spec(["admin", "market"], "banner_pole", 0.6, 0.6, "edge", face=True)]},
    "candles":    {"dress": [spec(["admin", "market", "inn", "poor", "craft"], "street_lamp", 0.6, 0.6), spec(["admin", "market"], "flower_planter", 0.5, 0.7, "edge", face=True), spec(["poor", "inn"], "basket_produce", 0.3, 0.5)]},
    "herbs":      {"dress": [spec(["poor", "craft", "inn", "admin"], "d:drying_rack", 0.5, 1.5, "yard", face=True), spec(["poor", "inn", "admin"], "flower_bed", 0.5, 1.3, "yard"), spec(["poor", "craft"], "basket_produce", 0.5, 0.5), spec(["admin", "poor"], "g:region/road/wayshrine", 0.08, 1.3, "edge", face=True)]},
    "academy":    {"dress": [spec(["admin", "market", "inn"], "bench", 0.55, 1.0, "edge", face=True), spec(["admin", "market"], "street_lamp", 0.7, 0.6), spec(["admin", "market", "craft"], "g:notice_board", 0.3, 1.3, "edge", face=True, solid=True), spec(["admin", "market"], "flower_planter", 0.5, 0.7, "edge", face=True)]},
    "lanterns":   {"dress": [spec(["admin", "market", "inn", "poor", "craft"], "street_lamp", 0.9, 0.6), spec(["market", "inn", "poor"], "lamp_post", 0.4, 0.5), spec(["inn", "poor", "craft"], "d:drying_rack", 0.3, 1.5, "yard")]},
    # --- criminal / shabby
    "alleys":     {"dress": [spec(["poor", "craft", "inn", "market"], "crate_stack", 0.7, 0.9), spec(["poor", "craft", "inn"], "barrel_cluster", 0.6, 1.0), spec(["poor", "inn", "craft"], "sack_pile", 0.5, 1.0), spec(["poor", "inn"], "g:region/ruins/campfire", 0.1, 1.3, "yard"), spec(["poor", "craft"], "g:region/ruins/bandit_tent", 0.08, 2.4, "yard")]},
    "smugglers":  {"dress": [spec(["poor", "craft", "inn"], "crate_stack", 0.6, 0.9), spec(["poor", "inn"], "g:rowboat", 0.08, 2.2, "yard", solid=True), spec(["poor", "craft"], "barrel_cluster", 0.5, 1.0), spec(["poor", "inn", "craft"], "g:region/ruins/bandit_tent", 0.1, 2.4, "yard")]},
    # --- boats / fishing
    "boats":      {"dress": [spec(["craft", "poor", "inn"], "g:rowboat", 0.3, 2.2, "yard", solid=True), spec(["craft", "poor", "inn"], "d:drying_rack", 0.6, 1.5, "yard", face=True), spec(["craft", "poor", "inn"], "woodpile", 0.3, 1.7, "yard"), spec(["craft", "inn", "poor"], "barrel_cluster", 0.4, 1.0)],
                   "yards": [{"kind": "waterfront", "n": 1}]},
    "salt":       {"dress": [spec(["craft", "poor", "market", "inn"], "sack_pile", 0.9, 1.0), spec(["craft", "market", "inn"], "crate_stack", 0.6, 0.9), spec(["craft", "poor", "inn"], "d:drying_rack", 0.6, 1.5, "yard", face=True), spec(["craft", "inn"], "g:rowboat", 0.12, 2.2, "yard", solid=True)],
                   "yards": [{"kind": "waterfront", "n": 1}, {"kind": "salt_pans", "n": 5}]},
    "reeds":      {"dress": [spec(["poor", "craft", "inn"], "basket_produce", 0.8, 0.5), spec(["poor", "craft", "inn"], "hay", 0.5, 1.2, "yard"), spec(["poor", "craft"], "d:drying_rack", 0.4, 1.5, "yard", face=True), spec(["poor", "inn"], "g:rowboat", 0.1, 2.2, "yard", solid=True)],
                   "yards": [{"kind": "waterfront", "n": 1}]},
}

# --- meshy_free pack pieces (Assets.BUILDINGS "mf_*" keys, docs/qa/ASSET_AUDIT.md section A "use the unused models"):
# extra dressing per kit, appended so every older spec (and its position in the list) stays as it was.
MF_EXTRA = {
    "haystacks":  [spec(["poor", "inn", "craft", "market"], "mf_hay_bale_yellow_large", 0.3, 1.0, "yard"), spec(["poor", "inn"], "mf_hay_bale_round", 0.3, 1.1, "yard")],
    "granary":    [spec(["poor", "craft"], "mf_shed_thatch_small", 0.05, 2.0, "yard", solid=True)],
    "pens":       [spec(["poor", "inn", "craft"], "mf_fence_rail_grass_a", 0.4, 1.5, "yard"), spec(["poor", "inn"], "mf_fence_rail_grass_b", 0.3, 1.5, "yard")],
    "dairy":      [spec(["poor", "inn"], "mf_hay_bale_lowpoly", 0.3, 1.0, "yard"), spec(["poor", "inn"], "mf_chicken_coop_fenced", 0.05, 1.6, "yard", solid=True)],
    "brewery":    [spec(["inn", "craft"], "mf_tavern_set_barrels_b", 0.2, 2.0, "yard"), spec(["inn", "market"], "mf_table_barrel_top", 0.2, 0.8, "edge", face=True)],
    "bees":       [spec(["market", "inn", "poor"], "mf_bouquet_wild", 0.6, 0.4), spec(["poor", "inn"], "mf_bush_raspberry", 0.3, 1.0, "yard")],
    "wool":       [spec(["poor", "craft"], "mf_fence_picket_low", 0.3, 1.5, "yard")],
    "fair_green": [spec(["market", "inn"], "mf_stall_open_roof", 0.12, 2.7, "edge", face=True, solid=True), spec(["market", "inn"], "mf_stall_potatoes", 0.1, 2.9, "edge", face=True, solid=True)],
    "mine":       [spec(["craft", "poor"], "mf_chest_orange_metal", 0.04, 0.8, "edge", face=True)],
    "quarry":     [spec(["craft", "poor"], "mf_wall_stone_railing", 0.3, 1.4, "edge", face=True)],
    "forge_smoke": [spec(["craft", "poor"], "mf_axe_long_handle", 0.2, 0.9, "edge")],
    "stalls":     [spec(["market", "inn", "admin"], "mf_stall_meat_shingle", 0.1, 2.7, "edge", face=True, solid=True), spec(["market"], "mf_shed_striped_awning", 0.06, 3.0, "edge", face=True, solid=True)],
    "guild":      [spec(["market", "admin"], "mf_chest_silver_lock", 0.06, 0.8, "edge", face=True)],
    "wagons":     [spec(["craft", "poor", "inn"], "mf_hay_bale_round", 0.2, 1.1, "yard")],
    "caravan":    [spec(["market", "inn"], "mf_chest_gold", 0.03, 0.8, "edge", face=True)],
    "dyers":      [spec(["craft", "poor"], "mf_fence_picket_tall", 0.2, 1.5, "yard")],
    "tannery":    [spec(["craft", "poor"], "mf_fence_picket_tall", 0.2, 1.5, "yard")],
    "barracks":   [spec(["military", "admin"], "mf_lamp_post_timber_cross", 0.3, 0.7), spec(["military"], "mf_chest_red_black", 0.05, 0.8, "edge", face=True)],
    "watch":      [spec(["military", "poor"], "mf_lamp_post_timber_cross", 0.25, 0.7)],
    "stables":    [spec(["inn", "military"], "mf_hay_bale_round", 0.3, 1.1, "yard"), spec(["inn", "military"], "mf_shed_plank_low", 0.04, 1.8, "yard", solid=True)],
    "ferry":      [spec(["poor", "craft"], "mf_fence_broken_rail", 0.2, 1.2, "yard")],
    "smugglers":  [spec(["poor", "craft"], "mf_chest_blue_iron", 0.05, 0.8, "edge", face=True)],
    "boats":      [spec(["craft", "poor"], "mf_fence_broken_rail", 0.2, 1.2, "yard")],
    "hunters":    [spec(["poor", "craft"], "mf_axe_long_handle", 0.35, 0.9, "edge")],
    "smokehouse": [spec(["craft", "poor"], "mf_shed_plank_low", 0.06, 1.8, "yard", solid=True)],
    "ravens":     [spec(["poor", "military"], "mf_lamp_post_timber_cross", 0.25, 0.7)],
    "shrines":    [spec(["admin", "market"], "mf_street_lantern_whimsical", 0.2, 0.6), spec(["admin", "market", "poor"], "mf_bouquet_wild", 0.4, 0.4)],
    "candles":    [spec(["admin", "market", "poor"], "mf_street_lantern_whimsical", 0.25, 0.6)],
    "herbs":      [spec(["poor", "inn", "admin"], "mf_bush_raspberry", 0.5, 1.0, "yard"), spec(["poor", "craft"], "mf_bouquet_wild", 0.5, 0.4), spec(["poor"], "mf_mushroom_glow_brown", 0.25, 0.6, "yard")],
    "academy":    [spec(["admin", "market"], "mf_street_lamp_twin_gold", 0.35, 0.8)],
    "lanterns":   [spec(["admin", "market", "inn"], "mf_street_lantern_gothic", 0.5, 0.7), spec(["market", "poor"], "mf_street_lantern_whimsical", 0.4, 0.6)],
    "reeds":      [spec(["poor", "craft"], "mf_fence_broken_rail", 0.2, 1.2, "yard")],
    "salt":       [spec(["craft", "poor"], "mf_fence_broken_rail", 0.15, 1.2, "yard")],
}
for _k, _v in MF_EXTRA.items():
    KITS[_k]["dress"] = KITS[_k].get("dress", []) + _v

# ------------------------------------------------------------------ archetypes
# activity groups -> multiplier on the micro_events catalogue groups (activity_groups below)
ARCH = {
    "royal":    {"realm": "merchant", "palette": "neutral", "roof": {"tall": 0.55, "shingle": 0.15, "slate": 0.15, "red": 0.15}, "wall": "stone", "layout": "royal", "tower": 1.0,
                 "stalls": 1.0, "lamps": 1.0, "guards": 1.0, "shabby": 0.0, "stone": 0.6, "banner": ["#B3202A", "#E6B93A"], "awning": ["#C2301F", "#F2E8CC"], "guard": "#B3202A",
                 "cloth": ["#B3202A", "#E6B93A", "#2F4E8E", "#F2E8CC"], "kits": [], "activity": {"noble": 1.4, "military": 1.2, "trade": 1.2}, "prop_mult": {}},
    "merchant": {"realm": "merchant", "palette": "cream_gold", "roof": {"tall": 0.4, "slate": 0.25, "red": 0.25, "shingle": 0.1}, "wall": "stone", "layout": "radial", "tower": 1.0,
                 "stalls": 1.8, "lamps": 1.2, "guards": 0.9, "shabby": 0.0, "stone": 0.55, "banner": ["#2F5FA8", "#E3B23C"], "awning": ["#2F5FA8", "#F2E8CC"], "guard": "#2F5FA8",
                 "cloth": ["#2F5FA8", "#E3B23C", "#8E1F2F", "#F2E8CC"], "kits": ["stalls", "guild"], "activity": {"trade": 1.9, "noble": 1.1, "farm": 0.6},
                 "prop_mult": {"market_stall_red": 1.4, "market_stall_green": 1.4, "banner_pole": 1.6}},
    "craft":    {"realm": "merchant", "palette": "terracotta", "roof": {"red": 0.4, "shingle": 0.3, "tall": 0.2, "slate": 0.1}, "wall": "low", "layout": "bank", "tower": 0.0,
                 "stalls": 1.0, "lamps": 0.9, "guards": 0.8, "shabby": 0.1, "stone": 0.4, "banner": ["#A02A24", "#2F4F8F"], "awning": ["#A02A24", "#EFE2C0"], "guard": "#7A4A2A",
                 "cloth": ["#A02A24", "#2F4F8F", "#D9A92E", "#6B8E3A"], "kits": [], "activity": {"craft": 1.7, "trade": 1.2, "farm": 0.7}, "prop_mult": {"flower_planter": 0.5}},
    "farming":  {"realm": "farming", "palette": "honey", "roof": {"thatch": 0.7, "shingle": 0.3}, "wall": "none", "layout": "loose", "tower": 0.0,
                 "stalls": 0.6, "lamps": 0.5, "guards": 0.6, "shabby": 0.15, "stone": 0.2, "banner": ["#6B8E3A", "#EAD9A0"], "awning": ["#B8872E", "#EFE2B8"], "guard": "#8A7A4A",
                 "cloth": ["#6B4F36", "#D9C8A0", "#5E6B3A", "#A23B24"], "kits": ["haystacks"], "activity": {"farm": 2.2, "trade": 0.7, "military": 0.5, "noble": 0.4},
                 "prop_mult": {"flower_planter": 0.5, "street_lamp": 0.4, "market_stall_red": 0.6, "banner_pole": 0.5, "hay": 1.8}},
    "pastoral": {"realm": "farming", "palette": "moss", "roof": {"thatch": 0.5, "shingle": 0.35, "slate": 0.15}, "wall": "none", "layout": "loose", "tower": 0.0,
                 "stalls": 0.8, "lamps": 0.5, "guards": 0.6, "shabby": 0.1, "stone": 0.15, "banner": ["#4F8F4A", "#F0F0E0"], "awning": ["#4F8F4A", "#F0ECD8"], "guard": "#6E8A4A",
                 "cloth": ["#5E7A3A", "#F0ECD8", "#8A6B3C", "#4C7A9C"], "kits": ["pens"], "activity": {"farm": 2.0, "trade": 0.9, "military": 0.5, "noble": 0.4},
                 "prop_mult": {"street_lamp": 0.4, "banner_pole": 0.6, "fence": 1.5}},
    "mining":   {"realm": "mining", "palette": "iron", "roof": {"shingle": 0.5, "slate": 0.4, "red": 0.1}, "wall": "none", "layout": "strung", "tower": 0.0,
                 "stalls": 0.6, "lamps": 0.7, "guards": 0.8, "shabby": 0.35, "stone": 0.7, "banner": ["#6A6F78", "#D07A2A"], "awning": ["#6A6F78", "#D8CFC0"], "guard": "#5A5F68",
                 "cloth": ["#4A4F58", "#8A5A32", "#B0A89A", "#D07A2A"], "kits": ["mine"], "activity": {"mining": 2.2, "craft": 1.4, "farm": 0.5, "noble": 0.3},
                 "prop_mult": {"flower_planter": 0.2, "flower_bed": 0.2, "banner_pole": 0.4, "market_stall_green": 0.5}},
    "fortress": {"realm": "fortress", "palette": "stone_grey", "roof": {"slate": 0.45, "shingle": 0.35, "red": 0.2}, "wall": "stone", "layout": "terraced", "tower": 1.7,
                 "stalls": 0.7, "lamps": 1.0, "guards": 2.0, "shabby": 0.1, "stone": 0.85, "banner": ["#9B1F2A", "#1E1E24"], "awning": ["#9B1F2A", "#CFC8B8"], "guard": "#9B1F2A",
                 "cloth": ["#9B1F2A", "#1E1E24", "#5A5F66", "#C9C2B0"], "kits": ["barracks"], "activity": {"military": 2.4, "trade": 0.7, "farm": 0.5, "faith": 0.8, "noble": 0.8},
                 "prop_mult": {"weapon_rack": 2.0, "banner_pole": 1.8, "flower_planter": 0.3, "g:region/road/checkpoint_barrier": 2.0}},
    "hunting":  {"realm": "fortress", "palette": "umber", "roof": {"shingle": 0.6, "thatch": 0.25, "slate": 0.15}, "wall": "palisade", "layout": "hold", "tower": 0.0,
                 "stalls": 0.5, "lamps": 0.4, "guards": 1.3, "shabby": 0.3, "stone": 0.1, "banner": ["#8A5A2B", "#D9873A"], "awning": ["#8A5A2B", "#D8C9A8"], "guard": "#7A5A32",
                 "cloth": ["#6B4F36", "#8A5A2B", "#3F5A3A", "#C9B28A"], "kits": ["hunters"], "activity": {"hunt": 2.0, "military": 1.3, "farm": 0.8, "noble": 0.2, "trade": 0.6},
                 "prop_mult": {"flower_planter": 0.1, "flower_bed": 0.1, "banner_pole": 0.5}},
    "religious": {"realm": "religious", "palette": "whitewash", "roof": {"slate": 0.4, "red": 0.3, "tall": 0.2, "thatch": 0.1}, "wall": "low", "layout": "close", "tower": 0.0,
                 "stalls": 0.8, "lamps": 1.3, "guards": 0.6, "shabby": 0.0, "stone": 0.6, "banner": ["#F2EFE6", "#C9A23A"], "awning": ["#F2EFE6", "#C9A23A"], "guard": "#E8E2D0",
                 "cloth": ["#F2EFE6", "#C9A23A", "#7A2B3A", "#8C8A86"], "kits": ["shrines"], "activity": {"faith": 2.4, "trade": 0.8, "military": 0.4, "noble": 0.8},
                 "prop_mult": {"flower_planter": 1.6, "flower_bed": 1.6, "bench": 1.5}},
    "scholarly": {"realm": "scholarly", "palette": "slate_cool", "roof": {"slate": 0.55, "red": 0.2, "tall": 0.15, "shingle": 0.1}, "wall": "low", "layout": "campus", "tower": 0.0,
                 "stalls": 0.8, "lamps": 1.8, "guards": 0.7, "shabby": 0.0, "stone": 0.5, "banner": ["#3C4FA0", "#E8C95A"], "awning": ["#3C4FA0", "#EDE6D0"], "guard": "#3C4FA0",
                 "cloth": ["#3C4FA0", "#E8C95A", "#6A4C93", "#E6E1D0"], "kits": ["academy"], "activity": {"scholar": 2.4, "faith": 1.0, "trade": 0.9, "military": 0.4, "noble": 1.0},
                 "prop_mult": {"street_lamp": 1.8, "bench": 1.8, "g:notice_board": 1.6}},
    "criminal": {"realm": "criminal", "palette": "umber", "roof": {"shingle": 0.55, "thatch": 0.3, "slate": 0.15}, "wall": "none", "layout": "lanes", "tower": 0.0,
                 "stalls": 0.5, "lamps": 0.3, "guards": 0.35, "shabby": 0.8, "stone": 0.2, "banner": ["#3A2F3F", "#8A3A5A"], "awning": ["#3A2F3F", "#B8A890"], "guard": "#3A2F3F",
                 "cloth": ["#3A2F3F", "#5A4A38", "#8A3A5A", "#7A7266"], "kits": ["alleys"], "activity": {"crime": 2.4, "trade": 0.9, "military": 0.3, "noble": 0.2, "faith": 0.6},
                 "prop_mult": {"flower_planter": 0.05, "flower_bed": 0.05, "street_lamp": 0.25, "banner_pole": 0.15, "bench": 0.5}},
    "fishing":  {"realm": "merchant", "palette": "teal", "roof": {"shingle": 0.4, "slate": 0.3, "thatch": 0.3}, "wall": "low", "layout": "bank", "tower": 0.0,
                 "stalls": 0.9, "lamps": 0.9, "guards": 0.7, "shabby": 0.2, "stone": 0.3, "banner": ["#2D7C8C", "#EFE8D2"], "awning": ["#2D7C8C", "#EFE8D2"], "guard": "#2D5F7A",
                 "cloth": ["#2D5F7A", "#EFE8D2", "#C06A3A", "#4F8F7A"], "kits": ["boats"], "activity": {"water": 2.2, "trade": 1.1, "farm": 0.6, "noble": 0.3},
                 "prop_mult": {"flower_planter": 0.5, "g:rowboat": 1.5}},
}

# ------------------------------------------------------------------ towns (WorldGen NAMES order = settlement id)
# Each town: arch (+ optional realm identity override), culture + influence, palette/roof/wall/layout/kit overrides, colours.
T = {}
def town(name, arch, **kw):
    T[name] = dict(arch=arch, **kw)

town("Ashford", "farming", flavour="hearth and stone", culture="caldric", palette="honey", roof={"thatch": 0.8, "shingle": 0.2}, wall="runestones", layout="loose",
     banner=["#6B8E3A", "#EAD9A0"], awning=["#B8872E", "#EFE2B8"], guard="#8A7A4A", kits=["great_oak"], terrain=["hearth"], hint=[])
town("Kingsreach", "royal", flavour="crown and court", culture="caldric", kits=[], terrain=["capital"])
town("Millbrook", "farming", flavour="mill and bakehouse", culture="caldric", palette="sand", roof={"thatch": 0.55, "shingle": 0.25, "slate": 0.2}, layout="loose",
     banner=["#D9A92E", "#7A4A2A"], awning=["#D9A92E", "#F3E9C8"], guard="#9A7A3A", kits=["mills", "granary"], hint=["stream"])
town("Stonehollow", "mining", flavour="quarry and masons", culture="caldric", palette="stone_grey", roof={"slate": 0.55, "shingle": 0.35, "red": 0.1}, layout="strung",
     banner=["#5E6B7C", "#C9C2B0"], awning=["#5E6B7C", "#D8D2C4"], guard="#4E5C6E", kits=["quarry"])
town("Eastmere", "pastoral", flavour="dairy and cheese", culture="caldric", palette="whitewash", roof={"thatch": 0.45, "slate": 0.3, "shingle": 0.25}, layout="loose",
     banner=["#4C8CC0", "#F4F1E4"], awning=["#4C8CC0", "#F4F1E4"], guard="#5E86A8", kits=["dairy"], hint=["mere"])
town("Redwater", "craft", flavour="dyers and cloth", culture="caldric", palette="rose", roof={"red": 0.5, "shingle": 0.2, "tall": 0.3}, wall="low", layout="bank",
     banner=["#B02A2A", "#2F4F9F"], awning=["#B02A2A", "#2F4F9F"], guard="#8A2A3A", kits=["dyers", "stalls"], hint=["river"])
town("Thornfield", "farming", flavour="barley and brewery", culture="caldric", palette="ochre", roof={"thatch": 0.35, "shingle": 0.35, "tall": 0.3}, wall="hedge", layout="green",
     banner=["#C9A02E", "#3F6A33"], awning=["#C9A02E", "#3F6A33"], guard="#7A6A2E", kits=["brewery", "haystacks"])
town("Greywatch", "fortress", flavour="spear hall and militia", culture="caldric", palette="stone_grey", roof={"slate": 0.55, "shingle": 0.35, "red": 0.1}, wall="palisade", layout="hold",
     banner=["#7E1F26", "#B8B8B8"], awning=["#7E1F26", "#C8C8C0"], guard="#7E1F26", kits=["barracks", "watch"])
town("Oakvale", "farming", flavour="fields and the great oak", culture="caldric", palette="moss", roof={"thatch": 0.65, "shingle": 0.35}, wall="hedge", layout="loose",
     banner=["#3F6A33", "#8A5A2B"], awning=["#3F6A33", "#EAE0B8"], guard="#4F6A3A", kits=["great_oak", "big_fields"])
town("Highcliff", "fortress", flavour="armoury and stables", culture="caldric", palette="slate_cool", roof={"slate": 0.55, "tall": 0.25, "red": 0.2}, wall="stone", layout="terraced", tower=2.2,
     banner=["#B3202A", "#14141A"], awning=["#B3202A", "#D8D0C0"], guard="#A01E2A", kits=["stables", "watch"], terrain=["hill"])
town("Brackenmoor", "hunting", flavour="hunters and pelts", culture="caldric", palette="umber", roof={"shingle": 0.65, "thatch": 0.25, "slate": 0.1}, wall="palisade", layout="hold",
     banner=["#8A5A2B", "#D9873A"], awning=["#8A5A2B", "#D8C9A8"], guard="#6A4A2A", kits=["hunters"], terrain=["moor"])
town("Westfen", "religious", flavour="herbwives and boardwalk", culture="caldric", influence="veyl", palette="moss", roof={"thatch": 0.55, "shingle": 0.25, "slate": 0.2}, wall="hedge", layout="close",
     banner=["#7FA08A", "#B79BD0"], awning=["#7FA08A", "#EFE9D8"], guard="#6A8A72", kits=["herbs", "reeds"], hint=["marsh"])
town("Ironmarch", "merchant", flavour="guild town on the ford", culture="caldric", palette="cream_gold", roof={"tall": 0.45, "slate": 0.3, "red": 0.25}, wall="stone", layout="radial",
     banner=["#E3B23C", "#2F5FA8"], awning=["#E3B23C", "#2F5FA8"], guard="#C9992E", kits=["guild", "stalls"], hint=["river"])
town("Saltwick", "fishing", flavour="salt pans and fisheries", culture="caldric", influence="seirune", palette="teal", roof={"red": 0.3, "slate": 0.3, "shingle": 0.4}, wall="low", layout="bank",
     banner=["#E8F2F0", "#2D7C8C"], awning=["#E8F2F0", "#2D7C8C"], guard="#2D5F7A", kits=["salt"], hint=["coast"])
town("Cindermoor", "mining", flavour="charcoal burners", culture="caldric", palette="ash", roof={"shingle": 0.7, "thatch": 0.2, "slate": 0.1}, layout="strung",
     banner=["#3A3A3E", "#D8742A"], awning=["#3A3A3E", "#C8BCA8"], guard="#3A3A3E", kits=["kilns"], terrain=["moor"])
town("Dunhallow", "craft", flavour="wheelwrights and carters", culture="caldric", palette="ochre", roof={"shingle": 0.5, "thatch": 0.3, "tall": 0.2}, wall="none", layout="strung",
     banner=["#B97A2E", "#5A3A1E"], awning=["#B97A2E", "#EAD8B0"], guard="#7A5A2A", kits=["wagons"])
town("Wolfsend", "fortress", flavour="wolf watch", culture="caldric", influence="urrokai", palette="stone_grey", roof={"shingle": 0.5, "thatch": 0.25, "slate": 0.25}, wall="palisade", layout="hold",
     banner=["#8A8E96", "#F0F0F0"], awning=["#8A8E96", "#E8E8E0"], guard="#6E737C", kits=["watch", "hunters"], terrain=["hill"])
town("Harrowgate", "merchant", flavour="the southern gate", culture="caldric", influence="solenne", palette="whitewash", roof={"red": 0.4, "slate": 0.3, "tall": 0.3}, wall="none", layout="radial",
     banner=["#6A2E8E", "#E6C04A"], awning=["#6A2E8E", "#F2E8C8"], guard="#6A2E8E", kits=["caravan", "stalls"], terrain=["crossroads"])
town("Emberfall", "scholarly", flavour="glass kilns and the fallen star", culture="caldric", palette="plum", roof={"slate": 0.5, "red": 0.3, "tall": 0.2}, wall="none", layout="campus",
     banner=["#E2742A", "#6A3FA0"], awning=["#E2742A", "#6A3FA0"], guard="#7A3FA0", kits=["glass", "lanterns"], terrain=["crater"])
town("Ravenscar", "criminal", flavour="trappers below the pass", culture="caldric", palette="ash", roof={"shingle": 0.7, "thatch": 0.2, "slate": 0.1}, wall="palisade", layout="lanes",
     banner=["#18181E", "#7A4AA0"], awning=["#18181E", "#B8A8C0"], guard="#18181E", kits=["smugglers", "ravens"], terrain=["pass"])
town("Longmeadow", "pastoral", flavour="wool and fairs", culture="caldric", palette="moss", roof={"thatch": 0.4, "shingle": 0.3, "slate": 0.3}, wall="none", layout="green",
     banner=["#5A9A4A", "#FFFFFF"], awning=["#5A9A4A", "#FFFFFF"], guard="#4F8A4A", kits=["fair_green", "wool", "pens"])
town("Blackwater", "fortress", flavour="ferry and garrison", culture="caldric", palette="slate_cool", roof={"slate": 0.5, "shingle": 0.35, "red": 0.15}, wall="palisade", layout="bank",
     banner=["#1F4F5A", "#B0B8BC"], awning=["#1F4F5A", "#C8CCC8"], guard="#1F4F5A", kits=["ferry", "watch"], hint=["river"])
town("Frostmere", "hunting", flavour="smokehouses and trappers", culture="caldric", palette="frost", roof={"shingle": 0.55, "slate": 0.3, "thatch": 0.15}, wall="none", layout="hold",
     banner=["#8FB8E0", "#F4F8FF"], awning=["#8FB8E0", "#F4F8FF"], guard="#6A8FB8", kits=["smokehouse"], hint=["mere"], terrain=["frozen"])
town("Amberley", "religious", flavour="honey and beeswax", culture="caldric", palette="amber", roof={"thatch": 0.5, "red": 0.3, "shingle": 0.2}, wall="hedge", layout="close",
     banner=["#E8A22A", "#FFF3D2"], awning=["#E8A22A", "#FFF3D2"], guard="#C9882A", kits=["candles", "bees"])
town("Skarholm", "mining", flavour="ore and coal", culture="caldric", influence="durrow", palette="iron", roof={"slate": 0.5, "shingle": 0.4, "red": 0.1}, layout="strung",
     banner=["#7A7F88", "#B5532A"], awning=["#7A7F88", "#CDBFAE"], guard="#5A5F68", kits=["forge_smoke"], terrain=["hill"])
town("Thistledown", "pastoral", flavour="sheep and spinners", culture="caldric", palette="plum", roof={"thatch": 0.6, "shingle": 0.2, "slate": 0.2}, wall="none", layout="loose",
     banner=["#8E5AA8", "#5A8A4A"], awning=["#8E5AA8", "#EDE6D8"], guard="#7A5A8A", kits=["wool"])
town("Marrowick", "criminal", flavour="hides and tanners", culture="caldric", palette="umber", roof={"shingle": 0.6, "thatch": 0.25, "red": 0.15}, wall="none", layout="lanes",
     banner=["#5A4630", "#7A8A3A"], awning=["#5A4630", "#B8A888"], guard="#5A4630", kits=["tannery"])
town("Coldharbor", "fishing", flavour="boatwrights", culture="caldric", palette="slate_cool", roof={"shingle": 0.5, "slate": 0.4, "thatch": 0.1}, wall="low", layout="bank",
     banner=["#1F3A6A", "#C9B28A"], awning=["#1F3A6A", "#E0D2B0"], guard="#1F3A6A", kits=["boats"], hint=["river"])
town("Hollowmere", "fishing", flavour="reeds and baskets", culture="caldric", influence="veyl", palette="moss", roof={"thatch": 0.7, "shingle": 0.3}, wall="hedge", layout="loose",
     banner=["#7A9A4A", "#3F8A8A"], awning=["#7A9A4A", "#E8E4C8"], guard="#5F8A4A", kits=["reeds"], hint=["mere"])
town("Duskwater", "scholarly", flavour="lanterns and night fishers", culture="caldric", palette="slate_cool", roof={"slate": 0.6, "shingle": 0.25, "red": 0.15}, wall="low", layout="bank",
     banner=["#3A3A8A", "#F0C85A"], awning=["#3A3A8A", "#F0C85A"], guard="#3A3A7A", kits=["lanterns"], hint=["mere"])

ACTIVITY_GROUPS = {
    "farm":    ["hay_wagon", "farmers_return_dusk", "farmers_out_dawn", "flock_through", "cattle_home", "grain_porters", "dog_chasing_chickens", "milk_pail", "baker_delivery"],
    "military": ["patrol_returning", "soldiers_marching", "training_drills", "sparring_pair", "guard_shift_change", "guard_questions_traveller", "recruiters_calling", "night_watch_rounds", "wounded_return"],
    "trade":   ["cart_through", "delivery_to_shops", "caravan_arrival", "merchant_argument", "market_haggling", "peddler", "market_opening", "market_closing", "crate_haul", "tax_collector", "courier_runs"],
    "faith":   ["pilgrims", "street_sermon", "monk_alms", "mourners_at_temple", "funeral_procession", "wedding_procession", "healer_rounds"],
    "scholar": ["teacher_lesson", "courier_runs", "town_crier", "lamp_lighter", "apprentice_errand", "evening_sweepers"],
    "crime":   ["thief_running", "pickpocket", "drunk_ejected", "tavern_brawl", "beggar", "curfew_straggler", "refugee_cart"],
    "mining":  ["wood_cart", "crate_haul", "water_carriers", "wounded_return", "broken_cart"],
    "craft":   ["wood_cart", "crate_haul", "apprentice_errand", "laundry_day", "water_carriers", "delivery_to_shops"],
    "hunt":    ["hunters_return", "patrol_returning", "night_watch_rounds", "wood_cart"],
    "water":   ["water_carriers", "crate_haul", "laundry_day", "gossips_at_well", "delivery_to_shops", "hunters_return"],
    "noble":   ["noble_carriage", "travelling_adventurers", "tax_collector", "festival_dancers"],
}

def build():
    data = {
        "version": 1,
        "_doc": "Per-settlement visual identity (generated by tools/town_identity/gen_town_identity.py). Read scripts/world/town_identity.gd.",
        "palettes": PALETTES, "kits": KITS, "archetypes": ARCH, "activity_groups": ACTIVITY_GROUPS, "towns": T,
    }
    return data

if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(build(), f, indent=1, sort_keys=False)
    print("wrote", OUT, len(T), "towns")
