extends RefCounted
## Who owns what in the world (package F5). Pure static helpers, no nodes except `owner_of`, which reads a node's meta.
##
## An owner is a plain string (so it rides in node meta, save deltas and signals):
##   ""  / "public"            nobody's: a bench, a well, wild loot
##   "player"                  the player's own things
##   "npc:<id>"                one person's belongings (a villager's coin purse, a dropped tool)
##   "household:<sid>:<lot>"   a house of settlement <sid>, lot plan index <lot>
##   "shop:<sid>:<id>"         a shop or the inn of settlement <sid> (<id> = building asset or shop kind)
##
## Taking something that belongs to somebody else is theft (`is_theft`). The player's own house and property are fine.
## What theft does about it lives in scripts/sim/theft.gd; trespass in scripts/population/trespass.gd.
## Persistence of "taken" / "opened" lives in WorldState deltas keyed by the object's stable id (`state_*` below).
## Preload this script; no class_name.

const WorldState := preload("res://scripts/world/world_state.gd")

const PUBLIC := "public"
const PLAYER := "player"

enum Kind { PUBLIC, PLAYER, NPC, HOUSEHOLD, SHOP }

## Building assets that are shops / services (their interiors follow ShopHours) rather than homes.
const SHOP_ASSETS := ["inn", "blacksmith", "healer_house", "adventurer_guild"]
## Building asset -> ShopHours kind.
const ASSET_HOURS_KIND := {"inn": "inn", "blacksmith": "blacksmith", "healer_house": "healer", "adventurer_guild": "guild"}


# ---------------------------------------------------------------- strings
static func npc(person_id: Variant) -> String:
	return "npc:%s" % str(person_id)


static func household(sid: int, lot: int) -> String:
	return "household:%d:%d" % [sid, lot]


static func shop(sid: int, id: String) -> String:
	return "shop:%d:%s" % [sid, id]


## {kind: Kind, sid: int (-1 none), id: String (npc id / lot index / shop id)}.
static func parse(owner: String) -> Dictionary:
	if owner == "" or owner == PUBLIC:
		return {"kind": Kind.PUBLIC, "sid": -1, "id": ""}
	if owner == PLAYER:
		return {"kind": Kind.PLAYER, "sid": -1, "id": ""}
	var p := owner.split(":", true, 2)
	match p[0]:
		"npc":
			return {"kind": Kind.NPC, "sid": -1, "id": p[1] if p.size() > 1 else ""}
		"household":
			var rest := owner.split(":")
			return {"kind": Kind.HOUSEHOLD, "sid": int(rest[1]) if rest.size() > 1 else -1, "id": rest[2] if rest.size() > 2 else ""}
		"shop":
			var rest2 := owner.split(":", true, 2)
			return {"kind": Kind.SHOP, "sid": int(rest2[1]) if rest2.size() > 1 else -1, "id": rest2[2] if rest2.size() > 2 else ""}
	return {"kind": Kind.PUBLIC, "sid": -1, "id": ""}


static func kind_of(owner: String) -> int:
	return int(parse(owner)["kind"])


## The settlement an owner belongs to (-1 for public / player / a person with no town).
static func sid_of(owner: String) -> int:
	return int(parse(owner)["sid"])


## The property-registry lot id ("s0:l3") of a household owner, "" for anything else.
static func lot_id_of(owner: String) -> String:
	var d := parse(owner)
	if int(d["kind"]) != Kind.HOUSEHOLD:
		return ""
	return "s%d:l%s" % [int(d["sid"]), String(d["id"])]


# ---------------------------------------------------------------- resolving
## The owner string of a world node: its own meta "owner" (or `owner_id` property), else the nearest ancestor's
## meta "building_owner" (set on an interior room when it loads), else public.
static func owner_of(node: Object) -> String:
	if node == null or not is_instance_valid(node):
		return PUBLIC
	var cur: Object = node
	var first := true
	while cur != null and is_instance_valid(cur):
		if cur is Node:
			var n := cur as Node
			if first:
				if n.has_meta("owner") and String(n.get_meta("owner")) != "":
					return String(n.get_meta("owner"))
				var oid: Variant = n.get("owner_id")
				if oid is String and oid != "":
					return oid
			if n.has_meta("building_owner") and String(n.get_meta("building_owner")) != "":
				return String(n.get_meta("building_owner"))
			cur = n.get_parent()
		else:
			break
		first = false
	return PUBLIC


## Sets the owner on a node (meta, mirrored to `owner_id` when the node has that property).
static func set_owner(node: Object, owner: String) -> void:
	if node == null:
		return
	if node is Node:
		(node as Node).set_meta("owner", owner)
	if node.get("owner_id") != null:
		node.set("owner_id", owner)


