extends Node3D
## Ore rocks to mine around Greyseam Mine (the WorldGen site of kind "mine"):
## iron, copper and coal. The rocks stand at fixed offsets around the site (in
## the site's own frame, clear of the portal, track, hut and ore heaps), so they
## are in the same place every visit. Bodies come from a small fixed pool and
## only exist while the player is within ACTIVATE of the mine; they go back to
## the pool beyond DEACTIVATE (the same ring pattern as forage_nodes.gd). A mined
## rock stays bare for RESPAWN_DAYS in-game days.
##
## Each live rock is in the "interactable" group with prompt() and use(). Like
## ForageNodes, the manager polls "interact" itself while the player stands by
## one of its rocks, so main.gd needs no dispatcher; a per-frame guard stops a
## double strike if main.gd also calls use().
##
## Yield: 1-2 ore, +1 while carrying or wielding a pickaxe, and a chance of +1
## that grows with the Mining skill (Life.crafting, when Life owns one).

const Crafting := preload("res://scripts/sim/crafting.gd")
const ACTIVATE := 90.0
const DEACTIVATE := 120.0
const RESPAWN_DAYS := 1
const ROCK_MODEL := "res://assets/generated/region/nature/rock_medium_lod1.glb"
const ROCK_MODEL_FULL := "res://assets/generated/region/nature/rock_medium.glb"
const MINING_XP := 4

const ORES := {
	"iron": {"item": "iron_ore", "min": 1, "max": 2, "color": Color(0.62, 0.34, 0.22), "verb": "Mine iron ore"},
	"copper": {"item": "copper_ore", "min": 1, "max": 2, "color": Color(0.28, 0.66, 0.52), "verb": "Mine copper ore"},
	"coal": {"item": "coal", "min": 1, "max": 3, "color": Color(0.08, 0.08, 0.09), "verb": "Mine coal"},
}
## [local offset (site frame: +y front, +x right), ore]. Clear of the site's parts
## (region_sites.gd _mine: portal at 0,0, track 0,5..17, hut 9,8, heaps 4,6 / -3,9 / 6,11).
const LAYOUT := [
	[Vector2(-11, -3), "iron"], [Vector2(-13, 6), "coal"], [Vector2(13, 1), "copper"],
	[Vector2(15, -5), "iron"], [Vector2(-9, 15), "coal"], [Vector2(13, 17), "copper"],
	[Vector2(-15, -9), "iron"],
]

var focus := Vector3.ZERO
## The mine site ({} when the world has none).
var site: Dictionary = {}
## rock index -> day it was mined
var mined: Dictionary = {}
var _rocks: Array = []              # OreRock, one per LAYOUT entry
var _live := false
var _timer := 0.0
var _menu_was_open := false
var _rock_scene: PackedScene
var _mats: Dictionary = {}
var _nugget: Mesh


class OreRock extends Node3D:
	var manager: Node
	var index := 0
	var ore := "iron"
	var _last_frame := -1000

	func prompt() -> String:
		return String(ORES.get(ore, {}).get("verb", "Mine"))

	func use() -> void:
		var f := Engine.get_process_frames()
		if f - _last_frame < 10:
			return
		_last_frame = f
		manager.mine(self)


## World-space x/z of each rock for a site: [[Vector2, ore], ...].
static func layout_for(s: Dictionary) -> Array:
	var out := []
	if s.is_empty():
		return out
	var c: Vector2 = s["pos"]
	var basis := Basis(Vector3.UP, float(s.get("yaw", 0.0)))
	for e: Array in LAYOUT:
		var off: Vector2 = e[0]
		var w := basis * Vector3(off.x, 0.0, off.y)
		out.append([c + Vector2(w.x, w.z), e[1]])
	return out


static func find_mine(sites: Array) -> Dictionary:
	for s: Dictionary in sites:
		if String(s.get("kind", "")) == "mine":
			return s
	return {}


func _ready() -> void:
	site = find_mine(WorldGen.sites)
	if site.is_empty():
		set_process(false)
		return
	var spots := layout_for(site)
	for i in spots.size():
		var r := OreRock.new()
		r.manager = self
		r.index = i
		r.ore = String(spots[i][1])
		r.name = "Ore_%d_%s" % [i, r.ore]
		r.visible = false
		add_child(r)
		var p: Vector2 = spots[i][0]
		r.position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
		r.rotation.y = float(i) * 1.7
		_rocks.append(r)


func _process(delta: float) -> void:
	_poll_interact()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var p := _center()
	var d := p.distance_to(site["pos"])
	if not _live and d < ACTIVATE:
		_live = true
		_refresh()
	elif _live and d > DEACTIVATE:
		_live = false
		for r: OreRock in _rocks:
			_hide(r)
	elif _live:
		_refresh()


func _center() -> Vector2:
	var pl: Variant = Life.player
	if pl is Node3D and is_instance_valid(pl):
		return Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	return Vector2(focus.x, focus.z)


## Shows every rock that isn't mined out (and lets mined ones regrow).
func _refresh() -> void:
	var day: int = WorldSim.day
	for i: int in mined.keys():
		if day - int(mined[i]) >= RESPAWN_DAYS:
			mined.erase(i)
	for r: OreRock in _rocks:
		if mined.has(r.index):
			_hide(r)
		elif not r.visible:
			_show(r)


