"""Shared helpers for Region 1 art (stones, Highwatch keep): storybook lighting, glb import, grid sheets.
Run inside Blender 5.x (-b --python ...). Not imported by the game."""
import bpy, math, mathutils, os, sys

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene

def engine(sc):
    eng = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    for n in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
        if n in eng:
            sc.render.engine = n; return n

def storybook_world(sc, sky_top=(0.33, 0.58, 0.95), sky_hor=(0.85, 0.92, 1.0), strength=1.1):
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    nt = w.node_tree; nt.nodes.clear()
    tc = nt.nodes.new('ShaderNodeTexCoord'); sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    ramp = nt.nodes.new('ShaderNodeValToRGB'); bg = nt.nodes.new('ShaderNodeBackground'); out = nt.nodes.new('ShaderNodeOutputWorld')
    nt.links.new(tc.outputs['Generated'], sep.inputs[0]); nt.links.new(sep.outputs['Z'], ramp.inputs[0])
    ramp.color_ramp.elements[0].position = 0.45; ramp.color_ramp.elements[0].color = (*sky_hor, 1)
    ramp.color_ramp.elements[1].position = 0.85; ramp.color_ramp.elements[1].color = (*sky_top, 1)
    nt.links.new(ramp.outputs[0], bg.inputs[0]); bg.inputs[1].default_value = strength
    nt.links.new(bg.outputs[0], out.inputs[0])

def sun(sc, energy=4.5, rot=(52, 0, 35), color=(1.0, 0.9, 0.72)):
    d = bpy.data.lights.new("sun", 'SUN'); d.energy = energy; d.color = color; d.angle = math.radians(4)
    o = bpy.data.objects.new("sun", d); o.rotation_euler = [math.radians(a) for a in rot]; sc.collection.objects.link(o); return o

def color_mgmt(sc):
    try:
        sc.view_settings.view_transform = 'AgX'
    except Exception:
        sc.view_settings.view_transform = 'Standard'
    try:
        sc.view_settings.look = 'AgX - Punchy'
    except Exception:
        pass

def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    return new

def meshes(objs):
    return [o for o in objs if o.type == 'MESH']

def tri_count(objs):
    n = 0
    for o in meshes(objs):
        me = o.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh() if False else o.data
        me.calc_loop_triangles(); n += len(me.loop_triangles)
    return n

def bbox(objs):
    pts = [o.matrix_world @ mathutils.Vector(c) for o in meshes(objs) for c in o.bound_box]
    mn = mathutils.Vector([min(p[i] for p in pts) for i in range(3)])
    mx = mathutils.Vector([max(p[i] for p in pts) for i in range(3)])
    return mn, mx

def ground(sc, size=200, color=(0.42, 0.55, 0.2)):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    g = bpy.context.active_object
    m = bpy.data.materials.new("grass"); m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1
    g.data.materials.append(m); return g

def text(sc, s, loc, size=0.35, rot=(math.radians(90), 0, 0)):
    c = bpy.data.curves.new("t", 'FONT'); c.body = s; c.size = size; c.align_x = 'CENTER'
    o = bpy.data.objects.new("t", c); o.location = loc; o.rotation_euler = rot
    m = bpy.data.materials.new("tm"); m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.1, 0.07, 0.04, 1)
    o.data.materials.append(m); sc.collection.objects.link(o); return o

def camera(sc, loc, target, lens=50, ortho=None):
    cd = bpy.data.cameras.new("cam"); cd.lens = lens
    if ortho:
        cd.type = 'ORTHO'; cd.ortho_scale = ortho
    co = bpy.data.objects.new("cam", cd); sc.collection.objects.link(co); sc.camera = co
    co.location = loc
    co.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return co

def render(sc, path, w, h, samples=32):
    sc.render.resolution_x = w; sc.render.resolution_y = h; sc.render.filepath = path
    try: sc.eevee.taa_render_samples = samples
    except Exception: pass
    bpy.ops.render.render(write_still=True)

def args():
    return sys.argv[sys.argv.index("--") + 1:]
