extends RefCounted
## Tunables and allowlists for the headless world linter (tools_qa/lint_world/lint_core.gd).
## Pure data: edit here, never in the core. Read tools/.claude skill "ashes-world-lint" for the rules.

# --- Thresholds ---------------------------------------------------------------------------------------------------
const FLOAT_TOL := 0.25            # m: lowest point above the LOWEST ground sample under the footprint (corners at 80 % + centre)
const FLOAT_SEVERE := 1.0          # m: severe above this
const FLOAT_SOFT_TOL := 1.5        # m: plants and other soft clutter (foliage skirts hide a hanging side)
const SINK_FRAC := 0.40            # share of the height below ground at the centre
const SINK_FRAC_BURIED_OK := 0.65  # rocks, boulders, cliff stones, stumps: designed to be embedded ~30 %
const SINK_MIN_M := 0.25           # ignore sinks smaller than this (flat decals, pebbles)
const ROCK_BURIED_DEPTH := 0.3     # boulders: every sampled vertex this far below ground = invisible (reported minor)
const ROCK_USE_MESH_GROUND := true # judge boulders against the rendered terrain triangles (terrain_streamer), not WorldGen.height
const TERRAIN_CELL := 2.0          # terrain_streamer.CELL
const THIN_M := 0.06               # m: flatter than this (blobs, decals) is not checked against the ground
const MIN_HEIGHT_FOR_SINK := 0.30  # ignore sink check for things flatter than this
const OVERLAP_FRAC := 0.25         # share of the smaller volume
const OVERLAP_MIN_VOL := 4.0       # m3: both props need at least this much volume to count
const LARGE_VOL := 30.0            # m3 AABB volume that makes an untagged prop "large"
const LARGE_FOOT := 3.0            # m: ... and at least this much on its longest side
const FOOT_SHRINK := 0.8           # footprint samples sit at 80 % of the half-extent (as the game's snap does)
const DRAW_BUDGET := 32            # distinct mesh+material draws per dressing site
const DRAW_BUDGET_BY_GROUP := {"settlement": 500, "vale": 120, "r1look": 120, "caves": 32, "tower": 64}
const FLAT_MAX_H := 0.7            # m: lower than this = a flat ground piece (plot pad, plinth, yard pad, pan, decal quad)
const FLAT_MIN_AREA := 6.0        # m2 footprint: smaller bits read as clutter, not as a pad
const FLAT_PALE_LUM := 0.50        # rendered luminance (albedo x vertex colour x texture mean x instance tint) at or above = pale
const ROAD_SEVERE_FRAC := 0.5      # centre within this share of the road width = on the road (severe for solid props)

# --- Tag lists (lower-case substrings of "asset | node name | mesh name | resource path") -----------------------------
## Sink allowed up to SINK_FRAC_BURIED_OK.
const BURIED_OK := ["rock", "boulder", "cliff", "stone", "stump", "log", "root", "mound", "drift", "snow", "scree", "ruin",
	"rubble", "crag", "slab", "menhir", "megalith", "cairn", "bones", "skull", "wall_low", "bush", "hedge", "grass", "fern", "reed", "plinth"]
## Never a sink/buried finding (they are meant to be embedded).
const SINK_OK := ["plinth", "waterfall", "fallsfoam", "falls"]
## Never an overlap finding (natural clusters, bases under buildings, trees and plants).
const OVERLAP_SKIP := ["gdressing", "snow", "drift", "mound", "fx", "vines", "waterfall", "fallsfoam", "rock", "boulder", "cliff", "plinth", "tree", "pine", "oak", "birch", "willow", "bush", "fern", "flower", "grass",
	"hedge", "stump", "log", "nature", "baked"]   # "baked": RegionDressing._bake_site merges a whole site into one mesh (not a prop)
## Boulders: judged by mesh vertices against the terrain (embedded, never plinthed), not by their box.
const ROCKY := ["rock", "boulder", "cliff", "crag", "scree", "menhir", "megalith", "cairn"]
## May hover on purpose.
const FLOAT_OK := ["gdressing", "lantern_hang", "hanging", "banner", "flag", "sail", "hanging", "chandelier", "rift", "portal", "crystal", "orb", "spirit",
	"mist", "fog", "rune", "glow", "smoke", "sign_hang", "bell", "cloud", "bird", "firefly", "wisp", "beam", "shaft",
	"bunting", "garland", "streamer", "pennant"]
## May stand in water (is_water) without the site being tagged wet.
const WET_OK := ["bridge", "dock", "pier", "boat", "ferry", "reed", "lily", "water", "fish", "raft", "cattail", "pond", "pool",
	"waterfall", "jetty", "wharf", "net", "buoy", "fallsfoam", "falls"]
