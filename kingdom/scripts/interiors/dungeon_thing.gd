extends InteriorDoor
## Everything you can touch inside a dungeon: chests, levers, resource nodes, inscriptions and journals,
## the torch cache, sealed doors that need a rune or a pick, pressure plates and spike traps, plus the
## "reveal" spots of hidden cave entrances (vines to cut, rockfall to clear).
##
## It extends InteriorDoor on purpose: main.gd's interact handler already calls use() on the nearest
## InteriorDoor, and the HUD already shows a door's prompt(), so none of this needs a hook in main.gd
## or the HUD. (Standalone scenes must call InteriorDoor.tag_player(player), which main.gd does.)

const Kit := preload("res://scripts/interiors/dungeon_kit.gd")
const Items := preload("res://scripts/interiors/dungeon_items.gd")

var kind := ""
var data: Dictionary = {}
var dungeon: Node = null      # dungeon_root.gd (or region_caves_view.gd for "reveal")
var theme := "cave"
var done := false
var _lid: Node3D = null
var _stick: Node3D = null


func setup(k: String, d: Dictionary, owner_root: Node, th: String, radius := 1.8) -> void:
	kind = k
	data = d
	dungeon = owner_root
	theme = th
	name = "%s_%s" % [k, String(d.get("id", ""))]
	collision_layer = 0
	collision_mask = PLAYER_TRIGGER_LAYER
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	cs.shape = sph
	cs.position.y = 0.8
	add_child(cs)
	_build_visual()


func _ready() -> void:
	super()
	# Plates and traps trigger on contact (PLAYER_TRIGGER_LAYER only), so they never join "interactable".
	if kind in ["plate", "trap"]:
		set_process(false)


func prompt() -> String:
	if done:
		return ""
	match kind:
		"chest":
			return "Open %s" % String(data.get("label", "chest")).to_lower()
		"boss_chest":
			return "Open the champion's chest"
		"lever":
			return "Pull the lever"
		"node":
			var n := String(data["kind"]).replace("_", " ")
			if bool(data.get("needs_pick", false)):
				return "Mine %s" % n if _has_pick() else "Hard rock (%s)" % n
			return "Gather %s" % n
		"lore":
			return "Read: %s" % String(data.get("title", "inscription"))
		"torch_cache":
			return "Take a torch"
		"reveal":
			if String(data.get("rkind", "")) == "rockfall":
				return "Clear the rockfall" if _has_pick() else "Loose rubble (a pickaxe would clear it)"
			return "Cut back the vines"
		"gate":
			match String(data.get("gkind", "")):
				"rune":
					return "Study the sealed rune" if not _knows(String(data.get("fact", ""))) else "Speak the rune"
				"collapse":
					return "Clear the rockfall" if _has_pick() else "Collapsed passage (needs a pick)"
	return ""


func use() -> void:
	if done or dungeon == null:
		return
	match kind:
		"chest", "boss_chest":
			_open_chest()
		"lever":
			done = true
			if _stick:
				var tw := create_tween()
				tw.tween_property(_stick, "rotation:z", 0.9, 0.3)
			_say("A deep clunk, somewhere in the walls.")
			dungeon.call("open_gate", int(data["gate"]), "lever")
			_retire()
		"node":
			_gather()
		"lore":
			_read()
		"torch_cache":
			_take_torch()
		"gate":
			_use_gate()
		"reveal":
			if String(data.get("rkind", "")) == "rockfall" and not _has_pick():
				_say("Rubble is stacked across a dark gap. A pickaxe could clear it.")
				return
			_say("You clear the way: a hidden entrance lies behind.")
			dungeon.call("reveal_by_thing", String(data["site"]), String(data["rkind"]))
			done = true
			_retire()


# --- actions ---------------------------------------------------------------------------------

func _life() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("Life") if loop != null else null


func _say(t: String) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	var g: Node = loop.root.get_node_or_null("Game") if loop != null else null
	if g != null:
		g.call("say", t)


func _has_pick() -> bool:
	var life := _life()
	return life != null and int(life.call("count", "pickaxe")) > 0


