"""W4 landmark/POI kits -> kingdom/data/region1/world/w4_sites.json (the JSON is the source of truth for the game; this script writes it).
   py -I kingdom/tools/region1/gen_w4_sites.py
Every part is an EXISTING asset ("free:" meshy_free pack, "r1:" region 1 kits, "nature:" / "farm/" / "road/" / "props/" generated kits).
Part = [asset, x, z, yaw_deg, collide, y_offset] in the site frame (site yaw 0 = north up, +z = south).
Site keys: id, name, kind, clear, flatten, at [x, z], snap (search radius for the nearest good ground), fixed (exact spot, no free-ground test),
           slope (max ground slope for the search), bank (stand on the nearest dry bank), covers (inventory ids this site gives a body to),
           x (RegionDressing extras: label), lights, milestones (road posts along the road nearest to `near`).
"""
import json, math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "region1", "world", "w4_sites.json")
sites = []


def face(x, z):
    return round(math.degrees(math.atan2(-x, -z)), 1)


def label(text, sub, h=5.2):
    return {"label": {"text": text, "sub": sub, "at": [0, h], "h": 2.4}}


# --- named forests: a landmark grove (old big tree + standing stone / runestone marker) -----------------------------
def grove(sid, name, at, covers, tree, extra, rune="free:magic/runestone_face_moss@2.3", sub=""):
    parts = [
        [tree, 0, 0, 20, 1, 0],                                  # the old tree
        ["nature:dark_oak" if "twisted" in tree else "nature:oak_b", 7.5, 3.5, 40, 1, 0],
        ["nature:young_oak", -6.0, 5.5, 200, 0, 0],
        ["r1:stones/road_stone_b_menhir@3.2", 4.2, -5.6, 15, 1, 0],   # standing stone
        [rune, -4.4, -4.0, 160, 1, 0],                                # marker
        ["nature:log_mossy", -7.5, -1.5, 80, 0, 0],
        ["nature:stump_mossy", 8.5, -3.5, 0, 0, 0],
        ["nature:fern_a", -3.0, 7.5, 0, 0, 0], ["nature:fern_b", 2.5, 8.5, 90, 0, 0],
    ] + extra
    sites.append({"id": sid, "name": name, "kind": "waystone", "clear": 14, "flatten": False, "at": at, "snap": 140, "slope": 0.16,
                  "covers": covers, "parts": parts, "lights": [], "x": label(name.upper(), sub)})


grove("w4_grove_duskbriar", "Duskbriar Old Oak", [380, 480], ["lore:duskbriar_wood"], "free:nature/tree_old_twisted@13",
      [["nature:dark_oak", -9, -6, 300, 1, 0], ["nature:bush_dark", 6, 8, 0, 0, 0], ["nature:bush_berry", -8, 8, 50, 0, 0]],
      rune="free:magic/runestone_ember@2.4", sub="Edge of the runestone ward")
grove("w4_grove_duskfen", "Duskfen Black Pine", [-768, -4106], ["lore:duskfen_wood"], "free:nature/tree_old_b@13",
      [["nature:dead_snag", -9, -5, 20, 0, 0], ["nature:dead_snag", 9, 6, 150, 0, 0], ["nature:pine_scots", -7, 9, 0, 1, 0]],
      sub="Pines and black water")
grove("w4_grove_greywood", "Greywood Elder Ash", [-1494, 1789], ["lore:greywood"], "free:nature/tree_old_a@14",
      [["nature:rock_cluster", 8, 7, 30, 0, 0], ["nature:boulder_large", -9, -6, 100, 1, 0]],
      sub="Older than Ashford")
grove("w4_grove_hollowfang", "Hollowfang Ring Tree", [1422, 3959], ["lore:hollowfang_wood"], "free:nature/tree_old_twisted@12.5",
      [["free:nature/rock_limestone_tall@4.6", 9, -2, 20, 1, 0], ["free:nature/rock_limestone_tall@3.8", -9, 3, 200, 1, 0],
       ["free:nature/rock_limestone_tall@4.2", 1, 10, 110, 1, 0]],
      sub="The rings are older than the Long Dark")
