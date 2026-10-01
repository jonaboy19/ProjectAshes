extends Node
## Four seasons of 28 days: spring, summer, autumn, winter, then a new year.
##
## Owned by WorldSim (autoload/world_sim.gd adds one as a child and exposes
## `WorldSim.season` -> "spring" / "summer" / "autumn" / "winter", which
## scripts/world/weather.gd already reads to bias its daily weather).
##
## Calendar: calendar day = WorldSim.day + day_offset, so day 1 is the first day
## of spring of year 1 (day_offset shifts the whole calendar; it is saved).
## Every pure function takes an explicit calendar day (1-based) and optional
## hour, so tests and tools need no running world; the instance helpers without
## arguments read the live WorldSim clock.
##
## Look: four shader globals (plus winter_amount), registered at runtime with
## RenderingServer.global_shader_parameter_add (once per process), read by the
## terrain, grass, Blender-tree leaves (tree_wind) and region nature shaders:
##   season_tint   vec3   multiplies living greens (1,1,1 = summer, unchanged)
##   autumn_amount float  0..1 leaves turn gold / orange / red, grass yellows, leaf litter
##   winter_amount float  0..1 bare, desaturated deciduous crowns, short frosty grass
##   snow_amount   float  0..1 snow on flat ground and top-facing leaves / rocks
##   bloom_amount  float  0..1 spring blossom speckles on some trees
## Every default is 0 / white, so without this node the world looks exactly as
## it did before seasons existed (summer). The globals are recomputed at most
## once per in-game hour (WorldSim.hour_changed), never per frame.
##
## Transitions: `season_blend` rises 0 -> 1 over the last BLEND_DAYS of each
## season, and the visuals / day length lerp towards the next season with it.
##
## Preview: `-- --season=autumn` (or spring / summer / winter / a number 0..3)
## jumps the calendar to the middle of that season; `--season_day=N` picks the
## day inside it (1..28). Used by the screenshot tooling in main.gd.

signal season_changed(season_name: String, year: int)
## A festival day has begun (also at load when the day is a festival).
signal festival_started(festival: Dictionary)

enum { SPRING, SUMMER, AUTUMN, WINTER }
const NAMES := ["spring", "summer", "autumn", "winter"]
const DAYS_PER_SEASON := 28
const DAYS_PER_YEAR := DAYS_PER_SEASON * 4
const BLEND_DAYS := 3.0
## Sunrise, sunset hour per season (main.gd's cycle used a fixed 6 -> 18).
const DAYLIGHT := [Vector2(6.0, 19.0), Vector2(5.5, 20.0), Vector2(6.5, 18.0), Vector2(7.5, 16.5)]
## Crop growth speed multiplier per season; 0 = nothing grows (winter).
const CROP_GROWTH := [1.0, 1.25, 0.75, 0.0]
## Which seasons each forage kind (Gathering.FORAGE keys) can be found in.
const FORAGE_SEASONS := {
	"berries": [SUMMER, AUTUMN],
	"mushroom": [AUTUMN],
	"herb": [SPRING, SUMMER, AUTUMN],
	"firewood": [SPRING, SUMMER, AUTUMN, WINTER],
}
const FESTIVALS := [
	{"id": "planting", "name": "Planting Festival", "season": SPRING, "day": 7},
	{"id": "midsummer", "name": "Midsummer Fair", "season": SUMMER, "day": 14},
	{"id": "harvest", "name": "Harvest Festival", "season": AUTUMN, "day": 21},
	{"id": "solstice", "name": "Winter Solstice", "season": WINTER, "day": 14},
	# Region1 (docs/regions/STORY_R1.md): the night Ashford floats lanterns for the dead. Last night of autumn.
	{"id": "kindling_night", "name": "Kindling Night", "season": AUTUMN, "day": 28},
]
## Global shader parameter names and their summer (neutral) defaults.
const G_TINT := &"season_tint"
const G_AUTUMN := &"autumn_amount"
const G_WINTER := &"winter_amount"
const G_SNOW := &"snow_amount"
const G_BLOOM := &"bloom_amount"
const GLOBAL_DEFAULTS := {
	G_TINT: Vector3.ONE, G_AUTUMN: 0.0, G_WINTER: 0.0, G_SNOW: 0.0, G_BLOOM: 0.0,
}
## Snow cover kept while it is actually snowing outside winter (snow regions).
const SNOWFALL_COVER := 0.55

