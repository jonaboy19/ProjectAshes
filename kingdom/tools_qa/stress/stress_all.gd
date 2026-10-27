extends RefCounted
## WP-06 stress scenario, sim half (docs/plans/MASTER_BACKLOG.md): one headless run with a caravan Ashford -> Kingsreach on the
## road, a fire in Ashford, a raid on a second settlement and a dungeon floor generated, then 48 in-game hours of the whole
## realm hub + economy, timing every module. `run()` returns the report; stress_all_cli.gd prints it, tests/test_stress_sim.gd
## asserts it. The windowed frame-time half is a LOCAL job.
## Unit of cost: one busy sim frame, i.e. one RealmHub.pump() call that has queued work (jobs run until PUMP_BUDGET_USEC is spent,
## at least one job). Frames with nothing queued cost ~0 and are left out, so the average is a conservative per-frame figure.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const RAEconomy := preload("res://scripts/sim/economy.gd")
const RAMarket := preload("res://scripts/sim/market.gd")
const DungeonGen := preload("res://scripts/interiors/dungeon_gen.gd")

const HOURS := 48
const SEED := 1066
const BUDGET_MS := 4.0


static func _town(name: String) -> int:
	for s: Dictionary in WorldGen.settlements:
		if String(s["name"]) == name:
			return int(s["id"])
	return -1


static func _bump(acc: Dictionary, key: String, usec: int) -> void:
	acc[key] = int(acc.get(key, 0)) + usec


static func run(hours := HOURS) -> Dictionary:
	print("STRESS step: worldgen")
	WorldGen.setup(SEED)
	var sim: Node = (Engine.get_main_loop() as SceneTree).root.get_node("WorldSim")   # autoload: no compile-time name in -s scripts
	sim.day = 1
	var ashford := _town("Ashford")
	var kings := _town("Kingsreach")
	var raided := -1
	for s: Dictionary in WorldGen.settlements:
		var sid := int(s["id"])
		if sid != ashford and sid != kings and String(s["kind"]) != "castle":
			raided = sid
			break
	var rep := {"ok": ashford >= 0 and kings >= 0 and raided >= 0, "hours": hours, "events": {}}
	if not bool(rep["ok"]):
		return rep

	var t0 := Time.get_ticks_usec()
	var hub: RefCounted = Hub.new()
	hub.mod("organizations").auto_seed = false
	print("STRESS step: warm_up")
	hub.warm_up()
	print("STRESS step: economy")
	var eco := RAEconomy.new()
	eco.setup(0)
	eco.bind_home_market(0, RAMarket.new())
	rep["setup_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0

	var start_abs := float(int(sim.day) * 24 + 6)
	# 1. caravan Ashford -> Kingsreach with a little cargo and two guards
	var car: Dictionary = eco.caravans.send(ashford, kings, {"grain": 40, "iron": 10}, 2, "kingdom", 0.1, start_abs, SEED)
	# 2. a building fire in Ashford (the settlements emergency the player can answer with gold)
	var set_mod: RefCounted = hub.mod("settlements")
	set_mod._ensure()
	var fire: Dictionary = set_mod._start(ashford, "fire", 0.8)
	# 3. a faction raid on another settlement
	set_mod.raid_aftermath(raided, 0.7)
	hub.mod("news")._ensure()
	rep["events"] = {"caravan": int(car.get("id", 0)), "caravan_hours": float(car.get("arrive", 0.0)) - start_abs,
		"fire": int(fire.get("id", 0)), "raid_sid": raided}
	# 4. a dungeon floor loads (generation is the sim-side cost of a floor load)
	var td := Time.get_ticks_usec()
	var floor_g: Dictionary = DungeonGen.generate(SEED, "cave", 2)
	rep["dungeon_ms"] = float(Time.get_ticks_usec() - td) / 1000.0
	rep["dungeon_rooms"] = (floor_g.get("rooms", []) as Array).size()

	# 5. advance `hours` in-game hours the way the game does: RealmHub.on_hour queues every module's tick (day / week ticks at 06:00),
	# the economy queues its chunked hourly jobs, and each frame runs queued jobs until PUMP_BUDGET_USEC is spent (RealmHub.pump).
	# Jobs are popped here instead of calling pump() so the time can be charged to a module.
	var per_mod := {}
	var frames := 0
	var worst_frame := 0
	var total := 0
	var arrived := 0
	var base_day: int = sim.day
	for h in hours:
		var abs_h := int(start_abs) + h
		var day := abs_h / 24
		var hod := abs_h % 24
		sim.day = day
		var ctx := {"season": "summer", "festival": false, "at_war": false, "mine_opened": false, "abs_hours": abs_h, "gold": 500, "life": null}
		hub.on_hour(hod, day, ctx)
		hub.queue_jobs(eco.queue_hour_jobs(1.0, ctx))
		while not hub._queue.is_empty():
			var frame := 0
			while not hub._queue.is_empty():
				var j: Array = hub._queue.pop_front()
				var key := String(j[0]) if String(j[0]) != "" else "economy"
				var t := Time.get_ticks_usec()
				var lines: Array = hub._run_job(j)
				var dt := Time.get_ticks_usec() - t
				if key == "economy":
					arrived += lines.size()
				_bump(per_mod, key, dt)
				frame += dt
				if frame > Hub.PUMP_BUDGET_USEC:
					break
			frames += 1
			total += frame
			worst_frame = maxi(worst_frame, frame)
	sim.day = base_day
	var rows: Array = []
	for k: String in per_mod:
		rows.append({"module": k, "ms": float(per_mod[k]) / 1000.0})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ms"]) > float(b["ms"]))
	rep["per_module"] = rows
	rep["frames"] = frames
	rep["avg_ms"] = float(total) / 1000.0 / float(maxi(frames, 1))
	rep["worst_ms"] = float(worst_frame) / 1000.0
	rep["total_ms"] = float(total) / 1000.0
	var c2: Dictionary = eco.caravans.get_caravan(int(car["id"]))
	rep["caravan_status"] = String(c2.get("status", ""))
	rep["caravan_reports"] = arrived
	rep["fire_open"] = set_mod.emergencies(ashford).size()
	return rep
