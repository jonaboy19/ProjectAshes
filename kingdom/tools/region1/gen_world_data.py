#!/usr/bin/env python3
"""Generates data/region1/world/settlements.json (package C2: settlement identity) and the parts of the C1/C10
sites (data/region1/world/sites.json). Run from the kingdom dir:  python3 tools/region1/gen_world_data.py
Parts are [asset, x, y, yaw_deg, collide, y_offset]: site-local metres (x right, y FRONT = toward the settlement), see
RegionSites. Assets: "free:<cat>/<name>@H" (incoming/meshy_free, fitted to H metres), "r1:<dir>/<name>" (incoming/region1),
"gen:<name>@scale" (assets/generated), "props/<name>", "nature:<name>" and bare region keys ("farm/barn")."""
import json, math, os

OUT = "data/region1/world"


def P(a, x, y, yaw=0, col=0, yo=0):
    return [a, round(x, 2), round(y, 2), yaw, 1 if col else 0, yo]


def ring(a, n, r, cx=0.0, cy=0.0, face_in=True, col=0, start=0.0, yo=0):
    out = []
    for i in range(n):
        ang = math.tau * i / n + math.radians(start)
        x, y = cx + math.cos(ang) * r, cy + math.sin(ang) * r
        yaw = math.degrees(math.atan2(-(x - cx), -(y - cy))) if face_in else 0
        out.append(P(a, x, y, round(yaw), col, yo))
    return out


def row(a, n, x0, y0, dx, dy, yaw=0, col=0):
    return [P(a, x0 + dx * i, y0 + dy * i, yaw, col) for i in range(n)]