grove("w4_grove_mistwood", "Mistwood Heart-Tree", [-3221, -614], ["lore:mistwood"], "free:nature/tree_old_b@14",
      [["nature:fern_a", 9, -7, 0, 0, 0], ["nature:fern_b", -9, 8, 40, 0, 0]],
      rune="free:magic/runestone_verdant@2.4", sub="Fog-hung, western edge")
grove("w4_grove_thornwold", "Thornwold Gallows Oak", [2908, -1820], ["lore:thornwold"], "free:nature/tree_old_a@12",
      [["nature:bush_dark", 5, 8, 0, 0, 0], ["nature:bush_dark", -6, 8, 90, 0, 0], ["nature:bush_dark", 9, -2, 40, 0, 0],
       ["nature:dead_snag", -9, -6, 130, 0, 0]],
      sub="Black thorn, east of the Silverrun")

# --- Ashford runestone circle (story place ashford_ring, 0,12): a ring of stones on the village green ---------------------
parts = []
for i in range(8):
    a = 2 * math.pi * i / 8 + 0.2
    x, z = round(math.cos(a) * 8.5, 2), round(math.sin(a) * 8.5, 2)
    parts.append(["r1:stones/road_stone_b_menhir@2.6" if i % 2 == 0 else "free:magic/runestone_face_moss@2.2", x, z, face(x, z), 1, 0])
parts += [["r1:stones/road_stone_a_slab@0.7", 0, 0, 0, 0, 0], ["nature:flowers_warm", 2.0, 1.5, 0, 0, 0], ["nature:flowers_cool", -2.2, -1.2, 70, 0, 0]]
sites.append({"id": "w4_ashford_ring", "name": "Ashford Runestone Circle", "kind": "waystone", "clear": 11, "flatten": False, "at": [0, 12], "fixed": True,
              "covers": ["ashford_ring"], "parts": parts, "lights": [[0, 2.6, 0, [0.55, 0.8, 1.0], 8, False]],
              "x": label("ASHFORD RING", "The ring of stones at the heart of Ashford", 4.6)})

# --- the unnamed Elder pin on the parchment (-700, -215): Elden Road marker, beside the Shrine of the Sleeping Flame --------------
sites.append({"id": "w4_elden_marker", "name": "Elden Road Marker", "kind": "waystone", "clear": 8, "flatten": False, "at": [-700, -215], "snap": 40, "slope": 0.2,
              "covers": ["parchment:", "lore:elden_road"],
              "parts": [["r1:stones/road_stone_d_pillar@3.6", 0, 0, 0, 1, 0], ["r1:stones/road_stone_c_squat@1.4", 3.2, 2.0, 40, 1, 0],
                        ["r1:stones/road_stone_a_slab@1.0", -3.0, 2.4, 100, 0, 0], ["nature:rock_cluster", 2.5, -3.0, 0, 0, 0]],
              "lights": [], "x": label("ELDEN ROAD", "The old runestone road runs west from here", 4.6)})

# --- Miller's Stone (123, -14): the slab by the Old Mill Staff Yard -------------------------------------------------------
sites.append({"id": "w4_millers_stone", "name": "The Miller's Stone", "kind": "waystone", "clear": 3, "flatten": False, "at": [123, -14], "snap": 26, "slope": 0.3,
              "covers": ["miller_stone"],
              "parts": [["r1:stones/road_stone_a_slab@2.1", 0, 0, 20, 1, 0], ["nature:flowers_warm", 1.6, 1.2, 0, 0, 0], ["nature:rock_cluster", -1.8, 0.8, 90, 0, 0]],
              "lights": [], "x": {}})