func _knows(fact: String) -> bool:
	var life := _life()
	if life == null or life.get("realm") == null:
		return false
	var soc: Variant = life.realm.mod("society")
	return soc != null and soc.knows(fact)


func _learn(fact: String, text: String) -> bool:
	var life := _life()
	if life == null or life.get("realm") == null or fact == "":
		return false
	var soc: Variant = life.realm.mod("society")
	return soc != null and soc.learn(fact, text)


func _retire() -> void:
	if is_in_group("interactable"):
		remove_from_group("interactable")
	set_process(false)
	monitoring = false


func _give_list(loot: Array) -> String:
	var life := _life()
	var loop := Engine.get_main_loop() as SceneTree
	var game: Node = loop.root.get_node_or_null("Game") if loop != null else null
	var parts := PackedStringArray()
	if life != null:
		Items.register(life)
	for e: Array in loot:
		if e[0] == "gold":
			if game != null:
				game.call("add_gold", int(e[1]))
			parts.append("%d gold" % int(e[1]))
		elif life != null:
			life.call("give", String(e[0]), int(e[1]))
			var nm: String = String(life.call("item_name", String(e[0]))) if life.has_method("item_name") else String(e[0])
			parts.append("%d %s" % [int(e[1]), nm])
	return ", ".join(parts)


func _open_chest() -> void:
	done = true
	var loot: Array = data.get("loot", [])
	if kind == "boss_chest":
		loot = loot.duplicate()
		if String(data.get("trophy", "")) != "":
			loot.append([String(data["trophy"]), 1])
	var text := _give_list(loot)
	_say("%s: %s." % [String(data.get("label", "Chest")), text])
	dungeon.call("mark_looted", String(data["id"]))
	if _lid:
		var tw := create_tween()
		tw.tween_property(_lid, "rotation:x", -1.7, 0.4)
	_retire()


func _gather() -> void:
	var item: String = Items.NODE_ITEM.get(String(data["kind"]), String(data["kind"]))
	var n := int(data.get("count", 1))
	if bool(data.get("needs_pick", false)):
		if not _has_pick():
			_say("Hard stone. A pickaxe would get this out.")
			return
		n += 1
	done = true
	var life := _life()
	if life != null:
		Items.register(life)
		life.call("give", item, n)
	_say("You gather %d %s." % [n, item.replace("_", " ")])
	dungeon.call("mark_harvested", String(data["id"]))
	dungeon.call("hide_node", String(data["id"]), String(data["kind"]))
	_retire()


func _read() -> void:
	var fact := String(data.get("fact", ""))
	var text := String(data.get("text", ""))
	dungeon.call("mark_read", String(data["id"]))
	_say("%s: %s" % [String(data.get("title", "")), text])
	if fact != "":
		var fresh := _learn(fact, String(data.get("fact_text", text)))
		if fact.begins_with("cave:"):
			_say("You commit the rune to memory. You could open the sealed door now.")
		elif fresh:
			_say("You learned something new (%s)." % fact.get_slice(":", 0))
	# a lead to somewhere else: lore in one dungeon points at a hidden place
	var lead := String(data.get("lead", ""))
	if lead != "":
		dungeon.call("reveal_lead", lead)


func _take_torch() -> void:
	var life := _life()
	if life != null:
		Items.register(life)
		if int(life.call("count", "torch")) >= 1:
			_say("You already carry a torch.")
			return
		life.call("give", "torch", 1)
	done = true
	_say("You take a torch. Dark caves are easier with a light.")
	dungeon.call("refresh_light")
	_retire()


func _use_gate() -> void:
	var gk := String(data.get("gkind", ""))
	var gid := int(data["gate"])
	if gk == "rune":
		var fact := String(data["fact"])
		if not _knows(fact):
			_say("An unfamiliar rune seals the door. Somewhere here, someone carved its twin.")
			return
		_say("You trace the rune from memory. The door sighs open.")
		done = true
		dungeon.call("open_gate", gid, "rune")
		_retire()
	elif gk == "collapse":
		if not _has_pick():
			_say("Fallen rock chokes the passage. A pickaxe could clear it.")
			return
		_say("You swing the pick until the passage is clear.")
		done = true
		dungeon.call("open_gate", gid, "collapse")
		_retire()


