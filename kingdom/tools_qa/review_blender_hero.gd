extends SceneTree
var source: Node3D
var candidate: Node3D
var rows: Array = []
func _initialize():
 call_deferred("review")
func review():
 source = load("res://scripts/style_lab/lab_chars.gd").hero_g()
 root.add_child(source)
 var doc = GLTFDocument.new()
 var state = GLTFState.new()
 var err = doc.append_from_file("res://assets/incoming/ai3d/hero_styleg_blender_mobile_candidate.glb",state)
 if err != OK:
  push_error("Candidate GLTF load failed");quit(1);return
 candidate = doc.generate_scene(state)
 root.add_child(candidate)
 candidate.position.x=.8
 source.position.x=-.8
 var sk_a: Skeleton3D = source.find_children("*","Skeleton3D",true,false)[0]
 var sk_b: Skeleton3D = candidate.find_children("*","Skeleton3D",true,false)[0]
 var ap_a = Assets.animation_player(source)
 ap_a.stop()
 var ap_b = AnimationPlayer.new()
 candidate.add_child(ap_b)
 ap_b.add_animation_library("",Assets._ual_for(candidate.get_path_to(sk_b)))
 var world = WorldEnvironment.new()
 var env=Environment.new()
 env.background_mode=Environment.BG_COLOR
 env.background_color=Color(.12,.13,.15)
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color=Color.WHITE
 env.ambient_light_energy=.65
 world.environment=env
 root.add_child(world)
 var light=DirectionalLight3D.new()
 light.rotation_degrees=Vector3(-45,-30,0)
 light.light_energy=1.5
 root.add_child(light)
 var camera=Camera3D.new()
 root.add_child(camera)
 camera.position=Vector3(0,1,5)
 camera.look_at(Vector3(0,.9,0))
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.size=3.0
 camera.current=true
 root.size=Vector2i(1200,700)
 var missing=[]
 var rest_max=0.0
 for i in sk_a.get_bone_count():
  var name=sk_a.get_bone_name(i)
  var j=sk_b.find_bone(name)
  if j<0:missing.append(name);continue
  var a=sk_a.global_transform*sk_a.get_bone_global_rest(i)
  var b=sk_b.global_transform*sk_b.get_bone_global_rest(j)
  rest_max=maxf(rest_max,(a.origin-source.position).distance_to(b.origin-candidate.position))
 print("RIG_REVIEW bones ",sk_a.get_bone_count()," / ",sk_b.get_bone_count()," missing ",missing," rest_position_delta ",rest_max)
 var names=["Sword_Idle","Running_A","Jump_Rise","Jump_Land_Roll","Roll","Sword_Regular_A","Idle_Shield"]
 for name in names:
  if not ap_a.has_animation(name) or not ap_b.has_animation(name):
   rows.append({"clip":name,"available":false});continue
  for fraction in [.1,.3,.45,.65,.9]:
   ap_a.play(name);ap_b.play(name)
   var t=ap_a.get_animation(name).length*fraction
   ap_a.seek(t,true);ap_b.seek(t,true)
   ap_a.pause();ap_b.pause()
   await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("C:/Users/Jonna/Documents/Codex/3d-tools/TripoSR/rig_review_"+name+"_"+str(fraction)+".png")
   var pose_max=0.0
   for bone in ["head","hand_l","hand_r","foot_l","foot_r","pelvis"]:
    var i=sk_a.find_bone(bone)
    var j=sk_b.find_bone(bone)
    if i<0 or j<0:continue
    var a=sk_a.global_transform*sk_a.get_bone_global_pose(i)
    var b=sk_b.global_transform*sk_b.get_bone_global_pose(j)
    pose_max=maxf(pose_max,(a.origin-source.position).distance_to(b.origin-candidate.position))
   rows.append({"clip":name,"available":true,"sample_seconds":t,"max_landmark_delta_metres":pose_max})
 var f=FileAccess.open("C:/Users/Jonna/Documents/Codex/3d-tools/TripoSR/rig_review.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"missing_bones":missing,"rest_position_delta_metres":rest_max,"clips":rows},"  "))
 f.close()
 source.free();candidate.free();world.free();light.free();camera.free();quit()


