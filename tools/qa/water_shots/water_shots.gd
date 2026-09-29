extends "../../store/store_shots.gd"
## Water QA shots (lake shore, river, pier) built on the store screenshot driver.
## Run: bash tools/qa/water_shots/run.sh <outdir> [quality=ultra] [shots=lake,river,pier] [extra --k=v]
## Shot args: hour, fov, and per shot camera offsets (see below).

func _lake_geo() -> Dictionary:
	var c: Vector2 = WorldGen.lake_center
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var out := (home - c).normalized()
	var shore := c
	var t := 0.0
	while t < WorldGen.lake_radius * 2.0:
		var q := c + out * t
		if not WorldGen.is_water(q.x, q.y):
			shore = q
			break
		t += 1.0
	return {"c": c, "into": -out, "shore": shore}


func _stage(p: Vector2) -> void:
	if _args().has("oldwater"):
		var m: ShaderMaterial = main.water.get("_material")
		m.shader = load("res://shaders/water.gdshader")
		m.set_shader_parameter("use_refraction", true)
	teleport(p)
	player.visible = false
	main.water.focus = Vector3(p.x, 0, p.y)
	main.water.build_all_now()
	await wait(6.0)


## Shore of Emberglass Mere, camera low on the beach looking across the water.
func _shot_lake() -> bool:
	hour(float(_args().get("hour", "11.5")))
	var a := _args()
	var g := _lake_geo()
	var shore: Vector2 = g["shore"]
	var into: Vector2 = g["into"]
	var side := Vector2(into.y, -into.x)
	await _stage(shore)
	var cp := shore - into * float(a.get("back", "-2")) + side * float(a.get("side", "6"))
	var lv: float = WorldGen.lake_level
	var look := shore + into * float(a.get("dist", "22")) - side * float(a.get("lside", "4"))
	free_cam(Vector3(cp.x, lv + float(a.get("cy", "2.6")), cp.y), Vector3(look.x, lv - 0.6, look.y), float(a.get("fov", "60")))
	await wait(2.0)
	await _fps()
	return false


func _shot_river() -> bool:
	hour(float(_args().get("hour", "11.5")))
	var a := _args()
	var pts: PackedVector2Array = WorldGen.rivers[0]["points"]
	var i := clampi(int(pts.size() * float(a.get("frac", "0.6"))), 1, pts.size() - 3)
	var p := pts[i]
	var tan := (pts[i + 1] - p).normalized()
	var n := Vector2(-tan.y, tan.x)
	await _stage(p)
	var lv := WorldGen.water_level_at(p.x, p.y)
	var cp := p + n * float(a.get("off", "9")) - tan * float(a.get("up", "8"))
	var lp := p + tan * float(a.get("ahead", "12"))
	free_cam(Vector3(cp.x, lv + float(a.get("cy", "4.0")), cp.y), Vector3(lp.x, lv - 0.5, lp.y), float(a.get("fov", "60")))
	await wait(2.0)
	await _fps()
	return false


func _shot_pier() -> bool:
	hour(float(_args().get("hour", "11.5")))
	var a := _args()
	var g := _lake_geo()
	var shore: Vector2 = g["shore"]
	var into: Vector2 = g["into"]
	var side := Vector2(into.y, -into.x)
	await _stage(shore + into * 6.0)
	var lv: float = WorldGen.lake_level
	var cp := shore + into * float(a.get("pd", "4")) + side * float(a.get("ps", "5"))
	var lp := shore + into * float(a.get("pl", "13")) - side * float(a.get("pls", "0"))
	free_cam(Vector3(cp.x, lv + float(a.get("cy", "2.4")), cp.y), Vector3(lp.x, lv - 0.3, lp.y), float(a.get("fov", "62")))
	await wait(2.0)
	await _fps()
	return false


func _fps() -> void:
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < 4000:
		await frames(1)
		n += 1
	print("STORE: WATERFPS quality=%s fps=%.1f" % [Quality.tier_name(), n / ((Time.get_ticks_msec() - t0) / 1000.0)])
