extends Node3D
## In-engine check of life clips on the real villager rig WITH props (LifeProps grip contract) and the smart
## object each clip is authored against (anchor from the sidecar). Up to 6 clips per page, 3 x 2 grid.
##
##   Godot --path kingdom --rendering-method mobile res://tools_qa/living_world/clip_gallery.tscn --write-movie out.avi
##         --fixed-fps 30 --quit-after 120 -- --clips=Life_Smith_Hammer,Life_Farm_Hoe [--look=villager_smith] [--view=side|q34|front]

const ANCHOR_PROPS := {
	"anvil": "res://assets/generated/props/anvil_stump.glb", "sawhorse": "res://assets/generated/life_props/sawhorse.glb",
	"chopping_block": "res://assets/generated/life_props/chopping_block.glb", "wash_tub": "res://assets/generated/life_props/wash_tub.glb",
	"cook_pot": "res://assets/generated/life_props/cook_pot.glb", "table": "res://assets/generated/life_props/table.glb",
	"bellows": "res://assets/generated/life_props/bellows.glb", "milking_stool": "res://assets/generated/life_props/milking_stool.glb",
	"bar_counter": "res://assets/generated/life_props/bar_counter.glb", "counter": "res://assets/generated/life_props/bar_counter.glb",
	"stool": "res://assets/generated/life_props/stool.glb", "bench": "res://assets/generated/props/bench.glb",
	"lectern": "res://assets/generated/life_props/lectern.glb", "trough": "res://assets/generated/props/water_trough.glb",
	"stall": "res://assets/generated/props/produce_table.glb", "market_stall": "res://assets/generated/props/produce_table.glb",
}


func _ready() -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.78, 0.84, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.66)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.58, 0.4)
	g.material_override = gm
	add_child(g)
	var clips: PackedStringArray = String(args.get("clips", "Life_Smith_Hammer")).split(",", false)
	var look := String(args.get("look", "villager_man_a"))
	for i in mini(clips.size(), 6):
		var clip := clips[i]
		var cell := Vector3((i % 3) * 3.2 - 3.2, 0, -(i / 3) * 3.6)
		var model := Assets.mh_character(look, 1.75, [])
		model.set_meta("lw_model_root", true)
		add_child(model)
		model.position = cell
		var anim := Assets.animation_player(model)
		LifeLibrary.install(anim)
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var holder := LifeProps.Holder.new(sk)
		holder.show_for_clip(clip)
		if anim.has_animation(clip):
			anim.play(clip)
		else:
			push_warning("gallery: missing clip " + clip)
		var info := LifeLibrary.info(clip)
		var an = info.get("anchor")
		if typeof(an) == TYPE_DICTIONARY and an.get("at") != null:
			var at: Array = an["at"]
			var path := String(ANCHOR_PROPS.get(String(an.get("type", "")), ""))
			var node: Node3D = null
			if path != "" and ResourceLoader.exists(path):
				node = (load(path) as PackedScene).instantiate()
			else:
				var box := MeshInstance3D.new()
				var bm := BoxMesh.new()
				var sz: Array = an.get("size", [0.5, 0.4, max(0.05, float(at[2]))])
				bm.size = Vector3(float(sz[0]), float(sz[2]), float(sz[1]))
				box.mesh = bm
				box.position.y = float(sz[2]) * 0.5
				node = Node3D.new()
				node.add_child(box)
			add_child(node)
			node.position = cell + Vector3(float(at[0]), 0, float(at[1]))
			node.rotation.y = PI
		var lbl := Label3D.new()
		lbl.text = clip
		lbl.font_size = 40
		lbl.pixel_size = 0.004
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = cell + Vector3(0, 2.15, 0)
		lbl.modulate = Color(0.1, 0.1, 0.1)
		lbl.outline_size = 0
		add_child(lbl)
	var cam := Camera3D.new()
	add_child(cam)
	var view := String(args.get("view", "q34"))
	var rows := 1 if clips.size() <= 3 else 2
	var center := Vector3(0, 0.9, -1.8 * (rows - 1))
	match view:
		"side":
			cam.position = center + Vector3(-9, 0.9, 0.4)
		"front":
			cam.position = center + Vector3(0, 1.2, 6.5 + rows * 1.5)
		_:
			cam.position = center + Vector3(-4.2, 1.9, 5.0 + rows * 1.5)
	cam.fov = 42
	cam.look_at(center)
