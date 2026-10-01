# Shared helpers for the horse ASSET stage (coats, tack, export). Blender 5.2, headless.
import bpy, os, sys, math, zlib, struct
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import hb_common as H

V = lambda x, y, z: Vector((x, y, z))
OUT = H.OUT_DIR
DOCS = H.DOCS
RES_PATH = "res://assets/generated/horses/"


def log(*a):
    print("HX", *a, flush=True)


# ------------------------------------------------------------------ scene
def open_rig():
    """Open horse_rig.blend (never saved back), drop Rigify / helper objects, rest pose."""
    bpy.ops.wm.open_mainfile(filepath=H.BLEND)
    keep = {"HorseSkeleton", "Horse_LOD0"}
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.collections):
        if not c.objects and not c.children:
            bpy.data.collections.remove(c)
    for blk in (bpy.data.armatures, bpy.data.meshes, bpy.data.actions, bpy.data.materials, bpy.data.images):
        for d in list(blk):
            if d.users == 0:
                blk.remove(d)
    arm = bpy.data.objects["HorseSkeleton"]
    arm.data.pose_position = "POSE"
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    if arm.animation_data:
        arm.animation_data.action = None
    bpy.context.view_layer.update()
    return arm, bpy.data.objects["Horse_LOD0"]


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def select_only(*obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


def to_mode(mode):
    if bpy.context.object and bpy.context.object.mode != mode:
        bpy.ops.object.mode_set(mode=mode)


# ------------------------------------------------------------------ png
def write_png(path, rgba):
    """rgba float (h, w, 4) in 0..1 (sRGB encoded, row 0 = bottom like Blender) -> 8 bit PNG."""
    a = np.clip(np.asarray(rgba) * 255.0 + 0.5, 0, 255).astype(np.uint8)[::-1]
    h, w, c = a.shape
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(t, d):
        c_ = struct.pack(">I", len(d)) + t + d
        return c_ + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6 if c == 4 else 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def load_png(path, name, srgb=True):
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    img = bpy.data.images.load(path)
    img.name = name
    img.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    img.pack()
    return img


def write_tres(path, tex_name, roughness=0.75, extra=""):
    txt = ('[gd_resource type="StandardMaterial3D" load_steps=2 format=3]\n\n'
           '[ext_resource type="Texture2D" path="%s%s" id="1"]\n\n'
           '[resource]\nresource_name = "%s"\nalbedo_texture = ExtResource("1")\nmetallic = 0.0\nroughness = %.2f\n%s') % (
        RES_PATH, tex_name, os.path.splitext(os.path.basename(path))[0], roughness, extra)
    with open(path, "w", newline="\n") as f:
        f.write(txt)


# ------------------------------------------------------------------ materials
def textured_material(name, img, roughness=0.75):
    if name in bpy.data.materials:
        bpy.data.materials.remove(bpy.data.materials[name])
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = img
    tx.interpolation = "Linear"
    bs.inputs["Roughness"].default_value = roughness
    bs.inputs["Metallic"].default_value = 0.0
    nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"])
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    return m


def set_material(ob, mat):
    ob.data.materials.clear()
    ob.data.materials.append(mat)


# ------------------------------------------------------------------ rendering (EEVEE, warm sun + cool sky)
def setup_scene_render(w=1400, h=800):
    sc = bpy.context.scene
    for e in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = e
            break
        except TypeError:
            continue
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    try:
        sc.eevee.taa_render_samples = 24
    except Exception:
        pass
    try:
        sc.view_settings.view_transform = "Standard"
    except Exception:
        pass
    w_ = sc.world if sc.world else bpy.data.worlds.new("hxw")
    sc.world = w_
    w_.use_nodes = True
    bg = w_.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.55, 0.72, 0.95, 1)
    bg.inputs["Strength"].default_value = 0.9
    for o in [o for o in bpy.data.objects if o.name.startswith("hx_light")]:
        bpy.data.objects.remove(o)
    sun = bpy.data.objects.new("hx_light_sun", bpy.data.lights.new("hx_sun", "SUN"))
    bpy.context.scene.collection.objects.link(sun)
    sun.data.energy = 3.4
    sun.data.color = (1.0, 0.88, 0.70)
    sun.data.angle = math.radians(6)
    sun.rotation_euler = (math.radians(50), math.radians(8), math.radians(-38))
    return sc


def camera(loc, target, lens=60, ortho=None):
    cam = bpy.data.objects.get("hx_cam")
    if cam is None:
        cam = bpy.data.objects.new("hx_cam", bpy.data.cameras.new("hx_cam"))
        bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
    bpy.context.scene.camera = cam
    return cam


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    log("rendered", path)


def ground(size=40, color=(0.55, 0.62, 0.32), z=0.0, at=(0, 0)):
    g = bpy.data.objects.get("hx_ground")
    if g is None:
        bpy.ops.mesh.primitive_plane_add(size=size, location=(at[0], at[1], z))
        g = bpy.context.object
        g.name = "hx_ground"
        m = bpy.data.materials.new("hx_ground_m")
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1)
        m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
        g.data.materials.append(m)
    g.location = (at[0], at[1], z)
    return g


# ------------------------------------------------------------------ skinning helpers
def limit_normalize(ob, maxinf=4, allowed=None):
    """Keep the strongest maxinf groups per vertex, normalize. Pure python (no mode switch)."""
    names = [g.name for g in ob.vertex_groups]
    for v in ob.data.vertices:
        gs = [(g.weight, g.group) for g in v.groups]
        if allowed is not None:
            gs = [x for x in gs if names[x[1]] in allowed]
        gs.sort(reverse=True)
        keep = gs[:maxinf]
        tot = sum(w for w, _ in keep)
        for g in list(v.groups):
            ob.vertex_groups[g.group].remove([v.index])
        if tot <= 1e-9:
            continue
        for w, gi in keep:
            ob.vertex_groups[gi].add([v.index], w / tot, "REPLACE")


def pose(arm, d):
    """quick FK test pose: dict bone -> (x, y, z) euler degrees (empty dict = rest)"""
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0, 0, 0)
    for n, e in d.items():
        arm.pose.bones[n].rotation_euler = tuple(math.radians(x) for x in e)
    bpy.context.view_layer.update()
