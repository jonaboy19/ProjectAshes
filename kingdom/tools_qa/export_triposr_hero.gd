extends SceneTree
func _initialize():
 call_deferred("export_hero")
func export_hero():
 var hero = load("res://scripts/style_lab/lab_chars.gd").hero_g()
 root.add_child(hero)
 await process_frame
 var ap = hero.find_child("AnimationPlayer", true, false)
 if ap: ap.stop()
 var doc = GLTFDocument.new()
 var state = GLTFState.new()
 var err = doc.append_from_scene(hero, state)
 if err == OK: err = doc.write_to_filesystem(state, "C:/Users/Jonna/Documents/Codex/3d-tools/TripoSR/hero_source.glb")
 print("HERO_EXPORT_RESULT ", err)
 quit(err)
