extends Node
## TechniqueVfx: the ONE timing template of every technique (docs/design/AAA_POLISH_PLAN.md, P1 powers and VFX).
## It is driven by AbilityRunner's phases (started -> windup -> executed) and plays six VFX phases:
##
##   anticipation  hold: a small ground ring gathers at the feet (0 .. windup - FLASH_LEAD)
##   flash         cheap screen flash + radial blur on HIGH (the last FLASH_LEAD seconds before release)
##   glow          toon glow shells on hand / foot / spine bone attachments, from the flash until the impact
##   travel        a swirl orb flies caster -> target (only for techniques without a bespoke VFX method)
##   impact        the pooled impact scene (impact_hook; a ToonVfx burst stub until the combat-feel agent plugs one in)
##   residue       0.5 .. 1 s of lingering motes, plus a fading ground decal (scorch / frost / cracks / ...)
##
## Colours and shapes come from ElementLanguage. The node is a child of the caster (technique_caster.gd, NPC casters
## may bind their own runner); `bind_runner()` connects the runner signals, `play()` runs the template directly
## (tests, the QA harness, NPC code).
##
##   var tv := TechniqueVfx.new(); caster.add_child(tv); tv.bind_runner(runner, ctx)
##   ctx = {origin: Callable()->Vector3 (chest), aim: Callable()->Vector3 (unit forward), world: Callable()->Node,
##          is_player: bool, skeleton_root: Node3D, bespoke: Callable(def)->bool}
## Pure timing: TechniqueVfx.schedule(def, distance) -> {phase: [t0, t1]} (seconds after the commit).

signal phase_entered(id: String, phase: String, run: Dictionary)
signal finished(id: String)

const Lang := preload("res://scripts/vfx/element_language.gd")
const Toon := preload("res://scripts/vfx/toon_vfx.gd")
const Decals := preload("res://scripts/vfx/ground_decals.gd")

const PHASES: Array[String] = ["anticipation", "flash", "glow", "travel", "impact", "residue"]
const FLASH_LEAD := 0.12
const FLASH_LEN := 0.12
const MIN_ANTICIPATION := 0.1
const TRAVEL_SPEED := 22.0
const TRAVEL_MAX := 0.6
const IMPACT_LEN := 0.15
const RESIDUE_MIN := 0.5
const RESIDUE_MAX := 1.0
const MAX_RUNS := 3
const LIMB_BONES := {
	"hand_r": ["hand_r", "Hand_R", "hand.R", "RightHand", "mixamorig:RightHand", "Hand.R"],
	"hand_l": ["hand_l", "Hand_L", "hand.L", "LeftHand", "mixamorig:LeftHand", "Hand.L"],
	"foot_r": ["foot_r", "Foot_R", "foot.R", "RightFoot", "mixamorig:RightFoot", "Foot.R"],
	"foot_l": ["foot_l", "Foot_L", "foot.L", "LeftFoot", "mixamorig:LeftFoot", "Foot.L"],
	"spine": ["spine_03", "Spine2", "spine_02", "Spine", "mixamorig:Spine2", "spine.002", "Chest"],
}
## limb kind (ElementLanguage "limb") -> [[bone key, size, fallback offset]]
const LIMB_SETS := {
	"hand": [["hand_r", 0.36, Vector3(0.3, 1.1, -0.2)], ["hand_l", 0.28, Vector3(-0.3, 1.1, -0.2)]],
	"foot": [["foot_r", 0.4, Vector3(0.15, 0.1, 0.0)], ["foot_l", 0.4, Vector3(-0.15, 0.1, 0.0)], ["hand_r", 0.26, Vector3(0.3, 1.1, -0.2)]],
	"body": [["spine", 0.6, Vector3(0, 1.1, 0)], ["hand_r", 0.3, Vector3(0.3, 1.1, -0.2)]],
}

## Swap point for the combat-feel agent's pooled impact scene: Callable(world, element, pos, power, def). When empty,
## the default `_pool_impact` plays impact_pool.gd (combat-feel) plus a ToonVfx ring burst. Static so one assignment at boot serves every caster.
static var impact_hook: Callable = Callable()

var ctx: Dictionary = {}
var visuals := true                       ## false: phases are emitted but nothing is spawned (timing tests)
var _runs: Array = []
var _runner: RefCounted
var _limb_cache: Dictionary = {}          # "<skeleton id>/<bone key>" -> BoneAttachment3D


func _ready() -> void:
	set_process(false)


# --- timing -------------------------------------------------------------------------

