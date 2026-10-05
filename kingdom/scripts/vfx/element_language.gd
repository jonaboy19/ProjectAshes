extends RefCounted
## ElementLanguage: the colour and shape language of every element / power path, loaded from
## data/vfx/element_language.json (one table, three readers: technique VFX, HUD tint, unlock cards).
##
##   ElementLanguage.get_lang("fire")            -> {name, shape, core, mid, edge (Color), hud (Color), decal, limb, glow, ...}
##   ElementLanguage.get_lang("none", "knight")  -> element first, path as fallback
##   ElementLanguage.tint("water")               -> HUD / unlock-card tint (Color)
##   ElementLanguage.color("fire", "core")       -> one of core | mid | edge | hud
##   ElementLanguage.canon("frost")              -> "ice"
##   ElementLanguage.ids()                       -> every canonical id

const PATH := "res://data/vfx/element_language.json"
const FALLBACK := "qi"

static var _data: Dictionary = {}
static var _cache: Dictionary = {}


static func _load() -> void:
	if not _data.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			_data = j
	if _data.is_empty():
		_data = {"aliases": {}, "paths": {}, "elements": {FALLBACK: {"name": "Qi", "shape": "rings", "core": "fff2b3",
			"mid": "ffc247", "edge": "d9731f", "hud": "ffcc4d", "decal": "dust", "limb": "hand", "glow": 2.0}}}


static func ids() -> Array:
	_load()
	return (_data["elements"] as Dictionary).keys()


## Canonical element id for an element name, alias or path name ("frost", "sect", "none"...). Unknown -> qi.
static func canon(element: Variant, path := "") -> String:
	_load()
	var e := String(element).to_lower()
	var els: Dictionary = _data["elements"]
	var al: Dictionary = _data["aliases"]
	if els.has(e) and e != "none":
		return e
	if al.has(e) and e != "none":
		return String(al[e])
	var p := path.to_lower()
	if p != "":
		var pm: Dictionary = _data["paths"]
		if pm.has(p):
			return String(pm[p])
	if al.has(e):
		return String(al[e])
	return FALLBACK


static func get_lang(element: Variant, path := "") -> Dictionary:
	var id := canon(element, path)
	if _cache.has(id):
		return _cache[id]
	var row: Dictionary = (_data["elements"] as Dictionary).get(id, (_data["elements"] as Dictionary).get(FALLBACK, {})).duplicate(true)
	for k: String in ["core", "mid", "edge", "hud"]:
		row[k] = Color.html(String(row.get(k, "ffffff")))
	row["id"] = id
	_cache[id] = row
	return row


static func color(element: Variant, which := "mid", path := "") -> Color:
	return get_lang(element, path).get(which, Color.WHITE)


## HUD tint and unlock-card accent for an element or path.
static func tint(element: Variant, path := "") -> Color:
	return color(element, "hud", path)


static func shape(element: Variant, path := "") -> String:
	return String(get_lang(element, path)["shape"])
