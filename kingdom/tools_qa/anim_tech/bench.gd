extends RefCounted
## Performance bench for the anim_tech techniques: ms per character per frame.
##
##   Godot --path kingdom --rendering-method mobile res://tools_qa/anim_tech/anim_tech_demo.tscn -- --bench=<abs json path> [--tech=foot_ik,flinch]
##
## For every technique T and N in COUNTS the demo spawns N UAL characters (a grid, all playing the Walk clip and
## moving on a small circle, so movement-driven code is exercised), attaches T to each, warms up, then records
## FRAMES frames. The animation mixers and the skeleton modifier stacks are switched to MANUAL mode and advanced by
## this script inside a microsecond timer (AnimationMixer.advance + Skeleton3D.advance, plus the rig's physics-tick
## ray code called by hand), so the number is the CPU cost of animation + techniques only: no renderer, GPU skinning,
## vsync or driver noise (measured wall-clock frame time drifted +-30 % between runs, more than these costs). The
## ragdolls need the physics server, so they use the wall-clock slope (frame ms vs N) instead. Numbers are PC (RTX laptop, mobile renderer, vsync off);
## the phone estimate is x PHONE_FACTOR (see .claude/skills/ashes-performance: a phone CPU is ~5x slower).
## Composite QUALITY TIERS (LOW / MEDIUM / HIGH bundles) are measured the same way at the end.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const Flinch := preload("res://tools_qa/anim_tech/lib/flinch.gd")
const LeanAim := preload("res://tools_qa/anim_tech/lib/lean_aim.gd")
const Loco := preload("res://tools_qa/anim_tech/lib/loco_tree.gd")
const LookAtRig := preload("res://tools_qa/anim_tech/lib/look_at.gd")
const FootIK := preload("res://tools_qa/anim_tech/lib/foot_ik.gd")
const Cape := preload("res://tools_qa/anim_tech/lib/cape.gd")
const PartialRagdoll := preload("res://tools_qa/anim_tech/lib/partial_ragdoll.gd")
const Ragdoll := preload("res://scripts/actors/ragdoll.gd")
const MotionWarp := preload("res://tools_qa/anim_tech/lib/motion_warp.gd")

const COUNTS := [1, 10, 25, 50]
const WARMUP := 45
const FRAMES := 180
const PHONE_FACTOR := 5.0
## Character budget share of the frame CPU budget (ashes-performance: LOW <= 6 ms, MEDIUM/HIGH <= 3 ms CPU on PC).
const TIER_BUDGET_MS := {"LOW": 6.0 * 0.4, "MEDIUM": 3.0 * 0.4, "HIGH": 3.0 * 0.4}
## [bench id, demo id (for --tech filtering), label]
const TECHS := [
	["clip", "", "plain clip (baseline)"],
	["loco_tree", "blendtree", "synced locomotion blend space (AnimationTree)"],
	["flinch_idle", "flinch", "additive flinch tree, idle"],
	["flinch_hit", "flinch", "additive flinch tree, hit every 0.6 s"],
	["lean_aim", "lean", "lean + aim twist (SkeletonModifier3D)"],
	["look_at", "look_at", "head look-at (2x LookAtModifier3D)"],
	["foot_ik", "foot_ik", "foot IK + toe probe (2x TwoBoneIK3D, 6 rays/tick)"],
	["cape", "springs", "cape springs (12 spring bones + skinned quad)"],
	["root_motion", "rootmotion", "root motion + motion warp step"],
	["partial_ragdoll", "ragdoll", "partial ragdoll hit reaction (cap 3 live)"],
	["full_ragdoll", "ragdoll", "full ragdoll, simulating (cap 3 live)"],
]
## Composite bundles per quality tier (what a character runs at that tier).
const TIERS := {
	"LOW": ["clip"],
	"MEDIUM": ["loco_tree", "lean_aim", "flinch_idle"],
	"HIGH": ["loco_tree", "lean_aim", "flinch_idle", "foot_ik", "look_at", "cape"],
}

var _d: Node3D
var _t := 0.0                     # scene time for the circle movement
var _target: MeshInstance3D