## Phase windows in seconds after the commit (the runner's windup is the release). `dist` is the caster-target
## distance. Residue lasts 0.5-1 s depending on the technique's size.
static func schedule(def: Dictionary, dist := 0.0, bespoke := false) -> Dictionary:
	var flat: Dictionary = def.get("flat", def)
	var windup := maxf(float(def.get("windup", flat.get("hit_time", 0.25))), 0.0)
	var anticip := maxf(windup - FLASH_LEAD, MIN_ANTICIPATION)
	var release := maxf(windup, anticip + 0.02)
	var shape := String(flat.get("shape", (def.get("targeting", {}) as Dictionary).get("kind", "aoe")))
	var travel := 0.0
	if shape == "projectile" or shape == "line":
		travel = clampf(dist / TRAVEL_SPEED, 0.06, TRAVEL_MAX)
	elif shape == "chain":
		travel = 0.12
	var radius := float(flat.get("radius", (def.get("targeting", {}) as Dictionary).get("radius", 2.0)))
	var residue := clampf(RESIDUE_MIN + radius / 12.0, RESIDUE_MIN, RESIDUE_MAX)
	var impact_t := release + travel
	return {
		"anticipation": [0.0, anticip], "flash": [anticip, anticip + FLASH_LEN],
		"glow": [anticip, impact_t + IMPACT_LEN], "travel": [release, impact_t],
		"impact": [impact_t, impact_t + IMPACT_LEN],
		"residue": [impact_t + IMPACT_LEN, impact_t + IMPACT_LEN + residue],
		"total": impact_t + IMPACT_LEN + residue, "release": release, "bespoke": bespoke,
	}


# --- runner wiring ----------------------------------------------------------------------

func bind_runner(runner: RefCounted, context: Dictionary) -> void:
	ctx = context
	_runner = runner
	runner.connect("started", _on_started)
	runner.connect("executed", _on_executed)
	runner.connect("interrupted", _on_interrupted)


func _on_started(id: String, ability: Dictionary) -> void:
	begin(id, ability, _runner_opts())


func _runner_opts() -> Dictionary:
	return {}


func _on_executed(id: String, _ability: Dictionary, cast: Dictionary) -> void:
	for r: Dictionary in _runs:
		if String(r["id"]) == id and not bool(r["executed"]):
			r["executed"] = true
			var tgt: Variant = cast.get("target")
			if tgt is Node3D and is_instance_valid(tgt):
				r["target"] = tgt
				r["to"] = (tgt as Node3D).global_position
			return


func _on_interrupted(id: String, _reason: String) -> void:
	for r: Dictionary in _runs.duplicate():
		if String(r["id"]) == id and not bool(r["executed"]):
			_end(r, true)


## Direct entry: start the template for ability `def` now. opts: {to: Vector3 target ground point, execute: bool
## (release automatically at the schedule, default true when there is no runner), element, power}.
func begin(id: String, def: Dictionary, opts := {}) -> Dictionary:
	while _runs.size() >= MAX_RUNS:
		_end(_runs[0], true)
	var flat: Dictionary = def.get("flat", def)
	var element: Variant = String(def.get("element", flat.get("element", "qi")))
	var path := String(def.get("path", ""))
	var from := _origin()
	var aim := _aim()
	var to: Vector3 = opts.get("to", from + aim * clampf(float(flat.get("range", 4.0)), 2.0, 8.0))
	to.y = from.y - 1.2 if not opts.has("to") else to.y
	var bespoke := false
	if ctx.has("bespoke") and (ctx["bespoke"] as Callable).is_valid():
		bespoke = bool((ctx["bespoke"] as Callable).call(def))
	var run := {"id": id, "def": def, "t": 0.0, "lang": Lang.get_lang(element, path), "element": element, "path": path,
		"from": from, "to": to, "sched": schedule(def, from.distance_to(to), bespoke), "entered": {}, "limbs": [],
		"executed": bool(opts.get("execute", _runner == null)), "target": null, "orb": null, "power": float(opts.get("power", 1.0))}
	_runs.append(run)
	set_process(true)
	_enter(run, "anticipation")
	return run


func _process(delta: float) -> void:
	var pause_action := false
	if ctx.has("action_paused") and ctx["action_paused"] is Callable and (ctx["action_paused"] as Callable).is_valid():
		pause_action = bool((ctx["action_paused"] as Callable).call())
	for r: Dictionary in _runs.duplicate():
		if pause_action and not bool(r["executed"]):
			continue
		r["t"] = float(r["t"]) + delta
		_tick(r)
	if _runs.is_empty():
		set_process(false)