def fence_box(a, x0, y0, x1, y1, step=3.1, gap_front=True):
    """Fence rectangle with a gap in the front (+y) side."""
    out = []
    n = int(abs(x1 - x0) // step)
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / max(n, 1)
        out.append(P(a, x, y0, 0))
        if not (gap_front and abs(x) < 3.2):
            out.append(P(a, x, y1, 0))
    m = int(abs(y1 - y0) // step)
    for j in range(1, m):
        y = y0 + (y1 - y0) * j / m
        out.append(P(a, x0, y, 90))
        out.append(P(a, x1, y, 90))
    return out


def light(x, y, z, col, rng, flick=True):
    return [x, y, z, col, rng, flick]


WARM = [1.0, 0.72, 0.4]
HOT = [1.0, 0.55, 0.25]
COOL = [0.55, 0.8, 1.0]
VIOLET = [0.7, 0.4, 1.0]


def town(name, alias, trade, tagline, lname, clear, parts, lights, npc, rumours, label=None, doors=None, people=None, extra=None):
    x = {"label": {"text": (alias or name).upper(), "sub": tagline, "at": [0, 10.5], "h": 3.3}}
    x["npcs"] = [npc]
    if doors:
        x["doors"] = doors
    if people:
        x["people"] = people
    if extra:
        x.update(extra)
    return {"name": name, "alias": alias, "trade": trade, "tagline": tagline,
            "landmark": {"name": lname, "clear": clear, "parts": parts, "lights": lights, "x": x},
            "npc": npc, "rumours": rumours}


def npc(name, role, look, at, greet, trade, lines, yaw=0):
    return {"name": name, "role": role, "look": look, "at": at, "yaw": yaw, "greet": greet, "trade": trade, "lines": lines}


S = []

# 0 Ashford: the Old Mill Staff Yard and the Miller's Stone
S.append(town("Ashford", "", "Milling and the hearth: the stream turns the mill, the ring of stones keeps the dark out.", "Hearth and Stone", "Old Mill Staff Yard", 20,
    fence_box("free:fences/fence_rail_rustic@1.2", -9, -4, 9, 10) +
    [P("farm/scarecrow", -5, 0, 20, 1), P("farm/scarecrow", 0, 1.5, 0, 1), P("farm/scarecrow", 5, 0, -20, 1),
     P("props/weapon_rack", -7, -2.5, 90), P("props/weapon_rack", 7, -2.5, -90), P("props/hay_bales", 8, 7, 30),
     P("props/water_trough", -8, 7, 90), P("free:buildings/hut_long_thatch@4.6", 0, -10, 0, 1),
     P("r1:stones/road_stone_b_menhir", -14, 3, 90, 1), P("free:props/well_wood_roof@3.2", 13, 4, 0, 1),
     P("props/bench", 4, 12, 0), P("props/lamp_post", -4, 12.5, 0), P("props/lamp_post", 4, 12.5, 0)],
    [light(-4, 3.4, 12.5, WARM, 8, True), light(4, 3.4, 12.5, WARM, 8, True)],
    npc("Maren Coldbrook", "staff teacher", "Mage", [2.5, 4.5], "Staff up. Feet apart. No, the other apart.",
        "Ashford lives by the mill and the ring: every child learns the staff in this yard, and every child learns to touch the stones.",
        ["Not bad. Not good. Not bad. Come back when your grip stops trembling.",
         "Forty slept the night I held the stone. Fair trade. Don't tell your mother I said so.",
         "The Miller's Stone sang a little flat last week. Idra says stones get tired. I say so do I."], 200),
    ["The Miller's Stone hums flat some evenings. Idra Vell says it is only tired.",
     "The Guard has nine spears for forty-one stones. Captain Hollis counts them like sheep.",
     "Children who beat Maren Coldbrook at staves get honey cakes. Nobody has yet.",
     "Somebody left a lantern on the Miller's Stone at dusk. Nobody will say who."]))

# 1 Kingsreach: the royal lists
S.append(town("Kingsreach", "", "Crown and court: the Council of Wardens sits here, the tournaments are run here, the great market is here.", "Crown, Court and Lists", "Royal Tourney Lists", 26,
    fence_box("free:fences/fence_board_panel@1.4", -11, -8, 11, 8, 3.4) +
    [P("free:camp/tent_conical_striped@4.2", -15, -6, 50, 1), P("free:camp/tent_conical_striped@4.2", 15, -6, -50, 1),
     P("free:camp/tent_conical_striped@4.2", -16, 6, 70, 1), P("free:market/stall_striped_shields@3.2", 16, 7, -80, 1),
     P("free:banners/banner_tall_cross@5.2", -12, 10, 0), P("free:banners/banner_tall_cross@5.2", 12, 10, 0),
     P("free:banners/banner_stand_spear_flag@4.6", -6, -9, 180), P("free:banners/banner_stand_spear_flag@4.6", 6, -9, 180),
     P("free:interior/weapon_rack_swords@1.6", -9, -10, 0), P("free:props/shield_dragon_heraldic@1.4", 9, -10.5, 0),
     P("gen:bunting@1.0", 0, 9.5, 0), P("props/lamp_post", -3, 11, 0), P("props/lamp_post", 3, 11, 0),
     P("r1:highwatch/banner_pole", -8, 12, 0), P("r1:highwatch/banner_pole", 8, 12, 0)],
    [light(-3, 3.4, 11, WARM, 8, True), light(3, 3.4, 11, WARM, 8, True)],
    npc("Herald Corwin Vale", "Herald of the Wardens", "Noble", [0, 6], "Hear ye. Well, hear me, at least.",
        "Kingsreach is where Valencious decides things: the Council of Wardens, the Royal Ember Academy and the Midsummer tourney all answer to this one hill.",
        ["The Crown Princess rode out with four guards and came back with six more. Nobody knows where they came from.",
         "The Wardens vote on the stones each Kindling Night. The vote is always 'more hands'. The hands never come.",
         "The Dawn Throne's envoy has taken the old chapel. The King let him. Make of that what you will."])
    ,
    ["The Crown Princess rode out with four guards and came back with six.",
     "The Council voted 'more hands for the stones' again. The hands are still not here.",
     "The Dawn Throne's envoy took the old chapel by the north road. The King allowed it.",
     "The Academy is scouting: a scholar in blue asked after children who can make the stones hum."]))

# 2 Millbrook: the great mill and bakehouse
S.append(town("Millbrook", "", "Flour and bread: the great windmill grinds the vale's wheat; the bakehouse feeds three villages.", "Mill and Bakehouse", "Millbrook Great Mill", 22,
    [P("farm/windmill", 0, -6, 0, 1), P("free:buildings/cottage_small_thatch@5.4", -11, 0, 70, 1),
     P("free:market/stall_awning_red@3.0", 9, 5, -60, 1), P("free:market/stall_crates_cream@2.8", 13, 1, -80, 1),
     P("free:carts/cart_cargo_spoke@2.4", -8, 9, 30, 1), P("props/sack_pile", 6, 1, 0), P("props/sack_pile", -5, 4, 40),
     P("props/barrel", 7.5, 8.5, 0), P("props/hay_bales", -13, 8, 20), P("props/lamp_post", 3, 11, 0),
     P("props/basket_produce", 10.5, 7, 0), P("props/crate_stack", -4, -1, 0), P("props/woodpile", -12, -7, 0)]
    + [P("farm/crop_wheat", -6 + 4.1 * c, -14 - 4.1 * r, 0) for r in range(2) for c in range(4)],
    [light(3, 3.4, 11, WARM, 8, True), light(-11, 2.4, 3, HOT, 6, True)],
    npc("Hob Millwright", "miller", "Barbarian", [3, 6], "Mind the sails and mind your hat.",
        "Millbrook's windmill grinds the flour for the whole vale; the smell of its bakehouse is the first thing travellers mention.",
        ["The sails turned backward on their own last Tuesday. Swear to it. Flour everywhere.",
         "Redwater dyers pay in cloth, Thornfield brewers pay in ale. I prefer the ale.",
         "A sack of Millbrook flour is good luck on a road with no stones. Take two."]),
    ["The mill sails turned backward on their own last Tuesday. Flour everywhere.",
     "Thornfield's brewer pays for barley in ale. The miller prefers that.",
     "A sack of Millbrook flour is said to be good luck on a stoneless road.",
     "The east road is quiet. Quieter than it should be, says the baker."]))

# 3 Stonehollow: the quarry
S.append(town("Stonehollow", "", "Cut stone: its quarry squared the stones of half the vale's waymarks, and its masons carve for the Guild at Silverford.", "Quarry and Masons", "Stonehollow Quarry", 24,
    [P("free:nature/rock_limestone_tall@6.5", -8, -9, 20, 1), P("free:nature/rock_limestone_tall@5.2", -3, -13, 160, 1), P("free:nature/rock_blue_brown@4.0", 7, -11, 60, 1),
     P("mine/mine_winch", 6, -4, 180, 1), P("props/anvil_stump", -4, 1, 0), P("props/anvil_stump", -1.5, 3, 40)]
    + [P("nature:rock_slab", -10 + 1.9 * i, 4 + 0.3 * (i % 2), 10 * i, 0, 0.0) for i in range(5)]
    + [P("nature:rock_slab", -8.5 + 1.9 * i, 4.2, 4 * i, 0, 0.42) for i in range(3)]
    + [P("nature:rock_cluster", 11, 3, 0), P("nature:boulder_large", 13, -4, 40, 1), P("mine/mine_cart", 2, -6, 90, 1),
       P("mine/rail_straight", 2, -2, 0), P("mine/rail_straight", 2, 2, 0), P("free:ruins/arch_baroque_old@5.6", 0, 8.5, 0, 0),
       P("props/lamp_post", -6, 10, 0), P("free:carts/cart_plain_a@2.2", 11, 8, -30, 1), P("props/woodpile", -13, 1, 0)],
    [light(-6, 3.4, 10, WARM, 8, True)],
    npc("Brenna Flint", "quarrymaster", "Blacksmith", [2, 7], "Stone doesn't care how your morning went.",
        "Stonehollow cuts the stone: every waymark on the Ember Road came from this quarry, and every Silverford mason starts here.",
        ["A good waystone takes three weeks to cut and a day to crack. Cheaper to keep them lit, I say.",
         "We sent forty blocks to Silverford for the Guild. Odrin Thale paid late and apologised well.",
         "The deep face hums at night. Not the stones; the rock. It remembers being mountain."]), 
    ["A good waystone takes three weeks to cut and a day to crack, says the quarrymaster.",
     "The deep quarry face hums at night. The masons have stopped working past dusk.",
     "Silverford's Guild ordered forty blocks and paid late, but apologised well.",
     "A cart of green-veined stone went north with a Runeward escort. Nobody says where."]))

# 4 Eastmere: dairy
S.append(town("Eastmere", "", "Milk, butter and cheese: the eastern pastures' herds come home to Eastmere's dairy.", "Dairy and Cheese", "Eastmere Dairy", 22,
    [P("farm/barn", -2, -8, 0, 1), P("free:market/stall_cheese_awning@3.0", 9, 4, -70, 1), P("free:farm/cows_pair@1.6", -10, 3, 70),
     P("free:farm/cow_spotted@1.5", -13, 7, 20), P("free:farm/cow_spotted@1.5", -7, 9, 130), P("props/water_trough", -9, 0, 90)]
    + fence_box("free:fences/fence_farm_white@1.2", -16, -1, -4, 13, 3.3, False)
    + [P("props/barrel", 6, 8.5, 0), P("props/barrel", 7.4, 8, 0), P("props/barrel", 6.6, 9.6, 0), P("props/hay_bales", 12, -3, 20),
       P("free:farm/chicken_coop_small@1.8", 13, 6, -90, 1), P("props/lamp_post", 2, 11, 0), P("props/basket_produce", 10, 8, 0),
       P("props/sack_pile", 5, -4, 0), P("farm/crop_cabbage", 4, -14, 0), P("farm/crop_cabbage", 8, -14, 0)],
    [light(2, 3.4, 11, WARM, 8, True)],
    npc("Tilda Marsh", "dairymaid", "Mage", [3, 6.5], "Mind the pail, it's still warm.",
        "Eastmere's herds are the vale's largest: cheese wheels from this dairy go west as far as Kingsreach's tables.",
        ["The spotted cow prefers the roadside verge. She knows which stones are dark. Clever girl.",
         "We send cheese to Silverford for the Solkar traders. They pay in saffron. I don't know what to do with saffron.",
         "Eastmere's butter keeps three weeks in a cold cellar. Four if the Runeward blesses the cellar."]),
    ["The spotted cow prefers the roadside verge. She seems to know which stones are dark.",
     "Saffron has arrived at the dairy. Nobody ordered saffron.",
     "Eastmere butter keeps three weeks in a cold cellar, four if a warden blesses it.",
     "Wolves took no sheep this year. Wolves took a dairy cart, on the east road, in daylight."]))

# 5 Redwater: dyers
S.append(town("Redwater", "", "Dyes and cloth: madder red, woad blue and weld gold steep in the vats along the stream.", "Dyers and Cloth", "Redwater Dye Works", 22,
    [P("free:buildings/house_timber_tall@7.0", 0, -9, 0, 1)]
    + [P("props/barrel", -6 + 2.2 * i, 0.5, 0) for i in range(4)]
    + [P("free:banners/banner_crossbar@4.5", -10 + 4 * i, 6, 0) for i in range(6)]
    + [P("free:banners/banner_gold_finials@4.8", -8 + 4 * i, 8, 0) for i in range(5)]
    + [P("free:market/stall_red_awning_goods@3.0", 11, 3, -70, 1), P("free:market/stall_market_sign_red@3.0", -12, 3, 70, 1),
       P("gen:bunting@1.0", 0, 4.5, 0), P("props/crate_stack", 7.5, -3, 0), P("props/sack_pile", -8, -4, 30),
       P("free:carts/cart_open_wide@2.2", 13, 9, -40, 1), P("props/water_trough", 4, 1.5, 90), P("props/lamp_post", 0, 12, 0),
       P("free:flora/bellflower_purple@0.9", -12, 10, 0), P("free:flora/bouquet_bright@0.8", 12, 11, 0)],
    [light(0, 3.4, 12, WARM, 9, True)],
    npc("Mirel Redhand", "master dyer", "Mage", [-3, 6.5], "Don't shake my hand; you'll be red until Tuesday.",
        "Redwater's dyers colour half the vale's cloth: their red is the Crown's red, and the Guild's blue comes from their woad vats.",
        ["Royal blue is woad and a lot of patience. Silverford pays double for the good batch.",
         "The stream runs red on dye days. Children in the next valley think it is an omen. We let them.",
         "Somebody stole a bolt of Highwatch blue. The thief is easy to spot. He is the man who is not wearing it."]),
    ["The stream runs red on dye days. Children downstream think it is an omen.",
     "A bolt of Highwatch blue went missing. The thief should be easy to spot.",
     "Silverford pays double for the good woad batch, and complains the price.",
     "The Solkar traders want a yellow we don't know how to make."]))

# 6 Thornfield: brewery
S.append(town("Thornfield", "", "Barley and ale: Thornfield's brewery and tithe barn; its hedgerows of thorn keep the fields safe.", "Barley and Brewery", "Thornfield Brewery", 24,
    [P("farm/granary", -3, -10, 0, 1), P("free:buildings/tavern_wooden_long@5.6", 10, -4, -90, 1)]
    + [P("free:props/keg_iron_banded_upright@1.2", -8 + 1.6 * i, 0.5, 0) for i in range(4)]
    + [P("free:props/keg_iron_banded_side@0.9", -7 + 1.6 * i, 2.4, 90) for i in range(3)]
    + [P("free:furniture/table_tavern_feast@1.1", -1, 5.5, 0), P("free:furniture/table_bench_tavern@0.9", 3, 7.5, 90),
       P("free:furniture/tavern_set_barrels_a@1.3", 6, 4, 0), P("free:carts/cart_barrels@2.1", -12, 7, 50, 1),
       P("props/lamp_post", -3, 12, 0), P("props/lamp_post", 3, 12, 0)]
    + [P("farm/crop_wheat", -14 + 4.1 * c, -18 - 4.1 * r, 0) for r in range(2) for c in range(4)]
    + [P("free:fences/fence_woven_wattle@1.2", -16 + 3.2 * i, 14, 0) for i in range(3)]
    + [P("free:fences/fence_woven_wattle@1.2", 6 + 3.2 * i, 14, 0) for i in range(3)],
    [light(-3, 3.4, 12, WARM, 9, True), light(3, 3.4, 12, WARM, 9, True), light(10, 2.6, -1, HOT, 7, True)],
    npc("Hesta Thorne", "brewmistress", "Innkeeper", [0, 8.5], "First pint is free if you can name the hop.",
        "Thornfield's barley goes into the vale's ale, and its thorn hedges have kept the wolves off the fields for three generations.",
        ["Thorn hedges hold better than stones, some years. Wolves hate the scratch; stones hate the wear.",
         "My ale won a Kingsreach prize. The Council gave a scroll. I asked for gold. They sent a second scroll.",
         "The tithe barn is half full. Half. After a good harvest. Somebody is sitting on the rest."]),
    ["Thorn hedges hold better than stones some years, says the brewmistress.",
     "The tithe barn stands half empty after a good harvest. Someone has been sitting on the rest.",
     "Thornfield ale won a Kingsreach prize and a scroll. The brewer wanted gold.",
     "A Church envoy's cart passed east and did not stop to buy ale. The brewer took it personally."]))

# 7 Greywatch: spear hall
S.append(town("Greywatch", "", "Spears and discipline: the Greywatch Spear Hall drills the militia that marches under the Order of the Highwatch.", "Spear Hall and Militia", "Greywatch Spear Hall", 26,
    [P("free:buildings/tavern_wooden_long@6.4", 0, -10, 0, 1), P("r1:highwatch/training_yard", -15, 0, 0, 0),
     P("free:castle/tower_square_small@9.0", 14, -8, -40, 1), P("r1:highwatch/guard_post", -5, 6, 15), P("r1:highwatch/guard_post", 5, 6, -15),
     P("free:interior/weapon_racks_spears@1.8", 9, 2, -90), P("free:banners/banner_tall_cross@5.0", -9, 9, 0), P("free:banners/banner_tall_cross@5.0", 9, 9, 0),
     P("r1:highwatch/banner_pole", 0, 7.5, 0), P("props/lamp_post", -3, 12, 0), P("props/lamp_post", 3, 12, 0),
     P("props/hay_bales", 13, 4, 10), P("props/water_trough", 12, -1, 90)],
    [light(-3, 3.4, 12, WARM, 9, True), light(3, 3.4, 12, WARM, 9, True), light(14, 9, -8, HOT, 10, True)],
    npc("Sergeant Ulric Greyspear", "drill sergeant", "Guard", [0, 4], "Shoulders back. The spear is not a walking stick.",
        "Greywatch trains the spear line for the north: the Order's recruits come through this hall before they see Highwatch.",
        ["Spears up, feet planted, and do not look at the wolf. Look at the man next to you.",
         "The Order sent us forty recruits. Thirty stayed. Twenty can hold a line. Ten can keep it.",
         "Sir Rowan Ashby says a knight is a spearman who did not quit. Rowan would."]),
    ["The Order sent forty recruits to the Spear Hall. Thirty stayed, ten can hold a line.",
     "Sergeant Greyspear says a knight is just a spearman who did not quit.",
     "The watch-fires at Highwatch burned twice last week. Nobody will say why.",
     "Drums on the north wind after dusk. The sergeant says it is the wind."]))

# 8 Oakvale = Greenhollow
S.append(town("Oakvale", "Greenhollow", "Crops and the great oak: Greenhollow's south meadows feed the vale; the Pennick farm is the largest.", "Fields and the Great Oak", "Pennick Farm, Greenhollow", 26,
    [P("nature:oak_a", -3, -14, 0, 1, 0), P("farm/barn", 10, -9, 90, 1), P("farm/granary", -11, -7, 0, 1), P("farm/chicken_coop", 14, 1, -90, 1),
     P("farm/hay_wagon", 4, 0, 100, 1), P("props/hay_bales", -5, 2, 0), P("props/hay_bales", -8, 4, 40),
     P("free:farm/wheelbarrow_wooden_old@1.0", 8, 6, 30)]
    + [P("farm/crop_wheat", -16 + 4.1 * c, 4 + 4.1 * r, 0) for r in range(3) for c in range(3)]
    + [P("farm/crop_cabbage", 1 + 4.1 * c, 6 + 4.1 * r, 0) for r in range(2) for c in range(3)]
    + [P("farm/scarecrow", -4, 11, 0, 1), P("props/water_trough", 13, 7, 90), P("props/lamp_post", 0, 13, 0)]
    + [P("farm/fence_rail", -17 + 3.2 * i, 18, 0) for i in range(11)],
    [light(0, 3.4, 13, WARM, 9, True)],
    npc("Gilda Pennick", "farmer", "Mother", [2, 6], "If you're here for eggs, the hens are sulking.",
        "Greenhollow's south fields are the vale's bread: the Pennick farm brings in a third of the harvest, and the Great Oak is older than the village.",
        ["The south fields have gone strange at the edge. Violet. Only a little. I'm told it's the light.",
         "We tithe to the Crown in wheat and to the Runeward in bread. The Runeward eat better.",
         "My barn burned once. Only the once. I keep the old scorch on the beam so the new barn remembers."]),
    ["The south fields have gone violet at the edge. Only a little. Somebody says it's the light.",
     "The Great Oak hums in a storm. Gilda Pennick insists it always has.",
     "The Runeward eat better than the Crown's tax men; Greenhollow bread has a lot to do with it.",
     "Wolves came to the hedge at noon. Not at night. At noon."]))

# 9 Highcliff: armoury and stables under Highwatch Keep
S.append(town("Highcliff", "", "Steel and horses: the armourers and stablers who outfit the knights of Highwatch Keep on the ridge above.", "Armoury and Stables", "Highcliff Armoury", 22,
    [P("free:buildings/smithy_open_shed@5.6", 0, -9, 0, 1), P("props/anvil_stump", -2, -2, 20), P("free:interior/armour_stand_knight@2.4", 7, 0, -30),
     P("free:interior/weapon_rack_swords@1.6", -8, -4, 90), P("free:interior/shelf_weapons_display@2.2", 9, -6, -90), P("free:creatures/horse_saddled@2.0", -9, 6, 60),
     P("free:props/chest_iron_box@0.9", 4, -4, 0), P("props/water_trough", -12, 3, 90), P("props/hay_bales", -14, 8, 10),
     P("r1:highwatch/banner_pole", -6, 11, 0), P("r1:highwatch/banner_pole", 6, 11, 0), P("props/lamp_post", 0, 12, 0),
     P("props/barrel", 6, 7, 0), P("free:fences/fence_rail_rustic@1.2", -16, 4, 90), P("free:fences/fence_rail_rustic@1.2", -16, 7.1, 90),
     P("free:fences/fence_rail_rustic@1.2", -16, 10.2, 90)],
    [light(0, 3.4, 12, WARM, 9, True), light(0, 2.0, -6, HOT, 8, True)],
    npc("Dagna Holt", "armourer", "Blacksmith", [2, 5], "Steel's honest. People aren't. Show me your blade.",
        "Highcliff outfits the Order of the Highwatch: the lancers' mail is hammered here, and the ridge stable breeds the knights' chargers.",
        ["Sir Rowan's armour has been mended eleven times. He refuses to buy new. Says it remembers his knees.",
         "Steel from Hollowdeep comes south through Kingsreach. The price of it is a crime.",
         "The chargers know the road to the pass. They won't go past the last banner. Smart animals."]),
    ["Sir Rowan Ashby's armour has been mended eleven times. He refuses new.",
     "The chargers will not go past the last banner on the north road. Smart animals.",
     "A knight rode down from Highwatch with frost on his cloak in midsummer.",
     "Hollowdeep steel is three times the price this season."]))

# 10 Brackenmoor: hunters
S.append(town("Brackenmoor", "", "Pelts and venison: a hunters' hold on the edge of the wild, where every hunter carries a wolf-tooth token.", "Hunters and Pelts", "Hunters' Lodge", 22,
    [P("free:buildings/hut_long_thatch@5.2", 0, -9, 0, 1), P("free:camp/tent_hide_hut@3.4", -11, -2, 60, 1), P("free:camp/tent_hide_hut@3.4", 11, -3, -60, 1),
     P("ruins/campfire", 0, 1, 0), P("free:fences/fence_woven_wattle@1.3", -9, 5, 0), P("free:fences/fence_woven_wattle@1.3", -6, 5, 0),
     P("free:fences/fence_woven_wattle@1.3", 6, 5, 0), P("free:fences/fence_woven_wattle@1.3", 9, 5, 0),
     P("props/weapon_rack", -5, -3, 90), P("props/weapon_rack", 5, -3, -90), P("free:banners/banner_ragged_spear@3.6", -5, 9, 0),
     P("free:banners/banner_ragged_spear@3.6", 5, 9, 0), P("props/woodpile", 10, 3, 10), P("free:props/axe_battle_upright@1.4", -3, 3, 0),
     P("free:creatures/wolf_grey@0.9", 2.5, 4.5, 200), P("props/lamp_post", 0, 12, 0)],
    [light(0, 0.8, 1, HOT, 10, True), light(0, 3.4, 12, WARM, 8, True)],
    npc("Garrick Bracken", "huntmaster", "Hunter", [-3, 6], "Keep your voice down. The bracken listens.",
        "Brackenmoor hunts what the stones do not reach: its pelts and venison feed the frontier, and its hunters know every den by smell.",
        ["Wolves came in from the east ridge at noon last week. Noon. They have learned the stones are tired.",
         "A white hart was seen in the north wood, antlers like a cathedral. We do not shoot the white hart.",
         "If you see a den, tell me before you tell the Guard. The Guard counts. I hunt."]),
    ["Wolves came down from the east ridge at noon last week. They have learned the stones are tired.",
     "A white hart was seen in the north wood, antlers like a cathedral. Nobody shoots the white hart.",
     "The huntmaster pays for news of dens, and double for news of wasps.",
     "Hunters say the bog to the west has started singing at night."]))

# 11 Westfen: herb marsh
S.append(town("Westfen", "", "Herbs and peat: the marsh's boardwalks, reed huts and herb racks; the only healers who will walk into the fen.", "Herbwives and Boardwalk", "Westfen Herb Walk", 22,
    [P("free:buildings/hut_wood_vine@4.8", 0, -9, 0, 1), P("free:buildings/hut_long_thatch@4.4", -13, -4, 70, 1),
     P("free:water/dock_weathered_pier@0.6", 0, 4, 0, 0)]
    + [P("free:flora/mushrooms_blue_glow@0.9", -6 + 3 * i, 1.5 + (i % 2) * 1.2, 20 * i) for i in range(5)]
    + [P("free:flora/mushroom_redcap@0.7", 7, 0, 0), P("free:flora/mushroom_brown@0.6", 8.5, 2.5, 30), P("free:flora/mushroom_bowl_orange@0.8", 6, 3.2, 70)]
    + [P("free:flora/bellflower_purple@0.9", 10 + i * 1.4, 7, 0) for i in range(3)]
    + [P("nature:fern_a", -10 + i * 2.6, 9, 40 * i) for i in range(8)]
    + [P("free:fences/fence_woven_wattle@1.3", -8 + 3.2 * i, 6, 0) for i in range(4)]
    + [P("free:market/stall_potion@3.0", 12, -2, -70, 1), P("props/basket_produce", 9.5, 1, 0), P("nature:dead_snag", 14, -8, 0),
       P("props/lamp_post", 0, 12, 0)],
    [light(0, 3.4, 12, WARM, 9, True), light(-2, 0.9, 1.5, [0.4, 0.9, 1.0], 6, True)],
    npc("Nessa Fenn", "herbwife", "Herbalist", [3, 6.5], "Wipe your boots. The moss minds.",
        "Westfen's herbwives are the only healers who will walk the fen at night, and the boardwalk keeps the marsh from swallowing the road.",
        ["The toads are bigger this year. Bog toads. Long tongue, short temper. Don't step on the pretty ones.",
         "Westfen tea cures fever. It also cures company. People don't stay to ask for a second cup.",
         "Something sings under the boards when the wind is west. The Veyl rangers say it is only the marsh."]),
    ["The bog toads are bigger this year. Long tongue, short temper.",
     "Westfen tea cures fever. It also cures company.",
     "Something sings under the boards when the wind is from the west.",
     "Veyl rangers passed through, speaking of a black fen further south-west."]))

# 12 Ironmarch = Silverford: guild town
S.append(town("Ironmarch", "Silverford", "Crafts and contracts: the Masons' and Runecarvers' Guild, the Merchants' Hall and the Adventurers' branch all keep hall here by the ford.", "Guild Town on the Ford", "Silverford Guild Hall", 30,
    [P("r1:silverford/guildhall_silverford", 0, -12, 0, 1), P("free:buildings/house_stone_fantasy@8.0", -17, -10, 70, 1),
     P("free:market/stall_blue_shields@3.0", 11, 3, -80, 1), P("free:market/stall_small_workshop@3.0", -11, 4, 80, 1),
     P("free:market/stall_potion@3.0", 13, -4, -60, 1), P("r1:stones/road_stone_a_slab", -6, 8, 0, 1), P("r1:stones/road_stone_d_pillar", 6, 8, 0, 1),
     P("free:banners/banner_stand_tall_narrow@4.4", -7, 11, 0), P("free:banners/banner_stand_tall_narrow@4.4", 7, 11, 0),
     P("props/well", 0, 4, 0, 1), P("props/notice_board", -9, 9, 0), P("props/crate_stack", 9, -8, 0), P("gen:bunting@1.0", 0, 11.5, 0),
     P("props/lamp_post", -3, 12, 0), P("props/lamp_post", 3, 12, 0), P("props/bench", 4, 7.5, 90)],
    [light(-3, 3.4, 12, WARM, 10, True), light(3, 3.4, 12, WARM, 10, True), light(0, 3.0, 6, COOL, 9, False)],
    npc("Odrin Thale", "Guildmaster of Runecarvers", "Noble", [0, -5.5], "Irritatingly clean, my ledgers. You may look.",
        "Silverford is where the vale's crafts are licensed: no stone is carved, no contract sealed and no caravan weighed without the Guild's mark.",
        ["The Guild holds the only licence to cut a waystone. The Crown holds the only licence to be angry about it.",
         "A Solkar mistress has paid the Hall in sunstone oil. It burns silver. Nobody asks how.",
         "We count stones for the Runeward. The count, I confess, has been... generous."]), 
    ["The Guild alone may cut a waystone; the Crown alone may be angry about it.",
     "A Solkar caravan mistress paid the Hall in sunstone oil. It burns silver.",
     "The Merchants' Hall is buying iron at any price. Somebody is arming somebody.",
     "Guild ledgers say forty stones are lit. Wardens say twenty-six. One of them is counting wrong."],
    doors=[{"scene": "res://scenes/interiors/guildhall_interior.tscn", "at": [0, -5.0], "yaw": 0.0, "prompt": "Enter the Guild Hall"}]))

# 13 Saltwick: salt works
S.append(town("Saltwick", "", "Salt and dried fish: the far south-west's salt pans and fish-racks, every wagon south of the stones smells of Saltwick.", "Salt Pans and Fisheries", "Saltwick Salt Works", 24,
    [P("free:buildings/lumber_mill@6.5", 0, -10, 0, 1)]
    + [P("props/sack_pile", -9 + 2.8 * i, 0.5, 30 * i) for i in range(6)]
    + [P("props/barrel", -8 + 2.2 * i, 5, 0) for i in range(4)]
    + [P("free:props/barrels_crates_stack@1.8", 11, -1, -60, 1), P("free:market/stall_crates_cream@2.8", 10, 6, -70, 1),
       P("gen:rowboat@1.0", -12, 8, 30, 0), P("gen:rowboat@1.0", -15, 4, -20, 0), P("gen:pier@0.7", -10, 12, 90, 0),
       P("free:fences/fence_rail_orange@1.2", 3, -1, 0), P("free:fences/fence_rail_orange@1.2", 6.2, -1, 0),
       P("free:carts/cart_hand_long@1.8", 7, 10, 40, 1), P("props/lamp_post", 0, 13, 0), P("props/water_trough", -3, 9, 0),
       P("props/crate_stack", 13, 8, 0)],
    [light(0, 3.4, 13, WARM, 9, True)],
    npc("Orla Saltmaster", "salt-master", "Innkeeper", [3, 6.5], "Lick the wall if you don't believe me.",
        "Saltwick's pans are the vale's pantry: salted fish and sea-salt go north along the frontier road, and nothing keeps a winter like Saltwick salt.",
        ["A pinch of Saltwick salt on the doorstep keeps the small dark things out. Also the neighbours.",
         "The last caravan never made it past the Emberfall Roadhouse. Bandits, or worse: bad weather.",
         "Frontier roads have few stones. We salt the verge. Wolves hate a salted track."]),
    ["A pinch of salt on the doorstep keeps small dark things out, say Saltwick folk.",
     "The last salt caravan never made it past the Emberfall Roadhouse.",
     "Wolves hate a salted track; Saltwick salts its verges where the stones are few.",
     "The far pans have a sheen no salt should have."]))

# 14 Cindermoor: charcoal
S.append(town("Cindermoor", "", "Charcoal and smelting: Cindermoor's kilns burn the moorland oak that feeds the vale's forges.", "Charcoal Burners", "Cindermoor Kilns", 24,
    [P("mine/miners_hut", 10, -8, -60, 1)]
    + [P("props/woodpile", -10 + 3.2 * i, -6 + (i % 2) * 2.5, 15 * i) for i in range(5)]
    + [P("mine/ore_pile_coal", -8, 0, 0), P("mine/ore_pile_coal", -3, 2.5, 50), P("mine/ore_pile_coal", 3, 0.5, 120), P("mine/ore_pile_coal", 8, 3, 200),
       P("mine/mine_cart", 11, 3, 90, 1), P("mine/rail_straight", 11, 7, 0), P("mine/rail_end", 11, 11, 0),
       P("ruins/campfire", -1, -1, 0), P("nature:stump_broken", -13, 4, 0), P("nature:stump_broken", -15, 8, 40),
       P("free:carts/cart_plain_b@2.2", -9, 9, -30, 1), P("props/barrel", 6, 8, 0), P("props/lamp_post", 0, 13, 0)]
    + [P("nature:dead_snag", -14 + 2 * i, -14, 40 * i) for i in range(4)],
    [light(-1, 0.9, -1, HOT, 11, True), light(-8, 1.0, 0, HOT, 7, True), light(0, 3.4, 13, WARM, 9, True)],
    npc("Dov Sutt", "charcoal burner", "Rogue", [2, 6], "Don't breathe near the kiln. Or do. I'm not your mother.",
        "Cindermoor burns the moorland oak to charcoal; every forge from Stonehollow to Highcliff cooks on Cindermoor black.",
        ["Smoke on the moor after dusk is ours. If it's smoke you can't smell, it isn't.",
         "Charcoal costs more this year. The forests are thinner. Somebody is cutting beyond the ward.",
         "The far kiln was cold when I woke. No fire, no ash, not even the scorch on the ground. Odd."]),
    ["Smoke on the moor after dusk is ours. If you can't smell it, it is not.",
     "Charcoal costs more this year: someone is cutting trees beyond the ward.",
     "A kiln went cold overnight with no ash and no scorch left.",
     "Dov Sutt swears the old moor road has a stone nobody carved."]))

# 15 Dunhallow: carters and wheelwrights
S.append(town("Dunhallow", "", "Carts and wheels: the wheelwrights and carters of the north-west, where every wagon on the vale's roads was mended at least once.", "Wheelwrights and Carters", "Dunhallow Wagon Yard", 26,
    [P("free:carts/wagon_covered@3.2", -8, -4, 30, 1), P("free:carts/cart_thatched_roof@2.6", 2, -8, 0, 1), P("free:carts/cart_apothecary@2.6", 11, -3, -80, 1),
     P("free:carts/cart_two_wheel@2.0", -13, 3, 70, 1), P("free:carts/cart_plain_a@2.2", 10, 7, -50, 1), P("free:carts/cart_hand_long@1.8", -4, 6, 10, 1),
     P("free:buildings/smithy_tiled_house@6.4", 0, -15, 0, 1), P("props/covered_wagon", 15, 4, -100, 1), P("props/woodpile", -15, -8, 0),
     P("props/anvil_stump", 4, -4, 30), P("props/barrel", 7, 3, 0), P("props/hay_bales", -8, 10, 10), P("props/water_trough", 6, 10, 90),
     P("free:farm/wheelbarrow_planter@1.0", -1, 10, 40), P("props/lamp_post", 0, 13, 0), P("props/lamp_post", -7, 13, 0)],
    [light(0, 3.4, 13, WARM, 9, True), light(-7, 3.4, 13, WARM, 9, True)],
    npc("Wynn Cartwright", "master wheelwright", "Barbarian", [2, 7], "Never trust a wheel that squeaks. It's telling you something.",
        "Dunhallow mends the wheels of the world: every caravan that crosses the vale's far roads stops here for an axle and a bowl of soup.",
        ["A wheel lasts four hundred miles on stone road and forty on none. Do the maths on the frontier.",
         "I fixed a Solkar wagon. Wheels were different. Wider. They roll in sand, so, fewer stones.",
         "The Dunhallow road to Ashford is the longest ungarrisoned track in the vale. Take a spare axle."]),
    ["A wheel lasts four hundred miles on stone road and forty on none.",
     "Dunhallow fixed a Solkar wagon with wide desert wheels. Carters are still arguing.",
     "The Dunhallow road to Ashford is the longest ungarrisoned track in the vale.",
     "A wagon-train lost a wheel near the old beacon and the carters came home without a driver."]))

# 16 Wolfsend: wolf hunters at the eastern frontier
S.append(town("Wolfsend", "", "Watch and wolf-hunting: the easternmost village, where the ditch-and-stake watch keeps an eye on the Eastern Gate road.", "Wolf Watch", "Wolfsend Watch Post", 22,
    [P("free:castle/watchtower_stone_small@9.0", 0, -10, 0, 1)]
    + [P("free:fences/fence_palisade@3.2", -12 + 3.2 * i, -2, 0, 1) for i in range(3)]
    + [P("free:fences/fence_palisade@3.2", 5 + 3.2 * i, -2, 0, 1) for i in range(3)]
    + [P("free:lighting/torch_stake@2.0", -5, 3, 0), P("free:lighting/torch_stake@2.0", 5, 3, 0),
       P("free:banners/banner_ragged_spear@3.6", -9, 7, 0), P("free:banners/banner_ragged_spear@3.6", 9, 7, 0),
       P("free:creatures/wolf_dark@0.9", -2, 6, 160), P("free:creatures/wolf_grey@0.9", 2.5, 7.5, 210),
       P("props/weapon_rack", 10, -5, -90), P("props/woodpile", -11, -6, 0), P("ruins/campfire", 0, 2, 0),
       P("props/hay_bales", 12, 4, 30), P("props/lamp_post", 0, 12, 0)],
    [light(0, 0.8, 2, HOT, 10, True), light(-5, 2.6, 3, HOT, 6, True), light(5, 2.6, 3, HOT, 6, True)],
    npc("Carrow Dunmere", "wolf-warden", "Hunter", [2, 5.5], "Eastward is the Gate. Westward is home. Wolves are everywhere.",
        "Wolfsend is the vale's last village before the Eastern Gate: its watchmen turn back pilgrims, hunt wolves and sell wolf-tooth luck.",
        ["The Gate's shut. Church's order. Pilgrims queue at the ditch and wait. We feed them, nobody asked.",
         "Wolves come at dawn this month, not dusk. Hunters say it's the moon. The hunters are wrong.",
         "A rider came through at night, sunlit banner under his cloak. He did not stop. Horse was lathered."]),
    ["The Eastern Gate is shut by the Patriarch's order. Pilgrims queue at the ditch.",
     "Wolves come at dawn this month, not at dusk.",
     "A rider with a sun-banner under his cloak crossed at night and did not stop.",
     "Wolf-tooth luck sells well in Wolfsend. Hunters wear it; the pilgrims buy it."]))

# 17 Harrowgate: southern gate, Solkar staging
S.append(town("Harrowgate", "", "The south gate of the vale: every caravan from the Solkar road stages here, and the harrow arch marks the last stones before the desert track.", "The Southern Gate", "Harrow Arch and Caravan Stage", 28,
    [P("free:ruins/arch_baroque_old@9.0", 0, -4, 0, 1), P("gen:bunting@1.0", 0, -3, 0)]
    + [P("free:camp/tent_conical_striped@4.2", -13, -7, 60, 1), P("free:camp/tent_conical_striped@4.2", 13, -8, -60, 1),
       P("free:market/stall_potion@3.0", -10, 4, 80, 1), P("free:market/stall_fruit_cream@3.0", 10, 3, -80, 1),
       P("free:carts/wagon_covered@3.2", -15, 5, 70, 1), P("props/covered_wagon", 15, 6, -70, 1), P("road/caravan_wagon", 8, 10, -20, 1),
       P("props/sack_pile", -6, 6, 0), P("props/sack_pile", -5, 7.6, 40), P("props/barrel", 6, 6, 0), P("props/crate_stack", 4, 8, 0),
       P("free:banners/banner_stand_spear_flag@4.4", -5, 12, 0), P("free:banners/banner_stand_spear_flag@4.4", 5, 12, 0),
       P("props/lamp_post", -2.5, 13.5, 0), P("props/lamp_post", 2.5, 13.5, 0), P("free:flora/stump_dead_tall@3.0", 17, -2, 0)],
    [light(-2.5, 3.4, 13.5, WARM, 9, True), light(2.5, 3.4, 13.5, WARM, 9, True), light(0, 4.0, -3, [1.0, 0.8, 0.45], 11, True)],
    npc("Kavi ar-Sunhaven", "Solkar spice merchant", "Trader", [-7, 6], "Saffron, cardamom, sunstone salt. Smell first, argue after.",
        "Harrowgate is the vale's southern door: the Solkar caravans from the desert come up this road, and the spice smell reaches Emberfall on a south wind.",
        ["Midsummer we go north to the Fair at Silverford. The spice price doubles by the Guild's hall. It's fair, it's only mathematics.",
         "Our wagons have wide wheels for sand. Your stone roads are too narrow. We drive on the verge. The verge is quite full.",
         "Sunstone oil burns silver. A drop on a dark stone makes it glow for an hour. Don't tell the Runeward; they'd buy all of it."]),
    ["Solkar caravans are due at the Midsummer Fair. The spice price doubles by Silverford.",
     "Sunstone oil, a drop on a dark stone, makes it glow for an hour. The Runeward would buy all of it.",
     "The south road is quiet but for Solkar wagons, and the wagons say it is very busy in the desert.",
     "An old arch on the south road: the Harrow. Nobody knows who built it. The spice-merchants bow."]))

# 18 Emberfall: glass kiln and fallen star
S.append(town("Emberfall", "", "Glass and ember-crystal: a star fell here in the old days, and Emberfall's glassblowers have worked its red glass since.", "Glass Kilns and the Fallen Star", "Emberfall Glass Kiln", 22,
    [P("free:magic/crystal_red_pedestal@2.4", 0, -6, 0, 1), P("free:magic/orb_red_stand@1.6", -5, -3, 0, 0), P("free:buildings/hut_long_thatch@4.6", 11, -7, -60, 1)]
    + ring("nature:rock_cluster", 8, 8.5, 0, -6, True)
    + [P("props/anvil_stump", -7, 3, 20), P("free:market/stall_potion@3.0", 10, 3, -80, 1), P("props/barrel", 6, 7, 0),
       P("props/crate_stack", -9, 6, 10), P("free:magic/crystal_red_pedestal@1.2", 5, 3, 0, 0), P("props/lamp_post", 0, 13, 0),
       P("ruins/campfire", -2.5, 2, 0), P("nature:flowers_warm", 4, 8, 0), P("nature:flowers_warm", -4, 9, 0)],
    [light(0, 2.4, -6, [1.0, 0.45, 0.3], 14, True), light(-2.5, 0.9, 2, HOT, 9, True), light(0, 3.4, 13, WARM, 8, True)],
    npc("Teyo Emberglass", "glasswright", "Innkeeper", [3, 5.5], "Red glass, hot and honest. Mind the heat.",
        "Emberfall's red glass is the vale's rarest craft: the fallen star's crystal gives it its glow, and the lantern-makers of Silverford pay in silver.",
        ["The crystal hums when the stones dim. I'm not saying it means anything. I'm saying it hums.",
         "Wind from the south brings spice. Wind from the west brings cold. Wind from the Scar brings nothing. That's worse.",
         "A Solkar trader wanted a window for a desert temple. I made it. It was the reddest thing I have ever seen."]),
    ["Emberfall's crystal hums whenever a stone goes dim.",
     "Wind from the south brings spice, the west brings cold. Wind from the Scar brings nothing, and that is worse.",
     "The lantern makers of Silverford pay in silver for Emberfall red glass.",
     "A fallen-star fragment went missing from the kiln. The glass was bluer the next day."]))

# 19 Ravenscar: trappers below Grimfen Pass
S.append(town("Ravenscar", "", "Furs and ravens: the last village before Grimfen Pass, where trappers watch the snowline and ravens watch the trappers.", "Trappers below the Pass", "Ravenscar Raven Tower", 22,
    [P("free:castle/watchtower_stone_small@10.0", 0, -10, 0, 1), P("nature:dead_snag", -8, -4, 0), P("nature:dead_snag", 9, -6, 90),
     P("free:camp/tent_hide_hut@3.4", -12, 3, 50, 1), P("free:camp/tent_hide_hut@3.4", 12, 2, -50, 1),
     P("props/weapon_rack", -6, 4, 90), P("props/woodpile", 7, 3, 0), P("ruins/campfire", 0, 2.5, 0),
     P("free:banners/banner_ragged_spear@3.6", -4, 9, 0), P("free:banners/banner_ragged_spear@3.6", 4, 9, 0),
     P("free:props/chest_dark_iron@0.8", 3, -3, 0), P("r1:landmarks/giant_tusk", -15, -8, 40), P("props/lamp_post", 0, 13, 0)]
    + [P("nature:spruce_a", -17 + 3.4 * i, -16, 30 * i, 1) for i in range(3)],
    [light(0, 0.9, 2.5, HOT, 9, True), light(0, 3.4, 13, WARM, 8, True), light(0, 11, -10, [0.6, 0.9, 1.0], 12, False)],
    npc("Ulla Crowe", "trapper", "Hunter", [-3, 6], "Ravens are listening. Don't say anything you'd regret.",
        "Ravenscar trades furs for grain: the trappers know the snowline, and they are the only ones who have seen Grimfen Pass this century.",
        ["The Pass has been shut since the Long Dark. Snow is the lock. The key is spring, if spring ever comes up there.",
         "We've found bones bigger than a cart below the ridge. Horned. Frosted. Nothing alive has horns that long.",
         "On clear winter nights the north sky goes green. The ravens go quiet. So do we."]),
    ["The Pass has been shut since the Long Dark. Snow is the lock, and spring is the key.",
     "Trappers found bones bigger than a cart below the ridge. Horned, and frosted.",
     "On clear winter nights the north sky goes green and the ravens go quiet.",
     "A Highwatch knight came up to watch the snowline. He stayed three days and left his tent."]))

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "settlements.json"), "w") as f:
    json.dump({"version": 1,
               "_doc": "Package C2: one trade, landmark, named NPC and rumour set per settlement (WorldGen NAMES order = settlement id). `alias` = the poster name shown instead (Oakvale = Greenhollow, Ironmarch = Silverford). Landmark parts use the RegionSites part format plus 'free:'/'r1:' keys (see tools/region1/gen_world_data.py). Consumed by scripts/world/region1_world.gd (sites) and scripts/world/region1_identity.gd (rumours).",
               "settlements": S}, f, indent=1)
