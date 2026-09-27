import bpy, sys, os, json, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "meshy", "creature_rig"))
from common import *
spec = json.load(open(sys.argv[-1]))
reset(30)
sc = bpy.context.scene
F = 1000
sc.frame_set(F)
x = 0.0; gap = spec.get("gap", 0.4); yaw = math.radians(spec.get("yaw", 0))
tops = []
def mat(col):
    m = bpy.data.materials.new("m"); m.diffuse_color = col; return m
black = mat((0.05,0.05,0.05,1)); grey = mat((0.55,0.55,0.55,1)); line = mat((0.75,0.3,0.2,1))
def text(s, loc, size, m=black):
    cu = bpy.data.curves.new("t", 'FONT'); cu.body = s; cu.size = size; cu.align_x = 'CENTER'
    o = bpy.data.objects.new("t", cu); sc.collection.objects.link(o)
    o.location = loc; o.rotation_euler = (math.radians(90), 0, 0); o.data.materials.append(m)
    return o
maxh = 0
for it in spec["items"]:
    objs, acts = import_new(it["file"])
    for o in objs:
        for s in getattr(o, "material_slots", []):
            m = s.material
            if m and m.use_nodes:
                b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if b and b.inputs["Base Color"].links: m.node_tree.nodes.active = b.inputs["Base Color"].links[0].from_node
    roots = [o for o in objs if o.parent is None]
    arms = [o for o in objs if o.type == 'ARMATURE']
    meshes = [o for o in objs if o.type == 'MESH']
    for o in objs:
        if o.animation_data:
            o.animation_data.action = None
            for t in list(o.animation_data.nla_tracks): o.animation_data.nla_tracks.remove(t)
    if it.get("action") and arms:
        cand = [a for a in acts if a.name.split('|')[-1].split('.')[0] == it["action"]] or [a for a in acts if it["action"] in a.name]
        ac = cand[0]
        arm = arms[0]
        d = it.get("frame", 0)
        if isinstance(d, float) and d <= 1.0 and it.get("frac"):
            d = ac.frame_range[0] + d * (ac.frame_range[1] - ac.frame_range[0])
        tr = arm.animation_data_create().nla_tracks.new()
        st = tr.strips.new("s", int(round(F - d)), ac)
        if ac.slots: st.action_slot = ac.slots[0]
        st.extrapolation = 'HOLD'
    for r in roots:
        r.rotation_mode = "XYZ"; r.rotation_euler.z += yaw
    bpy.context.view_layer.update()
    mn, mx = world_bbox(meshes, bpy.context.evaluated_depsgraph_get())
    w = mx.x - mn.x
    dx = x - mn.x
    for r in roots: r.location.x += dx
    cx = x + w/2
    maxh = max(maxh, mx.z)
    it["_cx"] = cx; it["_h"] = mx.z; it["_minz"] = mn.z
    x += w + gap
total = x - gap
fs = spec.get("font", 0.12 * max(1.0, maxh/1.5))
for it in spec["items"]:
    text(it.get("label", ""), (it["_cx"], -0.6, -fs*1.4), fs)
    if spec.get("show_h", False):
        text(f'{it["_h"]:.2f} m', (it["_cx"], -3, it["_h"] + fs*0.4), fs*0.8, line)
# ground and height lines
bpy.ops.mesh.primitive_plane_add(size=1, location=(total/2, 0.5, -0.005)); g = bpy.context.object
g.scale = (total + 2, 3, 1); g.data.materials.append(grey)
if spec.get("grid", False):
    for hgt in range(1, int(maxh) + 2):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(total/2, 4, hgt)); c = bpy.context.object
        c.scale = (total + 1, 0.01, 0.01); c.data.materials.append(line)
        text(f"{hgt} m", (-0.5, 3.9, hgt + 0.03), fs*0.8, line)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
cam.data.type = 'ORTHO'
W_, H_ = spec.get("res", [1600, 800])
top = maxh + fs*1.2; bot = -fs*3.2
cw = total + 1.2; ch = top - bot
cam.data.ortho_scale = max(cw, ch * W_ / H_)
el = math.radians(spec.get("elev", 5))
cam.location = (total/2, -30*math.cos(el), (top+bot)/2 + 30*math.sin(el))
cam.rotation_euler = (math.radians(90) - el, 0, 0)
sc.camera = cam
if spec.get("engine") == "eevee":
    sc.render.engine = "BLENDER_EEVEE"
    for m_ in (black, line, grey):
        m_.use_nodes = True; nt_ = m_.node_tree
        for n_ in list(nt_.nodes):
            if n_.type == 'BSDF_PRINCIPLED': nt_.nodes.remove(n_)
        if m_ is grey:
            b_ = nt_.nodes.new("ShaderNodeBsdfDiffuse"); b_.inputs[0].default_value = (0.42, 0.42, 0.40, 1)
        else:
            b_ = nt_.nodes.new("ShaderNodeEmission"); b_.inputs[0].default_value = m_.diffuse_color
        nt_.links.new(b_.outputs[0], next(n for n in nt_.nodes if n.type == 'OUTPUT_MATERIAL').inputs[0])
    sc.view_settings.look = "AgX - Medium High Contrast" if False else "None"
    w = bpy.data.worlds.new("we"); w.use_nodes = True
    bg = w.node_tree.nodes.get("Background"); bg.inputs[0].default_value = (0.8, 0.8, 0.78, 1); bg.inputs[1].default_value = 0.55
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sc.collection.objects.link(sun)
    sun.data.energy = 2.2; sun.rotation_euler = (math.radians(50), math.radians(-25), math.radians(-30))
    sun.data.angle = math.radians(8)
    sc.view_settings.view_transform = 'Standard'
    try: sc.eevee.taa_render_samples = 32
    except Exception: pass
    sc.render.resolution_x, sc.render.resolution_y = W_, H_
    sc.render.filepath = spec["out"]
    bpy.ops.render.render(write_still=True)
    for it in spec["items"]: print("ITEM", it.get("label"), "h=%.3f minz=%.3f" % (it["_h"], it["_minz"]))
    raise SystemExit(0)
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading; sh.light = 'STUDIO'; sh.color_type = 'TEXTURE'; sh.show_shadows = False; sh.show_cavity = False
sc.render.resolution_x, sc.render.resolution_y = W_, H_
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.9, 0.9, 0.88)
sc.view_settings.view_transform = 'Standard'
sc.render.filepath = spec["out"]
bpy.ops.render.render(write_still=True)
for it in spec["items"]: print("ITEM", it.get("label"), "h=%.3f minz=%.3f" % (it["_h"], it["_minz"]))
