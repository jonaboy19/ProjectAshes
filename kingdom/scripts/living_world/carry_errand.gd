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
}
const ORDER := ["sack", "crate", "basket", "sack", "basket"]

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


## Drop at once (urgent act, despawn): no clip.
func drop(props: LifeProps.Holder) -> void:
	if _shown and props != null:
		props.clear()
	_shown = false
	state = S.NONE
	kind = ""


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