## What the player holds: {"lots": ["s0:l3", ...], "npcs": [...]}. Default reads Life.property (null-safe).
static func player_holdings(player: Variant = null) -> Dictionary:
	if player is Dictionary:
		return player
	var lots: Array = []
	var loop := Engine.get_main_loop()
	var life: Node = (loop as SceneTree).root.get_node_or_null("Life") if loop is SceneTree else null
	if life != null and life.get("property") != null:
		var prop: Object = life.get("property")
		for h: Array in [prop.call("owned"), prop.call("rented")]:
			for info: Dictionary in h:
				lots.append(String(info.get("lot_id", "")))
	return {"lots": lots, "npcs": []}


## True when taking `owner`'s things is a crime: owned by a person, a household that is not the player's own
## (owned or rented), or a shop. Public, player and unowned things are free. `player` may be a holdings
## Dictionary ({"lots": [...]}) for tests; null reads the live game.
static func is_theft(owner: String, player: Variant = null) -> bool:
	var d := parse(owner)
	match int(d["kind"]):
		Kind.PUBLIC, Kind.PLAYER:
			return false
		Kind.HOUSEHOLD:
			return not (player_holdings(player).get("lots", []) as Array).has(lot_id_of(owner))
		_:
			return true


## Is `owner` private space (a home that is not the player's)? Shops are handled by hours (ShopHours).
static func is_private_home(owner: String, player: Variant = null) -> bool:
	return kind_of(owner) == Kind.HOUSEHOLD and is_theft(owner, player)


## Owner of a building's interior from its lot: houses -> their household (the player's own when held),
## inns / smithy / healer / guild hall -> the shop, anything else public. `asset` is the building asset name.
static func building_owner(sid: int, lot: int, asset: String, player: Variant = null) -> String:
	if asset in SHOP_ASSETS:
		return shop(sid, asset)
	var BP := load("res://scripts/world/building_profiles.gd")
	if bool(BP.call("is_house", asset)):
		var h := household(sid, lot)
		return PLAYER if not is_theft(h, player) else h
	return PUBLIC


## Owner of the interior an entrance `door` (an InteriorDoor with meta "lot_pos") leads to: looks the lot up in the
## generated settlement plans. Public when the door has no lot (a ruin, a quest room).
static func owner_for_door(door: Object, player: Variant = null) -> String:
	if door == null or not (door is Node) or not (door as Node).has_meta("lot_pos"):
		return PUBLIC
	var lp: Variant = (door as Node).get_meta("lot_pos")
	if not lp is Vector2:
		return PUBLIC
	var settlements: Array = WorldGen.settlements
	for si in settlements.size():
		var lots: Array = (settlements[si] as Dictionary).get("plan", {}).get("lots", [])
		for li in lots.size():
			var pos: Vector2 = lots[li].get("pos", Vector2.INF)
			if pos.distance_squared_to(lp) < 0.0001:
				return building_owner(si, li, String(lots[li].get("asset", "")), player)
	return PUBLIC


## The ShopHours kind of an owner string ("shop:0:blacksmith" -> "blacksmith"), "" for anything not a shop.
static func hours_kind_of(owner: String) -> String:
	var d := parse(owner)
	if int(d["kind"]) != Kind.SHOP:
		return ""
	var id := String(d["id"])
	return String(ASSET_HOURS_KIND.get(id, id))


## Gold value of a stack, for scaling a theft (ItemsDB price, at least 1).
static func value_of(item: String, qty := 1) -> int:
	var ItemsDB := load("res://scripts/sim/items_db.gd")
	var info: Dictionary = ItemsDB.call("info", item)
	return maxi(1, int(info.get("price", 1))) * maxi(qty, 1)


# ---------------------------------------------------------------- persistence (WorldState deltas)
static func _ws(ws: RefCounted) -> RefCounted:
	return ws if ws != null else WorldState.shared()


## A ground item / pickup id has been taken.
static func state_taken(id: String, ws: RefCounted = null) -> bool:
	return bool((_ws(ws).call("get_state", id, {"taken": false}) as Dictionary)["taken"])


static func mark_taken(id: String, ws: RefCounted = null) -> void:
	_ws(ws).call("set_state", id, {"taken": true}, {"taken": false})


## A container's saved state: {"opened": bool, "contents": Array or null (null = still the rolled default)}.
static func container_state(id: String, ws: RefCounted = null) -> Dictionary:
	var st: Dictionary = _ws(ws).call("get_state", id, {"opened": false})
	return {"opened": bool(st.get("opened", false)), "contents": st.get("contents", null)}


static func save_container(id: String, contents: Array, ws: RefCounted = null) -> void:
	_ws(ws).call("set_state", id, {"opened": true, "contents": contents.duplicate(true)}, {"opened": false})
