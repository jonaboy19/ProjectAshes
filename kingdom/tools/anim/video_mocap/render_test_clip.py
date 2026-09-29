# Renders a UAL clip on the Quaternius mannequin as a fake "phone video" (PNG frames + gt.json ground-truth joints).
#   blender -b --python render_test_clip.py -- <ual.glb> <action> <ABS outdir> <cam_azimuth_deg> <repeats>
# env: CAMR=camera distance (m), CLIPGLB=other GLB whose first action is played on the mannequin instead (retarget check),
#      GT=0 skips nothing (gt always written). Azimuth 180 = camera in front of the character.
import bpy, sys, math, json, os
from mathutils import Vector
glb, actname, outdir, az, reps = sys.argv[sys.argv.index("--")+1:][:5]
az = float(az); reps = int(reps)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=glb)
arm = bpy.data.objects["Armature"]
for o in list(bpy.data.objects):
    if o.name.startswith("Icosphere"): bpy.data.objects.remove(o)
act = bpy.data.actions[actname]
if os.environ.get("CLIPGLB"):
    before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=os.environ["CLIPGLB"])
    act = [a for a in bpy.data.actions if a not in before][0]
    for o in list(bpy.data.objects):
        if o.type == "ARMATURE" and o is not arm: bpy.data.objects.remove(o)

arm.animation_data_create(); arm.animation_data.action = act
if hasattr(arm.animation_data, "action_slot") and len(act.slots): arm.animation_data.action_slot = act.slots[0]
f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
sc = bpy.context.scene
sc.render.fps = 30
n = f1 - f0
import sys as _s
total = n * reps
sc.frame_start = 1; sc.frame_end = total
# material
m = bpy.data.materials.new("skin"); m.use_nodes = True
b = m.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value = (0.75,0.5,0.38,1); b.inputs["Roughness"].default_value=0.6
for o in bpy.data.objects:
    if o.type=="MESH": o.data.materials.clear(); o.data.materials.append(m)
# floor
bpy.ops.mesh.primitive_plane_add(size=60, location=(0,0,0))
fl = bpy.context.object; fm = bpy.data.materials.new("fl"); fm.use_nodes=True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value=(0.35,0.4,0.3,1)
fl.data.materials.append(fm)
# world + sun
sc.world = bpy.data.worlds.new("w"); sc.world.use_nodes=True
sc.world.node_tree.nodes["Background"].inputs[0].default_value=(0.6,0.75,0.95,1)
sc.world.node_tree.nodes["Background"].inputs[1].default_value=1.0
sun = bpy.data.lights.new("sun","SUN"); sun.energy=3
so = bpy.data.objects.new("sun", sun); sc.collection.objects.link(so); so.rotation_euler=(math.radians(50),0,math.radians(30))
cam = bpy.data.cameras.new("c"); cam.lens=float(os.environ.get("LENS","35"))
co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera=co
def place_cam(center):
    r=float(os.environ.get("CAMR","4.2")); a=math.radians(az)
    # character faces +Y in Blender (glTF -Z forward -> +Y). az=0 -> camera in front (+Y side)
    co.location = (center.x + r*math.sin(a), center.y + r*math.cos(a), 1.25)
    d = Vector((center.x, center.y, 0.95)) - co.location
    co.rotation_euler = d.to_track_quat("-Z","Y").to_euler()
sc.render.resolution_x=720; sc.render.resolution_y=1280
sc.render.engine="BLENDER_EEVEE"
sc.view_settings.view_transform="Standard"
try: sc.eevee.taa_render_samples=8
except Exception: pass
sc.render.image_settings.file_format="PNG"
os.makedirs(outdir, exist_ok=True)
# ground truth joints
GT = ["pelvis","spine_03","neck_01","Head","upperarm_l","lowerarm_l","hand_l","upperarm_r","lowerarm_r","hand_r","thigh_l","calf_l","foot_l","ball_l","thigh_r","calf_r","foot_r","ball_r"]
gt = []
def pose_at(i):
    k, fi = divmod(i, n)
    sc.frame_set(f0 + fi)
    arm.location = Vector((0,0,0)) + k*disp
    bpy.context.view_layer.update()
    return {j: list(arm.matrix_world @ arm.pose.bones[j].head) for j in GT}
sc.frame_set(f0); bpy.context.view_layer.update()
p0 = Vector(arm.matrix_world @ arm.pose.bones["pelvis"].head)
sc.frame_set(f1); bpy.context.view_layer.update()
p1 = Vector(arm.matrix_world @ arm.pose.bones["pelvis"].head)
disp = Vector((p1.x-p0.x, p1.y-p0.y, 0)) if reps>1 else Vector((0,0,0))
gt = [pose_at(i) for i in range(total)]
a_ = Vector(gt[0]["pelvis"]); b_ = Vector(gt[-1]["pelvis"])
place_cam((a_+b_)/2)
for i in range(total):
    pose_at(i)
    sc.render.filepath = os.path.join(outdir, "f%04d.png" % (i+1))
    bpy.ops.render.render(write_still=True)
json.dump({"fps":30,"joints":gt}, open(os.path.join(outdir,"gt.json"),"w"))
print("DONE", total)