print("settlements", len(S))


# ---------------------------------------------------------------------------------------------------------------------
# C1 / C10 canon sites: data/region1/world/sites.json. Each has a `search` block (where RegionSites-style placement looks):
#   center: [x, z] | "settlement:<Name>" | "site:<name>" ; d: [min, max] metres; a: [min, max] radians (0 = +x east, -pi/2 = north)
#   r: footprint for the free-ground test; slope: max slope; prefer_high: weight on height; flatten; clear
# ---------------------------------------------------------------------------------------------------------------------
def highwatch_parts():
    site = json.load(open("assets/incoming/region1/highwatch/highwatch_site.json"))
    collide = {"wall_14", "tower_round", "watchtower", "keep", "well", "guard_post"}
    parts = []
    for p in site["placements"]:
        piece = p["piece"]
        x, y, z = p["pos"]
        parts.append(P("r1:highwatch/" + piece, x, z + 17.3, p["yaw_deg"], piece in collide, y))
    parts.append(P("r1:highwatch/banner_pole", -7.5, 27, 0))
    parts.append(P("r1:highwatch/banner_pole", 7.5, 27, 0))
    return parts


def chain_road_stones(n, x0, y0, dx, dy, start="a"):
    return []


SITES = []

SITES.append({
    "id": "highwatch_keep", "name": "Highwatch Keep", "kind": "keep", "clear": 42, "flatten": True,
    "search": {"center": "settlement:Highcliff", "d": [190, 460], "a": [-2.45, -0.7], "r": 42, "slope": 0.2, "prefer_high": 0.04, "d_pref": 290, "face": "center"},
    "parts": highwatch_parts(),
    "lights": [light(-6, 3.6, 18.5, HOT, 10, True), light(6, 3.6, 18.5, HOT, 10, True), light(0, 7.0, 1.5, WARM, 14, True), light(0, 4.5, 27, COOL, 12, False)],
    "x": {"label": {"text": "HIGHWATCH KEEP", "sub": "Order of the Highwatch", "at": [-10.5, 29], "h": 3.4},
          "npcs": [npc("Sir Rowan Ashby", "knight-captain of the Highwatch", "Plate_Knight", [0, 6.5], "You look like you can carry a spear. Can you carry it upright?",
                       "Highwatch Keep holds the north pass: the Order's knights and Ember Lancers drill in this yard, and their banners are the first thing a northerner sees of Valencious.",
                       ["The Order holds the pass. The pass holds the snow. The snow holds the north. I'd rather it held longer.",
                        "A knight is a spearman who did not quit. I'd add 'and cleaned his own armour'.",
                        "Grimfen Pass has been snowed shut since the Long Dark. Something up there is watching the drifts. We watch it back."], 0)],
          "people": [{"look": "Guard", "at": [-6, 16.6], "yaw": 0}, {"look": "Guard", "at": [6, 16.6], "yaw": 0},
                     {"look": "Knight", "at": [-16, 8], "yaw": 70}]},
    "town": "Highcliff",
    "hooks": "Elder Stone (elder_highwatch) stands before the gate; Sir Rowan Ashby (quest id rowan_ashby) in the yard; oath site: the Wyrm's Ribs to the north."
})