# --- contact triggers -------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if done:
		return
	if kind == "plate" or kind == "trap":
		if not body.is_in_group("player"):
			return
		done = kind == "plate"
		if kind == "plate":
			_say("Click. Something moves inside the walls.")
			dungeon.call("open_gate", int(data["gate"]), "plate")
			var tw := create_tween()
			tw.tween_property(self, "position:y", position.y - 0.08, 0.15)
		else:
			if body.has_method("take_damage"):
				body.call("take_damage", int(data.get("damage", 10)), self, Vector3.ZERO)
			_say("Spikes punch up through the floor!")
			done = true
			var sp := MeshInstance3D.new()
			sp.mesh = Kit.box_acc_mesh([[Vector3(-0.25, 0.25, -0.25), Vector3(0.06, 0.5, 0.06), 0.0, Color(0.5, 0.5, 0.52)],
				[Vector3(0.25, 0.25, -0.25), Vector3(0.06, 0.5, 0.06), 0.0, Color(0.5, 0.5, 0.52)],
				[Vector3(-0.25, 0.25, 0.25), Vector3(0.06, 0.5, 0.06), 0.0, Color(0.5, 0.5, 0.52)],
				[Vector3(0.25, 0.25, 0.25), Vector3(0.06, 0.5, 0.06), 0.0, Color(0.5, 0.5, 0.52)]], theme)
			sp.position.y = -0.45
			add_child(sp)
			var tw2 := create_tween()
			tw2.tween_property(sp, "position:y", 0.0, 0.08)
			tw2.tween_interval(1.5)
			tw2.tween_property(sp, "position:y", -0.45, 0.4)
		return
	super(body)


# --- visuals ---------------------------------------------------------------------------------

