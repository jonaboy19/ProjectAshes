extends SceneTree
## Prints the world [x, z] of the Thornfield wilds POIs (for env_views.json). Data only, headless OK.
func _initialize() -> void:
	WorldGen.setup(WorldSim.SEED)
	var Wilds: GDScript = load("res://scripts/world/thornfield/wilds.gd")
	var HP: GDScript = load("res://scripts/world/thornfield/hidden_places.gd")
	var th: Vector2 = Wilds.anchor()
	var r := float(Wilds.data().get("anchor_ring", 175.0))
	var best := Vector2.INF; var bd := 1e9; var a := 0.0
	while a < 360.0:
		var p := th + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * r
		var d := WorldGen.road_distance(p.x, p.y)
		if d < bd: bd = d; best = p
		a += 2.0
	print("ANCHOR ", th, " ROAD ", best, " HEAD ", Wilds.road_heading(best))
	print("CAMP ", Wilds.at(Wilds.data()["bandit_camp"]["offset"]))
	print("SHRINE ", HP.pos_of("ruined_shrine"))
	print("POST ", Wilds.post()["pos"])
	quit()