# --- Greenhollow's south fields (-842.5, -612.9): wheat rows with a scarecrow ----------------------------------------------
parts = []
for ix in range(-2, 3):
    for iz in range(-1, 2):
        parts.append(["farm/crop_wheat", round(ix * 4.1, 2), round(iz * 4.1, 2), (ix * 37 + iz * 11) % 4 * 90, 0, 0])
parts.append(["farm/scarecrow", 0.0, 0.0, 15, 0, 0])
for ix in range(-2, 3):
    parts.append(["farm/fence_rail", round(ix * 4.1, 2), 7.4, 0, 0, 0])
for iz in range(-1, 2):
    parts.append(["farm/fence_rail", -10.8, round(iz * 4.1, 2), 90, 0, 0])
parts += [["farm/fence_gate", 0, 7.4, 0, 0, 0], ["nature:dead_snag", 12, -5, 30, 0, 0]]
sites.append({"id": "w4_greenhollow_fields", "name": "Greenhollow South Fields", "kind": "roadside", "clear": 13, "flatten": True, "at": [-842.5, -612.9], "snap": 90,
              "slope": 0.16, "covers": ["greenhollow_south_fields"], "parts": parts, "lights": [], "x": {}})

# --- The Rift Mouth (2699.9, 2513.4): the violet mouth at the bottom of the Ashen Scar crater ---------------------------------
sites.append({"id": "w4_rift_mouth", "name": "The Rift Mouth", "kind": "roadside", "clear": 24, "flatten": True, "at": [2699.9, 2513.4], "fixed": True,
              "covers": ["rift_mouth"],
              "parts": [["meshy:landmark_rift@10", 0, 0, 0, 1, 0], ["nature:dead_snag", 12, -6, 25, 0, 0], ["nature:dead_snag", -13, 4, 120, 0, 0],
                        ["nature:rock_cluster", 7, 9, 12, 0, 0], ["nature:boulder_large", -8, -9, 57, 1, 0],
                        ["r1:rift/crystals/scar_crystal_a", 16, 3, -80, 0, 0], ["r1:rift/crystals/scar_crystal_b", -15, -3, 100, 0, 0],
                        ["r1:rift/crystals/scar_crystal_c", 3, 15, 200, 0, 0]],
              "lights": [[0, 4.0, 0, [0.7, 0.35, 1.0], 22, True]], "x": label("THE RIFT MOUTH", "The violet mouth of the Ashen Scar", 8.0)})

# --- Lower Greyseam rift seam (the Elder Stone is at -188.1, -499.2; the seam shows ~25 m toward the mine) ---------------------
sites.append({"id": "w4_greyseam_seam", "name": "Lower Greyseam Rift Seam", "kind": "waystone", "clear": 4, "flatten": False, "at": [-171, -486], "snap": 30, "slope": 0.6,
              "covers": ["greyseam_seam"],
              "parts": [["r1:rift/crystals/scar_crystal_a", 0, 0, 20, 0, 0], ["r1:rift/crystals/scar_crystal_b", 2.6, 1.4, 130, 0, 0],
                        ["r1:rift/crystals/scar_crystal_c", -2.2, 1.9, 250, 0, 0], ["r1:rift/crystals/scar_crystal_b", 1.1, -2.6, 60, 0, 0],
                        ["nature:rock_slab", -1.0, -1.6, 15, 0, 0], ["nature:boulder_large", 4.5, -1.5, 70, 1, 0]],
              "lights": [[0, 1.6, 0.5, [0.7, 0.4, 1.0], 7, True]], "x": {}})

# --- Silverford market square before the Guild Hall (2066.2, -1807.5) ---------------------------------------------------------
parts = [["free:props/well_stone_roofed@3.4", 0, 0, 0, 1, 0]]
stalls = ["free:market/stall_small_workshop@3.0", "free:market/stall_potion@3.0", "free:market/stall_apples@3.0", "free:market/stall_cheese_awning@3.0",
          "free:market/stall_blue_shields@3.0", "free:market/stall_red_awning_goods@3.0", "free:market/stall_meat_shingle@3.0", "free:market/stall_potatoes@3.0"]