func _mesh_node(mesh: Mesh, at := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(mi)
	return mi


## Meshy free pack coins scattered on the floor round a vault or boss chest (docs/qa/ASSET_AUDIT.md "loot/"): flat, static, no collider.
const COIN_GOLD := "res://assets/incoming/meshy_free/loot/coin_gold_big_lod0.glb"
const COIN_SILVER := "res://assets/incoming/meshy_free/loot/coin_silver_big_lod0.glb"


func _coin_pile(boss: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var n := 11 if boss else 6
	for i in n:
		var path := COIN_SILVER if i % 3 == 2 else COIN_GOLD
		if not ResourceLoader.exists(path):
			return
		var coin: Node3D = Assets.static_model(path)
		if coin == null:
			return
		add_child(coin)
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.75, 1.25 if boss else 1.0)
		coin.position = Vector3(cos(a) * r, 0.03 + (i % 4) * 0.006, sin(a) * r)
		coin.rotation = Vector3(-PI * 0.5, rng.randf() * TAU, 0.0)
		coin.scale = Vector3.ONE * (1.7 if boss else 1.4)
		if coin is GeometryInstance3D:
			(coin as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_visual() -> void:
	match kind:
		"chest", "boss_chest":
			var vault := bool(data.get("vault", false)) or kind == "boss_chest"
			var cm := Kit.chest_meshes(vault, theme)
			_mesh_node(cm[0])
			_lid = Node3D.new()
			_lid.position = Vector3(0, 0.5, -0.3)
			add_child(_lid)
			_mesh_node(cm[1], Vector3.ZERO, _lid)
			if vault:
				var glow := OmniLight3D.new()
				glow.light_color = Color(1.0, 0.85, 0.45)
				glow.omni_range = 3.5
				glow.light_energy = 0.8
				glow.position.y = 1.0
				glow.distance_fade_enabled = true
				glow.distance_fade_begin = 12.0
				glow.distance_fade_length = 6.0
				add_child(glow)
			if vault:
				_coin_pile(kind == "boss_chest")
		"lever":
			_mesh_node(Kit.box_acc_mesh([[Vector3(0, 0.9, 0), Vector3(0.5, 0.25, 0.25), 0.0, Color(0.3, 0.27, 0.25)]], theme))
			_stick = Node3D.new()
			_stick.position = Vector3(0, 0.95, 0.15)
			_stick.rotation.z = -0.9
			add_child(_stick)
			_mesh_node(Kit.box_acc_mesh([[Vector3(0, 0.3, 0), Vector3(0.08, 0.6, 0.08), 0.0, Color(0.55, 0.4, 0.22)],
				[Vector3(0, 0.62, 0), Vector3(0.16, 0.16, 0.16), 0.0, Color(0.7, 0.2, 0.15)]], theme), Vector3.ZERO, _stick)
		"node":
			pass      # drawn by the dungeon's per-kind MultiMesh (dungeon_build.gd)
		"lore":
			var rune := String(data.get("kind", "")) == "rune"
			if String(data.get("kind", "")) == "journal":
				_mesh_node(Kit.box_acc_mesh([[Vector3(0, 0.05, 0), Vector3(0.36, 0.06, 0.26), 0.0, Color(0.45, 0.3, 0.18)],
					[Vector3(0, 0.1, 0), Vector3(0.3, 0.02, 0.2), 0.0, Color(0.85, 0.8, 0.65)]], theme))
			else:
				var stone := Color(0.55, 0.55, 0.58) if not rune else Color(0.45, 0.42, 0.55)
				_mesh_node(Kit.box_acc_mesh([[Vector3(0, 1.1, -0.05), Vector3(1.3, 1.6, 0.12), 0.0, stone]], theme))
				var glow_m := StandardMaterial3D.new()
				glow_m.albedo_color = Color(0.6, 0.85, 1.0) if not rune else Color(0.85, 0.5, 1.0)
				glow_m.emission_enabled = true
				glow_m.emission = glow_m.albedo_color
				glow_m.emission_energy_multiplier = 1.4
				var q := MeshInstance3D.new()
				var qm := BoxMesh.new()
				qm.size = Vector3(0.8, 0.9, 0.03)
				q.mesh = qm
				q.material_override = glow_m
				q.position = Vector3(0, 1.1, 0.03)
				q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(q)
		"torch_cache":
			_mesh_node(Kit.box_acc_mesh([[Vector3(-0.09, 0.4, 0), Vector3(0.07, 0.85, 0.07), 0.0, Color(0.4, 0.28, 0.16)],
				[Vector3(0.0, 0.4, 0), Vector3(0.07, 0.85, 0.07), 0.0, Color(0.42, 0.3, 0.17)],
				[Vector3(0.09, 0.4, 0), Vector3(0.07, 0.85, 0.07), 0.0, Color(0.38, 0.27, 0.15)],
				[Vector3(0, 0.14, -0.1), Vector3(0.4, 0.28, 0.4), 0.0, Color(0.4, 0.3, 0.2)]], theme))
		"plate":
			_mesh_node(Kit.box_acc_mesh([[Vector3(0, 0.03, 0), Vector3(1.4, 0.08, 1.4), 0.0, Color(0.45, 0.45, 0.5)],
				[Vector3(0, 0.08, 0), Vector3(0.7, 0.04, 0.7), 0.0, Color(0.75, 0.6, 0.3)]], theme))
		"trap":
			_mesh_node(Kit.box_acc_mesh([[Vector3(0, 0.03, 0), Vector3(1.3, 0.05, 1.3), 0.0, Color(0.35, 0.33, 0.32)]], theme))


static var _ore_mats: Dictionary = {}


static func _ore_material(nk: String) -> StandardMaterial3D:
	if _ore_mats.has(nk):
		return _ore_mats[nk]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	match nk:
		"iron_ore": m.albedo_color = Color(1.4, 0.85, 0.6)
		"copper_ore": m.albedo_color = Color(0.7, 1.4, 1.0)
		"coal": m.albedo_color = Color(0.3, 0.3, 0.32)
		"silver_ore": m.albedo_color = Color(1.6, 1.7, 1.9)
		_: m.albedo_color = Color.WHITE
	_ore_mats[nk] = m
	return m
