extends RefCounted
## Farming data (Living World Stage 3, LW-3.1..3.3): crops, animals, buildings, climate and the land ladder, as plain
## constants plus a few pure static helpers. No state, no nodes. scripts/realm/farming.gd owns the farms; the per-field
## and per-animal maths live in farming_fields.gd and farming_herd.gd.
## Calendar: Seasons.DAYS_PER_SEASON = 28, so a year is 112 days; a field takes 14..28 growing days, so a field gives
## roughly two to four harvests a year depending on the crop and the season it is sown in.

const Seasons := preload("res://scripts/sim/seasons.gd")

const SPRING := 0
const SUMMER := 1
const AUTUMN := 2
const WINTER := 3

## Land ladder, lowest first. A rung is derived from what the person holds (farming.gd rung()).
const RUNGS := ["", "farmhand", "sharecropper", "tenant", "owner", "estate"]

## crop id -> {d growing days at full rate, s seasons it may be sown in, fam family, draw fertility taken at harvest (negative = restored),
##   y units per field at full soil, p base price, w water need 0..1, seed seed units to sow one field, hardy grows in winter,
##   clim yield multiplier [cold, temperate, dry]}
const CROPS := {
	"wheat": {"d": 24, "s": [0, 2], "fam": "grain", "draw": 0.10, "y": 40, "p": 2, "w": 0.35, "seed": 4, "hardy": false, "clim": [0.85, 1.0, 0.95]},
	"barley": {"d": 20, "s": [0, 1], "fam": "grain", "draw": 0.09, "y": 36, "p": 2, "w": 0.30, "seed": 4, "hardy": false, "clim": [1.0, 1.0, 0.95]},
	"peas": {"d": 14, "s": [0], "fam": "legume", "draw": -0.08, "y": 22, "p": 3, "w": 0.40, "seed": 2, "hardy": false, "clim": [0.95, 1.0, 0.8]},
	"broad_beans": {"d": 18, "s": [0, 2], "fam": "legume", "draw": -0.07, "y": 24, "p": 3, "w": 0.40, "seed": 2, "hardy": false, "clim": [1.0, 1.0, 0.85]},
	"turnip": {"d": 16, "s": [0, 1, 2, 3], "fam": "root", "draw": 0.08, "y": 45, "p": 2, "w": 0.30, "seed": 2, "hardy": true, "clim": [1.05, 1.0, 0.9]},
	"carrot": {"d": 18, "s": [0, 1, 2], "fam": "root", "draw": 0.08, "y": 36, "p": 3, "w": 0.40, "seed": 2, "hardy": false, "clim": [0.95, 1.0, 0.85]},
	"cabbage": {"d": 20, "s": [0, 1], "fam": "veg", "draw": 0.09, "y": 34, "p": 3, "w": 0.50, "seed": 2, "hardy": false, "clim": [0.9, 1.0, 0.75]},
	"onion": {"d": 18, "s": [0, 1], "fam": "veg", "draw": 0.08, "y": 30, "p": 3, "w": 0.35, "seed": 2, "hardy": false, "clim": [0.95, 1.0, 0.9]},
	"flax": {"d": 26, "s": [0, 1], "fam": "fibre", "draw": 0.12, "y": 24, "p": 6, "w": 0.40, "seed": 3, "hardy": false, "clim": [0.9, 1.0, 0.8]},
	"hops": {"d": 28, "s": [1], "fam": "hops", "draw": 0.14, "y": 20, "p": 8, "w": 0.55, "seed": 2, "hardy": false, "clim": [0.7, 1.0, 0.6]},
	"hay": {"d": 14, "s": [0, 1, 2], "fam": "fodder", "draw": -0.05, "y": 60, "p": 1, "w": 0.30, "seed": 2, "hardy": false, "clim": [0.9, 1.0, 0.8]},
}
const CROP_IDS := ["wheat", "barley", "peas", "broad_beans", "turnip", "carrot", "cabbage", "onion", "flax", "hops", "hay"]
## Crops that put fertility back (their family, or draw < 0).
const GOOD_ROTATION := ["wheat", "peas", "turnip", "barley", "broad_beans", "hay"]

