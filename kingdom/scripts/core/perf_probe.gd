extends RefCounted
## Section timer for the CPU profile (tools_qa/cpu_mem/cpu_profile.gd). Off by default: each call is one static call and a
## bool test, so the probes can stay in the hot paths. Use it through a preload (no class_name, so no class-cache entry):
##   const Probe := preload("res://scripts/core/perf_probe.gd")
##   var t0 := Probe.t()
##   ...work...
##   Probe.add("population_lod.sort", t0)
static var on := false
static var us := {}         # key -> total microseconds since reset()
static var calls := {}      # key -> number of timed sections
static var worst := {}      # key -> longest single section in microseconds


static func t() -> int:
	return Time.get_ticks_usec() if on else 0


static func add(key: String, t0: int) -> void:
	if not on:
		return
	add_us(key, Time.get_ticks_usec() - t0)


## Adds an already measured duration (one call) under `key`.
static func add_us(key: String, d: int) -> void:
	if not on:
		return
	us[key] = int(us.get(key, 0)) + d
	calls[key] = int(calls.get(key, 0)) + 1
	if d > int(worst.get(key, 0)):
		worst[key] = d


static func reset() -> void:
	us.clear()
	calls.clear()
	worst.clear()
