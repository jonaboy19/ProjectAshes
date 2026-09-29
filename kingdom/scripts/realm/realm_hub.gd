extends RefCounted
## Realm simulation hub: owns every realm module and runs the time-tier
## schedule from docs/design/SIM_HIERARCHY.md so nothing spikes a frame.
##
## Life (autoload/life.gd) owns one hub as `Life.realm` and calls:
##   on_hour(hour, ctx)  -> queues each module's tick_hour (and tick_day at 06:00,
##                          tick_week on day % 7 == 0)
##   pump()              -> every frame; runs queued jobs until PUMP_BUDGET_USEC
##   catch_up(days, ctx) -> after long sleeps / loads
## Messages from ticks are returned by pump() for Life to Game.say().

const MODULES := {
	"followers": preload("res://scripts/realm/followers.gd"),
	"camps": preload("res://scripts/realm/camps.gd"),
	"settlements": preload("res://scripts/realm/settlements.gd"),
	"land": preload("res://scripts/realm/land.gd"),
	"factions": preload("res://scripts/realm/factions.gd"),
	"strongholds": preload("res://scripts/realm/strongholds.gd"),
	"campaign": preload("res://scripts/realm/campaign.gd"),
	"city_life": preload("res://scripts/realm/city_life.gd"),
	"society": preload("res://scripts/realm/society.gd"),
}
## Order matters within a tier: land before factions before campaign.
const ORDER := ["settlements", "land", "camps", "followers", "factions", "strongholds", "campaign", "city_life", "society"]
## Max microseconds of realm work per frame (mobile: ~0.6 ms of a 16.6 ms frame).
const PUMP_BUDGET_USEC := 600

var mods := {}
var _queue: Array = []   # [module_name, method, arg, ctx]


func _init() -> void:
	for k: String in ORDER:
		var m: RefCounted = MODULES[k].new()
		m.hub = self
		mods[k] = m


## Builds every module's lazy data (rosters, schedules, guilds) up front so the
## first in-game hour/day never pays for it. Call behind a loading screen.
func warm_up() -> void:
	for k: String in ORDER:
		var m: RefCounted = mods[k]
		for f: String in ["_ensure", "_ensure_npcs", "_ensure_guilds"]:
			if m.has_method(f) and m.get_method_argument_count(f) == 0:
				m.call(f)
	var cl: RefCounted = mods["city_life"]
	if cl.has_method("_ensure"):
		for st in WorldGen.settlements:
			cl.call("_ensure", int(st["id"]))


func mod(name: String) -> RefCounted:
	return mods.get(name)


func on_hour(hour: int, day: int, ctx: Dictionary) -> void:
	for k: String in ORDER:
		_queue.append([k, "tick_hour", hour, ctx])
	if hour == 6:
		for k: String in ORDER:
			_queue.append([k, "tick_day", day, ctx])
		if day % 7 == 0:
			for k: String in ORDER:
				_queue.append([k, "tick_week", day / 7, ctx])


## Runs queued jobs within the frame budget; at least one job per call so the
## queue always drains. Returns messages to show.
func pump() -> Array:
	var out: Array = []
	if _queue.is_empty():
		return out
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty():
		var j: Array = _queue.pop_front()
		var m: RefCounted = mods[j[0]]
		out.append_array(m.call(j[1], j[2], j[3]))
		if Time.get_ticks_usec() - t0 > PUMP_BUDGET_USEC:
			break
	return out


## Flush everything now (tests, save, sleep).
func drain() -> Array:
	var out: Array = []
	while not _queue.is_empty():
		var j: Array = _queue.pop_front()
		out.append_array(mods[j[0]].call(j[1], j[2], j[3]))
	return out


func catch_up(days: int, ctx: Dictionary) -> Array:
	var out := drain()
	for k: String in ORDER:
		out.append_array(mods[k].catch_up(days, ctx))
	return out


func serialize() -> Dictionary:
	var d := {}
	for k: String in ORDER:
		d[k] = mods[k].serialize()
	return d


func deserialize(d: Dictionary) -> void:
	_queue.clear()
	for k: String in ORDER:
		if d.get(k) is Dictionary:
			mods[k].deserialize(d[k])
