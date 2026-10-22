"""Blender Mantaflow FLIP liquid -> water splash flipbook (4x4 frames of 256 px = 1024 atlas).

Run:  blender -b --python tools/vfx/bake_water_splash.py -- <out_dir> [cache_dir] [--rebake]

A sphere of water is dropped into a pool; the liquid mesh is rendered with Cycles side-on (ortho,
slightly from above) using a toon water shader (aqua body, pale foam at grazing angles / on the tips).
Everything at or below the pool surface is masked transparent in the shader, so the sheet holds
only the crown, droplets and ripple band. Reuses the look/render helpers of bake_gas_sims.py.
"""
import sys, os, math
import bpy, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flipbook_common as fc
import bake_gas_sims as G

COLS = ROWS = 4
FS = 256
SS = 2
END = 56
START, STEP = 4, 2.9
POOL_Z = -1.2       # pool surface height in the domain
ELEV = 14           # camera elevation, degrees


def build(cache):
    G.clear()
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, END
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    dom = bpy.context.object
    dom.name = "Domain"
    dom.scale = (4, 4, 4)
    bpy.ops.object.modifier_add(type="FLUID")
    dm = dom.modifiers["Fluid"]
    dm.fluid_type = "DOMAIN"
    d = dm.domain_settings
    d.domain_type = "LIQUID"
    d.resolution_max = 112
    d.cache_directory = cache
    d.cache_type = "ALL"
    d.cache_frame_start, d.cache_frame_end = 1, END
    d.use_mesh = True
    d.mesh_scale = 2
    d.particle_radius = 1.0
    d.use_fractions = True
    d.viscosity_base = 1.0
    d.viscosity_exponent = 6          # ~ water
    d.use_spray_particles = False
    d.use_foam_particles = False

    # pool: fills the domain floor up to POOL_Z
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, (POOL_Z - 2.0) / 2))
    pool = bpy.context.object
    pool.name = "Pool"
    pool.scale = (3.9, 3.9, POOL_Z + 2.0)
    pool.hide_render = True
    bpy.ops.object.modifier_add(type="FLUID")
    pm = pool.modifiers["Fluid"]
    pm.fluid_type = "FLOW"
    pm.flow_settings.flow_type = "LIQUID"
    pm.flow_settings.flow_behavior = "GEOMETRY"
    pm.flow_settings.flow_source = "MESH"
    pm.flow_settings.use_initial_velocity = False

    # falling blob, big enough to throw a proper crown
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.42, location=(0, 0, POOL_Z + 0.55), segments=32, ring_count=16)
    drop = bpy.context.object
    drop.name = "Drop"
    drop.hide_render = True
    bpy.ops.object.modifier_add(type="FLUID")
    dfm = drop.modifiers["Fluid"]
    dfm.fluid_type = "FLOW"
    df = dfm.flow_settings
    df.flow_type = "LIQUID"
    df.flow_behavior = "GEOMETRY"
    df.flow_source = "MESH"
    df.use_initial_velocity = True
    df.velocity_coord = (0, 0, -5.5)
    df.surface_distance = 1.0
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = dom
    dom.select_set(True)
    return scene, d


def water_material():
    m = bpy.data.materials.new("toon_water")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mix_mask = nt.nodes.new("ShaderNodeMixShader")
    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    gt = nt.nodes.new("ShaderNodeMath"); gt.operation = "LESS_THAN"; gt.inputs[1].default_value = POOL_Z + 0.11
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], gt.inputs[0])

    rlen = nt.nodes.new("ShaderNodeCombineXYZ")
    vl = nt.nodes.new("ShaderNodeVectorMath"); vl.operation = "LENGTH"
    rgt = nt.nodes.new("ShaderNodeMath"); rgt.operation = "GREATER_THAN"; rgt.inputs[1].default_value = 1.0
    both = nt.nodes.new("ShaderNodeMath"); both.operation = "MAXIMUM"
    nt.links.new(sep.outputs["X"], rlen.inputs["X"]); nt.links.new(sep.outputs["Y"], rlen.inputs["Y"])
    nt.links.new(rlen.outputs["Vector"], vl.inputs[0]); nt.links.new(vl.outputs["Value"], rgt.inputs[0])
    nt.links.new(gt.outputs[0], both.inputs[0]); nt.links.new(rgt.outputs[0], both.inputs[1])
    # body: emission ramp keyed on facing (toon) + a little diffuse for form
    lw = nt.nodes.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.35
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    el = ramp.color_ramp.elements
    el[0].position = 0.0;  el[0].color = (0.05, 0.36, 0.72, 1)     # deep blue-teal
    el[1].position = 0.30; el[1].color = (0.12, 0.62, 0.90, 1)     # aqua
    e2 = el.new(0.62);     e2.color = (0.55, 0.88, 0.98, 1)        # light
    e3 = el.new(0.86);     e3.color = (0.97, 1.0, 1.0, 1)          # foam white on the rim
    nt.links.new(lw.outputs["Facing"], ramp.inputs["Fac"])
    inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
    nt.links.new(lw.outputs["Facing"], inv.inputs[1])
    nt.links.new(inv.outputs[0], ramp.inputs["Fac"])                 # grazing = high value = foam
    emit = nt.nodes.new("ShaderNodeEmission"); emit.inputs["Strength"].default_value = 1.0
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse"); diff.inputs["Color"].default_value = (0.2, 0.55, 0.85, 1)
    body = nt.nodes.new("ShaderNodeMixShader"); body.inputs[0].default_value = 1.0   # pure emission: diffuse gave black patches on back faces
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    nt.links.new(diff.outputs["BSDF"], body.inputs[1])
    nt.links.new(emit.outputs["Emission"], body.inputs[2])
    nt.links.new(both.outputs[0], mix_mask.inputs[0])
    nt.links.new(body.outputs["Shader"], mix_mask.inputs[1])
    nt.links.new(transp.outputs["BSDF"], mix_mask.inputs[2])
    nt.links.new(mix_mask.outputs["Shader"], out.inputs["Surface"])
    return m