func _show(r: OreRock) -> void:
	if r.get_child_count() == 0:
		r.add_child(_visual(r.ore))
	r.visible = true
	r.add_to_group("interactable")


func _hide(r: OreRock) -> void:
	r.visible = false
	if r.is_in_group("interactable"):
		r.remove_from_group("interactable")


# --- mining ---------------------------------------------------------------------------

## Yield for a strike: base roll, +1 with a pickaxe, +1 on a skill roll.
static func yield_for(ore: String, roll_base: float, roll_skill: float, has_pick: bool, mining_level: int) -> int:
	var o: Dictionary = ORES.get(ore, {})
	if o.is_empty():
		return 0
	var lo := int(o["min"])
	var hi := int(o["max"])
	var n := lo + mini(int(clampf(roll_base, 0.0, 0.999) * (hi - lo + 1)), hi - lo)
	if has_pick:
		n += 1
	if roll_skill < 0.06 * float(mining_level - 1):
		n += 1
	return n


func mine(r: OreRock) -> void:
	if not r.visible or mined.has(r.index):
		return
	var o: Dictionary = ORES.get(r.ore, {})
	var item := String(o["item"])
	var crafting: Variant = Life.get("crafting")
	var equipment: Variant = Life.get("equipment")
	var has_pick: bool = Life.count("pickaxe") > 0
	if equipment is Object and String((equipment as Object).call("item_in", "main_hand")) == "pickaxe":
		has_pick = true
	var lvl := 1
	if crafting is Object:
		lvl = int((crafting as Object).call("level", "mining"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(r.index, WorldSim.day, 5151))
	var n := yield_for(r.ore, rng.randf(), rng.randf(), has_pick, lvl)
	Life.give(item, n)
	Life.record("mined", 0.6)
	var text := "Mined %d %s." % [n, Life.item_name(item)]
	if crafting is Object:
		var mult := Crafting.TOOL_XP_MULT if has_pick else 1.0
		var before := lvl
		var after := int((crafting as Object).call("add_xp", "mining", int(round(MINING_XP * mult))))
		if after > before:
			text += "  Mining is now %d!" % after
	if not has_pick and r.index == 0:
		text += " (A pickaxe would help.)"
	Game.say(text)
	Audio.play_ui("pickup")
	mined[r.index] = WorldSim.day
	_hide(r)


## Self-dispatch of the interact key while standing by one of our rocks.
func _poll_interact() -> void:
	var menu_open := _menu_open()
	var was := _menu_was_open
	_menu_was_open = menu_open
	if menu_open or was or not _live:
		return
	var pl: Variant = Life.player
	if not (pl is Node3D) or not is_instance_valid(pl) or not Input.is_action_just_pressed("interact"):
		return
	if not (pl as Node3D).has_method("nearest_interactable"):
		return
	var target: Variant = (pl as Node3D).call("nearest_interactable")
	if target is OreRock and (target as OreRock).manager == self:
		(target as OreRock).use()


func _menu_open() -> bool:
	var scene := get_tree().current_scene
	var hud: Variant = scene.get("hud") if scene else null
	return hud is Object and is_instance_valid(hud) and (hud as Object).has_method("is_menu_open") \
		and bool((hud as Object).call("is_menu_open"))


# --- visuals ----------------------------------------------------------------------------

func _mat(key: String, col: Color, emit := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.55 if emit > 0.0 else 0.95
		m.metallic = 0.4 if emit > 0.0 else 0.0
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = emit
		_mats[key] = m
	return _mats[key]


func _visual(ore: String) -> Node3D:
	var root := Node3D.new()
	if _rock_scene == null:
		var path := ROCK_MODEL if ResourceLoader.exists(ROCK_MODEL) else ROCK_MODEL_FULL
		if ResourceLoader.exists(path):
			_rock_scene = load(path)
	var h := 1.0
	if _rock_scene:
		var rock: Node3D = _rock_scene.instantiate()
		var box := Assets.visual_aabb(rock)
		var k := 1.1 / maxf(box.size.y, 0.01)
		rock.scale = Vector3.ONE * k
		root.add_child(rock)
		h = box.size.y * k
	else:
		var s := SphereMesh.new()
		s.radius = 0.7
		s.height = 1.0
		s.radial_segments = 7
		s.rings = 4
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = _mat("rock", Color(0.45, 0.43, 0.4))
		mi.position.y = 0.4
		mi.scale = Vector3(1.0, 0.8, 0.85)
		root.add_child(mi)
	if _nugget == null:
		var b := BoxMesh.new()
		b.size = Vector3(0.16, 0.12, 0.14)
		_nugget = b
	var col: Color = ORES[ore]["color"]
	var mat := _mat("ore_" + ore, col, 0.0 if ore == "coal" else 0.25)
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		var mi := MeshInstance3D.new()
		mi.mesh = _nugget
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cos(a) * 0.5, h * (0.35 + 0.25 * sin(a * 2.0)), sin(a) * 0.45)
		mi.rotation = Vector3(a, a * 0.7, 0.3)
		root.add_child(mi)
	return root