## Per season: chance of rain a day, evaporation a day, how much one rain wets the soil, how fast pests / disease start.
const RAIN_P := [0.38, 0.18, 0.34, 0.30]
const EVAP := [0.09, 0.12, 0.07, 0.03]
const RAIN_AMOUNT := 0.55
const PEST_SEASON := [1.0, 1.6, 0.8, 0.1]
const DIS_SEASON := [1.2, 0.8, 1.4, 0.2]
## climate index: 0 cold, 1 temperate, 2 dry.
const CLIMATE_NAMES := ["cold", "temperate", "dry"]
const CLIM_GROWTH := [0.85, 1.0, 1.0]
const CLIM_RAIN := [1.05, 1.0, 0.5]
const CLIM_EVAP := [0.9, 1.0, 1.3]
const CLIM_BY_SID := [1, 1, 2, 0, 1, 2, 1, 0]
const START_FERTILITY := 0.80
## Calibration of the whole farm economy against the wage ladder (see tests/test_farming_career.gd and docs/design/LIVING_WORLD_SANDBOX.md Stage 3).
const YIELD_MULT := 1.15

## species -> {mat days to adulthood, old age, life max, gest days (eggs: brooding), litter max, lact lactation days,
##   prod item and rate per adult-day (wool: per shear), shear days between shearings, feed per day, feed items (first found),
##   price grown adult, young price, space shelter units, br daily conception chance in breeding seasons, meat}
const ANIMALS := {
	"cow": {"mat": 56, "old": 420, "life": 560, "gest": 34, "litter": 1, "lact": 40, "prod": "milk", "rate": 4.0, "shear": 0,
		"feed": 1.0, "items": ["hay", "turnip"], "price": 60, "young": 18, "space": 1.0, "br": 0.04, "meat": "beef"},
	"sheep": {"mat": 40, "old": 340, "life": 450, "gest": 20, "litter": 2, "lact": 0, "prod": "wool", "rate": 2.0, "shear": 56,
		"feed": 0.4, "items": ["hay", "turnip"], "price": 16, "young": 5, "space": 0.5, "br": 0.05, "meat": "mutton"},
	"horse": {"mat": 90, "old": 700, "life": 900, "gest": 44, "litter": 1, "lact": 0, "prod": "", "rate": 0.0, "shear": 0,
		"feed": 1.4, "items": ["hay", "barley"], "price": 140, "young": 45, "space": 1.5, "br": 0.025, "meat": ""},
	"pig": {"mat": 36, "old": 240, "life": 320, "gest": 16, "litter": 4, "lact": 0, "prod": "", "rate": 0.0, "shear": 0,
		"feed": 0.7, "items": ["turnip", "barley", "wheat"], "price": 20, "young": 5, "space": 0.5, "br": 0.05, "meat": "pork"},
	"chicken": {"mat": 20, "old": 180, "life": 240, "gest": 6, "litter": 3, "lact": 0, "prod": "egg", "rate": 0.7, "shear": 0,
		"feed": 0.15, "items": ["wheat", "barley"], "price": 3, "young": 1, "space": 0.15, "br": 0.08, "meat": "chicken"},
}
const SPECIES := ["cow", "sheep", "horse", "pig", "chicken"]
## Share of the daily feed that grazing covers, per season, when the farm has pasture for it.
const GRAZE := [0.8, 1.0, 0.7, 0.0]
## Specialisations: product multiplier, a price bonus on what it sells, and the building it needs.
const SPECS := {
	"": {"name": "Mixed", "mult": 1.0, "price": 1.0, "needs": ""},
	"dairy": {"name": "Dairy", "mult": 1.25, "price": 1.2, "needs": "barn", "species": "cow"},
	"wool": {"name": "Wool", "mult": 1.3, "price": 1.15, "needs": "", "species": "sheep"},
	"horse": {"name": "Horse stud", "mult": 1.3, "price": 1.25, "needs": "pen", "species": "horse"},
}
## Processing: a mill grinds grain into flour and a dairy barn turns milk into cheese, worth more.
const PROCESS := {"wheat": ["flour", 1.0, 3.0], "milk": ["cheese", 0.2, 14.0]}
## Base prices for goods the market does not list yet.
const GOODS_PRICE := {"milk": 3, "cheese": 14, "flour": 3, "hay": 1, "beef": 14, "mutton": 9, "pork": 9, "chicken": 4, "egg": 2,
	"wool": 5, "horse": 140, "manure": 1}