for i, a in enumerate([-150, -110, -70, -30, 30, 70, 110, 150]):
    r = 10.5
    x, z = round(math.cos(math.radians(a)) * r, 2), round(math.sin(math.radians(a)) * r, 2)
    parts.append([stalls[i], x, z, face(x, z), 1, 0])
parts += [["props/crate_stack", 4.5, 4.0, 30, 0, 0], ["props/crate_stack", -4.5, -4.5, 100, 0, 0], ["props/sack_pile", -5, 4, 0, 0, 0], ["props/barrel", 5.5, -4, 0, 0, 0],
          ["gen:bunting@1.0", 0, 7, 0, 0, 0], ["props/lamp_post", 7, 7, 0, 0, 0], ["props/lamp_post", -7, -7, 0, 0, 0],
          ["props/lamp_post", -7, 7, 0, 0, 0], ["props/lamp_post", 7, -7, 0, 0, 0]]
sites.append({"id": "w4_silverford_market", "name": "Silverford Market Square", "kind": "roadside", "clear": 14, "flatten": True, "at": [2066.2, -1807.5], "snap": 60,
              "slope": 0.12, "covers": ["silverford_market"], "parts": parts,
              "lights": [[7, 3.4, 7, [1.0, 0.72, 0.4], 9, True], [-7, 3.4, -7, [1.0, 0.72, 0.4], 9, True]],
              "x": label("SILVERFORD MARKET", "The market before the Guild Hall", 6.0)})


# --- river markers: the Ashrun (-400, 220 is in the Mere: nearest bank) and the Silverrun (2640, 336) ------------------------
def river_marker(sid, name, at, covers, sub, boat=False):
    parts = [["r1:stones/road_stone_d_pillar@3.4", 0, 0, 0, 1, 0], ["r1:stones/road_stone_c_squat@1.3", 2.6, 1.8, 40, 1, 0], ["nature:rock_cluster", -2.6, 2.2, 0, 0, 0],
             ["free:lighting/lantern_post_wood@3.0", 4.2, -0.5, 0, 0, 0], ["nature:fern_a", -3.4, -1.8, 0, 0, 0], ["nature:bush_hazel", 4.6, 3.2, 0, 0, 0]]
    if boat:
        parts.append(["free:water/boat_rowing@1.1", -5.5, 6.0, 70, 0, 0])
    sites.append({"id": sid, "name": name, "kind": "waystone", "clear": 8, "flatten": False, "at": at, "snap": 160, "slope": 0.2, "bank": True,
                  "covers": covers, "parts": parts, "lights": [[4.2, 2.8, -0.5, [1.0, 0.7, 0.4], 7, True]], "x": label(name.upper(), sub, 4.8)})


river_marker("w4_ashrun_marker", "Ashrun Bank Stone", [-400, 220], ["lore:ashrun_river"], "Cold and clear, fed by snowmelt")
river_marker("w4_silverrun_marker", "Silverrun Ferry Stone", [2640, 336], ["lore:silverrun_river"], "Broad and silver-grey")


# --- map-edge border cairns: the four edge texts of the parchment ---------------------------------------------------------------
def edge(sid, name, at, covers, banner):
    parts = [["r1:stones/road_stone_d_pillar@5.0", -3.4, 0, 0, 1, 0], ["r1:stones/road_stone_d_pillar@5.0", 3.4, 0, 0, 1, 0],
             ["r1:stones/road_stone_b_menhir@3.0", 0, 4.0, 0, 1, 0], [banner, 0, -1.5, 0, 0, 0],
             ["nature:rock_cluster", -6, 3, 0, 0, 0], ["nature:boulder_large", 6.5, 3.5, 40, 1, 0],
             ["free:lighting/torch_stake@1.6", -3.4, 2.4, 0, 0, 0], ["free:lighting/torch_stake@1.6", 3.4, 2.4, 0, 0, 0]]
    sites.append({"id": sid, "name": name, "kind": "waystone", "clear": 10, "flatten": False, "at": at, "snap": 150, "slope": 0.3,
                  "covers": covers, "parts": parts, "lights": [[0, 3.0, 2.4, [1.0, 0.7, 0.4], 8, True]], "x": label(name.upper(), "Edge of the Ashford Vale", 6.2)})


