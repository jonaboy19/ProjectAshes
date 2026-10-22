extends Node3D
## A bed in a modular interior (package F6): the "Sleep" interactable. The visual is part of the room's batched mesh,
## so this node has none. Rules, using the existing sleep logic (Life.sleep, the inn's BED_PRICE):
##   your own home (owner "player"): free, and the bed becomes your respawn point
##   a shop / inn bed (owner "shop:..."): rent it for BED_PRICE gold
##   somebody else's household bed: refused ("not your bed"), nothing happens
## Ownership strings come from scripts/sim/ownership.gd; the owner is the node's meta "owner", else the room's
## meta "building_owner".

const Ownership_ := preload("res://scripts/sim/ownership.gd")
const BED_PRICE := 3

var bed_id := ""


static func spawn(parent: Node, pos: Vector3, id: String, owner := "") -> Node3D:
	var b: Node3D = (load("res://scripts/interiors/bed_prop.gd") as GDScript).new()
	b.set("bed_id", id)
	b.name = "Bed_" + id.replace("/", "_")
	if owner != "":
		Ownership_.set_owner(b, owner)
	parent.add_child(b)
	b.global_position = pos
	return b


func _ready() -> void:
	Interactable.attach(self, {"id_fn": func() -> String: return "bed/%s" % bed_id, "verb": "Sleep", "range": 2.4,
		"do": func(_p: Node) -> void: use(),
		"label": func() -> Dictionary: return {"verb": "Sleep", "target": target_text()}})


func owner_key() -> String:
	return Ownership_.owner_of(self)


func target_text() -> String:
	var who := owner_key()
	if Ownership_.kind_of(who) == Ownership_.Kind.SHOP:
		return "Bed (%dg)" % BED_PRICE
	if Ownership_.is_theft(who):
		return "Bed (not yours)"
	return "Your bed"


## Pure: can this owner's bed be used, and for what price? {ok, price, reason}.
static func terms(who: String, holdings: Variant = null) -> Dictionary:
	if not Ownership_.is_theft(who, holdings):
		return {"ok": true, "price": 0, "reason": ""}
	if Ownership_.kind_of(who) == Ownership_.Kind.SHOP:
		return {"ok": true, "price": BED_PRICE, "reason": ""}
	return {"ok": false, "price": 0, "reason": "That is somebody else's bed."}


func use() -> void:
	var t := terms(owner_key())
	var say := func(msg: String) -> void:
		var g := get_node_or_null("/root/Game")
		if g != null and g.has_method("say"):
			g.call("say", msg)
	if not bool(t["ok"]):
		say.call(String(t["reason"]))
		return
	var price := int(t["price"])
	if price > 0:
		if Game.gold < price:
			say.call("A bed costs %d gold." % price)
			return
		Game.add_gold(-price)
	elif Life.player and is_instance_valid(Life.player) and "spawn_point" in Life.player:
		Life.player.spawn_point = global_position + Vector3(0.0, 0.1, 0.0)
	say.call(Life.sleep(1.0))
