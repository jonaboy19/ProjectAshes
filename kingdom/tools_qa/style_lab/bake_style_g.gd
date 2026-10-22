extends SceneTree
## Bakes Style G into resources/style_g/*.tres (Environment per tier + role materials without per-asset albedo).
## Run: godot --headless --path kingdom -s tools_qa/style_lab/bake_style_g.gd
## Source of truth stays scripts/style_g.gd; re-bake after changing it.
const StyleG := preload("res://scripts/style_g.gd")
const OUT := "res://resources/style_g/"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for tier in StyleG.TIERS:
		_save(StyleG.make_environment(tier), "env_%s.tres" % tier)
	for role in ["ground", "gate_stone", "gate_trim", "iron", "banner", "flag"]:
		_save(StyleG.material_for(role), "mat_%s.tres" % role)
	quit()

func _save(r: Resource, f: String) -> void:
	var err := ResourceSaver.save(r, OUT + f)
	print("style_g bake ", f, " -> ", error_string(err))
