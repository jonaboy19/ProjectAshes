class_name VatResidents
extends Node3D
## The FAR crowd tier for WorldSim residents (no nodes per person): PopulationLOD hands it the residents in the
## VAT distance band each refresh (4 Hz); this node keeps a VatCrowd instance per resident, chooses the clip from
## what the resident is doing (walking, job at the work spot, market, guard), and moves walkers smoothly between
## refreshes (straight toward their WorldSim target at WorldSim.WALK_SPEED, ground height sampled at 4 Hz).
##
## Hook (docs/anim/patches/P13_vat_population_lod.md):
##   var vat_res := VatResidents.new(); add_child(vat_res)                  # PopulationLOD.setup()
##   vat_res.begin()                                                         # in refresh(), before the sprite loop
##   if vat_res.want(id, pos2, target2, job, phase, ground_y): continue      # resident drawn by VAT, skip sprite
##   vat_res.end()                                                           # after the loop: drops the rest
## `height_fn` (WorldGen.height) is only called at refresh time for walkers' targets.

const LOOKS_BY_JOB := [
	["villager_farmer", "villager_man_a", "villager_woman_a", "villager_woman_b", "elder_man"],   # Farmer
	["villager_man_b", "villager_man_a"],                                                        # Blacksmith
	["villager_woman_a", "villager_woman_b", "villager_man_b"],                                  # Merchant
	["villager_guard"],                                                                          # Guard
	["villager_man_a", "villager_man_b", "villager_woman_b"],                                    # Laborer
	["villager_man_b", "villager_man_a"],                                                        # Woodcutter
]
## Work clips per job at the work spot (first the VAT bake has wins).
const WORK_CLIPS := [
	["Life_Farm_Hoe", "Life_Farm_Harvest", "Life_Farm_Sow", "Farm_Harvest"],
	["Life_Talk_Explain", "Idle_Talking"],
	["Life_Market_Call_Out", "Idle_Talking"],
	["Life_Guard_Lean_Spear", "Life_Guard_Attention", "Idle"],
	["Walk+Life_Carry_Sack_Upper", "Life_Chore_Sweep", "Idle"],
	["Life_Wood_Chop", "TreeChopping"],
]
const WALK_SPEED := 1.3
const LOW_LOOKS := ["villager_man_a", "villager_woman_a", "villager_farmer", "villager_guard"]
## Max residents drawn as VAT (per quality tier LOW..ULTRA); the rest fall back to sprites.
const CAP := [40, 80, 140, 220]

var crowd: VatCrowd
var height_fn: Callable
var cap := 140
var _live: Dictionary = {}     # id -> {pos: Vector3, target: Vector3, walking: bool, clip, scale, look}
var _seen: Dictionary = {}


func _ready() -> void:
	crowd = VatCrowd.new()
	crowd.name = "VatCrowd"
	add_child(crowd)
	var looks := {}
	for l: Array in LOOKS_BY_JOB:
		for k: String in l:
			looks[k] = true
	var q := get_node_or_null("/root/Quality")
	var tier := 2
	if q and q.get("tier") != null:
		tier = clampi(int(q.tier), 0, CAP.size() - 1)
	cap = CAP[tier]
	# LOW: four looks (~12 MB of VAT textures instead of ~27 MB); every job list still finds one of them.
	crowd.load_looks(LOW_LOOKS if tier == 0 else looks.keys())


func begin() -> void:
	_seen.clear()