func run(d: Node3D, ids: Array[String], path: String) -> void:
	_d = d
	var results := {}
	var want: Array = []
	for t: Array in TECHS:
		if t[0] == "clip" or ids.is_empty() or ids.size() >= 10 or ids.has(t[1]):
			want.append(t)
	var sizes := COUNTS
	for t: Array in want:
		var per := []
		for n: int in sizes:
			if (t[0] == "partial_ragdoll" or t[0] == "full_ragdoll") and n > 3:
				continue
			var m := await _measure(d, [t[0]], n)
			per.append(m)
			print("[bench] %-16s N=%-2d frame %.3f ms  anim+tech CPU %.4f ms (%.4f ms/char)" % [t[0], n, m["wall_ms"], m["anim_ms"], m["anim_ms"] / n])
		results[t[0]] = {"label": t[2], "runs": per}
	# tiers
	var tiers := {}
	for tier: String in TIERS:
		var per := []
		for n: int in sizes:
			var m := await _measure(d, TIERS[tier], n)
			per.append(m)
			print("[bench] tier %-6s N=%-2d frame %.3f ms  anim+tech CPU %.4f ms (%.4f ms/char)" % [tier, n, m["wall_ms"], m["anim_ms"], m["anim_ms"] / n])
		tiers[tier] = per
	var base_runs: Array = results["clip"]["runs"]
	var out := {"counts": sizes, "results": results, "tiers": tiers, "phone_factor": PHONE_FACTOR}
	var table := []
	var base_pc := _per_char(base_runs)
	for id: String in results:
		if id == "clip":
			continue
		var runs: Array = results[id]["runs"]
		var ragdoll := id.ends_with("ragdoll")
		var pc: float
		if ragdoll:
			var ns: Array = []
			for r: Dictionary in runs:
				ns.append(r["n"])
			pc = _slope(runs, "wall_ms") - _slope(base_runs, "wall_ms", ns)
		else:
			pc = _per_char(runs) - base_pc
		table.append({"id": id, "label": results[id]["label"], "ms_per_char": pc, "phone_ms_per_char": pc * PHONE_FACTOR, "method": "wall slope" if ragdoll else "manual advance timer"})
		print("[bench] RESULT %-16s +%.4f ms/char (phone ~%.3f ms)  [%s]" % [id, pc, pc * PHONE_FACTOR, "wall slope" if ragdoll else "advance timer"])
	out["per_char"] = table
	out["baseline_ms_per_char"] = base_pc
	print("[bench] RESULT clip baseline (AnimationPlayer + skeleton, no technique): %.4f ms/char (phone ~%.3f ms)" % [base_pc, base_pc * PHONE_FACTOR])
	var tier_table := {}
	for tier: String in tiers:
		var pc := _per_char(tiers[tier])
		var budget: float = TIER_BUDGET_MS[tier]
		var afford := int(floor(budget / maxf(pc, 0.0005)))
		tier_table[tier] = {"ms_per_char": pc, "phone_ms_per_char": pc * PHONE_FACTOR, "budget_ms": budget, "afford": afford}
		print("[bench] TIER %-6s %.4f ms/char (phone ~%.3f), character budget %.1f ms -> %d characters" % [tier, pc, pc * PHONE_FACTOR, budget, afford])
	out["tier_table"] = tier_table
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
		print("[bench] wrote ", path)


## Mean of anim_ms / n over the runs with n >= 10 (small crowds are dominated by timer resolution).
func _per_char(runs: Array) -> float:
	var sum := 0.0
	var k := 0
	for r: Dictionary in runs:
		if int(r["n"]) >= 10:
			sum += float(r["anim_ms"]) / int(r["n"])
			k += 1
	return sum / maxi(k, 1)


## Least-squares slope of `key` vs n. `only_n` restricts the baseline to the same N values.
func _slope(runs: Array, key: String, only_n: Array = []) -> float:
	var xs: Array[float] = []
	var ys: Array[float] = []
	for r: Dictionary in runs:
		if only_n.is_empty() or only_n.has(r["n"]):
			xs.append(float(r["n"]))
			ys.append(float(r[key]))
	if xs.size() < 2:
		return ys[0] / xs[0] if xs.size() == 1 else 0.0
	var mx := 0.0
	var my := 0.0
	for i in xs.size():
		mx += xs[i]
		my += ys[i]
	mx /= xs.size()
	my /= xs.size()
	var num := 0.0
	var den := 0.0
	for i in xs.size():
		num += (xs[i] - mx) * (ys[i] - my)
		den += (xs[i] - mx) * (xs[i] - mx)
	return num / maxf(den, 0.0001)


