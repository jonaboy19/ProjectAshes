extends SceneTree
## Close-up before/after screenshots for specific grounding-report spots. This is
## the "--shots" companion mentioned in grounding_check.gd's header: rather than
## bolt an every-location screenshot pass onto the main scan (slow, and most
## locations have nothing worth a picture), this takes a small, explicit list of
## world positions -- normally copied straight out of report.md's worst-floating
## table -- and frames a close-up of each one.
##
## Run:
##   godot --path kingdom --resolution 1280x720 -s <abs>/tools/qa/grounding/shots.gd -- \
##     --adult --skipintro --out=<abs dir> --tag=before
## `--tag` is just a filename suffix (e.g. "before"/"after") so two runs at the
## same spots don't overwrite each other.

var main: Control
var args := {}
var out_dir := ""
var tag := ""
var phase := "boot"
var t := 0.0
var spot_i := 0

## label, world (x, z) of the thing to look at, and how far back/high to stand.
var SPOTS := [
	{"label": "01_chunk_forest_a", "at": Vector2(-131.0, 27.2), "back": 11.0, "up": 2.0, "side": true},
	{"label": "02_chunk_forest_b", "at": Vector2(-133.5, 26.9), "back": 11.0, "up": 2.0, "side": true},
	{"label": "03_chunk_forest_c", "at": Vector2(-129.7, 3.2), "back": 11.0, "up": 2.0, "side": true},
	{"label": "04_ashford_greenery_a", "at": Vector2(62.85, 54.06), "back": 12.0, "up": 2.2, "side": true},
	{"label": "05_ashford_greenery_b", "at": Vector2(78.98, 33.16), "back": 12.0, "up": 2.2, "side": true},
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
		elif a.begins_with("--"):
			args[a.substr(2)] = true
	out_dir = args.get("out", OS.get_user_data_dir() + "/grounding")
	tag = String(args.get("tag", ""))
	DirAccess.make_dir_recursive_absolute(out_dir)
	change_scene_to_file("res://scenes/main.tscn")


func _process(delta: float) -> bool:
	t += delta
	match phase:
		"boot":
			main = current_scene as Control
			if main and main.get("player") and main.player.is_inside_tree() and main.hud and not main.hud._loading.visible:
				if main.settlements:
					main.settlements.set_process(false)
				if main.region:
					main.region.set_process(false)
				phase = "goto"
				t = 0.0
			elif t > 40.0:
				print("SHOTS boot timed out")
				quit()
		"goto":
			if spot_i >= SPOTS.size():
				print("SHOTS done, %d spots captured" % SPOTS.size())
				quit()
				return true
			var spot: Dictionary = SPOTS[spot_i]
			var at: Vector2 = spot["at"]
			var back: float = spot["back"]
			# A side-on view (east of the target, looking west) instead of
			# straight-on: straight-on hides a floating trunk's gap behind its
			# own canopy. Side-on puts the trunk/ground contact in profile
			# against open ground so a gap actually reads in the screenshot.
			var offset := Vector2(back, 0) if spot.get("side", false) else Vector2(0, back)
			var stand := at + offset
			main._teleport(stand, 0.0)
			var d := at - stand
			var yaw := atan2(-d.x, -d.y)
			main.player.set_camera(yaw, -0.18)
			main.player.reset_physics_interpolation()
			var up: float = spot["up"]
			main.player.global_position.y = _wg().height(stand.x, stand.y) + up
			if main.hud:
				main.hud.visible = false
			t = 0.0
			phase = "settle"
		"settle":
			if main.hud:
				main.hud.visible = false   # a discovery banner can pop up mid-settle too
			if t > 1.6:
				phase = "shoot"
		"shoot":
			var spot: Dictionary = SPOTS[spot_i]
			var img := root.get_viewport().get_texture().get_image()
			var suffix := ("_" + tag) if tag != "" else ""
			var path := "%s/%s%s.jpg" % [out_dir, spot["label"], suffix]
			img.save_jpg(path, 0.92)
			print("SHOT %s -> %s" % [spot["label"], path])
			spot_i += 1
			phase = "goto"
			t = 0.0
	return false


func _wg() -> Script:
	return load("res://scripts/world/world_gen.gd")