SITES.append({
    "id": "elder_highwatch", "name": "Highwatch Elder Stone", "kind": "elder_stone", "clear": 10, "flatten": False,
    "search": {"relative_to": "highwatch_keep", "offset": [0, 27]},
    "parts": [P("r1:stones/elder_stone", 0, 0, 0, 1)] + [P("r1:stones/road_stone_a_slab" if i % 2 == 0 else "r1:stones/road_stone_d_pillar", (-5.5 if i < 2 else 5.5), 4.5 + 6 * (i % 2) - 6, 0, 1) for i in range(4)],
    "lights": [light(0, 5.6, 0.5, COOL, 12, False)],
    "hooks": "Elder Stone elder_highwatch: before the keep gate (Act IV, Rowan's ember)."
})

SITES.append({
    "id": "elder_greyseam", "name": "Greyseam Elder Stone", "kind": "elder_stone", "clear": 16, "flatten": True,
    "search": {"center": "site:Greyseam Mine", "d": [48, 130], "a": [-3.14159, 3.14159], "r": 14, "slope": 0.22, "prefer_high": 0.02, "d_pref": 70, "face": "none"},
    "parts": [P("r1:stones/elder_stone", 0, 0, 0, 1)] + [P("r1:rift/crystals/scar_crystal_%s" % k, cx, cy, yw, 0) for k, cx, cy, yw in
              [("a", 5.5, 3.0, 20), ("b", -6.0, 2.2, 140), ("c", 1.5, -6.4, 250), ("a", -4.2, -4.5, 60)]]
             + [P("r1:stones/road_stone_c_squat", -8, 6, 30, 1), P("nature:rock_cluster", 8, -3, 10), P("nature:boulder_large", -9, -6, 70, 1)],
    "lights": [light(0, 5.6, 0.5, COOL, 10, False), light(5.5, 1.0, 3.0, VIOLET, 6, True)],
    "x": {"label": {"text": "GREYSEAM ELDER STONE", "sub": "Where the rift seam runs under the hill", "at": [0, 9.5], "h": 2.6}},
    "hooks": "Elder Stone elder_greyseam (Act IV, Harrok as ally). Rift seam crystals mark the lower mine."
})

