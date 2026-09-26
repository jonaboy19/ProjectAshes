class_name BirthCutscene
extends RefCounted
## Builds the shot list for the player's birth in the first village, for
## CutscenePlayer. Night sky over the village -> slow crane down to a lit
## house -> cut to the interior -> the parents name the baby -> dawn
## establishing shot. Positions are relative to the village centre and sit on
## the terrain via WorldGen.height(x, z) (or a height function you pass in).
##
## Shots carry a "time" key (hour of day). The caller applies it on
## CutscenePlayer.shot_started so the sky is night for the opening and dawn
## at the end, e.g. WorldSim.time_of_day = shot["time"].
##
## Hooking it in (later, from main.gd on a new game, after the world exists):
##   var home: Dictionary = WorldGen.settlements[0]
##   var shots := BirthCutscene.build(life_path.given_name, life_path.family_name,
##       life_path.parent("mother")["name"], life_path.parent("father")["name"],
##       home["pos"], life_path.home_pos, String(home["name"]))
##   cutscene_player.play(shots)
## The house should be a real lit house from the village plan; pass its ground
## position as `house`. Give it a warm OmniLight3D at night so the crane lands on
## something glowing.

## Default house: a little off the village centre.
const DEFAULT_HOUSE := Vector2(14.0, 9.0)


## Returns an Array of shot Dictionaries. `height_fn` is Callable(x, z) -> float;
## when invalid, WorldGen.height is used.
static func build(baby: String, family: String, mother: String, father: String,
		village := Vector2.ZERO, house := DEFAULT_HOUSE, village_name := "the village",
		height_fn := Callable(), interior := Vector3.INF) -> Array:
	var hf := height_fn if height_fn.is_valid() else Callable(WorldGen, "height")
	var v_ground := float(hf.call(village.x, village.y))
	var h_ground := float(hf.call(house.x, house.y))
	var v := Vector3(village.x, v_ground, village.y)
	var h := Vector3(house.x, h_ground, house.y)
	# Direction from the village centre to the house, flattened, for framing.
	var out := Vector3(h.x - v.x, 0.0, h.z - v.z)
	if out.length() < 0.1:
		out = Vector3(0, 0, 1)
	out = out.normalized()
	var side := out.cross(Vector3.UP).normalized()
	var full := ("%s %s" % [baby, family]).strip_edges()
	var shots: Array = []

	# 1. Night sky, tilting down from the stars to the sleeping village.
	shots.append({
		"from": v + Vector3(0, 55, 0) - out * 70.0,
		"to": v + Vector3(0, 48, 0) - out * 60.0,
		"look": v + Vector3(0, 140, 0) + out * 60.0,
		"look_to": v + Vector3(0, 6, 0),
		"fov": 62.0, "fov_to": 55.0,
		"duration": 7.0, "ease": "in_out", "fade_in": 2.5, "time": 23.5,
		"text": "The last night of the long winter, above %s." % village_name,
	})
	# 2. Slow crane down onto the one house with its lights still burning.
	shots.append({
		"from": h + Vector3(0, 40, 0) - out * 34.0 + side * 8.0,
		"to": h + Vector3(0, 4.5, 0) - out * 11.0 + side * 3.0,
		"look": h + Vector3(0, 1.0, 0),
		"look_to": h + Vector3(0, 2.2, 0),
		"fov": 50.0, "fov_to": 42.0,
		"duration": 8.0, "ease": "in_out", "time": 23.7,
		"fade_out": 0.6,
	})
	if interior != Vector3.INF:
		shots.append_array(_set_shots(interior, mother, father, baby, full))
	else:
		# 3. Interior: a simple, warm framing over the cradle by the hearth.
		var cradle := h + Vector3(0, 0.7, 0) + side * 0.8
		shots.append({
			"from": h + Vector3(0, 1.55, 0) - side * 1.6 + out * 1.4,
			"to": h + Vector3(0, 1.45, 0) - side * 1.3 + out * 1.1,
			"look": cradle,
			"fov": 46.0, "fov_to": 42.0,
			"duration": 4.0, "ease": "out", "fade_in": 0.6, "time": 23.9,
			"text": "A cry breaks the quiet.",
		})
		# 4-6. The parents name the child. Slow push-in, subtitles carry the names.
		shots.append({
			"from": h + Vector3(0, 1.45, 0) - side * 1.3 + out * 1.1,
			"to": h + Vector3(0, 1.3, 0) - side * 1.0 + out * 0.8,
			"look": cradle, "fov": 42.0, "fov_to": 38.0,
			"duration": 4.5, "ease": "linear", "time": 0.0,
			"speaker": mother, "text": "Look at you. Welcome, little one.",
		})
		shots.append({
			"from": h + Vector3(0, 1.75, 0) + side * 1.4 + out * 1.0,
			"to": h + Vector3(0, 1.65, 0) + side * 1.2 + out * 0.8,
			"look": cradle, "fov": 40.0, "fov_to": 37.0,
			"duration": 4.5, "ease": "linear", "time": 0.1,
			"speaker": father, "text": "%s. Your name is %s." % [baby, baby],
		})
		shots.append({
			"from": cradle + Vector3(0, 0.9, 0) + out * 0.5,
			"to": cradle + Vector3(0, 0.7, 0) + out * 0.35,
			"look": cradle, "fov": 36.0, "fov_to": 32.0,
			"duration": 4.0, "ease": "in_out", "time": 0.2, "fade_out": 1.2,
			"text": "%s, child of %s and %s." % [full, mother, father],
		})

	# 7. Dawn establishing shot over the village.
	shots.append({
		"from": v + Vector3(0, 32, 0) - out * 90.0 - side * 40.0,
		"to": v + Vector3(0, 24, 0) - out * 72.0 - side * 25.0,
		"look": v + Vector3(0, 4, 0),
		"look_to": h + Vector3(0, 3, 0),
		"fov": 58.0, "fov_to": 52.0,
		"duration": 7.0, "ease": "in_out", "fade_in": 1.5, "fade_out": 1.5, "time": 6.2,
		"text": "Dawn comes to %s. A new life begins." % village_name,
	})
	return shots


