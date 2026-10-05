extends Node
## The wilds of Thornfield as one node (F9), added by the Thornfield hub (hub.gd). It owns the modules and one poll:
##   danger       the safety field under the player (wilds.gd): road and runestones safe by day, off-road and night not.
##                A line is said when you cross from town to road to verge to wilds, and the danger drives the night:
##                a wolf pack (WolfThreat.probe) when it is high enough, a bandit ambush (the RoadEvents node) deeper still.
##   bandit camp  bandit_camp.gd       hidden places  hidden_places.gd     gather nodes  gather_nodes.gd
##   the Rift     rift_entrance.gd     the outpost    outpost.gd (the Soldier career's post)
## Everything is built by distance from a 2 s timer; no per-frame work here.

const Wilds := preload("res://scripts/world/thornfield/wilds.gd")
const BanditCamp := preload("res://scripts/world/thornfield/bandit_camp.gd")
const HiddenPlaces := preload("res://scripts/world/thornfield/hidden_places.gd")
const GatherNodes := preload("res://scripts/world/thornfield/gather_nodes.gd")
const RiftEntrance := preload("res://scripts/world/thornfield/rift_entrance.gd")
const Outpost := preload("res://scripts/world/thornfield/outpost.gd")
const POLL := 2.0
const LINE_GAP := 6.0

var camp: Node3D
var hidden: Node3D
var gather: Node3D
var rift: Node3D
var outpost: Node3D
var threat: Node                     # WolfThreat (from the Thornfield hub), may be null
var zone := ""
var danger := 0.0
var wolf_packs := 0
var ambushes := 0
var _acc := 0.0
var _line_cd := 0.0
var _wolf_cd := 45.0
var _ambush_cd := 90.0


static func attach(parent: Node, wolf_threat: Node = null) -> Node:
	var h: Node = (load("res://scripts/world/thornfield/wilds_hub.gd") as GDScript).new()
	h.set("threat", wolf_threat)
	parent.add_child(h)
	return h


func _ready() -> void:
	name = "WildsHub"
	camp = BanditCamp.create(self, Wilds.data()["bandit_camp"])
	hidden = HiddenPlaces.new()
	add_child(hidden)
	gather = GatherNodes.new()
	add_child(gather)
	rift = RiftEntrance.new()
	add_child(rift)
	outpost = Outpost.new()
	add_child(outpost)


func _process(delta: float) -> void:
	_acc += delta
	if _acc < POLL:
		return
	var dt := _acc
	_acc = 0.0
	poll(dt)


## One poll step (tests call it with a stand-in player in group "player").
func poll(dt: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var pp := Vector2(player.global_position.x, player.global_position.z)
	if InteriorDoor.active != null:
		return             # inside a Rift or a barracks: the world is paused around you
	camp.call("refresh", pp)
	hidden.call("refresh", pp)
	gather.call("refresh", pp)
	rift.call("refresh", pp)
	outpost.call("refresh", pp, dt)
	_line_cd -= dt
	_wolf_cd -= dt
	_ambush_cd -= dt
	status(pp)
	encounters(pp, float(WorldSim.time_of_day))


## Updates zone and danger under `pp`, saying the crossing line when the zone changes. Returns the zone.
func status(pp: Vector2) -> String:
	danger = Wilds.danger(pp)
	var z := Wilds.zone(pp)
	if z != zone:
		var line := Wilds.crossing_line(zone, z)
		zone = z
		if line != "" and _line_cd <= 0.0:
			Game.say(line)
			_line_cd = LINE_GAP
	return zone


## Night/off-road threats at the player's spot. Returns {"wolves": n, "ambush": n} of what started this call.
func encounters(pp: Vector2, hour: float) -> Dictionary:
	var out := {"wolves": 0, "ambush": 0}
	var d := Wilds.danger(pp, hour)
	if Wilds.zone(pp) == "town":
		return out
	var wolves := Wilds.wolf_pack_size(d)
	if wolves > 0 and _wolf_cd <= 0.0 and threat != null and is_instance_valid(threat) and threat.has_method("probe"):
		_wolf_cd = float(Wilds.data()["safety"]["wolves"]["cooldown"])
		threat.call("probe", pp, wolves)
		wolf_packs += 1
		out["wolves"] = wolves
		Game.say("Wolves, close by in the dark.")
	var bandits := Wilds.ambush_size(d)
	if bandits > 0 and _ambush_cd <= 0.0:
		_ambush_cd = float(Wilds.data()["safety"]["ambush"]["cooldown"])
		if randf() < float(Wilds.data()["safety"]["ambush"]["chance"]):
			var re: Node = get_tree().root.find_child("RoadEvents", true, false) if is_inside_tree() else null
			if re != null and re.has_method("force_ambush"):
				re.call("force_ambush", pp, bandits)
				ambushes += 1
				out["ambush"] = bandits
	return out