edge("w4_edge_west", "The Western Reaches", [-5800, 0], ["edge:the_western_reaches"], "free:banners/banner_tall_cross@4.5")
edge("w4_edge_east", "To the Aurelis Patriarchate", [5800, 0], ["edge:to_the_aurelis_patriarchate"], "free:banners/banner_crossbar@4.0")
edge("w4_edge_north", "To the Frostcrown Holds", [0, -5800], ["edge:to_the_frostcrown_holds"], "free:banners/banner_stand_spear_flag@4.6")
edge("w4_edge_south", "To the Solkar Dominion", [0, 5800], ["edge:to_the_solkar_dominion"], "free:banners/banner_gold_finials@4.2")

# --- road milestones (Greenhollow road, King's Ember Road) ----------------------------------------------------------------------
sites.append({"id": "w4_milestones_ember", "name": "Ember Road Milestone", "kind": "waystone", "clear": 2, "flatten": False, "covers": ["kings_ember_road"],
              "milestones": {"near": [280, -210], "count": 7, "spacing": 80, "side": 5.5}, "parts": [["road/milestone", 0, 0, 0, 1, 0]], "lights": [], "x": {}})
sites.append({"id": "w4_milestones_greenhollow", "name": "Greenhollow Road Milestone", "kind": "waystone", "clear": 2, "flatten": False, "covers": ["greenhollow_road"],
              "milestones": {"near": [-471, -317], "count": 7, "spacing": 80, "side": 5.5}, "parts": [["road/milestone", 0, 0, 0, 1, 0]], "lights": [], "x": {}})

# The Scar Mouth Arena: the planner puts it 44-120 m from the Scar (2398.8, 2468.2); the canon record is first_region.json (2864.1, 2586.4). Moving it
# AFTER planning keeps every later site on its own ground (a move inside the plan shifted 18 caves). Sites on the arena's old point move with it.
relocate = [{"r1id": "scar_arena", "to": [2864.1, 2586.4], "with_same_point": True}]

doc = {"version": 1,
       "_doc": "W4 landmark/POI bodies (kingdom/tools/region1/gen_w4_sites.py writes this). Planned by scripts/world/region1_w4.gd after every other site (no id moves). Part = [asset, x, z, yaw_deg, collide, y].",
       "aliases": {
           "exit:harrow_arch": "site:Harrow Arch and Caravan Stage (landmark_harrowgate, 0.3 m apart): the exit record is the arch, no second body",
           "exit:westfen_fen": "site:Westfen Herb Walk (landmark_westfen, 0.5 m apart): the exit record is the walk, no second body",
           "lore:elden_road": "Elden Waymarks (region1_world._elden_road, every 70 m from the Shrine to the Elden Elder Stone) + w4_elden_marker",
           "proposed:silverford": "parchment proposal only: the live Silverford is settlement:ironmarch (OWNER QUESTION, see docs/world/W4_LANDMARKS.md)",
           "site:Solkar Caravan Camp:1991:-1831": "summer-only by design (sites.json season gate); its body appears in summer",
           "scar_arena": "one record: the planner site moved to the canon point (2864.1, 2586.4) of data/world/first_region.json"},
       "relocate": relocate,
       "sites": sites}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=1)
print("wrote", os.path.normpath(OUT), len(sites), "sites", sum(len(s["parts"]) for s in sites), "parts")