## Calendar day = WorldSim.day + day_offset (saved).
var day_offset := 0
## Last applied shader values (to skip redundant sets).
var _applied: Dictionary = {}
var _last_cal_day := -1
var _weather: Node = null
var _snow_set := false
var _watching_nodes := false

static var _globals_added := false


static func _static_init() -> void:
	# Before any shader that declares the globals is drawn.
	ensure_globals()


## Adds the season shader globals once per process (skips any that project.godot
## already declares, so moving them there later does not double-add). A shader
## that declares `global uniform ...` gets the name auto-registered by the
## renderer as soon as it is parsed, with no value yet (global_shader_parameter_get
## returns null); calling _add on a name already known errors and is a no-op, so
## those just get their neutral default pushed with _set instead.
static func ensure_globals() -> void:
	if _globals_added or Engine.has_meta(&"ashes_season_globals"):
		_globals_added = true
		return
	_globals_added = true
	Engine.set_meta(&"ashes_season_globals", true)
	# The globals are declared in project.godot [shader_globals], so the engine
	# registers them at startup. (This used RenderingServer.global_shader_parameter_get_list(),
	# an editor-only call that syncs with the render thread — and _static_init can
	# run on a loader thread. It printed an error every boot; suspect in the boot crashes.)
	for g: StringName in GLOBAL_DEFAULTS:
		var v: Variant = GLOBAL_DEFAULTS[g]
		if ProjectSettings.has_setting("shader_globals/" + String(g)):
			continue
		var t := RenderingServer.GLOBAL_VAR_TYPE_VEC3 if v is Vector3 else RenderingServer.GLOBAL_VAR_TYPE_FLOAT
		RenderingServer.global_shader_parameter_add(g, t, v)


func _ready() -> void:
	_read_cmdline()
	var sim := _sim()
	if sim and sim.has_signal("hour_changed"):
		sim.hour_changed.connect(_on_hour)
	_last_cal_day = current_day()
	apply_visuals()
	if not _find_weather():
		# Weather is built later by main.gd; catch it the moment it enters the
		# tree (so a forced --weather=snow already sees winter), then stop listening.
		_watching_nodes = true
		get_tree().node_added.connect(_on_node_added)


# ------------------------------------------------------------------ calendar (pure)

static func season_of(cal_day: int) -> int:
	return posmod(cal_day - 1, DAYS_PER_YEAR) / DAYS_PER_SEASON


static func season_name_of(cal_day: int) -> String:
	return NAMES[season_of(cal_day)]


## 1..28
static func day_of_season_of(cal_day: int) -> int:
	return posmod(cal_day - 1, DAYS_PER_SEASON) + 1


## 1-based year.
static func year_of(cal_day: int) -> int:
	return floori(float(cal_day - 1) / DAYS_PER_YEAR) + 1


## First calendar day of `season` in `year`.
static func first_day_of(season: int, year := 1) -> int:
	return (year - 1) * DAYS_PER_YEAR + posmod(season, 4) * DAYS_PER_SEASON + 1


## 0 for most of the season, easing to 1 at the end of its last day.
static func blend_of(cal_day: int, hour := 12.0) -> float:
	var pos := float(day_of_season_of(cal_day) - 1) + clampf(hour, 0.0, 24.0) / 24.0
	return smoothstep(DAYS_PER_SEASON - BLEND_DAYS, float(DAYS_PER_SEASON), pos)


## Vector2(sunrise, sunset) hours, blended into the next season's at the end.
static func daylight_of(cal_day: int, hour := 12.0) -> Vector2:
	var s := season_of(cal_day)
	return (DAYLIGHT[s] as Vector2).lerp(DAYLIGHT[(s + 1) % 4], blend_of(cal_day, hour))


## 0 at night .. 1 around noon, with the same curve main.gd uses for 6..18.
static func day_amount_of(cal_day: int, hour: float) -> float:
	var dl := daylight_of(cal_day, hour)
	return clampf(sin((hour - dl.x) / maxf(dl.y - dl.x, 1.0) * PI) * 1.4, 0.0, 1.0)


## The festival held on a calendar day, or {}.
static func festival_on(cal_day: int) -> Dictionary:
	var s := season_of(cal_day)
	var d := day_of_season_of(cal_day)
	for f: Dictionary in FESTIVALS:
		if int(f["season"]) == s and int(f["day"]) == d:
			return f
	return {}


