r"""Shared helpers for headless Blender proofs of external tools.

Run scripts with:  tools/external/blender.sh <script.py> [-- args]
(the wrapper sets BLENDER_USER_SCRIPTS so add-ons installed in
C:\Users\Jonna\Tools\blender-addons are found, and uses --factory-startup).
"""
import bpy, addon_utils, math
from mathutils import Vector


def enable(*modules):
    """Enable add-ons headlessly. default_set=True is required for Rigify (it
    reads its own preferences entry inside register())."""
    for m in modules:
        addon_utils.enable(m, default_set=True, persistent=False)


def bone_lines(obj, names=None, color=(0.1, 0.1, 0.1, 1), radius=0.012, name="skel"):
    """Draw evaluated pose bones as thin tubes (Workbench renders no armatures)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 1
    for pb in ev.pose.bones:
        if names is not None and not names(pb.name):
            continue
        sp = cu.splines.new("POLY")
        sp.points.add(1)
        h = obj.matrix_world @ pb.head
        t = obj.matrix_world @ pb.tail
        sp.points[0].co = (*h, 1)
        sp.points[1].co = (*t, 1)
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new(name + "_m")
    mat.diffuse_color = color
    cu.materials.append(mat)
    return ob


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)


def setup_render(w=900, h=600, bg=(0.93, 0.9, 0.82)):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.film_transparent = False
    sc.world = sc.world or bpy.data.worlds.new("w")
    sc.world.color = bg
    sh = sc.display.shading
    sh.light = "FLAT"
    sh.color_type = "MATERIAL"
    sh.background_type = "WORLD"
    return sc


def camera(loc, target=(0, 0, 0.8), ortho=None, lens=50):
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.lens = lens
    bpy.context.scene.camera = cam
    return cam


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)
