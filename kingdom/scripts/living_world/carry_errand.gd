extends RefCounted
## Villager carry errand (street life, benchmark slice): some daytime trips carry something from where the trip starts to
## where it ends. NONE -> PICKUP (bend down, the item appears in the hand at the bottom of the bend) -> CARRY (the item stays
## on the hand / shoulder; spine and arms come from a carry clip layered over the gold walk and over the idle) -> SETDOWN at
## the destination (the same bend, the item goes at the bottom) -> NONE. The prop exists only during the errand.
## Villager hooks: start() after a new plan, tick() every body tick, upper() for the layer. Not on smart-object trips
## (the session owns the clip there), indoor trips (the body hides at the door) or urgent acts (pace > 1.5: dropped).

enum S { NONE, PICKUP, CARRY, SETDOWN }

const BEND_CLIP := "Life_Mx_Pick_Up"
const BEND_FALLBACK := ["Chore_Pick_Up_Box", "PickUp_Table"]
const SHOW_AT := 0.45            # fraction of the bend clip where the hand reaches the ground
const MIN_TRIP_M := 12.0
const SHARE := 0.30              # share of eligible trips that carry something
## kind -> prop (LifeProps id + hand) and the upper-body clip layered over walk / idle ("" = keep the walk's arm swing)
const KINDS := {
	"sack": {"prop": {"id": "sack", "hand": "r"}, "upper": "Life_Mz_Carry_Sack_Walk"},
	"crate": {"prop": {"id": "crate_small", "hand": "r"}, "upper": "Life_Mx_Carry_Box_Walk"},
	"basket": {"prop": {"id": "basket", "hand": "l"}, "upper": ""},
	"firewood": {"prop": {"id": "firewood_bundle", "hand": "r"}, "upper": "Life_Mz_Carry_Sack_Walk"},
}
const ORDER := ["sack", "crate", "basket", "firewood", "sack", "basket", "firewood"]
const DROP_KEEP_S := 30.0         # a load dropped when running for it lies in the street this long

var state := S.NONE
var kind := ""
var _t := 0.0
var _len := 1.6
var _shown := false


## Which item (or "") this trip carries: stable per person, day and half hour.
static func roll(person: int, day: int, hour: float, trip_m: float, child: bool, guard: bool) -> String:
	if child or guard or hour < 7.0 or hour > 18.5 or trip_m < MIN_TRIP_M:
		return ""
	var h := absi(hash([person, day, int(hour * 2.0), 7331]))
	var share := SHARE
	if OS.has_environment("ASHES_CARRY_SHARE"):          # QA recordings: more carriers in shot
		share = float(OS.get_environment("ASHES_CARRY_SHARE"))
	if float(h % 1000) / 1000.0 >= share:
		return ""
	return String(ORDER[(h / 1000) % ORDER.size()])


func carrying() -> bool:
	return state == S.CARRY or (state == S.PICKUP and _shown) or (state == S.SETDOWN and _shown)


func upper() -> String:
	return String(KINDS.get(kind, {}).get("upper", "")) if carrying() else ""


## Begin: returns the bend clip to play as a one-shot and its length (the caller holds the villager still that long).
func start(k: String, anim: AnimationPlayer) -> Array:
	if OS.has_environment("ASHES_CARRY_SHARE"):
		print("CARRY start ", k)
	kind = k
	state = S.PICKUP
	_t = 0.0
	_shown = false
	var clip := _bend(anim)
	_len = anim.get_animation(clip).length if clip != "" else 1.0
	return [clip, _len]


## Set down at the destination: same contract as start().
func finish(anim: AnimationPlayer) -> Array:
	if OS.has_environment("ASHES_CARRY_SHARE"):
		print("CARRY setdown ", kind)
	state = S.SETDOWN
	_t = 0.0
	var clip := _bend(anim)
	_len = anim.get_animation(clip).length if clip != "" else 1.0
	return [clip, _len]


## Drop at once (urgent act: running for it). The load leaves the hand and falls to the street, lies there DROP_KEEP_S and
## goes (no pop out of the hand). `world` is where the dropped prop lives (the villager's parent).
func drop(props: LifeProps.Holder, world: Node = null) -> void:
	if _shown and props != null:
		var prop: Dictionary = KINDS.get(kind, {}).get("prop", {})
		var key := String(prop.get("id", "")) + "|" + String(prop.get("hand", "r"))
		var att: Variant = props._att.get(key)
		if world != null and att is Node3D and is_instance_valid(att):
			props._att.erase(key)
			drop_to_ground(att as Node3D, world)
		props.clear()
	_shown = false
	state = S.NONE
	kind = ""


## Detach a hand prop into the world and let it fall onto the ground below (simple ease, no physics body), then free it.
static func drop_to_ground(att: Node3D, world: Node) -> void:
	var gx := att.global_transform
	att.get_parent().remove_child(att)
	var holder := Node3D.new()
	holder.name = "DroppedLoad"
	world.add_child(holder)
	holder.global_transform = Transform3D.IDENTITY
	holder.add_child(att)
	att.global_transform = gx
	var ground := WorldGen.height(gx.origin.x, gx.origin.z)
	var lie := Basis(Vector3.UP, gx.basis.get_euler().y) * Basis(Vector3.RIGHT, PI * 0.5)     # comes to rest on its side
	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(att, "global_position", Vector3(gx.origin.x, ground + 0.12, gx.origin.z), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(att, "global_basis", lie.scaled(gx.basis.get_scale()), 0.45)
	tw.chain().tween_interval(DROP_KEEP_S)
	tw.chain().tween_callback(holder.queue_free)


## Advance the timers; shows / hides the prop at the bottom of the bend. Returns true when the errand just ended.
func tick(delta: float, props: LifeProps.Holder) -> bool:
	if state == S.NONE:
		return false
	_t += delta
	var prop: Dictionary = KINDS.get(kind, {}).get("prop", {})
	match state:
		S.PICKUP:
			if not _shown and _t >= _len * SHOW_AT:
				_shown = true
			if _t >= _len:
				state = S.CARRY
		S.SETDOWN:
			if _shown and _t >= _len * SHOW_AT:
				_shown = false
				if props != null:
					props.clear()
			if _t >= _len:
				state = S.NONE
				kind = ""
				return true
	if _shown and props != null and not prop.is_empty():
		props.show_props([prop])      # idempotent; re-shows it if an act change cleared the hands mid-trip
	return false


func _bend(anim: AnimationPlayer) -> String:
	if anim == null:
		return ""
	if anim.has_animation(BEND_CLIP):
		return BEND_CLIP
	for c: String in BEND_FALLBACK:
		if anim.has_animation(c):
			return c
	return ""