## The next festival on or after `cal_day`, with "cal_day" and "in_days" added.
static func next_festival_from(cal_day: int) -> Dictionary:
	for k in DAYS_PER_YEAR:
		var f := festival_on(cal_day + k)
		if not f.is_empty():
			var out := f.duplicate()
			out["cal_day"] = cal_day + k
			out["in_days"] = k
			return out
	return {}


static func forage_in_season(kind: String, cal_day: int) -> bool:
	var seasons: Array = FORAGE_SEASONS.get(kind, [SPRING, SUMMER, AUTUMN, WINTER])
	return seasons.has(season_of(cal_day))


static func crop_growth_of(cal_day: int) -> float:
	return CROP_GROWTH[season_of(cal_day)]


## How far decorative fields have come, 0..1: sprouting through spring, tall in
## summer, ripe in autumn until the harvest festival, then stubble; bare in winter.
static func field_growth_of(cal_day: int) -> float:
	var d := float(day_of_season_of(cal_day) - 1) / (DAYS_PER_SEASON - 1)
	match season_of(cal_day):
		SPRING:
			return lerpf(0.05, 0.45, d)
		SUMMER:
			return lerpf(0.45, 0.95, d)
		AUTUMN:
			return 1.0 if day_of_season_of(cal_day) < int(FESTIVALS[2]["day"]) else 0.0
	return 0.0


## "sprouting" / "growing" / "ripe" / "stubble" / "fallow" (winter).
static func field_look_of(cal_day: int) -> String:
	match season_of(cal_day):
		SPRING:
			return "sprouting"
		SUMMER:
			return "growing"
		AUTUMN:
			return "ripe" if field_growth_of(cal_day) > 0.5 else "stubble"
	return "fallow"


## Shader values for a calendar day and hour (no weather): {tint, autumn, winter, snow, bloom}.
static func visuals_of(cal_day: int, hour := 12.0) -> Dictionary:
	var s := season_of(cal_day)
	var pos := float(day_of_season_of(cal_day) - 1) + clampf(hour, 0.0, 24.0) / 24.0
	var a := _season_look(s, pos)
	var b := _season_look((s + 1) % 4, 0.0)
	var k := blend_of(cal_day, hour)
	var out := {}
	for key: String in a:
		out[key] = lerp(a[key], b[key], k)
	return out


## The look of season `s` at `pos` days into it (0..28), before blending.
static func _season_look(s: int, pos: float) -> Dictionary:
	var v := {"tint": Vector3.ONE, "autumn": 0.0, "winter": 0.0, "snow": 0.0, "bloom": 0.0}
	match s:
		SPRING:
			v["tint"] = Vector3(0.93, 1.06, 0.9)                        # fresh, greener
			v["bloom"] = lerpf(0.8, 0.3, smoothstep(10.0, 24.0, pos))  # blossom peaks early, then fades
		SUMMER:
			pass
		AUTUMN:
			v["tint"] = Vector3(1.06, 0.98, 0.86)
			v["autumn"] = lerpf(0.45, 1.0, smoothstep(0.0, 12.0, pos))  # colours deepen
		WINTER:
			v["tint"] = Vector3(0.93, 0.95, 1.0)
			v["winter"] = 1.0
			v["snow"] = lerpf(0.7, 1.0, smoothstep(0.0, 8.0, pos))
	return v


# ------------------------------------------------------------------ live helpers

## Today's calendar day (WorldSim.day + day_offset).
func current_day() -> int:
	var sim := _sim()
	return (int(sim.get("day")) if sim else 1) + day_offset


func current_hour() -> float:
	var sim := _sim()
	return float(sim.get("time_of_day")) if sim else 12.0


func season_index() -> int:
	return season_of(current_day())


func season_name() -> String:
	return NAMES[season_index()]


func day_of_season() -> int:
	return day_of_season_of(current_day())


func year() -> int:
	return year_of(current_day())


func season_blend() -> float:
	return blend_of(current_day(), current_hour())


func sunrise() -> float:
	return daylight_of(current_day(), current_hour()).x


func sunset() -> float:
	return daylight_of(current_day(), current_hour()).y


## Drop-in for main.gd's `clampf(sin((t - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)`.
func day_amount(t: float) -> float:
	return day_amount_of(current_day(), t)


## Today's festival ({id, name, season, day}) or {} (for events, shops, NPC talk).
func festival_today() -> Dictionary:
	return festival_on(current_day())


