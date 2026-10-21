extends GdUnitTestSuite
## LW Stage 8 soak (docs/design/LIVING_WORLD_SANDBOX.md Part E, section 11 to 15): two game years of the whole realm hub with no player at all.
## About a thousand registry Characters live by the five decision layers over thousands of aggregate villagers: NPCs found organizations and
## businesses, marry, have children, move, grow old and die, estates pass to heirs, a noble succession runs, a chain of emergent events
## spreads and is announced as news, churches collect tithes and keep festivals. The save stays inside the doc's budget and each module's
## tick stays inside its job budget (with the allowance the other Stage 4/5 tests make for a slow shared container).

const Hub := preload("res://scripts/realm/realm_hub.gd")
const MINE := ["emergence", "faith", "dynasties", "homes", "minds", "rumours"]
const DAYS := 720
const START := 1000

static var _ready_world := false


func _bytes_zstd(s: String) -> int:
	return s.to_utf8_buffer().compress(FileAccess.COMPRESSION_ZSTD).size()


func test_two_years_without_the_player(timeout := 1_200_000) -> void:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	WorldSim.day = START
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.gold_ref = {"gold": 100000}
	var mn: RefCounted = h.mod("minds")
	mn.auto_seed = false
	mn.seed_target = 960
	mn.set_focus(-1)                                   # nobody is watching
	var seeded: int = mn.seed_minds(960)
	assert_int(seeded).is_greater(900)
	var reg: RefCounted = h.mod("registry")
	assert_int(reg.upgraded_count()).is_greater(900)
	var pop0: int = WorldSim.population()
	var simulated: int = reg.upgraded_count() + pop0
	assert_int(simulated).is_greater(1000)              # the thousand characters plus the aggregate villagers behind them

	var tot := {}
	var worst := {}
	var njobs := {}
	var size_y1 := {}
	var t_all0 := Time.get_ticks_usec()
	for i in DAYS:
		var d := START + 1 + i
		WorldSim.day = d
		h.on_hour(6, d, {})
		while not h._queue.is_empty():
			var j: Array = h._queue.pop_front()
			var nm: String = j[0] if j[0] != "" else "other"
			if j[0] in MINE and j[1] == "tick_day":
				var cbs: Array = h.mod(j[0]).tick_day_chunks(j[2], j[3])
				if cbs.is_empty():
					var t1 := Time.get_ticks_usec()
					h.mod(j[0]).tick_day(j[2], j[3])
					_note(tot, worst, njobs, nm + ".day", Time.get_ticks_usec() - t1)
				else:
					for cb: Callable in cbs:
						var t2 := Time.get_ticks_usec()
						cb.call()
						_note(tot, worst, njobs, nm + ".chunk", Time.get_ticks_usec() - t2)
			elif j[0] in MINE:
				var t3 := Time.get_ticks_usec()
				h._run_job(j)
				_note(tot, worst, njobs, nm + "." + String(j[1]).trim_prefix("tick_"), Time.get_ticks_usec() - t3)
			else:
				h._run_job(j)
		if i == 359:
			for k: String in MINE:
				size_y1[k] = JSON.stringify(h.mod(k).serialize()).length()
			size_y1["realm"] = JSON.stringify(h.serialize()).length()
	var wall: int = (Time.get_ticks_usec() - t_all0) / 1000

	# --- what happened -----------------------------------------------------------------
	var hm: RefCounted = h.mod("homes")
	var dn: RefCounted = h.mod("dynasties")
	var em: RefCounted = h.mod("emergence")
	var fa: RefCounted = h.mod("faith")
	var su: RefCounted = h.mod("succession")
	var rm: RefCounted = h.mod("rumours")
	var bz: RefCounted = h.mod("businesses")
	var ev: RefCounted = h.mod("events")
	print("SOAK minds ", mn.stats)
	print("SOAK homes ", hm.stats)
	print("SOAK dynasties ", dn.stats, " houses ", dn.house_count(), " feuds ", dn.feud_count())
	print("SOAK emergence ", em.stats, " ", em.history().slice(0, 12))
	print("SOAK faith ", fa.stats)
	print("SOAK rumours ", rm.stats)
	print("SOAK orgs ", om.stats, " businesses ", bz.stats)
	print("SOAK succession ", su.stats)
	print("SOAK events total ", ev.total(), " marriage ", ev.count("marriage"), " death ", ev.count("death"), " birth ", ev.count("birth"), " succession ", ev.count("succession"))
	print("SOAK wall ms ", wall, " minds alive ", mn.count(), " registry ", reg.upgraded_count())

	assert_int(mn.count()).is_greater(850)             # still about a thousand people (births and top-ups replace the dead)
	assert_int(int(om.stats["npc_founded"]) + int(mn.stats["org_found"])).is_greater(0)     # NPC-founded organizations
	assert_int(int(bz.stats["npc_founded"])).is_greater(0)                                  # NPC-founded businesses
	assert_int(int(mn.stats["business"]) + int(mn.stats["org_found"]) + int(mn.stats["org_join"])).is_greater(0)   # by the new decision layer too
	assert_int(ev.count("marriage")).is_greater(10)    # marriages
	assert_int(int(hm.stats["births"])).is_greater(5)
	assert_int(int(mn.stats["move"]) + int(hm.stats["relocations"])).is_greater(0)          # moves
	assert_int(int(mn.stats["deaths"])).is_greater(5)  # deaths
	assert_int(int(dn.stats["estates"])).is_equal(int(mn.stats["deaths"]))                  # each death settled an estate
	assert_int(int(dn.stats["successions"]) + int(su.stats["successions"]) + int(su.stats["disputes"])).is_greater(0)   # a succession
	assert_int(int(em.stats["started"])).is_greater(0)                                      # an emergent chain
	assert_int(int(em.stats["news"])).is_greater(0)                                         # announced as news
	assert_int(int(fa.stats["festivals"])).is_greater(3)
	assert_int(int(fa.stats["tithes"])).is_greater(0)
	assert_int(int(rm.stats["arrived"])).is_greater(0)

	# --- saves --------------------------------------------------------------------------
	var size_y2 := {}
	var new_raw := 0
	var new_zstd := 0
	for k: String in MINE:
		var raw := JSON.stringify(h.mod(k).serialize())
		size_y2[k] = raw.length()
		new_raw += raw.length()
		new_zstd += _bytes_zstd(raw)
	var realm_raw := JSON.stringify(h.serialize())
	size_y2["realm"] = realm_raw.length()
	var realm_zstd := _bytes_zstd(realm_raw)
	var growth := 0
	for k: String in MINE:
		growth += int(size_y2[k]) - int(size_y1[k])
	print("SOAK sizes year1 ", size_y1, " year2 ", size_y2)
	print("SOAK new modules raw ", new_raw, " zstd ", new_zstd, " growth in year two ", growth, " realm raw ", realm_raw.length(), " zstd ", realm_zstd)
	assert_int(realm_raw.length()).is_less(2_500_000)    # the doc's full-save limit for 1,000 characters
	assert_int(realm_zstd).is_less(600_000)
	assert_int(growth).is_less(150_000)                  # growth per year after the first
	assert_int(new_raw).is_less(700_000)
	assert_int(new_zstd).is_less(200_000)

	# --- the cost of a tick -------------------------------------------------------------
	var lines := []
	for k: String in tot:
		var days_n: float = float(DAYS) if (k.ends_with(".day") or k.ends_with(".chunk")) else float(DAYS) / 7.0
		lines.append("%s: %.3f ms a day, worst job %.2f ms over %d jobs" % [k, float(tot[k]) / 1000.0 / float(DAYS), float(worst[k]) / 1000.0, int(njobs[k])])
	lines.sort()
	for l: String in lines:
		print("SOAK cost ", l)
	# every module's day tick, summed, stays at or under the doc's per-module hour/day allowances (0.6 ms a job; slow-box allowance x4)
	for k: String in tot:
		if k.ends_with(".chunk"):
			assert_float(float(tot[k]) / float(maxi(1, int(njobs[k])))).is_less(2400.0)   # the average chunk
			assert_int(int(worst[k])).is_less(45_000)                                   # (a slow shared box: the typical worst chunk is 5 to 8 ms)
		else:
			assert_int(int(worst[k])).is_less(30_000)
	assert_float(float(tot["minds.chunk"]) / 1000.0 / float(DAYS)).is_less(25.0)          # decisions for a thousand characters, a day, in ms
	assert_float(float(tot.get("faith.day", 0)) / 1000.0 / float(DAYS)).is_less(2.4)
	assert_float(float(tot.get("rumours.day", 0)) / 1000.0 / float(DAYS)).is_less(2.4)


func _note(tot: Dictionary, worst: Dictionary, njobs: Dictionary, key: String, us: int) -> void:
	tot[key] = int(tot.get(key, 0)) + us
	worst[key] = maxi(int(worst.get(key, 0)), us)
	njobs[key] = int(njobs.get(key, 0)) + 1
