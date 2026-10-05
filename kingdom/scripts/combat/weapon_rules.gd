extends RefCounted
## F3 pure rules, no scene access (headless-testable): equipped weapon type -> move table, heavy-attack hold
## timing, bow draw -> power / damage / speed / stamina curves, bow aim assist, and the player knockdown
## thresholds. Every number lives in data/combat/player_weapons.json (DEFAULTS below only fill gaps).

const PATH := "res://data/combat/player_weapons.json"
const CombatFeel := preload("res://scripts/combat/combat_feel.gd")

const DEFAULTS := {
	"heavy": {"hold_time": 0.3, "charge_max": 1.0, "charge_bonus": 0.25},
	"style_of_type": {"sword": "sword", "spear": "spear", "staff": "staff", "shortbow": "bow", "longbow": "bow"},
	"ammo_of_type": {"shortbow": "arrow", "longbow": "arrow", "crossbow": "bolt"},
	"bow": {"draw_min": 0.12, "draw_full": 0.9, "power_min": 0.3, "power_curve": 1.6, "speed_min": 22.0,
		"speed_max": 44.0, "gravity": 5.5, "range": 60.0, "base_damage": 9.0, "weapon_damage_mult": 0.8,
		"ammo_damage_mult": 1.5, "stamina_min": 5.0, "stamina_full": 13.0, "assist_deg": 11.0, "assist_blend": 0.65,
		"lock_snap": true, "pick_range": 32.0, "pick_cone_dot": 0.82, "knockback_full": 3.0,
		"clips": {"draw": "Bow_Draw", "hold": "Bow_Hold", "loose": "Bow_Loose"}},
	"pool": {"arrows": 24, "orbs": 16, "stick_time": 3.0, "stick_time_body": 0.6, "arrow_life": 3.5},
	"knockdown": {"poise_threshold": 38.0, "knockback_threshold": 5.5, "ragdoll_knockback": 99.0,
		"ragdoll_enabled": false, "fall_time": 0.55, "down_time": 0.75, "getup_time": 1.1, "getup_iframes": 0.7,
		"roll_iframes": 0.45, "roll_min_down": 0.0, "cooldown": 1.5,
		"clips": {"fall": "Lie_Down", "fall_rate": 3.0, "getup": "Stand_From_Floor", "getup_rate": 1.8}},
}

static var _data: Dictionary = {}


