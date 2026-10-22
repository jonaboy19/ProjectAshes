extends RefCounted
## Region 1 landmarks as data (data/region1/landmarks.json): the Hollin's Reach valley, the Drowned Bell and
## Emberglass Ferry, Crownstead Mill Hill, the Stagborn Glade, the Wyrm's Ribs (docs/regions/LOOK_R1.md).
## `sites()` turns them into WorldGen.sites entries (RegionSites hook, one line in region_sites.gd) so trees
## clear, the ground scatter, the map, discovery and `--shot=site_<kind>` know them. They carry no parts:
## Region1Look (scripts/region1/region1_look.gd) builds their bodies, far silhouettes and cliff rocks.

const PATH := "res://data/region1/landmarks.json"


static func data() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return d if d is Dictionary else {}


## Site entries in the RegionSites format ({name, kind, pos, yaw, clear, flatten, parts, lights}).
## A landmark may list extra "sites" (sub-places with their own names, e.g. Hollin Falls).
static func sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if OS.get_cmdline_user_args().has("--r1off"):     # QA A/B: the vale without the Region 1 look pass
		return out
	for lm: Dictionary in data().get("landmarks", []):
		out.append(_site(lm))
		for sub: Dictionary in lm.get("sites", []):
			out.append(_site(sub))
	return out


static func _site(d: Dictionary) -> Dictionary:
	var p: Array = d["pos"]
	return {"name": String(d["name"]), "kind": String(d.get("kind", "landmark")), "pos": Vector2(float(p[0]), float(p[1])),
		"yaw": deg_to_rad(float(d.get("yaw", 0.0))), "clear": float(d.get("clear", 0.0)), "flatten": false,
		"parts": [], "lights": [], "region1": String(d.get("id", ""))}