## Shots 3-6 filmed on the cottage interior set (assets/generated/cottage_interior.glb)
## whose floor centre is `o`; the open wall faces +Z. Positions from its docstring.
static func _set_shots(o: Vector3, mother: String, father: String, baby: String, full: String) -> Array:
	var cradle := o + Vector3(1.05, 0.42, -1.2)
	var bed := o + Vector3(-2.35, 0.9, -1.2)
	var hearth := o + Vector3(0.0, 0.8, -2.1)
	var out: Array = []
	out.append({
		"from": o + Vector3(-0.6, 1.9, 3.6), "to": o + Vector3(-0.2, 1.7, 2.9),
		"look": hearth, "look_to": o + Vector3(0.2, 0.9, -1.6),
		"fov": 50.0, "fov_to": 46.0, "duration": 4.5, "ease": "out", "fade_in": 0.8, "time": 23.9,
		"text": "A cry breaks the quiet.",
	})
	out.append({
		"from": o + Vector3(-0.4, 1.55, 1.6), "to": o + Vector3(-0.6, 1.5, 1.2),
		"look": o + Vector3(-1.75, 1.2, -1.0), "fov": 46.0, "fov_to": 42.0, "duration": 4.5, "ease": "linear", "time": 0.0,
		"speaker": mother, "text": "Look at you. Welcome, little one.",
	})
	out.append({
		"from": o + Vector3(2.4, 1.6, 0.6), "to": o + Vector3(2.1, 1.5, 0.2),
		"look": cradle + Vector3(-0.3, 0.3, 0), "fov": 40.0, "fov_to": 36.0, "duration": 4.5, "ease": "linear", "time": 0.1,
		"speaker": father, "text": "%s. Your name is %s." % [baby, baby],
	})
	out.append({
		"from": cradle + Vector3(-0.2, 1.7, 1.6), "to": cradle + Vector3(-0.1, 1.45, 1.25),
		"look": cradle, "fov": 44.0, "fov_to": 40.0, "duration": 4.0, "ease": "in_out", "time": 0.2, "fade_out": 1.2,
		"text": "%s, child of %s and %s." % [full, mother, father],
	})
	return out
