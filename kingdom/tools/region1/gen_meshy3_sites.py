#!/usr/bin/env python3
"""Writes data/region1/world/meshy3_sites.json: the Meshy batch 3 ("dl3:") yards (docs/art/meshy_dl3/README.md "Placement").
Same spec as fill_sites.json (read by scripts/world/region1_fill.gd). Heights are the models' natural heights (scale 1.0), from
tools_qa/meshy3/dims.gd. Run: python3 tools/region1/gen_meshy3_sites.py   (JSON is the source of truth, this is how it was laid out)."""
import json, os

H = {  # natural height in metres
    "buildings/cottage_blue_roof": 5.31, "buildings/cottage_orange_roof": 8.03, "buildings/cottage_slate_timber": 5.84,
    "buildings/cottage_thatch_timber": 8.0, "buildings/house_gable_porch_a": 7.42, "buildings/house_gable_porch_b": 7.43,
    "buildings/house_orange_thatch": 6.98, "buildings/house_straw_thatch": 6.99, "buildings/house_tudor_corner": 6.94,
    "buildings/house_tudor_stone_base": 7.4, "buildings/tavern_dark_roof": 8.02, "buildings/tavern_red_roof": 8.02,
    "camp/tent_shop_canopy": 2.72, "camp/tent_shop_conical": 4.02, "carts/wagon_canvas_a": 3.37, "carts/wagon_canvas_lanterns": 3.86,
    "carts/wagon_shields_covered": 2.65, "castle/castle_small_towers": 9.38, "castle/fortress_grey_blue": 15.06,
    "creatures/horse_saddled_brown": 2.19, "furniture/bench_lantern_posts": 2.2, "furniture/table_bench_set": 1.07,
    "furniture/table_long_wood": 0.66, "magic/rack_elixirs": 0.62, "market/stall_rug_wood": 2.65, "props/chest_iron_banded": 0.66,
    "props/firewood_stack_oven": 1.04, "props/keg_big": 1.1, "props/shield_round_wood": 0.9, "props/swords_scabbards_trio": 1.09,
}


def P(model, x, z, yaw=0, solid=0, lift=0):
    return ["dl3:%s@%.2f" % (model, H[model]), x, z, yaw, solid, lift]


def FENCE(x0, x1, z, step=2.0):
    out, x = [], x0
    while x <= x1 + 1e-6:
        out.append(["free:fences/fence_picket_low@0.76", round(x, 2), z, 0, 0, 0])
        x += step
    return out


LAMP = [4, 1.0, 0.5, [1.0, 0.55, 0.25], 8, True]


def site(id_, name, town, center, outside, clear, parts, lights, hooks, face="center"):
    sr = {"center": center, "a": [-3.14159, 3.14159], "r": clear, "slope": 0.22, "prefer_high": 0.0, "d_pref": 0, "face": face, "gate": False}
    if outside is not None:
        sr["outside"] = outside
    return {"id": id_, "name": name, "kind": "roadside", "clear": clear, "flatten": True, "search": sr, "parts": parts,
            "lights": lights, "town": town, "hooks": hooks}


