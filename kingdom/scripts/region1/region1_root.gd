class_name Region1Root
extends Node3D
## Hook H1: `world.add_child(preload("res://scripts/region1/region1_root.gd").new())`.
##
## Owns no game logic. Once per `tick_interval` real seconds (a Timer: zero per-frame
## GDScript) it
##   1. reads the game clock (fractional days) and slices the elapsed time into chunks of at
##      most MAX_STEP_DAYS, at most MAX_CHUNKS_PER_TICK chunks per timer tick (a long sleep
##      catches up over several ticks instead of hitching);
##   2. ticks every sim in `Region1State.sims()`;
##   3. tells presenters (nodes in group "region1_presenter" with a `region1_present(root)`
##      method) to refresh.
## On `_ready` it instantiates the modules listed in `data/region1/modules.json` whose
## script exists, so a package only appends one row there to go live.

const MANIFEST_PATH := "res://data/region1/modules.json"
const GROUP_ROOT := &"region1_root"
const GROUP_PRESENTER := &"region1_presenter"
const MAX_STEP_DAYS := 1.0
const MAX_CHUNKS_PER_TICK := 4

signal ticked(dt_days: float)

@export var tick_interval := 1.0
## Optional override: a Callable returning the fractional game day. Default: WorldSim.
var clock: Callable = Callable()
## Set false in the sandbox/tests to drive `advance_to()` by hand.
var auto_bootstrap := true
var auto_timer := true

var last_day_f := -1.0
var _seen_serial := 0
var last_tick_ms := 0.0
var worst_tick_ms := 0.0
var tick_total := 0
var _timer: Timer


func _ready() -> void:
	name = "Region1Root"
	add_to_group(GROUP_ROOT)
	if auto_bootstrap:
		bootstrap_modules()
	if auto_timer:
		_timer = Timer.new()
		_timer.wait_time = tick_interval
		_timer.one_shot = false
		_timer.autostart = true
		_timer.timeout.connect(_on_timer)
		add_child(_timer)


func _exit_tree() -> void:
	remove_from_group(GROUP_ROOT)


## Current fractional game day from the clock override or the WorldSim autoload, or -1.0
## when there is no clock (sandbox without an override).
func current_day() -> float:
	if clock.is_valid():
		return float(clock.call())
	var ws := get_node_or_null("/root/WorldSim")
	if ws == null:
		return -1.0
	return float(ws.day) + float(ws.time_of_day) / 24.0


func world_seed() -> int:
	var ws := get_node_or_null("/root/WorldSim")
	return int(ws.SEED) if ws != null else 1


func _on_timer() -> void:
	var d := current_day()
	if d >= 0.0:
		advance_to(d)


## Move every sim forward to `day_f`. Public so the sandbox and tests can drive it.
## Returns the number of chunks processed.
func advance_to(day_f: float) -> int:
	if _seen_serial != Region1State.restore_serial:   # a save was loaded: re-anchor
		_seen_serial = Region1State.restore_serial
		last_day_f = -1.0
	if last_day_f < 0.0:
		last_day_f = day_f   # first call only anchors the clock
		return 0
	if day_f < last_day_f:   # clock went backwards (load, new game): re-anchor
		last_day_f = day_f
		return 0
	var t0 := Time.get_ticks_usec()
	var chunks := 0
	while day_f - last_day_f > 1e-6 and chunks < MAX_CHUNKS_PER_TICK:
		var dt := minf(day_f - last_day_f, MAX_STEP_DAYS)
		for mod: StringName in Region1State.sims():
			(Region1State.sims()[mod] as Region1Sim).tick(dt)
		last_day_f += dt
		chunks += 1
		ticked.emit(dt)
	if chunks > 0:
		refresh_presenters()
	last_tick_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	worst_tick_ms = maxf(worst_tick_ms, last_tick_ms)
	tick_total += 1
	return chunks


func refresh_presenters() -> void:
	if not is_inside_tree():
		return
	for p in get_tree().get_nodes_in_group(GROUP_PRESENTER):
		if p.has_method("region1_present"):
			p.region1_present(self)


## Instantiate and register the manifest modules that are not registered yet.
## Manifest row: {"name": "wardlines", "script": "res://scripts/region1/wardlines.gd", "enabled": true}.
## Returns the names that were created.
func bootstrap_modules() -> PackedStringArray:
	var made := PackedStringArray()
	if not FileAccess.file_exists(MANIFEST_PATH):
		return made
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return made
	for row: Dictionary in parsed.get("modules", []):
		var mod := StringName(row.get("name", ""))
		if mod == &"" or not row.get("enabled", true) or Region1State.sim(mod) != null:
			continue
		var path := String(row.get("script", ""))
		if not ResourceLoader.exists(path):
			continue   # package not merged yet
		var s: Object = (load(path) as GDScript).new()
		if not (s is Region1Sim):
			push_warning("Region1: %s does not extend Region1Sim" % path)
			continue
		(s as Region1Sim).setup(world_seed())
		Region1State.register_sim(s)
		made.append(String(mod))
	return made