## Draw resident `id` as VAT. Returns false when the cap is reached or no bake fits (caller draws a sprite).
## phase: WorldSim schedule phase (0 home, 1 work, 2 market). ground_y: terrain height at pos.
func want(id: int, pos: Vector2, target: Vector2, job: int, phase: int, ground_y: float) -> bool:
	if not _live.has(id) and _live.size() >= cap:
		return false
	var look := _look_for(id, job)
	if look == "" or not crowd.assets.has(look):
		return false
	_seen[id] = true
	var a: VatAsset = crowd.assets[look]
	var walking := pos.distance_to(target) > 0.6
	var clip := "Walk"
	if not walking:
		clip = _work_clip(a, job, id) if phase == 1 else ("Idle_Talking" if a.has_clip("Idle_Talking") and id % 3 != 0 else "Idle")
	elif job == 3 and a.has_clip("Life_Guard_Patrol_Walk"):
		clip = "Life_Guard_Patrol_Walk"
	elif job == 4 and a.has_clip("Walk+Life_Carry_Sack_Upper") and id % 2 == 0:
		clip = "Walk+Life_Carry_Sack_Upper"
	var e: Dictionary = _live.get(id, {})
	var p3 := Vector3(pos.x, ground_y, pos.y)
	var ty := ground_y
	if walking and height_fn.is_valid():
		ty = float(height_fn.call(target.x, target.y))
	if e.is_empty():
		var s := 1.72 / a.height * (0.95 + 0.1 * _h(id, 1))
		e = {"pos": p3, "target": Vector3(target.x, ty, target.y), "walking": walking, "clip": clip, "scale": s, "look": look, "yaw": _h(id, 6) * TAU}
		_live[id] = e
		var tint := Color(0.4 + 0.2 * _h(id, 2), 0.4 + 0.2 * _h(id, 3), 0.4 + 0.2 * _h(id, 4))
		crowd.put(id, look, _xf(e), clip, -1.0, 0.94 + 0.12 * _h(id, 5), tint)
	else:
		# trust our smoothed position unless the sim has moved the person far (skip, teleport)
		if (e["pos"] as Vector3).distance_to(p3) > 3.0:
			e["pos"] = p3
		e["target"] = Vector3(target.x, ty, target.y)
		e["walking"] = walking
		if e["clip"] != clip:
			e["clip"] = clip
			crowd.play(id, clip, -1.0, 0.94 + 0.12 * _h(id, 5))
	return true


func end() -> void:
	for id: int in _live.keys():
		if not _seen.has(id):
			crowd.remove(id)
			_live.erase(id)


func count() -> int:
	return _live.size()


func _process(delta: float) -> void:
	for id: int in _live:
		var e: Dictionary = _live[id]
		if not e["walking"]:
			continue
		var p: Vector3 = e["pos"]
		var to: Vector3 = (e["target"] as Vector3) - p
		var d := Vector2(to.x, to.z).length()
		if d < 0.05:
			continue
		var step := minf(d, WALK_SPEED * delta)
		p += to * (step / maxf(to.length(), 0.001))
		e["pos"] = p
		crowd.move(id, _xf(e))


func _xf(e: Dictionary) -> Transform3D:
	var to: Vector3 = (e["target"] as Vector3) - (e["pos"] as Vector3)
	var yaw := atan2(to.x, to.z) if Vector2(to.x, to.z).length() > 0.05 else float(e.get("yaw", 0.0))
	e["yaw"] = yaw
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(e["scale"])), e["pos"])


## Baked VAT look for a skeletal character built by Assets.mh_character (its imported scene file name),
## with stand-ins for looks that have no bake. "" when nothing fits.
const LOOK_FALLBACK := {"villager_smith": "villager_man_b", "villager_merchant": "villager_woman_a",
	"villager_baker": "villager_woman_b", "villager_healer": "villager_woman_b", "mother": "villager_woman_a",
	"father": "villager_man_b", "elder_woman": "villager_woman_b", "guard": "villager_guard", "player_young": "villager_man_a"}


static func look_of_model(model: Node) -> String:
	for c in model.get_children():
		var f := String(c.scene_file_path).get_file().get_basename().trim_suffix("_lod1")
		if f != "":
			var p := "res://assets/generated/vat/vat_%s.res" % f
			if ResourceLoader.exists(p):
				return f
			return String(LOOK_FALLBACK.get(f, "villager_man_a"))
	return ""


func look_for(id: int, job: int) -> String:
	return _look_for(id, job)


func _look_for(id: int, job: int) -> String:
	var l: Array = LOOKS_BY_JOB[clampi(job, 0, LOOKS_BY_JOB.size() - 1)]
	for k in l.size():
		var look: String = l[(id + k) % l.size()]
		if crowd.assets.has(look):
			return look
	return ""


func _work_clip(a: VatAsset, job: int, id: int) -> String:
	var l: Array = WORK_CLIPS[clampi(job, 0, WORK_CLIPS.size() - 1)]
	var n := l.size()
	for k in n:
		var c: String = l[(id + k) % n]
		if a.has_clip(c):
			return c
	return "Idle"


func _h(id: int, k: int) -> float:
	return float(absi(hash(id * 7349 + k * 31)) % 1000) / 1000.0
