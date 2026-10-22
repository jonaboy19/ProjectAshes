class_name Region1Sim
extends RefCounted
## Base class for every pure Region 1 simulation (Wardlines, Scar Tide, Ashsight, ...).
##
## Contract (see data/region1/README.md):
##   * No scene tree, no autoload access, no `randf()`: all randomness comes from `rng`,
##     which is seeded by `setup(seed)`. Same seed + same tick sequence = same state.
##   * Advance with `tick(dt_days)` (game days, fractional). Override `_step(dt_days)`.
##   * Report things that happened with `emit_event(kind, data)` (signal `event` + a ring
##     buffer in `event_log` for late listeners, tests and the sandbox).
##   * Persist with `serialize()` / `deserialize()`. Override `_save_state()` / `_load_state()`
##     for your own fields. Everything must be JSON-safe (Life saves as JSON): no Vector2,
##     Color or int keys, and no 64-bit ints above 2^53 (store those as Strings).
##   * Bump `state_version` when the saved shape changes and implement `migrate()`.
##   * Optionally draw a debug picture in `debug_image()` (the sandbox saves it as PNG).

signal event(kind: StringName, data: Dictionary)

const EVENT_LOG_MAX := 256

## Registry / save key, also the sandbox `--module=` name. Set it in `_init()` of the subclass.
var module_name: StringName = &"sim"
## Version of the saved shape produced by `_save_state()`.
var state_version := 1

var seed_value := 0
var rng := RandomNumberGenerator.new()
## Simulated time in game days since `setup` (or since the loaded save).
var day_f := 0.0
var tick_count := 0
var event_log: Array[Dictionary] = []


## Seed the sim. Call once after `new()`; the root does it for manifest modules.
func setup(p_seed: int) -> Region1Sim:
	seed_value = p_seed
	rng.seed = hash([p_seed, String(module_name)])
	day_f = 0.0
	tick_count = 0
	event_log.clear()
	_setup()
	return self


## Advance the simulation by `dt_days` (> 0, fractional). Keep it cheap: the root slices
## big jumps into chunks of at most `Region1Root.MAX_STEP_DAYS`.
func tick(dt_days: float) -> void:
	if dt_days <= 0.0:
		return
	day_f += dt_days
	tick_count += 1
	_step(dt_days)


func emit_event(kind: StringName, data: Dictionary = {}) -> void:
	var e := {"kind": String(kind), "day": day_f, "data": data}
	event_log.append(e)
	if event_log.size() > EVENT_LOG_MAX:
		event_log.pop_front()
	event.emit(kind, data)


# --- persistence ---------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"seed": seed_value,
		# rng.state is a 64-bit int: JSON would round it, so keep it as text.
		"rng_state": str(rng.state),
		"day_f": day_f,
		"ticks": tick_count,
		"state": _save_state(),
	}


func deserialize(d: Dictionary) -> void:
	seed_value = int(d.get("seed", seed_value))
	rng.seed = hash([seed_value, String(module_name)])
	if d.has("rng_state"):
		rng.state = int(str(d["rng_state"]))
	day_f = float(d.get("day_f", 0.0))
	tick_count = int(d.get("ticks", 0))
	event_log.clear()
	_load_state(d.get("state", {}))


## Upgrade `data` (what `serialize()` produced at `from_version`) by ONE version step and
## return it. The registry calls this repeatedly until `state_version` is reached.
## Default: nothing to migrate.
func migrate(_from_version: int, data: Dictionary) -> Dictionary:
	return data


## Stable fingerprint of the full state, for determinism tests and the sandbox.
func digest() -> String:
	return JSON.stringify(serialize(), "", true).md5_text()


## Optional debug picture (grid, graph, ...). Return null when the module has none.
func debug_image(_size: int = 256) -> Image:
	return null


## One-line human summary for logs.
func summary() -> String:
	return "%s day=%.2f ticks=%d" % [module_name, day_f, tick_count]


# --- override points -----------------------------------------------------------------

func _setup() -> void:
	pass


func _step(_dt_days: float) -> void:
	pass


func _save_state() -> Dictionary:
	return {}


func _load_state(_d: Dictionary) -> void:
	pass