## One section of the tuning file ("heavy", "bow", "pool", "knockdown", ...), defaults filled in.
static func cfg(section: String) -> Dictionary:
	if _data.is_empty():
		if FileAccess.file_exists(PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if parsed is Dictionary:
				_data = parsed
		if _data.is_empty():
			_data = {"_loaded": false}
	var out: Dictionary = (DEFAULTS.get(section, {}) as Dictionary).duplicate(true)
	var file: Variant = _data.get(section, {})
	if file is Dictionary:
		out.merge(file, true)
	return out


## Tests swap the tuning in and out (an empty dictionary reloads the file next time).
static func set_data(d: Dictionary) -> void:
	_data = d


# --- weapon type -> move table -------------------------------------------------------------

## "sword" for anything melee we have no table for (axes, maces, fists, bare hands), so nothing is ever unarmed.
static func style_for_type(weapon_type: String) -> String:
	return String(cfg("style_of_type").get(weapon_type, "sword"))


static func style_for_item(item_id: String, info: Dictionary) -> String:
	if item_id == "":
		return "sword"
	return style_for_type(String(info.get("weapon_type", info.get("type", ""))))


static func ammo_type_for(weapon_type: String) -> String:
	return String(cfg("ammo_of_type").get(weapon_type, "arrow"))


# --- heavy attack hold ---------------------------------------------------------------------

static func hold_time() -> float:
	return float(cfg("heavy")["hold_time"])


## "tap" (light combo), "charging" (held past the threshold, still down) -- on release a charging press is a heavy.
static func press_kind(held: float) -> String:
	return "charging" if held >= hold_time() else "tap"


## 0..1 over `charge_max` seconds after the threshold.
static func charge_fraction(held: float) -> float:
	var h := cfg("heavy")
	return clampf((held - float(h["hold_time"])) / maxf(float(h["charge_max"]), 0.01), 0.0, 1.0)


## Damage multiplier of a heavy released after `held` seconds (1.0 at the threshold).
static func charge_mult(held: float) -> float:
	return 1.0 + float(cfg("heavy")["charge_bonus"]) * charge_fraction(held)


# --- bow ------------------------------------------------------------------------------------

static func draw_fraction(held: float) -> float:
	return clampf(held / maxf(float(cfg("bow")["draw_full"]), 0.01), 0.0, 1.0)


## Draw-time curve: power_min at no draw, 1.0 at a full draw, eased by power_curve (> 1 rewards patience).
static func bow_power(held: float) -> float:
	var b := cfg("bow")
	return lerpf(float(b["power_min"]), 1.0, pow(draw_fraction(held), float(b["power_curve"])))


static func arrow_speed(held: float) -> float:
	var b := cfg("bow")
	return lerpf(float(b["speed_min"]), float(b["speed_max"]), bow_power(held))


static func bow_damage(weapon_damage: float, ammo_damage: float, held: float) -> int:
	var b := cfg("bow")
	var raw := float(b["base_damage"]) + weapon_damage * float(b["weapon_damage_mult"]) + ammo_damage * float(b["ammo_damage_mult"])
	return maxi(1, int(round(raw * bow_power(held))))


static func bow_stamina(held: float) -> float:
	var b := cfg("bow")
	return lerpf(float(b["stamina_min"]), float(b["stamina_full"]), draw_fraction(held))


## Release direction from `origin`: the locked target (snap) or the best cone pick (pulled toward it by
## `assist_blend`, never further than `assist_deg` off the facing), else the facing flattened to level.
## `locked` / `candidates` are world positions (chest height is added here). Uses CombatFeel.pick_target.
static func aim_direction(origin: Vector3, facing: Vector3, candidates: Array, locked: Variant = null) -> Dictionary:
	var b := cfg("bow")
	var f := Vector3(facing.x, 0.0, facing.z)
	f = f.normalized() if f.length() > 0.001 else Vector3.FORWARD
	var pick := CombatFeel.pick_target(origin, f, candidates, locked, float(b["pick_range"]), float(b["pick_cone_dot"]))
	if pick["pos"] == null:
		return {"dir": f, "target": null, "assisted": false}
	var tpos: Vector3 = (pick["pos"] as Vector3) + Vector3(0, 0.9, 0)
	var to := (tpos - origin).normalized()
	var is_lock: bool = locked is Vector3 and pick["index"] == -1
	if is_lock and bool(b["lock_snap"]):
		return {"dir": to, "target": pick["pos"], "assisted": true}
	var flat_to := Vector3(to.x, 0.0, to.z)
	var ang := f.angle_to(flat_to.normalized()) if flat_to.length() > 0.001 else 0.0
	var cap := deg_to_rad(float(b["assist_deg"]))
	if ang > cap:
		return {"dir": f, "target": pick["pos"], "assisted": false}
	var blended := f.lerp(to, float(b["assist_blend"])).normalized()
	return {"dir": blended, "target": pick["pos"], "assisted": true}


# --- knockdown ------------------------------------------------------------------------------

## "" (no knockdown), "fall" (full-body clip) or "ragdoll" (only when the data allows it) for one landed blow.
static func knockdown_kind(poise_damage: float, knockback: float) -> String:
	var k := cfg("knockdown")
	if poise_damage < float(k["poise_threshold"]) and knockback < float(k["knockback_threshold"]):
		return ""
	if bool(k["ragdoll_enabled"]) and knockback >= float(k["ragdoll_knockback"]):
		return "ragdoll"
	return "fall"