## Advance one run: enter every phase whose window has opened (travel and impact wait for the real release).
func _tick(r: Dictionary) -> void:
	var s: Dictionary = r["sched"]
	var t := float(r["t"])
	var entered: Dictionary = r["entered"]
	for ph in PHASES:
		if entered.has(ph):
			continue
		if t < float((s[ph] as Array)[0]):
			break
		if (ph == "travel" or ph == "impact" or ph == "residue") and not bool(r["executed"]):
			break
		_enter(r, ph)
	if t >= float(s["total"]) and bool(r["executed"]):
		_end(r, false)


## Advance every run by dt without the scene tree (tests): same as _process.
func advance(dt: float) -> void:
	_process(dt)


func active_runs() -> int:
	return _runs.size()


func _enter(r: Dictionary, phase: String) -> void:
	(r["entered"] as Dictionary)[phase] = true
	phase_entered.emit(String(r["id"]), phase, r)
	if not visuals or not is_inside_tree():
		return
	var world := _world()
	if world == null:
		return
	var lang: Dictionary = r["lang"]
	var from: Vector3 = r["from"]
	var to: Vector3 = r["to"]
	var s: Dictionary = r["sched"]
	var element: Variant = r["element"]
	var flat: Dictionary = (r["def"] as Dictionary).get("flat", r["def"])
	var radius := clampf(float(flat.get("radius", 2.5)), 1.2, 6.0)
	match phase:
		"anticipation":
			var secs := maxf(float((s["anticipation"] as Array)[1]), 0.2)
			Toon.ring(world, Vector3(from.x, from.y - 1.15, from.z), element, 1.1, minf(secs + 0.3, 1.0))
		"flash":
			if _is_player():
				var tier_n := int((r["def"] as Dictionary).get("tier", 1))
				Toon.screen_flash(element, 0.14, clampf(0.3 + 0.08 * tier_n, 0.3, 0.75))
		"glow":
			r["limbs"] = _glow_limbs(lang, element)
		"travel":
			if float((s["travel"] as Array)[1]) - float((s["travel"] as Array)[0]) > 0.0 and not bool(s["bespoke"]):
				_fly_orb(r, world, from, to)
		"impact":
			_release_limbs(r)
			if not bool(s["bespoke"]):
				_impact(world, element, Vector3(to.x, to.y, to.z), radius, r)
		"residue":
			var life := lerpf(3.5, 6.0, clampf(radius / 6.0, 0.0, 1.0))
			var ground := Vector3(to.x, to.y, to.z)
			Decals.spawn(world, String(lang["decal"]), ground, radius * 1.3, life, randf() * TAU)
			Toon.particles(world, ground + Vector3(0, 0.2, 0), lang, radius * 0.6)


func _end(r: Dictionary, cancelled: bool) -> void:
	_release_limbs(r)
	var orb: Variant = r["orb"]
	if is_instance_valid(orb):
		Toon.release(orb as Node, 0.1)
	_runs.erase(r)
	if cancelled and visuals and is_inside_tree() and _world() != null:
		Toon.ring(_world(), Vector3(r["from"].x, r["from"].y - 1.15, r["from"].z), r["element"], 0.7, 0.4)
	finished.emit(String(r["id"]))


func _release_limbs(r: Dictionary) -> void:
	for n: Variant in r["limbs"]:
		if is_instance_valid(n):
			Toon.release(n as Node, 0.25)
	r["limbs"] = []


# --- visuals -----------------------------------------------------------------------------

func _glow_limbs(lang: Dictionary, element: Variant) -> Array:
	var out: Array = []
	var set_: Array = LIMB_SETS.get(String(lang["limb"]), LIMB_SETS["hand"])
	var root := _skeleton_root()
	for row: Array in set_:
		var host := _limb_node(root, String(row[0]), row[2])
		if host != null:
			var g := Toon.glow_limb(host, element, float(row[1]))
			if g != null:
				out.append(g)
	return out


func _skeleton_root() -> Node3D:
	var r: Variant = ctx.get("skeleton_root", null)
	if r is Node3D and is_instance_valid(r):
		return r
	var p := get_parent()
	return p as Node3D


