extends Node
## Region 1 balance run (package L18): 100 game days for each archetype, deterministic by seed, through the real game
## systems (see balance_sim.gd). Headless:
##   Godot --headless --path kingdom res://tools_qa/region1/balance_run.tscn -- [--days=100] [--seeds=3] [--arch=farmer,soldier,...]
##       [--out=/tmp/claude-0/balance_r1] [--tag=after] [--markets=0]
## Writes <out>/<tag>_<arch>_s<seed>.csv (gold, career rank, soul tier, gear tier, house owned, food security, bounty, deaths
## per day) and <out>/<tag>_summary.json, and prints a summary table. Exit code 0.

const Sim := preload("res://tools_qa/region1/balance_sim.gd")
const PROBE_PATH := "res://tools_qa/region1/balance_probe.gd"      # loaded on demand: the probes need the C13 code, the plain run does not


func _ready() -> void:
	var args := _args()
	var days := int(args.get("days", "100"))
	var seeds := int(args.get("seeds", "3"))
	var out_dir := String(args.get("out", "/tmp/claude-0/balance_r1"))
	var tag := String(args.get("tag", "run"))
	var markets := int(args.get("markets", "0"))
	var archs: Array = String(args.get("arch", ",".join(Sim.ARCHETYPES))).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if args.has("probe"):
		_probes(String(args["probe"]).split(","), out_dir, tag, int(args.get("days", "30")))
		get_tree().quit(0)
		return
	var all: Array = []
	var t0 := Time.get_ticks_msec()
	for a: String in archs:
		for s in range(1, seeds + 1):
			var sim: RefCounted = Sim.new(a, s, days)
			sim.markets_limit = markets
			var sm: Dictionary = sim.run()
			var f := FileAccess.open("%s/%s_%s_s%d.csv" % [out_dir, tag, a, s], FileAccess.WRITE)
			f.store_string(sim.csv())
			f.close()
			sm["events"] = sim.events
			all.append(sm)
			print("%-10s seed %d: gold %5d  rank %d/%d %-18s soul %d (%.0f)  gear %d  house %s  deaths %d  lvl %d  fed %.0f%%  [%s]" % [a, s, sm["gold"], sm["career_rank"], sm["rank_count"],
				sm["career_rank_name"], sm["soul_tier"], Life.soul.power, sm["gear_tier"], str(sm["first_day"].get("house", "-")), sm["deaths"], sm["level"],
				100.0 * float(sm["fed_share"]), JSON.stringify(sm["first_day"])])
			if ResourceLoader.exists("res://scripts/region1/progression_spine.gd"):
				var ev: Dictionary = (load("res://scripts/region1/progression_spine.gd") as GDScript).call("evaluate", sm)
				var bad := PackedStringArray()
				for c: Dictionary in ev["checks"]:
					if not bool(c["ok"]):
						bad.append("%s (have %s)" % [String(c["name"]), str(c["have"])])
				print("   targets: ", "ALL MET" if bad.is_empty() else "MISSED " + ", ".join(bad))
			if args.has("v"):
				print("   xp_by ", JSON.stringify(sm["xp_by"]), "\n   counters ", JSON.stringify(sm["counters"]), "\n   income ", JSON.stringify(sm["income"]), "\n   spend ", JSON.stringify(sm["spend"]), "\n   events ", sim.events)
	var jf := FileAccess.open("%s/%s_summary_%s.json" % [out_dir, tag, String(args.get("arch", "all")).replace(",", "-")], FileAccess.WRITE)
	jf.store_string(JSON.stringify(all, "  "))
	jf.close()
	print("balance_run: %d runs in %.1f s -> %s" % [all.size(), float(Time.get_ticks_msec() - t0) / 1000.0, out_dir])
	get_tree().quit(0)


func _args() -> Dictionary:
	var d := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			d[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1)
	return d


## --probe=quests,wages,loops,pickpocket,oracle (see balance_probe.gd). Writes <out>/<tag>_probe.json and prints it.
func _probes(which: PackedStringArray, out_dir: String, tag: String, days: int) -> void:
	var Probe: GDScript = load(PROBE_PATH)
	var res := {}
	var sim: RefCounted = Sim.new("merchant", 1, days)
	sim.setup()
	if "quests" in which or "all" in which:
		var q: Dictionary = Probe.probe_quests()
		q.erase("rows")
		res["quests"] = q
	if "wages" in which or "all" in which:
		res["wages"] = Probe.probe_wages()
	if "loops" in which or "all" in which:
		res["loops"] = Probe.probe_loops()
	if "pickpocket" in which or "all" in which:
		res["pickpocket"] = {"stealth_3_witness_1": Probe.probe_pickpocket(days, 3.0, 1.0)}
		sim.setup()
		res["pickpocket"]["stealth_7_witness_0_5"] = Probe.probe_pickpocket(days, 7.0, 0.5)
		sim.setup()
	if "craft" in which or "all" in which:
		sim.setup()
		res["craft_loop"] = Probe.probe_craft_loop(min(days, 5), 30)
	if "oracle" in which or "all" in which:
		sim.setup()
		res["oracle_merchant"] = Probe.probe_oracle_merchant(sim, days, 6)
	var f := FileAccess.open("%s/%s_probe.json" % [out_dir, tag], FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()
	print("PROBE ", JSON.stringify(res))
