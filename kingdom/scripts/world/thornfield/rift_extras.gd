extends RefCounted
## The parts of the Thornfield Rift that dungeon_build.gd does not know about (F9), attached to the built interior root:
##   Rift's Edge Camp   a quartermaster with a shop (Station), a bedroll that rests and saves (Station)
##   Weeping Hall       the Rift vents (rift_vent.gd)
## The camp fire, lanterns, torch, chests, lever gate, creatures, the boss and its telegraph are ordinary dungeon
## content from the layout. Everything here is cheap: two Stations, a character model, two small vents.

const Wilds := preload("res://scripts/world/thornfield/wilds.gd")
const Vent := preload("res://scripts/world/thornfield/rift_vent.gd")
const Items := preload("res://scripts/interiors/dungeon_items.gd")
const BED_REST := 0.8


## Builds the extras under `root` (a Node3D at the dungeon origin). Returns {quartermaster, bed, vents}.
static func attach(root: Node3D, g: Dictionary) -> Dictionary:
	var content: Dictionary = g["content"]
	var out := {"vents": []}
	if not content.has("camp"):
		return out
	var camp: Dictionary = content["camp"]
	var fire: Vector3 = camp["fire"]
	var qm := Station.new(String(Wilds.quartermaster()["name"]), "Trade", Callable())
	qm.menu = func() -> Dictionary: return shop_menu(qm)
	qm.name = "Quartermaster"
	root.add_child(qm)
	qm.position = camp["quartermaster"]
	qm.rotation.y = atan2(fire.x - qm.position.x, fire.z - qm.position.z)
	var body := Assets.character("Trader", 1.74, [])
	if body != null:
		qm.add_child(body)
		var ap := Assets.animation_player(body)
		if ap:
			ap.play("Idle" if ap.has_animation("Idle") else ap.get_animation_list()[0])
	qm.set_meta("rift_camp", true)
	out["quartermaster"] = qm
	var bed := Station.new("Bedroll", "Rest", Callable())
	bed.menu = func() -> Dictionary: return bed_menu(bed)
	bed.name = "CampBed"
	root.add_child(bed)
	bed.position = camp["bed"]
	bed.add_child(_bedroll_visual())
	bed.set_meta("rift_camp", true)
	out["bed"] = bed
	var vcfg: Dictionary = content["vent"]
	var i := 0
	for h: Dictionary in content["hazards"]:
		var v: Node3D = Vent.new()
		v.call("configure", vcfg, float(i) * 3.2)
		v.name = "Vent_" + String(h["id"])
		root.add_child(v)
		v.position = h["pos"]
		(out["vents"] as Array).append(v)
		i += 1
	return out


static func _bedroll_visual() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.16, 2.0)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.3, 0.22)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position.y = 0.08
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var pillow := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.6, 0.12, 0.35)
	pillow.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.75, 0.7, 0.6)
	pillow.material_override = pmat
	pillow.position = Vector3(0, 0.2, 0.7)
	pillow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(pillow)
	return n


# --- the quartermaster ------------------------------------------------------------------------

static func shop_menu(_from: Node) -> Dictionary:
	var q := Wilds.quartermaster()
	Items.register(Life)
	var opts: Array = []
	for line: Array in q["stock"]:
		var item := String(line[0])
		var price := int(line[1])
		opts.append(["Buy %s  -  %dg" % [Life.item_name(item), price], buy.bind(item, price), Game.gold >= price])
	for item: String in q["buys"]:
		var n: int = Life.count(item)
		if n > 0:
			opts.append(["Sell %s x%d" % [Life.item_name(item), n], Life.sell.bind(item), true])
	return {"title": String(q["name"]),
		"body": "\"Everything in this camp is counted twice. Buy what you need, and bring me anything violet that hums.\"",
		"options": opts}


static func buy(item: String, price: int) -> String:
	if Game.gold < price:
		return "Not enough gold."
	Items.register(Life)
	Game.add_gold(-price)
	Life.give(item, 1)
	return "Bought %s for %dg." % [Life.item_name(item), price]


# --- the bedroll: rest and save ----------------------------------------------------------------

static func bed_menu(from: Node) -> Dictionary:
	return {"title": "Camp bedroll", "body": "The fire holds the Rift's wolves off. Rest here, or write down your progress.",
		"options": [["Rest until morning", rest.bind(from)], ["Save game", save]]}


static func rest(from: Node) -> String:
	var hud := Interaction.hud(from)
	if hud != null:
		hud.call("close_menu")
	return Life.sleep(BED_REST)


static func save() -> String:
	return "Game saved." if Life.save_game() else "Could not save."