SITES.append({
    "id": "elder_elden", "name": "Elden Elder Stone", "kind": "elder_stone", "clear": 18, "flatten": True,
    "search": {"center": [-1180.0, -240.0], "d": [0, 300], "a": [-3.14159, 3.14159], "r": 14, "slope": 0.2, "prefer_high": 0.0, "d_pref": 0, "face": "east"},
    "parts": [P("r1:stones/elder_stone", 0, 0, 0, 1), P("free:ruins/ruin_arch_pillars@9.0", 0, -10, 0, 1), P("free:ruins/pillar_mossy_a@5.0", -8, -4, 20, 1),
              P("free:ruins/pillar_mossy_b@4.2", 8, -5, -30, 1), P("free:ruins/ruin_wall_broken_a@3.2", -11, -10, 10), P("free:ruins/ruin_wall_corner@3.0", 11, -11, -10),
              P("r1:stones/road_stone_a_slab", -5, 8, 0, 1), P("r1:stones/road_stone_d_pillar", 5, 8, 0, 1), P("nature:oak_b", -14, 4, 0, 1)],
    "lights": [light(0, 5.6, 0.5, COOL, 10, False)],
    "x": {"label": {"text": "THE ELDEN ROAD", "sub": "The old runestone road ends here", "at": [0, 11], "h": 2.6}},
    "hooks": "Elder Stone elder_elden (Act IV, Snikkit's 'lonely shiny'; ancestor stone). The Elden Road runs east to the Shrine of the Sleeping Flame."
})