def look(scene):
    for o in list(bpy.data.objects):
        if o.type in ("LIGHT", "CAMERA"):
            bpy.data.objects.remove(o)
    G.setup_cycles(scene, FS * SS)
    scene.cycles.samples = 24
    scene.cycles.transparent_max_bounces = 64   # masked pool layers otherwise terminate rays as black
    G.world(scene, (0.6, 0.72, 0.98), 1.0)
    G.light("SUN", (1.0, 0.85, 0.62), 4.0, (0, 0, 5), (50, 0, 35))
    G.light("AREA", (0.55, 0.5, 1.0), 500, (-4, -3, -1), (70, 0, -55), 5.0)
    dom = bpy.data.objects["Domain"]
    dom.data.materials.clear()
    dom.data.materials.append(water_material())
    dom.display_type = "WIRE"
    cam = bpy.data.cameras.new("Cam")
    cam.type = "ORTHO"
    cam.ortho_scale = 2.3
    co = bpy.data.objects.new("Cam", cam)
    e = math.radians(ELEV)
    target = np.array([0.0, 0.0, POOL_Z + 0.75])
    co.location = (target[0], target[1] - 10 * math.cos(e), target[2] + 10 * math.sin(e))
    co.rotation_euler = (math.radians(90) - e, 0, 0)
    scene.collection.objects.link(co)
    scene.camera = co


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out_dir = argv[0]
    base = argv[1] if len(argv) > 1 and not argv[1].startswith("--") else os.path.join(os.environ.get("TEMP", "."), "ashes_vfx_cache")
    cache = os.path.join(base, "water_splash")
    os.makedirs(cache, exist_ok=True)
    blend = os.path.join(cache, "sim.blend")
    if os.path.exists(blend) and "--rebake" not in argv:
        bpy.ops.wm.open_mainfile(filepath=blend)
        scene = bpy.context.scene
    else:
        scene, d = build(cache)
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        bpy.ops.fluid.bake_data()
        bpy.ops.fluid.bake_mesh()
        bpy.ops.wm.save_as_mainfile(filepath=blend)
    look(scene)
    tmp = os.path.join(cache, "render.exr")
    scene.render.image_settings.file_format = "OPEN_EXR"
    scene.render.image_settings.color_depth = "32"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = tmp
    frames = []
    for i in range(COLS * ROWS):
        fr = min(int(round(START + i * STEP)), END)
        scene.frame_set(fr)
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp, check_existing=False)
        px = np.empty(len(img.pixels), np.float32)
        img.pixels.foreach_get(px)
        sz = tuple(img.size)
        bpy.data.images.remove(img)
        px = fc.box_down(px.reshape(sz[1], sz[0], 4)[::-1], SS)
        frames.append(fc.finish_frame(px, (0.5, 0.85, 0.98), 0.0, 4))
        print("frame", i, "sim", fr, "alpha mean %.3f" % (frames[-1][..., 3].mean() / 255))
    path = os.path.join(out_dir, "water_splash.png")
    fc.write_atlas(path, frames, COLS, ROWS)
    fc.report(path, frames, COLS, ROWS)


if __name__ == "__main__":
    main()