func _limb_node(root: Node3D, key: String, fallback_offset: Vector3) -> Node3D:
	if root == null:
		return null
	var sk: Skeleton3D = null
	if root is Skeleton3D:
		sk = root
	else:
		var found := root.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			sk = found[0] as Skeleton3D
	if sk != null:
		var ck := "%d/%s" % [sk.get_instance_id(), key]
		if _limb_cache.has(ck) and is_instance_valid(_limb_cache[ck]):
			return _limb_cache[ck]
		var bone := ""
		for cand: String in LIMB_BONES[key]:
			if sk.find_bone(cand) >= 0:
				bone = cand
				break
		if bone == "":
			var want_side := key.ends_with("_l")
			for i in sk.get_bone_count():
				var bn := sk.get_bone_name(i).to_lower()
				var kind := key.split("_")[0]
				if bn.contains(kind) and (key == "spine" or bn.ends_with("_l") == want_side or bn.contains("left") == want_side):
					bone = sk.get_bone_name(i)
					break
		if bone != "":
			var ba := BoneAttachment3D.new()
			ba.name = "VfxLimb_" + key
			ba.bone_name = bone
			sk.add_child(ba)
			_limb_cache[ck] = ba
			return ba
	# No usable skeleton (NPC billboards, tests): a plain marker at a body-relative offset.
	var ck2 := "%d/fallback/%s" % [root.get_instance_id(), key]
	if _limb_cache.has(ck2) and is_instance_valid(_limb_cache[ck2]):
		return _limb_cache[ck2]
	var m := Node3D.new()
	m.name = "VfxLimb_" + key
	m.position = fallback_offset
	root.add_child(m)
	_limb_cache[ck2] = m
	return m


func _fly_orb(r: Dictionary, world: Node, from: Vector3, to: Vector3) -> void:
	var s: Dictionary = r["sched"]
	var dur := float((s["travel"] as Array)[1]) - float((s["travel"] as Array)[0])
	var orb := Toon.shell(world, r["element"], 0.32, maxf(dur, 0.1), null, from, 1.0)
	if orb == null:
		return
	r["orb"] = orb
	var end := Vector3(to.x, from.y, to.z) if to.y < from.y - 0.5 else to
	var tw := orb.create_tween()
	tw.tween_property(orb, "global_position", end, maxf(dur, 0.05))


func _impact(world: Node, element: Variant, at: Vector3, radius: float, r: Dictionary) -> void:
	if impact_hook.is_valid():
		impact_hook.call(world, element, at, float(r["power"]), r["def"])
	else:
		_pool_impact(world, element, at, radius, r)


const IMPACT_POOL := "res://scripts/vfx/impact_pool.gd"
const IMPACT_VARIANT := {"ice": "water", "light": "qi", "dark": "qi", "knight": "physical", "beast": "physical"}


## Default impact: the combat-feel agent's pooled layered impact (element variants), plus our ring burst.
func _pool_impact(world: Node, element: Variant, at: Vector3, radius: float, r: Dictionary) -> void:
	_stub_impact(world, element, at, radius)
	if not ResourceLoader.exists(IMPACT_POOL):
		return
	var script := load(IMPACT_POOL) as GDScript
	var pool: Object = script.call("at", world)
	if pool == null:
		return
	var id := String(Lang.canon(element, String(r["path"])))
	var variant := String(IMPACT_VARIANT.get(id, id))
	if not (script.call("element_names") as Array).has(variant):
		variant = "physical"
	var tier_n := clampi(int((r["def"] as Dictionary).get("tier", 1)) - 1, 0, 2)
	pool.call("play", at + Vector3(0, 0.9, 0), variant, tier_n, Vector3.ZERO, false)


static func _stub_impact(world: Node, element: Variant, at: Vector3, radius: float) -> void:
	Toon.burst(world, at, element, radius, 1.0)
	Toon.shell(world, element, clampf(radius * 0.55, 0.8, 2.2), 0.45, null, at + Vector3(0, 0.6, 0))   # hot dome for the first frames


# --- context ----------------------------------------------------------------------------------

func _is_player() -> bool:
	var v: Variant = ctx.get("is_player", false)
	return bool((v as Callable).call()) if v is Callable else bool(v)


func _origin() -> Vector3:
	if ctx.has("origin") and (ctx["origin"] as Callable).is_valid():
		return (ctx["origin"] as Callable).call()
	var p := get_parent() as Node3D
	return p.global_position + Vector3(0, 1.2, 0) if p else Vector3(0, 1.2, 0)


func _aim() -> Vector3:
	if ctx.has("aim") and (ctx["aim"] as Callable).is_valid():
		return (ctx["aim"] as Callable).call()
	var p := get_parent() as Node3D
	return -p.global_basis.z if p else Vector3.FORWARD


func _world() -> Node:
	if ctx.has("world") and (ctx["world"] as Callable).is_valid():
		return (ctx["world"] as Callable).call()
	if is_inside_tree():
		var p := get_parent()
		return p.get_parent() if p and p.get_parent() else p
	return null