SITES.append({
    "id": "crownstead_estate", "name": "Crownstead Steward's Hall", "kind": "estate", "clear": 28, "flatten": True,
    "search": {"center": [430.0, -190.0], "d": [120, 320], "a": [-3.14159, 3.14159], "r": 28, "slope": 0.14, "prefer_high": 0.0, "d_pref": 180, "face": "center"},
    "parts": [P("free:buildings/house_stone_fantasy@9.0", 0, -8, 0, 1), P("farm/granary", -13, -6, 30, 1), P("farm/barn", 14, -8, -80, 1),
              P("r1:highwatch/banner_pole", -5, 7, 0), P("r1:highwatch/banner_pole", 5, 7, 0), P("props/well", 0, 5, 0, 1), P("props/notice_board", -8, 8, 0),
              P("props/hay_bales", 10, 2, 20), P("props/water_trough", 12, 5, 90), P("props/lamp_post", -2.5, 9.5, 0), P("props/lamp_post", 2.5, 9.5, 0)]
             + [P("farm/crop_wheat", -16 + 4.1 * c, 10 + 4.1 * r, 0) for r in range(3) for c in range(3)]
             + [P("farm/crop_cabbage", 6 + 4.1 * c, 11 + 4.1 * r, 0) for r in range(2) for c in range(3)]
             + [P("nature:young_oak", -18 + 6 * i, -17, 25 * i, 0) for i in range(6)]
             + [P("free:fences/fence_farm_white@1.3", -18 + 3.2 * i, 24, 0) for i in range(12)],
    "lights": [light(-2.5, 3.4, 9.5, WARM, 9, True), light(2.5, 3.4, 9.5, WARM, 9, True)],
    "x": {"label": {"text": "CROWNSTEAD", "sub": "The Crown's farms", "at": [0, 15.5], "h": 3.3},
          "npcs": [npc("Steward Alaric Penhallow", "Crown steward", "Noble", [3.5, 7], "The Crown's wheat, the Crown's tithe, the Crown's good opinion. Pick two.",
                       "Crownstead farms the land between Ashford and Kingsreach for the Crown: the royal granaries are here, and so is the great hill with the three windmills.",
                       ["The Crown's hill has a stone on it older than the Crown. The Crown would like it to stay quiet.",
                        "Kingsreach takes two parts in three. The Church envoy has asked for a tenth. The Steward has asked for a holiday.",
                        "Tithe wagons leave at dawn. Not one has failed. Not one has been searched. That should tell you something."], 200)]},
    "town": "Crownstead",
    "hooks": "Crownstead (registry place crownstead): beside the look agent's Crownstead Mill Hill and its Elder Stone; Steward Alaric; Act IV two ash layers."
})