## Buildings: their overlap is severe.
const BUILDING := ["house", "building", "barn", "hall", "keep", "temple", "chapel", "cottage", "hut", "mill", "stable", "forge",
	"inn", "tavern", "castle", "fort", "manor", "church", "cabin", "shop", "workshop", "granary", "lodge"]
## Other large solid props checked for overlap.
const LARGE := ["wall", "stall", "tent", "cart", "wagon", "tower", "gate", "bridge", "pavilion", "palisade", "barracks", "shed",
	"silo", "well", "statue", "monument", "arch", "gatehouse", "windmill"]
## Soft things that never block a road (plants, small clutter).
const SOFT := ["grass", "flower", "fern", "bush", "shrub", "weed", "moss", "reed", "mushroom", "pebble", "leaf", "clover", "herb"]
## Trees and bushes: canopy footprints are wide and trunks narrow, so float/sink findings are never above "minor".
const FOLIAGE := ["tree", "oak", "beech", "spruce", "pine", "birch", "willow", "poplar", "elm", "ash_", "snag", "bush", "fern", "hedge"]
## Solid props that legitimately stand on/next to a road.
const ROAD_OK := ["waystone", "signpost", "sign", "milestone", "marker", "bridge", "gate", "lamp", "lantern", "post", "waystation",
	"wayshrine", "toll", "barrier", "checkpoint", "banner", "flag", "border", "wall_tower", "wall_gate"]
## Site kinds that are wet on purpose (no water issue) / sit on the road on purpose (no road issue).
const WET_SITE_KINDS := ["bridge", "old_bridge", "ferry", "sunken_chapel", "waterfall", "poi_fishing", "hollow", "lakeside"]
const ROAD_SITE_KINDS := ["bridge", "old_bridge", "waystation", "waystone", "wayshrine", "roadside", "border_gate", "pass",
	"watchfort", "caravan_camp"]
## Flat pale ground pieces that are intended AND blended (a lower-case substring of "node | mesh | asset" text): salt pans have a dirt rim.
const FLAT_OK := ["salt_pan"]
## Parent names that mark a designed kit (overlaps between its children are intended).
const KIT_PARENT_TOKENS := ["kit", "interior", "cliff", "stalls_row"]
## Pairs of tokens that may overlap by design (walls with gates/towers, stalls with their goods...).
const OVERLAP_PAIR_OK := [["wall", "gate"], ["wall", "tower"], ["wall", "wall"], ["gate", "tower"], ["palisade", "palisade"],
	["palisade", "gate"], ["stall", "cart"], ["tent", "tent"]]

## Builder scripts whose MultiMesh transforms must be captured (see mm_shim.gd). Add a file here when a new builder
## batches props with MultiMesh.set_instance_transform.
const PATCH_SCRIPTS := ["res://scripts/world/region_dressing.gd", "res://scripts/region1/region1_look.gd", "res://scripts/world/vale_look.gd",
	"res://scripts/world/region1_extras.gd", "res://scripts/world/settlement_builder.gd", "res://scripts/world/exploration_director.gd",
	"res://scripts/world/grass_field.gd", "res://scripts/world/realm_presence.gd", "res://scripts/world/terrain_streamer.gd"]

## Literal in-memory source edits (restored after the run). Region1Look's far horizon builds a 57800-cell ground mesh on a
## worker thread that keeps reading WorldGen: pointless for the lint and a race when a test re-runs WorldGen.setup().
const SOURCE_TWEAKS := {
	"res://scripts/region1/region1_look.gd": [["qa.has(\"--r1nohorizon\")", "true"]],
}

# --- Allowlist ---------------------------------------------------------------------------------------------------
## {type: float|overhang|buried|water|overlap|road|draws|"*", site: site kind (or group id)|"*", match: substring of
##  "node path | asset | builder" (for overlaps: of both props), reason: text, todo: true when it is a real bug left for later}
## Allowlisted issues are listed separately in the report and never fail the run.
const ALLOW := [
	# Designed: MarketGoods "stall_fish" (hanging fish, 3.9 x 1.7 x 2.1 m) is drawn ON its own stall. Only the fish layout is tall
	# enough to count as a large prop; the other themes' goods are below the overlap volume threshold. (Matches the goods'
	# size text, so stall-on-stall overlaps of the real market_stall meshes are still reported.)
	{"type": "overlap", "site": "settlement", "match": "[3.9x1.7x2.1 m]", "reason": "stall_fish goods drawn on their own stall by design"},
]