func _measure(d: Node3D, techs: Array, n: int) -> Dictionary:
	d._clear_stage()
	d.set_cam(Vector3(0, 7.0, 15.0), Vector3(0, 0.8, 0), 55.0)
	_target = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	_target.mesh = sm
	d.stage.add_child(_target)
	var Ragdoll_ := Ragdoll
	Ragdoll_.reset_slots()
	var cs: Array = []
	var cols := 10
	for i in n:
		var pos := Vector3((i % cols - (cols - 1) * 0.5) * 1.6, 0, -(i / cols) * 1.8)
		var c: Dictionary = d.spawn(pos, 0.0)
		c["home"] = pos
		c["idx"] = i
		cs.append(c)
	var handles := {}
	var ragdolls0 := techs.has("partial_ragdoll") or techs.has("full_ragdoll")
	for c: Dictionary in cs:
		var ap: AnimationPlayer = c["ap"]
		var walk := U.find_clip(ap, ["Walk", "Walking_A"])
		c["walk"] = walk
		if not techs.has("loco_tree"):
			ap.play(walk)
			ap.seek(randf() * 1.3)
		for t: String in techs:
			_attach(t, c, handles)
		if not ragdolls0:
			c["mixers"] = [ap]
			for k in ["loco", "flinch"]:
				if c.has(k):
					c["mixers"].append((c[k] as RefCounted).tree)
			for mx: AnimationMixer in c["mixers"]:
				mx.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			(c["sk"] as Skeleton3D).modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
			if c.has("rig") and c["rig"] != null:
				(c["rig"] as Node).set_physics_process(false)
	var deltas: Array[float] = []
	var procs: Array[float] = []      # anim+technique CPU ms per frame for the whole crowd
	var frame := 0
	var hit_timer := 0.0
	var total := WARMUP + FRAMES
	var partial_timer := 0.0
	var die_done := false
	while frame < total:
		await d.get_tree().process_frame
		var dt: float = d.get_process_delta_time()
		_t += dt
		frame += 1
		# common movement: a small circle per character (speed ~1.2 m/s)
		var ragdolls := techs.has("partial_ragdoll") or techs.has("full_ragdoll")
		for c: Dictionary in cs:
			if ragdolls:
				break
			var a: Node3D = c["actor"]
			var ph: float = _t * 0.9 + int(c["idx"]) * 0.7
			a.position = (c["home"] as Vector3) + Vector3(sin(ph), 0, cos(ph) - 1.0) * 0.55
			a.rotation.y = ph + PI * 0.5
		_target.position = Vector3(0.0, 1.6, 3.0 + sin(_t) * 2.0)
		hit_timer += dt
		partial_timer += dt
		if techs.has("flinch_hit") and hit_timer > 0.6:
			hit_timer = 0.0
			for c: Dictionary in cs:
				(c["flinch"] as RefCounted).hit(Vector2(0, 1), 1.2)
		if techs.has("partial_ragdoll") and partial_timer > 1.0:
			partial_timer = 0.0
			for c: Dictionary in cs:
				(c["prag"] as Node).hit_react(Vector3(0.4, 0, -1.0), 3.0)
		if techs.has("full_ragdoll") and not die_done and frame == 10:
			die_done = true
			for c: Dictionary in cs:
				(c["rag"] as Node).die(Vector3(2.0, 0, -5.0), Vector3(-1.5, 1.1, 3.0))
		var us0 := Time.get_ticks_usec()
		if not ragdolls0:
			for c: Dictionary in cs:
				for mx: AnimationMixer in c["mixers"]:
					mx.advance(dt)
				if c.has("rig") and c["rig"] != null:
					(c["rig"] as Node).call("_physics_process", dt)
				(c["sk"] as Skeleton3D).advance(dt)
		if techs.has("root_motion"):
			_root_motion_step(cs, dt)
		var us := Time.get_ticks_usec() - us0
		if frame > WARMUP:
			deltas.append(dt * 1000.0)
			procs.append(us / 1000.0)
	# free the crowd (next run builds its own)
	handles.clear()
	deltas.sort()
	procs.sort()
	var wall := 0.0
	var proc := 0.0
	# trimmed mean (drop the slowest 5 % hitches, keep p95 separately)
	var keep := int(deltas.size() * 0.95)
	for i in keep:
		wall += deltas[i]
		proc += procs[i]
	return {"n": n, "wall_ms": wall / keep, "anim_ms": proc / keep, "wall_p95": deltas[keep - 1], "wall_max": deltas[-1]}


func _attach(tech: String, c: Dictionary, handles: Dictionary) -> void:
	var model: Node3D = c["model"]
	match tech:
		"clip":
			pass
		"loco_tree":
			c["loco"] = Loco.attach(model, Loco.SYNC_PHASE)
			(c["loco"] as RefCounted).set_speed(1.2 + (int(c["idx"]) % 5) * 0.8)
		"flinch_idle", "flinch_hit":
			c["flinch"] = Flinch.attach(model, c["walk"])
		"lean_aim":
			var m: SkeletonModifier3D = LeanAim.attach(model, c["actor"])
			m.set("aim_target", _target)
		"look_at":
			LookAtRig.attach(model, _target)
		"foot_ik":
			c["rig"] = FootIK.attach_toe(model, null, true)
		"cape":
			Cape.attach(model)
		"root_motion":
			var ap: AnimationPlayer = c["ap"]
			var names := U.import_clips(ap, c["sk"], U.FREE_DIR + "kicks/UAL_Free_Kicks.glb", ["MA_Kick_Jump_R"], true)
			c["rm_clip"] = names[0]
			U.enable_root_motion(ap, c["sk"], ap.get_animation(names[0]))
			var w := MotionWarp.new()
			w.begin(ap, c["sk"], c["actor"], names[0], _target, 0.9)
			c["warp"] = w
		"partial_ragdoll":
			c["prag"] = PartialRagdoll.attach_partial(c["actor"], model, [c["ap"]])
		"full_ragdoll":
			c["rag"] = Ragdoll.attach(c["actor"], model, [c["ap"]])


func _root_motion_step(cs: Array, dt: float) -> void:
	for c: Dictionary in cs:
		var w: RefCounted = c["warp"]
		w.step(dt)
		if w.done:
			# replay from home (the common movement code re-places the actor every frame anyway)
			w.begin(c["ap"], c["sk"], c["actor"], c["rm_clip"], _target, 0.9)