SITES.append({
    "id": "eastern_gate", "name": "The Eastern Gate", "kind": "border_gate", "clear": 46, "flatten": True, "locked": True,
    "hint": "Closed by order of the Aurelis Patriarchate. The Church realms lie beyond.",
    "search": {"center": "settlement:Wolfsend", "d": [330, 520], "a": [-0.6, 0.6], "r": 44, "slope": 0.22, "prefer_high": 0.0, "d_pref": 420, "face": "west"},
    "parts": [P("free:castle/gate_small_towers@10.5", 0, 0, 0, 0)]
             + [P("free:castle/gate_wall_long@6.0", -13, 0.5, 0, 1), P("free:castle/gate_wall_long@6.0", 13, 0.5, 0, 1)]
             + [P("free:fences/fence_palisade@3.6", -22 - 3.3 * i, 0.5, 0, 1) for i in range(5)] + [P("free:fences/fence_palisade@3.6", 22 + 3.3 * i, 0.5, 0, 1) for i in range(5)]
             + [P("road/checkpoint_barrier", -2.2, 3.5, 0, 0), P("road/checkpoint_barrier", 2.2, 3.5, 0, 0), P("free:props/crate_planks@1.2", -5, 3, 20), P("free:props/crate_planks@1.2", 5.5, 3.2, -20)]
             + [P("road/toll_booth", -10, 8, 0, 1), P("props/notice_board", 9, 8.5, 0), P("props/lamp_post", -4, 9.5, 0), P("props/lamp_post", 4, 9.5, 0),
                P("r1:highwatch/banner_pole", -8, 4.5, 0), P("r1:highwatch/banner_pole", 8, 4.5, 0)]
             + [P("free:camp/tent_camp_a@3.4", -18, 11, 40, 1), P("free:camp/tent_camp_b@3.4", -22, 16, 70, 1), P("free:camp/tent_camp_a@3.4", 18, 12, -40, 1),
                P("ruins/campfire", -13, 14, 0), P("ruins/campfire", 13, 15, 0), P("props/covered_wagon", 22, 19, -90, 1), P("props/hay_bales", -22, 9, 10)]
             + [P("free:banners/banner_gold_finials@6.0", -5, -4, 180), P("free:banners/banner_gold_finials@6.0", 5, -4, 180),
                P("free:banners/banner_gold_finials@6.0", -5, -12, 180), P("free:banners/banner_gold_finials@6.0", 5, -12, 180),
                P("free:camp/tent_conical_striped@5.0", -10, -10, 160, 1), P("free:camp/tent_conical_striped@5.0", 11, -11, 200, 1),
                P("free:churches/chapel_tan_tiled@8.5", 0, -26, 180, 1), P("ruins/campfire", 0, -8, 0)],
    "lights": [light(-4, 3.4, 9.5, WARM, 9, True), light(4, 3.4, 9.5, WARM, 9, True), light(-13, 0.9, 14, HOT, 8, True), light(13, 0.9, 15, HOT, 8, True),
               light(0, 1.0, -8, [1.0, 0.85, 0.5], 14, True)],
    "x": {"label": {"text": "THE EASTERN GATE", "sub": "Closed by the Patriarch's order", "at": [0, 13.5], "h": 3.4},
          "npcs": [npc("Border-Sergeant Hale", "Gate sergeant", "Guard", [-2.5, 6], "Gate's shut. Church's order, not ours. Don't shout at me, I voted against it.",
                       "The Eastern Gate is Valencious's door to the Church realms; it has been closed by the Aurelis Patriarchate's order since the tithe quarrel.",
                       ["Pilgrims wait at the ditch. We feed them. The Church says they're to be turned back. The Church doesn't feed them.",
                        "A sun-banner rider came through last month. He had papers. Real ones. Nobody has come since.",
                        "Beyond the gate is Varska to the north and Serathi to the south. Both answer to the Dawn Throne in Aurelis."], 0),
                 npc("Pilgrim Anselm", "turned-back pilgrim", "Monk", [3, 9], "Third time turned back. The fourth will be the charm.",
                     "Pilgrims come from the west to walk the Dawn Road to Aurelis; the Gate's closing has left hundreds waiting on this side.",
                     ["They say the Patriarch wants the runestones replaced with Dawn relics. The road is shut until Valencious agrees.",
                      "I carry a prayer for the Hierarch. It weighs nothing, but I'll wait all winter to deliver it."], 180)],
          "people": [{"look": "Monk", "at": [-1.5, 8.5], "yaw": 180}, {"look": "Rogue_Hooded", "at": [0.5, 10.0], "yaw": 180}, {"look": "Mother", "at": [1.6, 8.0], "yaw": 180},
                     {"look": "Elder_Man", "at": [-3.5, 9.8], "yaw": 170}, {"look": "Guard", "at": [-3.2, 1.5], "yaw": 0}, {"look": "Guard", "at": [3.2, 1.5], "yaw": 0}]},
    "hooks": "C10 border tease east. Locked exit: Church realms (Aurelis, Varska, Serathi). Pilgrims turned back; Lucan's chapel in Kingsreach."
})

SITES.append({
    "id": "grimfen_pass", "name": "Grimfen Pass", "kind": "pass", "clear": 30, "flatten": False, "locked": True,
    "hint": "Snowed shut since the Long Dark. The Frostcrown Holds lie beyond.",
    "search": {"center": [120.0, -3480.0], "d": [0, 520], "a": [-3.14159, 3.14159], "r": 24, "slope": 0.3, "prefer_high": 0.12, "d_pref": 0, "face": "south"},
    "parts": [P("nature:spruce_a", -24 + 4.4 * i, -10 - (i % 3) * 3, 40 * i, 1) for i in range(12)]
             + [P("free:nature/rock_limestone_tall@8.5", -17, -3, 30, 1), P("free:nature/rock_limestone_tall@9.5", 17, -4, 200, 1), P("free:nature/rock_blue_brown@5.5", -11, 4, 80, 1), P("free:nature/rock_blue_brown@5.0", 12, 3, 10, 1)]
             + [P("free:fences/fence_palisade@3.6", -9 + 3.3 * i, 0, 0, 1) for i in range(6)]
             + [P("r1:landmarks/giant_tusk@4.0", -7, 6, 30), P("r1:landmarks/giant_skull@3.2", 9, 7, 200), P("nature:dead_snag", -4, 10, 0), P("nature:dead_snag", 6, 12, 90)]
             + [P("free:camp/tent_hide_hut@3.4", -14, 12, 60, 1), P("free:camp/tent_hide_hut@3.4", 14, 13, -60, 1), P("ruins/campfire", 0, 9, 0),
                P("props/weapon_rack", -6, 10, 90), P("r1:highwatch/banner_pole", -4, 14, 0), P("r1:highwatch/banner_pole", 4, 14, 0), P("props/woodpile", 10, 10, 0)],
    "lights": [light(0, 0.9, 9, HOT, 10, True), light(0, 14, -8, [0.45, 1.0, 0.75], 34, False), light(-8, 12, -4, [0.5, 0.75, 1.0], 28, False)],
    "x": {"label": {"text": "GRIMFEN PASS", "sub": "Snowed shut since the Long Dark", "at": [0, 16], "h": 3.4},
          "mounds": [{"at": [-15 + 3.0 * i, -3.0 - 1.2 * (i % 2)], "r": 3.6 + (i % 3) * 0.7, "h": 3.4 + (i % 4) * 0.55} for i in range(11)]
                    + [{"at": [-9 + 4.5 * i, -7.5], "r": 4.8, "h": 5.2 + i * 0.3} for i in range(5)]
                    + [{"at": [-18, 6], "r": 3.0, "h": 2.0}, {"at": [18, 7], "r": 3.4, "h": 2.4}],
          "npcs": [npc("Watch-Knight Brannoch", "pass-watch of the Order", "Knight", [3, 8.5], "Keep your cloak on. The drift listens.",
                       "Grimfen Pass is the road north to the Frostcrown Holds; it has been snowed shut since the Long Dark, and the Order keeps a winter watch on the drift.",
                       ["The drift moved last night. I swear it. Snow doesn't move. This did.",
                        "On clear winter nights the sky goes green above the pass. The horses won't graze. Neither will I.",
                        "Frost-horned bones on the ridge: the Wyrm's Ribs is only the smallest. Nothing has come down from the Holds since."], 180)]},
    "hooks": "C10 border tease north. Locked exit: Frostcrown Holds. Bones (tusk, skull) from the Wyrm's Ribs kit; aurora lights."
})