SITES = [
    # --- Thornfield (vertical slice) -----------------------------------------------------------------------------------
    site("m3_thornfield_lane", "Thornfield Millers' Lane", "Thornfield", "settlement:Thornfield", [6, 80], 22, [
        P("buildings/cottage_thatch_timber", -8, -4, 8, 1), P("buildings/house_gable_porch_a", 6.5, -5, -6, 1),
        P("buildings/cottage_slate_timber", -2, -17, 4, 1)] + FENCE(-11, 11, 5.5) + [
        P("props/firewood_stack_oven", 12.5, -14, -20), P("props/keg_big", -12.5, 3.2, 0), P("props/keg_big", -11.2, 3.8, 40),
        P("furniture/bench_lantern_posts", 0.5, 3.4, 180)],
        [[0.5, 2.0, 3.4, [1.0, 0.7, 0.4], 8, True]], "Meshy3: three town cottages, kegs, bench lamp."),
    site("m3_thornfield_carters", "Thornfield Carters' Yard", "Thornfield", "settlement:Thornfield", [40, 130], 22, [
        P("carts/wagon_canvas_lanterns", -7, -4, 20, 1), P("carts/wagon_canvas_a", 7, -7, -25, 1), P("market/stall_rug_wood", -9, 8, 160, 1),
        P("camp/tent_shop_canopy", 9, 8, 200, 1), P("furniture/table_long_wood", 1.5, 9.5, 0), P("magic/rack_elixirs", 1.5, 9.5, 0, 0, 0.66),
        P("furniture/table_bench_set", -1.5, 1.5, 30), P("creatures/horse_saddled_brown", -2.5, -8, 70),
        P("creatures/horse_saddled_brown", 1.2, -9.4, 100), P("props/keg_big", 12, 0, 0), P("props/keg_big", 13.1, 0.7, 30),
        P("props/chest_iron_banded", -12.5, -2.5, 80)],
        [[-7, 2.6, -4, [1.0, 0.7, 0.4], 7, True], [0, 1.4, 4, [1.0, 0.6, 0.3], 7, True]], "Meshy3: caravan wagons, stalls, horses."),
    site("m3_thornfield_wayhouse", "The Hanged Thorn Wayhouse", "Thornfield", "settlement:Thornfield", [70, 170], 24, [
        P("buildings/tavern_dark_roof", 0, -6, 0, 1), P("furniture/table_bench_set", -7, 6, 20), P("furniture/table_bench_set", 7, 6.5, -20),
        P("furniture/bench_lantern_posts", 0, 8.5, 180), P("props/keg_big", 10.5, -9, 0), P("props/keg_big", 11.7, -8.2, 25),
        P("props/keg_big", 10.9, -10.4, 70), P("creatures/horse_saddled_brown", -10.5, 1, 100), P("props/firewood_stack_oven", -11, -12, 90)],
        [[-4, 2.2, -1, [1.0, 0.65, 0.35], 9, True], [4.5, 2.2, -1, [1.0, 0.65, 0.35], 9, True]], "Meshy3: dark-roof roadside inn."),
    # --- other sparse Region 1 towns -------------------------------------------------------------------------------------
    site("m3_ashford_lane", "Ashford Lane Houses", "Ashford", "settlement:Ashford", [0, 70], 20, [
        P("buildings/house_tudor_stone_base", -9, -4, 6, 1), P("buildings/house_gable_porch_b", 8.5, -5, -8, 1)] + FENCE(-12, 12, 6.0) + [
        P("furniture/bench_lantern_posts", 0, 4.4, 180)], [[0, 2.0, 4.4, [1.0, 0.7, 0.4], 8, True]], "Meshy3: two houses for Ashford."),
    site("m3_redwater_dyers", "Redwater Dyers' Cottages", "Redwater", "settlement:Redwater", [0, 70], 20, [
        P("buildings/cottage_blue_roof", -8, -4, 5, 1), P("buildings/cottage_orange_roof", 5, -5, -6, 1),
        P("market/stall_rug_wood", -3, 8.5, 170, 1), P("props/keg_big", 10.5, 3, 0), P("props/keg_big", 11.6, 3.8, 30),
        P("furniture/table_long_wood", 8, 9, 0)] + FENCE(-12, -6, 5.2), [[-3, 2.4, 7, [1.0, 0.65, 0.35], 7, True]], "Meshy3: dyers' cottages and a cloth stall."),
    site("m3_highcliff_stable", "Highcliff Stable Yard", "Highcliff", "settlement:Highcliff", [20, 100], 22, [
        P("creatures/horse_saddled_brown", -6, 2, 60), P("creatures/horse_saddled_brown", -3.2, 5, 110), P("creatures/horse_saddled_brown", 0.6, 2.4, 80),
        P("carts/wagon_shields_covered", 7, -6, -30, 1), P("props/swords_scabbards_trio", -9.5, -6, 0), P("props/shield_round_wood", -7.5, -6.5, 0),
        P("props/shield_round_wood", -5.8, -6.4, 0), P("camp/tent_shop_conical", -2, -8, 20, 1), P("props/keg_big", 11, 2, 0),
        P("furniture/table_long_wood", 9, 8, 0)] + FENCE(-10, 2, 8.5), [[-6, 1.6, -6, [1.0, 0.65, 0.35], 7, True]], "Meshy3: the horses of 'Steel and horses'."),
    site("m3_greywatch_spearhall", "Greywatch Spear Hall", "Greywatch", "settlement:Greywatch", [20, 110], 30, [
        P("castle/fortress_grey_blue", 0, -7, 0, 1), P("props/swords_scabbards_trio", -6, 12, 0), P("props/swords_scabbards_trio", 6, 12, 0),
        P("props/shield_round_wood", -4, 12.5, 0), P("props/shield_round_wood", 4, 12.5, 0), P("camp/tent_shop_conical", -13, 7, 40, 1),
        P("camp/tent_shop_conical", 13, 7, -40, 1)], [[-6, 2.4, 13, [1.0, 0.72, 0.4], 9, True], [6, 2.4, 13, [1.0, 0.72, 0.4], 9, True]],
        "Meshy3: the Spear Hall keep (plan: Greywatch stronghold)."),
    site("m3_blackwater_gate", "Blackwater Garrison Gate", "Blackwater", "settlement:Blackwater", [20, 100], 26, [
        P("castle/castle_small_towers", 0, -5, 0, 1), P("carts/wagon_shields_covered", -11, 9, 40, 1), P("camp/tent_shop_canopy", 11, 9, -30, 1),
        P("props/keg_big", 6, 9, 0), P("props/keg_big", 7.1, 9.8, 30)], [[-3, 2.2, 8, [1.0, 0.72, 0.4], 9, True], [3, 2.2, 8, [1.0, 0.72, 0.4], 9, True]],
        "Meshy3: ferry garrison gatehouse."),
    site("m3_marrowick_row", "Marrowick Tanners' Row", "Marrowick", "settlement:Marrowick", [0, 70], 20, [
        P("buildings/house_tudor_corner", -8, -4, 4, 1), P("buildings/house_straw_thatch", 8, -5, -8, 1),
        P("props/firewood_stack_oven", 0, 6, 0)] + FENCE(-13, -4, 7.5), [[0, 1.6, 6.8, [1.0, 0.6, 0.3], 7, True]], "Meshy3: tanners' houses."),
    site("m3_amberley_hives", "Amberley Honey Cottages", "Amberley", "settlement:Amberley", [0, 70], 20, [
        P("buildings/house_orange_thatch", -7, -4, 6, 1), P("buildings/house_straw_thatch", 6, -5, -10, 1),
        P("props/keg_big", 11, 3, 0), P("furniture/table_long_wood", 0, 7, 0)] + FENCE(-12, 12, 9.0), [], "Meshy3: honey cottages."),
    site("m3_longmeadow_fair", "Longmeadow Fair Green", "Longmeadow", "settlement:Longmeadow", [10, 90], 24, [
        P("market/stall_rug_wood", -9, -4, 20, 1), P("market/stall_rug_wood", 0, -7, 0, 1), P("market/stall_rug_wood", 9, -4, -20, 1),
        P("camp/tent_shop_canopy", -12, 7, 50, 1), P("camp/tent_shop_conical", 12, 7, -40, 1), P("carts/wagon_canvas_a", 0, 9, 90, 1),
        P("furniture/table_bench_set", -5, 3, 0), P("furniture/table_bench_set", 5, 3, 0), P("props/keg_big", -2, 0, 0),
        P("buildings/tavern_red_roof", 0, -18, 0, 1)],
        [[0, 2.0, -3, [1.0, 0.7, 0.4], 9, True]], "Meshy3: autumn fair stalls and tents."),
]

if __name__ == "__main__":
    out = {"version": 1, "_doc": "Meshy batch 3 yards (scripts/world/region1_fill.gd, tools/region1/gen_meshy3_sites.py): roadside clusters of 'dl3:' models "
           "(assets/incoming/meshy_dl3) beside sparse Region 1 towns, Thornfield first. Same spec as fill_sites.json. A/B: --meshy3off.",
           "sites": SITES}
    p = os.path.join(os.path.dirname(__file__), "..", "..", "data", "region1", "world", "meshy3_sites.json")
    json.dump(out, open(p, "w"), indent=1)
    print("wrote", os.path.normpath(p), len(SITES), "sites", sum(len(s["parts"]) for s in SITES), "parts")