## Per-day spoilage fraction of stored goods (a granary cuts grain losses to 40%).
const SPOIL := {"grain": 0.0020, "legume": 0.0020, "root": 0.0040, "veg": 0.0200, "fibre": 0.0004, "hops": 0.0030, "fodder": 0.0030,
	"milk": 0.30, "cheese": 0.004, "flour": 0.003, "egg": 0.03, "beef": 0.05, "mutton": 0.05, "pork": 0.04, "chicken": 0.05,
	"wool": 0.0005, "seed": 0.0005, "manure": 0.0}

## Buildings a farm can add. gold + mats + hours go through the construction staged site; the effect shows once it is done.
## npc: the construction_data.gd CATALOG kind an NPC farm raises instead.
const BUILDINGS := {
	"field": {"name": "Field", "gold": 45, "mats": {}, "hours": 10.0, "npc": "field", "value": 85},
	"barn": {"name": "Barn", "gold": 70, "mats": {"plank": 14}, "hours": 40.0, "npc": "barn", "store": 120, "shelter": 12.0, "value": 120},
	"granary": {"name": "Granary", "gold": 90, "mats": {"plank": 20}, "hours": 50.0, "npc": "granary", "store": 300, "value": 150},
	"pen": {"name": "Pen", "gold": 30, "mats": {"plank": 8}, "hours": 12.0, "npc": "fence", "shelter": 8.0, "value": 40},
	"cottage": {"name": "Worker cottage", "gold": 80, "mats": {"plank": 18}, "hours": 36.0, "npc": "hut", "housing": 2, "value": 90},
	"well": {"name": "Well", "gold": 30, "mats": {}, "hours": 10.0, "npc": "well", "water": true, "value": 35},
	"irrigation": {"name": "Irrigation ditch", "gold": 70, "mats": {"plank": 6}, "hours": 24.0, "npc": "fence", "irrigation": true, "value": 80},
	"fence": {"name": "Fence and gate", "gold": 25, "mats": {"plank": 10}, "hours": 10.0, "npc": "fence", "guard": 0.5, "value": 30},
	"mill": {"name": "Mill", "gold": 150, "mats": {"plank": 22}, "hours": 60.0, "npc": "workshop", "mill": true, "value": 170},
}
const STORE_BASE := 40
const SHELTER_BASE := 4.0        # an open yard
const FIELD_MAX := 12
const FIELDS_START := 3
const COLS := 3

## Land value: base by settlement kind, plus per field and per building (farming.gd value()).
const LAND_BASE := {"village": 90, "town": 140, "castle": 200}
const FIELD_VALUE := 85
const RENT_FRACTION := 0.06      # of value, per season
const SHARE_DEFAULT := 0.40
const SELL_FRACTION := 0.9       # a landlord who sells straight to a tenant takes this of value
const MORTGAGE_MAX := 0.6
const MORTGAGE_RATE := 0.04      # per season, added to what is owed when a payment is missed
const AUCTION_DAYS := 5
const LET_DAYS := 4


static func crop(id: String) -> Dictionary:
	return CROPS.get(id, {})


static func family(id: String) -> String:
	return String(CROPS.get(id, {}).get("fam", ""))


static func climate_of(sid: int) -> int:
	return int(CLIM_BY_SID[absi(sid) % CLIM_BY_SID.size()])


static func goods_family(item: String) -> String:
	if CROPS.has(item):
		return String(CROPS[item]["fam"])
	if item.begins_with("seed_"):
		return "seed"
	return item


## Daily growth rate of a crop: the season's growth (Seasons.CROP_GROWTH) and the climate; hardy crops keep growing slowly in winter.
static func growth_rate(id: String, season: int, clim: int) -> float:
	var cd: Dictionary = CROPS.get(id, {})
	if cd.is_empty():
		return 0.0
	var g: float = float(Seasons.CROP_GROWTH[season])
	if season == WINTER and bool(cd.get("hardy", false)):
		g = 0.35
	return g * float(CLIM_GROWTH[clim])


static func can_sow(id: String, season: int) -> bool:
	return CROPS.has(id) and (CROPS[id]["s"] as Array).has(season)


static func base_price(item: String) -> int:
	if CROPS.has(item):
		return int(CROPS[item]["p"])
	return int(GOODS_PRICE.get(item, 2))


static func spoil_rate(item: String) -> float:
	var f := goods_family(item)
	return float(SPOIL.get(f, 0.004))


static func rung_index(rung: String) -> int:
	return RUNGS.find(rung)