func next_festival() -> Dictionary:
	return next_festival_from(current_day())


## Crops (fields, farming) grow only from spring to autumn.
func crops_grow() -> bool:
	return crop_growth_of(current_day()) > 0.0


## Growth speed multiplier for planted crops (0 in winter).
func crop_growth_mult() -> float:
	return crop_growth_of(current_day())


## Planting is allowed in spring and summer (so it can ripen before winter).
func can_plant() -> bool:
	var s := season_index()
	return s == SPRING or s == SUMMER


func field_growth() -> float:
	return field_growth_of(current_day())


func field_look() -> String:
	return field_look_of(current_day())


func forage_available(kind: String) -> bool:
	return forage_in_season(kind, current_day())


# ------------------------------------------------------------------ hourly update

func _on_hour(_hour: int) -> void:
	var cal := current_day()
	if cal != _last_cal_day:
		var old := _last_cal_day
		_last_cal_day = cal
		if old < 0 or season_of(old) != season_of(cal):
			season_changed.emit(season_name_of(cal), year_of(cal))
		var f := festival_on(cal)
		if not f.is_empty():
			festival_started.emit(f)
	apply_visuals()


## Pushes the shader globals (skipping unchanged ones) and syncs the weather's
## snow gate. Called hourly; call it after changing the clock or day_offset.
func apply_visuals() -> void:
	ensure_globals()
	var v := visuals_of(current_day(), current_hour())
	var w := _find_weather()
	if w and w.has_method("is_snowing") and bool(w.call("is_snowing")):
		v["snow"] = maxf(float(v["snow"]), SNOWFALL_COVER)
	_set_global(G_TINT, v["tint"])
	_set_global(G_AUTUMN, v["autumn"])
	_set_global(G_WINTER, v["winter"])
	_set_global(G_SNOW, v["snow"])
	_set_global(G_BLOOM, v["bloom"])
	_sync_weather()


func _set_global(g: StringName, value: Variant) -> void:
	if _applied.has(g) and _applied[g] == value:
		return
	_applied[g] = value
	RenderingServer.global_shader_parameter_set(g, value)


## Winter lets rain fall as snow (weather.gd's region gate). We only flip the gate
## when our own wish changes, so biome code (mountains) can still use it.
func _sync_weather() -> void:
	var w := _find_weather()
	if w == null or not w.has_method("set_snow_region"):
		return
	var want := season_index() == WINTER
	if want != _snow_set:
		_snow_set = want
		w.call("set_snow_region", want)


func _find_weather() -> Node:
	if _weather != null and is_instance_valid(_weather) and _weather.is_inside_tree():
		return _weather
	if _weather != null:
		_weather = null
		_snow_set = false        # a new weather node starts with its own gate
	if not is_inside_tree():
		return null
	_weather = get_tree().get_first_node_in_group("weather")
	return _weather


func _on_node_added(n: Node) -> void:
	if not n.is_in_group("weather"):
		return
	if _watching_nodes:
		_watching_nodes = false
		get_tree().node_added.disconnect(_on_node_added)
	_weather = n
	_snow_set = false
	_sync_weather()
	apply_visuals()


# ------------------------------------------------------------------ save / args

func serialize() -> Dictionary:
	return {"offset": day_offset}


func deserialize(d: Dictionary) -> void:
	day_offset = int(d.get("offset", day_offset))
	_last_cal_day = current_day()
	if is_inside_tree():
		apply_visuals()


## `--season=autumn` (or 0..3) jumps to the middle of that season, `--season_day=N` picks the day.
func _read_cmdline() -> void:
	var want := ""
	var want_day := 15
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--season="):
			want = arg.substr(9).to_lower()
		elif arg.begins_with("--season_day="):
			want_day = clampi(int(arg.substr(13)), 1, DAYS_PER_SEASON)
	if want == "":
		return
	var s := NAMES.find(want)
	if s < 0 and want.is_valid_int():
		s = posmod(int(want), 4)
	if s < 0:
		push_warning("Seasons: unknown --season '%s'" % want)
		return
	var sim := _sim()
	var today := int(sim.get("day")) if sim else 1
	day_offset = first_day_of(s) + want_day - 1 - today


func _sim() -> Node:
	var p := get_parent()
	if p != null and "time_of_day" in p:
		return p
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("WorldSim") if tree and tree.root else null
