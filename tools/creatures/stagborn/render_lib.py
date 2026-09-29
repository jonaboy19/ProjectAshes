"""Shared render helpers for the Stagborn models (Blender 5.2, run headless with -b).
Sun-lit storybook lighting: warm key, blue-violet fill, light-blue sky."""
import bpy, math, mathutils, os

def setup_scene(res=(640, 480), ground=True, engine=None):
    sc = bpy.context.scene
    ids = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    sc.render.engine = engine or "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = 'Standard'
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.62, 0.78, 0.95, 1); bg.inputs[1].default_value = 1.15
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    sun.data.energy = 3.4; sun.data.color = (1.0, 0.9, 0.72); sun.data.angle = math.radians(6)
    sun.rotation_euler = (math.radians(48), math.radians(8), math.radians(-38)); sc.collection.objects.link(sun)
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", 'SUN'))
    fill.data.energy = 0.9; fill.data.color = (0.55, 0.62, 1.0)
    fill.rotation_euler = (math.radians(60), 0, math.radians(140)); sc.collection.objects.link(fill)
    if ground:
        bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.002)); g = bpy.context.object; g.name = "ground"
        m = bpy.data.materials.new("gm"); m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]; b.inputs["Roughness"].default_value = 1
        ck = m.node_tree.nodes.new("ShaderNodeTexChecker"); ck.inputs["Color1"].default_value = (0.36, 0.55, 0.20, 1); ck.inputs["Color2"].default_value = (0.42, 0.62, 0.24, 1); ck.inputs["Scale"].default_value = 20
        m.node_tree.links.new(ck.outputs["Color"], b.inputs["Base Color"])
        g.data.materials.append(m)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.lens = 50
    return sc, cam

def aim(cam, target, yaw_deg, dist, elev_deg=12):
    a = math.radians(yaw_deg); e = math.radians(elev_deg)
    cam.location = target + mathutils.Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()

def bbox(meshes):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg); me = ev.to_mesh()
        pts += [ev.matrix_world @ v.co for v in me.vertices]; ev.to_mesh_clear()
    mn = mathutils.Vector([min(p[i] for p in pts) for i in range(3)]); mx = mathutils.Vector([max(p[i] for p in pts) for i in range(3)])
    return mn, mx

def workbench_style(sc):
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'STUDIO'; sh.color_type = 'TEXTURE'; sh.show_shadows = True; sh.shadow_intensity = 0.35
    sh.show_cavity = False; sh.studio_light = 'rim.sl' if False else sh.studio_light
    sc.display.render_aa = '8'
    sc.render.film_transparent = False
    sc.world.color = (0.62, 0.78, 0.95)
    sc.view_settings.view_transform = 'Standard'
    for o in bpy.data.objects:
        if o.name == 'ground':
            o.data.materials.clear()
            m = bpy.data.materials.new("gw"); m.diffuse_color = (0.40, 0.58, 0.22, 1); o.data.materials.append(m)
    # 1 m grid lines so foot sliding is visible
    lm = bpy.data.materials.new("gl"); lm.diffuse_color = (0.95, 0.92, 0.55, 1)
    for i in range(-10, 11):
        for (sx, sy, lx, ly) in ((0.05, 20, i, 0), (20, 0.05, 0, i)):
            bpy.ops.mesh.primitive_cube_add(size=1, location=(lx, ly, 0.001)); c = bpy.context.object
            c.scale = (sx, sy, 0.002); c.data.materials.append(lm)

def activate_albedo():
    for m in bpy.data.materials:
        if not m.use_nodes: continue
        cand = [n for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]
        pick = [n for n in cand if 'albedo' in n.image.name.lower() or 'basecolor' in n.image.name.lower()] or cand[:1]
        if pick:
            for n in m.node_tree.nodes: n.select = False
            pick[0].select = True; m.node_tree.nodes.active = pick[0]
