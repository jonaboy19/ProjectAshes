extends Object
## Combat event bus for audio / VFX / UI listeners (combat-motion worker; for the combat-foley worker). One process-wide
## instance (CombatEvents.bus()), no autoload: combat code emits, listeners connect once.
##   CombatEvents.bus().hit.connect(func(e: Dictionary) -> void: ...)
## Every event is a Dictionary:
##   swing  {attacker, pos, weight: "light"|"heavy"|"finisher", speed: blade speed m/s estimate, clip, kind: "slash"|"thrust"|"overhead"}
##   hit    {attacker, victim, pos, weight, surface: "flesh"|"cloth"|"leather"|"metal"|"wood", damage, killed}
##   block  {attacker, defender, pos, weight, surface: "wood"|"metal" (shield / blade), broken: bool}
##   parry  {attacker, defender, pos, grade: "perfect"|"knockaway"|..., surface: "metal"}
##   dodge  {actor, pos, kind: "roll"|"back"}
## weight follows combat_feel tiers (light < heavy < finisher); `surface` is the thing struck.

signal swing(e: Dictionary)
signal hit(e: Dictionary)
signal block(e: Dictionary)
signal parry(e: Dictionary)
signal dodge(e: Dictionary)

const WEIGHTS := ["light", "heavy", "finisher"]

static var _bus: Object = null


static func bus() -> Object:
	if _bus == null:
		_bus = (load("res://scripts/combat/combat_events.gd") as GDScript).new()
	return _bus


static func weight_name(tier: int) -> String:
	return String(WEIGHTS[clampi(tier, 0, 2)])


## Surface a blow lands on for a body: armour pieces in its outfit list win (plate/mail -> metal, leather -> leather),
## else cloth over flesh. `keep` = the actor's outfit/prop tokens (soldier._keep) or [].
static func body_surface(keep: Array) -> String:
	for k in keep:
		var s := String(k).to_lower()
		if s.contains("plate") or s.contains("mail") or s.contains("helmet") or s.contains("armor") or s.contains("armour"):
			return "metal"
	for k in keep:
		if String(k).to_lower().contains("leather"):
			return "leather"
	return "cloth" if not keep.is_empty() else "flesh"


## Swing family from the clip's measured cut (data/combat/mx_combat_markers.json): thrust / overhead / slash.
static func swing_kind(clip: String) -> String:
	var m: Dictionary = (load("res://scripts/combat/combat_chains.gd") as GDScript).call("markers").get(clip, {})
	var d := String(m.get("dir", "left"))
	return "thrust" if d == "thrust" else ("overhead" if d == "overhead" else "slash")


## Surface of an actor: soldiers expose their outfit tokens (`_keep`), everything else is flesh.
static func surface_of(actor: Object) -> String:
	if actor == null or not is_instance_valid(actor):
		return "flesh"
	var keep: Variant = actor.get("_keep")
	return body_surface(keep as Array) if keep is Array else "flesh"


static func emit(kind: String, e: Dictionary) -> void:
	bus().emit_signal(kind, e)
