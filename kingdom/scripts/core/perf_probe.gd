extends RefCounted
## Section timer for the CPU profile (tools_qa/cpu_mem/cpu_profile.gd). Off by default: each call is one static call and a
## bool test, so the probes can stay in the hot paths. Use it through a preload (no class_name, so no class-cache entry):
##   const Probe := preload("res://scripts/core/perf_probe.gd")
##   var t0 := Probe.t()
##   ...work...
##   Probe.add("population_lod.sort", t0)
static var on := false
## `--perf-legacy`: QA A/B switch that puts back the pre-2026-10-23 hitch behaviours (settings parsed from disk on every call, one Style G
## double-sided shader per material, the whole sprite pass in one frame, full-rate far villagers, the 1 Hz story-context script error), so one build
## can be measured both ways in interleaved runs.
static var legacy := OS.get_cmdline_user_args().has("--perf-legacy")
static var us := {}         # key -> total microseconds since reset()
static var calls := {}      # key -> number of timed sections
static var worst := {}      # key -> longest single section in microseconds
## Hitch tooling (tools_qa/cpu_mem/hitch_route.gd): when `capture` is set every section of at least `min_us` is also appended to
## `events` as [key, microseconds], so the harness can say which sections ran inside a slow frame. It clears `events` per frame.
static var capture := false
static var min_us := 1000
static var events: Array = []


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
	if capture and d >= min_us:
		events.append([key, d])
	us[key] = int(us.get(key, 0)) + d
	calls[key] = int(calls.get(key, 0)) + 1
	if d > int(worst.get(key, 0)):
		worst[key] = d


static func reset() -> void:
	us.clear()
	calls.clear()
	worst.clear()
