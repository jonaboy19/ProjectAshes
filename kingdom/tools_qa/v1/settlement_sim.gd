extends SceneTree
## Ready v1 (C4) settlement growth sim: a founded camp, N followers and a player who lays plans (cottages, a well, a banner and a
## table) and keeps the stores stocked, run headless for 120 days through the real build_kit, construction, followers and growth
## modules. Writes one CSV row per day. Used by tests/test_v1_settlement_growth.gd.
##
## Run:  godot --headless --path . -s res://tools_qa/v1/settlement_sim.gd -- [--days=120] [--followers=3] [--csv=path]
## Exit code 1 unless the camp reaches Village between day 60 and 90.

const HUB_PATH := "res://scripts/realm/realm_hub.gd"      # loaded at run time: a -s script is compiled before the autoloads exist
const HEADER := "day,pop,food,food_days,content,tier,houses,capacity,made,eaten,pieces,hamlet_day,village_day"
## The player's plan: day -> what to lay down next (cell offsets of the cottage / the props).
const COTTAGES := [[0, 0], [4, 0], [0, 4], [4, 4]]
const COTTAGE_DAYS := [1, 15, 32, 48]
const WELL_DAY := 45
const HALL_DAY := 62
const BAG := {"log": 400, "plank": 300, "thatch": 300, "stone": 200, "clay": 100, "cut_stone": 100, "iron_ingot": 40, "cloth": 30, "tools": 3}


func _initialize() -> void:
	var days := 120
	var followers := 3
	var csv := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.get_slice("=", 1))
		elif a.begins_with("--followers="):
			followers = int(a.get_slice("=", 1))
		elif a.begins_with("--csv="):
			csv = a.get_slice("=", 1)
	var res := run(days, followers)
	var lines: PackedStringArray = [HEADER]
	lines.append_array(res["rows"])
	if csv != "":
		var f := FileAccess.open(csv, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
	else:
		print("\n".join(lines))
	var vd := int(res["village_day"])
	print("hamlet day %d, village day %d, final pop %d" % [int(res["hamlet_day"]), vd, int(res["pop"])])
	quit(0 if vd >= 60 and vd <= 90 else 1)


static func make_hub() -> RefCounted:
	var tree := Engine.get_main_loop() as SceneTree
	WorldGen.setup(int(tree.root.get_node("WorldSim").get("SEED")))
	var hub: RefCounted = (load(HUB_PATH) as GDScript).new()
	var rs := RARunestoneNetwork.new()
	rs.seed_road_stones()
	hub.mod("civilization").runestones = rs
	for m: String in ["civilization", "migration", "land"]:
		hub.mod(m)._ensure()
	hub.mod("build_kit").height_fn = func(x: float, z: float) -> float: return WorldGen.height(x, z)
	hub.mod("construction").bag = BAG.duplicate()
	return hub


## A claimable spot (the founding module says yes), the first on a fixed random walk.
static func find_spot(hub: RefCounted) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for _i in 6000:
		var p := Vector2(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0))
		if _flat(p) and bool(hub.mod("founding").check_site(p)["ok"]):
			return p
	return Vector2.INF


## Level ground for the whole build plan: no more than 0.5 m of fall within 14 m (the kit refuses steep foundations).
static func _flat(p: Vector2, tol := 0.5) -> bool:
	var h0: float = WorldGen.height(p.x, p.y)
	for k in 12:
		var a := TAU * float(k) / 12.0
		for r in [5.0, 10.0, 14.0]:
			if absf(WorldGen.height(p.x + cos(a) * r, p.y + sin(a) * r) - h0) > tol:
				return false
	return true


## Runs `days` days; returns {rows: CSV lines, hamlet_day, village_day, pop, hub, gid}.
static func run(days: int, followers: int, hub_in: RefCounted = null, hook: Callable = Callable()) -> Dictionary:
	var hub: RefCounted = hub_in if hub_in != null else make_hub()
	var spot := find_spot(hub)
	var kit: RefCounted = hub.mod("build_kit")
	var growth: RefCounted = hub.mod("growth")
	var cons: RefCounted = hub.mod("construction")
	var fm: RefCounted = hub.mod("followers")
	var r: Dictionary = kit.claim(Vector3(spot.x, 0.0, spot.y), "squat", "Simhold")
	var gid := int(r["gid"])
	for i in followers:
		fm.hire("guard", "s0", true, "sim%d" % i)
	var rows: Array = []
	var hamlet_day := -1
	var village_day := -1
	for day in range(1, days + 1):
		_player_turn(kit, gid, day)
		if hook.is_valid():
			hook.call(day, hub, gid)
		cons.tick_day(day, {})
		for h in 24:
			if h == 6:
				growth.tick_day(day, {})
			kit.tick_hour(h, {})
			cons.tick_hour(h, {})
		var l: Dictionary = growth.ledger(gid)
		if int(l["tier"]) >= 1 and hamlet_day < 0:
			hamlet_day = day
		if int(l["tier"]) >= 2 and village_day < 0:
			village_day = day
		rows.append("%d,%d,%.1f,%.2f,%.3f,%d,%d,%d,%.1f,%.1f,%d,%d,%d" % [day, l["pop"], l["food"], l["food_days"], l["content"], l["tier"], l["houses"],
			l["capacity"], l["food_made"], l["food_eaten"], int(l["structures"]["pieces"]), hamlet_day, village_day])
	var last: Dictionary = growth.ledger(gid)
	return {"rows": rows, "hamlet_day": hamlet_day, "village_day": village_day, "pop": int(last["pop"]), "hub": hub, "gid": gid}


static func _player_turn(kit: RefCounted, gid: int, day: int) -> void:
	var i: int = COTTAGE_DAYS.find(day)
	if i >= 0:
		var bp: Dictionary = kit.place_blueprint(gid, "cottage", int(COTTAGES[i][0]), int(COTTAGES[i][1]))
		if not bool(bp["ok"]):
			print("day %d cottage %d: %d placed, %d failed: %s" % [day, i, bp["placed"], bp["failed"], str(bp["reasons"]).left(200)])
	if day == WELL_DAY:
		_prop(kit, gid, "meshy_well_stone_roofed", Vector3(-6.0, 0.0, 6.0))
	if day == HALL_DAY:
		_prop(kit, gid, "meshy_banner_stand_iron_frame", Vector3(2.0, 0.0, 2.0))
		_prop(kit, gid, "table_bench", Vector3(4.0, 0.0, 2.0))


static func _prop(kit: RefCounted, gid: int, kind: String, local: Vector3) -> void:
	var s: Dictionary = kit.snap_local(gid, kind, local, 0, 0)
	var r: Dictionary = kit.place(gid, s, true)
	if not bool(r["ok"]):
		print("prop %s: %s" % [kind, r["reason"]])