SITES.append({
    "id": "scar_arena", "name": "Scar Mouth Arena", "kind": "scar_arena", "clear": 28, "flatten": True,
    "search": {"center": "site:The Ashen Scar", "d": [44, 120], "a": [-3.14159, 3.14159], "r": 26, "slope": 0.22, "prefer_high": 0.0, "d_pref": 70, "face": "rift"},
    "parts": ring("r1:rift/crystals/scar_crystal_a", 6, 16, 0, 0, True)
             + ring("r1:rift/crystals/scar_crystal_b", 5, 20, 0, 0, True, start=25)
             + ring("r1:rift/crystals/scar_crystal_c", 4, 12, 0, 0, True, start=50)
             + ring("free:magic/runestone_ember@3.6", 6, 24, 0, 0, True, 1, 10)
             + [P("free:magic/portal_dark_purple@7.5", 0, -22, 0, 0), P("free:magic/crystal_red_pedestal@2.6", -9, -21, 20, 0), P("free:magic/crystal_purple_pedestal@2.6", 9, -21, -20, 0),
                P("nature:dead_snag", -20, -8, 0), P("nature:dead_snag", 21, -6, 90), P("nature:dead_snag", 0, 26, 40), P("nature:boulder_large", -22, 10, 40, 1), P("nature:boulder_large", 22, 11, 200, 1)],
    "lights": [light(0, 5.0, -21, VIOLET, 30, True), light(-9, 2.2, -20, [1.0, 0.35, 0.25], 12, True), light(9, 2.2, -20, [0.75, 0.45, 1.0], 12, True)],
    "x": {"label": {"text": "THE RIFT MOUTH", "sub": "An arena for the Scarbound", "at": [0, 29], "h": 2.8}},
    "hooks": "Finale arena: the Scarbound Troll fight (optional encounter, no gate). Two chambers glimpsed beyond: Ember (red) and Bloom (violet)."
})

SITES.append({
    "id": "dawn_chapel", "name": "Chapel of the Dawn Throne", "kind": "chapel", "clear": 20, "flatten": True,
    "search": {"center": "settlement:Kingsreach", "d": [240, 400], "a": [-0.9, 0.9], "r": 18, "slope": 0.16, "prefer_high": 0.0, "d_pref": 290, "face": "center"},
    "parts": [P("r1:silverford/chapel_dawn_throne", 0, 0, 0, 1), P("free:banners/banner_gold_finials@5.4", -4.5, 9, 0), P("free:banners/banner_gold_finials@5.4", 4.5, 9, 0),
              P("props/lamp_post", -3, 11, 0), P("props/lamp_post", 3, 11, 0), P("props/bench", -7, 9, 90), P("props/bench", 7, 9, -90),
              P("free:flora/bouquet_bright@0.8", -2.2, 8, 0), P("free:flora/bouquet_bright@0.8", 2.2, 8, 0), P("nature:bush_round", -8, 4, 0), P("nature:bush_round", 8.5, 5, 0),
              P("nature:bush_round", -8.5, -4, 0), P("nature:bush_round", 8.5, -5, 0), P("props/water_trough", 9.5, 10, 90)],
    "lights": [light(-3, 3.4, 11, WARM, 9, True), light(3, 3.4, 11, WARM, 9, True), light(0, 4.0, 7.2, [1.0, 0.85, 0.45], 10, True)],
    "x": {"label": {"text": "DAWN THRONE CHAPEL", "sub": "Envoy of the Aurelis Patriarchate", "at": [0, 15], "h": 3.4},
          "doors": [{"scene": "res://scenes/interiors/chapel_interior.tscn", "at": [0, 6.6], "yaw": 0.0, "prompt": "Enter the Chapel"}],
          "npcs": [npc("Envoy Lucan", "envoy of the Dawn Throne", "Noble", [3.5, 10], "Peace of the Dawn. Do sit. The stones will not mind.",
                       "The Church of the Dawn Throne keeps this mission chapel in Kingsreach: the envoy offers Dawn relics in place of runestones, and the Crown has not yet said no.",
                       ["A relic of the Dawn burns without tending. No carving, no keeping, no dying for it. Think what that would save you.",
                        "The Patriarch is patient. The Gate is closed because the tithe is open. I am only the envoy. I carry messages, not opinions.",
                        "Your runestones are lovely. Old. Brave. They are also, I am told, dimming. The Dawn never dims."], 200)],
          "people": [{"look": "Monk", "at": [-3.5, 9.5], "yaw": 160}, {"look": "Monk", "at": [5.5, 7.5], "yaw": 200}]},
    "hooks": "C10 envoy chapel: Envoy Lucan (quest id lucan). Interior chapel_interior via InteriorDoor (--shot=interior_chapel). Church tease, east."
})

SITES.append({
    "id": "solkar_camp", "name": "Solkar Caravan Camp", "kind": "caravan_camp", "clear": 22, "flatten": True, "season": "summer",
    "search": {"center": "settlement:Ironmarch", "d": [185, 330], "a": [-3.14159, 3.14159], "r": 22, "slope": 0.14, "prefer_high": 0.0, "d_pref": 230, "face": "center"},
    "parts": [P("free:camp/tent_conical_striped@4.6", -9, -3, 40, 1), P("free:camp/tent_conical_striped@4.6", 9, -3, -40, 1), P("free:camp/tent_conical_striped@4.6", -10, 7, 80, 1),
              P("free:camp/tent_conical_striped@4.6", 11, 7, -80, 1), P("free:carts/wagon_covered@3.2", -15, 1, 70, 1), P("free:carts/wagon_covered@3.2", 15, 3, -70, 1),
              P("free:market/stall_potion@3.0", -4, 11, 0, 1), P("free:market/stall_fruit_cream@3.0", 4, 11, 0, 1), P("free:market/stall_red_awning_goods@3.0", 0, 13.5, 0, 1),
              P("gen:bunting@1.0", 0, 10, 0), P("props/sack_pile", -7, 5, 20), P("props/sack_pile", -6, 6.6, 70), P("props/sack_pile", 7, 5, 0), P("props/crate_stack", 6, 7, 40),
              P("ruins/campfire", -2.5, 2, 0), P("ruins/campfire", 2.5, 2.5, 0), P("free:creatures/horse_saddled@2.0", -13, 9, 60), P("free:creatures/horse_saddled@2.0", 13, 10, -60),
              P("free:banners/banner_stand_spear_flag@4.6", -6, 14, 0), P("free:banners/banner_stand_spear_flag@4.6", 6, 14, 0), P("props/lamp_post", 0, 16, 0)],
    "lights": [light(-2.5, 0.9, 2, HOT, 10, True), light(2.5, 0.9, 2.5, HOT, 10, True), light(0, 3.4, 16, WARM, 9, True)],
    "x": {"label": {"text": "SOLKAR CARAVANS", "sub": "Midsummer Fair: spice, sunstone oil, saffron", "at": [0, 18.5], "h": 3.4},
          "npcs": [npc("Imra Solvane", "Solkar caravan mistress", "Trader", [0, 7.5], "Saffron. Sunstone oil. A fair price, which means a little more than you hoped.",
                       "The Solkar caravans come north each Midsummer: spice, sunstone oil and desert glass, sold at the Fair beside Silverford.",
                       ["Sunstone oil burns silver and does not smoke. Your Guild is buying all it can. I wonder what for.",
                        "Our roads are sand. Yours are stone. Both need tending; only one of them is on fire.",
                        "The Dominion sends its greetings and its prices. Mostly its prices."], 180)],
          "people": [{"look": "Trader", "at": [-5, 9], "yaw": 180}, {"look": "Rogue", "at": [6.5, 9.5], "yaw": 190}]},
    "town": "Ironmarch",
    "hooks": "C10: Solkar caravans at the Midsummer Fair (summer only; RegionDressing season gate). Imra Solvane (quest id imra_solvane)."
})

with open(os.path.join(OUT, "sites.json"), "w") as f:
    json.dump({"version": 1,
               "_doc": "Packages C1/C10 canon sites. Consumed by scripts/world/region1_world.gd: each entry is placed by its `search` block (free ground near a centre) and becomes a RegionSites site. Parts/lights/x as in settlements.json. Regenerate with tools/region1/gen_world_data.py.",
               "sites": SITES}, f, indent=1)
print("sites", len(SITES))
