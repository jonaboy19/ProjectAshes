"""Blender Mantaflow -> flipbook baker for fire burst, smoke puff and dust/earth burst.

Run (Blender 5.2, no GUI):
  blender -b --python tools/vfx/bake_gas_sims.py -- <fire_burst|smoke_puff|dust_burst> <out_dir> [cache_dir]

Pipeline: build a Mantaflow gas domain + flow emitter, bake (data + noise), render N sampled
sim frames with Cycles (volume shader, transparent film, 2x supersampled), downsample, soft cel
banding, sRGB, straight alpha, then write one atlas PNG (<= 1024 px). All numbers live in CFG.
"""
import sys, os, math
import bpy, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flipbook_common as fc

CFG = {
    # cols x rows atlas, frame px, sim frames sampled (start, step), emitter setup, look
    "fire_burst": dict(cols=4, rows=4, fs=256, start=6, step=1.5, end=48, res=128, kind="fire", inflow_frames=9, ortho=3.4, cam_z=-0.3,
                       emit_scale=(1, 1, 1), emit_z=-1.0, emit_r=0.55, vel=2.6, elev=0, toon=0.55, bands=5),
    "smoke_puff": dict(cols=8, rows=8, fs=128, start=2, step=1.6, end=110, res=96, kind="smoke",
                       emit_scale=(1, 1, 0.9), emit_z=-1.15, emit_r=0.5, vel=1.8, elev=0, toon=0.6, bands=4),
    "dust_burst": dict(cols=8, rows=8, fs=128, start=1, step=1.1, end=80, res=96, kind="dust",
                       emit_scale=(1.0, 1.0, 0.28), emit_z=-1.75, emit_r=0.95, vel=3.4, elev=16, toon=0.55, bands=4),
}
SS = 2  # supersample


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup_cycles(scene, px):
    scene.render.engine = "CYCLES"
    cy = scene.cycles
    cy.samples = 40
    cy.use_denoising = False
    cy.volume_bounces = 2
    cy.volume_step_rate = 0.6
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for t in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = t
                prefs.get_devices()
                if any(d.type == t for d in prefs.devices):
                    for d in prefs.devices:
                        d.use = d.type == t
                    cy.device = "GPU"
                    print("CYCLES device", t)
                    break
            except Exception:
                continue
    except Exception as e:
        print("cpu fallback", e)
    scene.render.resolution_x = scene.render.resolution_y = px
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"


def world(scene, sky, strength):
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*sky, 1)
    bg.inputs[1].default_value = strength
    scene.world = w


def light(kind, color, energy, loc, rot, size=3.0):
    ld = bpy.data.lights.new(kind, kind)
    ld.color = color
    ld.energy = energy
    if kind == "SUN":
        ld.angle = math.radians(12)
    if kind == "AREA":
        ld.size = size
    o = bpy.data.objects.new(kind, ld)
    o.location = loc
    o.rotation_euler = [math.radians(a) for a in rot]
    bpy.context.scene.collection.objects.link(o)


def volume_material(kind):
    m = bpy.data.materials.new("vol_" + kind)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    nt.links.new(pv.outputs["Volume"], out.inputs["Volume"])
    dens = nt.nodes.new("ShaderNodeAttribute"); dens.attribute_name = "density"
    dmul = nt.nodes.new("ShaderNodeMath"); dmul.operation = "MULTIPLY"
    nt.links.new(dens.outputs["Fac"], dmul.inputs[0])
    nt.links.new(dmul.outputs[0], pv.inputs["Density"])
    if kind == "fire":
        dmul.inputs[1].default_value = 9.0
        pv.inputs["Color"].default_value = (0, 0, 0, 1)        # soot only absorbs; colour comes from the emission + gradient map
        fl = nt.nodes.new("ShaderNodeAttribute"); fl.attribute_name = "flame"
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "LINEAR"
        el = ramp.color_ramp.elements
        el[0].position = 0.0; el[0].color = (1, 1, 1, 1)   # white emission; the colour comes from fire_gradient_map() below
        el[1].position = 1.0; el[1].color = (1, 1, 1, 1)
        gain = nt.nodes.new("ShaderNodeMath"); gain.operation = "MULTIPLY"; gain.inputs[1].default_value = 2.2
        nt.links.new(fl.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(fl.outputs["Fac"], gain.inputs[0])
        nt.links.new(ramp.outputs["Color"], pv.inputs["Emission Color"])
        nt.links.new(gain.outputs[0], pv.inputs["Emission Strength"])
    elif kind == "smoke":
        dmul.inputs[1].default_value = 7.0
        pv.inputs["Color"].default_value = (0.95, 0.90, 0.84, 1)
        pv.inputs["Anisotropy"].default_value = 0.2
    else:  # dust
        dmul.inputs[1].default_value = 6.0
        pv.inputs["Color"].default_value = (0.88, 0.68, 0.44, 1)
        pv.inputs["Anisotropy"].default_value = 0.25
    return m


def build_sim(cfg, cache):
    """Domain + emitter only (this is what gets baked and saved)."""
    clear()
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, cfg["end"]
    kind = cfg["kind"]
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    dom = bpy.context.object
    dom.name = "Domain"
    dom.scale = (4, 4, 4)
    bpy.ops.object.modifier_add(type="FLUID")
    dm = dom.modifiers["Fluid"]
    dm.fluid_type = "DOMAIN"
    d = dm.domain_settings
    d.domain_type = "GAS"
    d.resolution_max = cfg["res"]
    d.use_noise = False   # Cycles in Blender 5.2 headless does not read the baked noise grids (renders empty)
    d.noise_scale = 2
    d.cache_directory = cache
    d.cache_type = "ALL"
    d.cache_frame_start, d.cache_frame_end = 1, cfg["end"]
    d.use_dissolve_smoke = True
    if kind == "fire":
        d.alpha = 0.8; d.beta = 1.6; d.vorticity = 0.55; d.burning_rate = 0.32; d.flame_ignition = 1.2
        d.flame_smoke = 1.0; d.flame_vorticity = 0.7; d.dissolve_speed = 40
    elif kind == "smoke":
        d.alpha = 0.6; d.beta = 0.05; d.vorticity = 0.35; d.dissolve_speed = 90
    else:
        d.alpha = 0.05; d.beta = 0.05; d.vorticity = 0.9; d.dissolve_speed = 70
        d.use_collision_border_bottom = True

    bpy.ops.mesh.primitive_uv_sphere_add(radius=cfg["emit_r"], location=(0, 0, cfg["emit_z"]), segments=32, ring_count=16)
    em = bpy.context.object
    em.name = "Emitter"
    em.scale = cfg["emit_scale"]
    em.hide_render = True
    bpy.ops.object.modifier_add(type="FLUID")
    fm = em.modifiers["Fluid"]
    fm.fluid_type = "FLOW"
    f = fm.flow_settings
    f.flow_type = "BOTH" if kind == "fire" else "SMOKE"
    f.flow_behavior = "GEOMETRY"
    f.flow_source = "MESH"
    f.use_initial_velocity = True
    f.velocity_normal = cfg["vel"]
    f.density = 1.0
    f.surface_distance = 1.2
    if kind == "fire":
        f.fuel_amount = 1.6
        f.flow_behavior = "INFLOW"          # feeds fuel for the first frames only (keyframed below), so the burst blooms then burns out
        f.use_inflow = True
        f.keyframe_insert("use_inflow", frame=1)
        f.use_inflow = False
        f.keyframe_insert("use_inflow", frame=cfg["inflow_frames"])
        f.temperature = 1.0
    # GEOMETRY emission only exists on the first frame; the sim does the rest.
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = dom
    dom.select_set(True)
    return scene, d


def look(scene, cfg):
    """Everything that only affects the picture: lights, world, camera, volume shader, render setup."""
    for o in list(bpy.data.objects):
        if o.type in ("LIGHT", "CAMERA"):
            bpy.data.objects.remove(o)
    dom = bpy.data.objects["Domain"]
    dom.data.materials.clear()
    dom.modifiers["Fluid"].domain_settings.use_noise = False
    kind = cfg["kind"]
    setup_cycles(scene, cfg["fs"] * SS)
    # storybook lighting: warm golden sun high from one side, cool blue-violet fill, sky ambient
    world(scene, (0.55, 0.68, 0.95), 0.9 if kind != "fire" else 0.5)
    light("SUN", (1.0, 0.83, 0.58), 5.0, (0, 0, 5), (50, 0, 35))
    light("AREA", (0.55, 0.5, 1.0), 900, (-4, -3, -1), (70, 0, -55), 5.0)
    dom.data.materials.append(volume_material(kind))
    # ortho camera looking along +Y (x = right, z = up); the dust burst tilts down a little
    cam = bpy.data.cameras.new("Cam")
    cam.type = "ORTHO"
    cam.ortho_scale = cfg.get("ortho", 4.0)
    co = bpy.data.objects.new("Cam", cam)
    e = math.radians(cfg["elev"])
    zc = cfg.get("cam_z", 0.0)
    co.location = (0, -10 * math.cos(e), zc + 10 * math.sin(e))
    co.rotation_euler = (math.radians(90) - e, 0, 0)
    scene.collection.objects.link(co)
    scene.camera = co




def blur3(a):
    """cheap 3x3 binomial blur (kills volume-sampling grain before the cel bands)."""
    k = np.array([1, 2, 1], np.float32) / 4
    a = a[:, 1:-1] * k[1] + a[:, :-2] * k[0] + a[:, 2:] * k[2] if False else a
    for ax in (0, 1):
        a = k[0] * np.roll(a, 1, ax) + k[1] * a + k[2] * np.roll(a, -1, ax)
    return a


def fire_gradient_map(px):
    """Rendered white emission (premult) -> painted fire: heat drives a warm ramp, soot drives alpha."""
    px = blur3(blur3(px))
    a = px[..., 3]
    heat = np.where(a > 1e-4, px[..., :3].mean(-1) / np.maximum(a, 1e-4), 0.0)
    heat = np.clip(heat / 1.75, 0, 1.3)
    stops = [0.0, 0.10, 0.28, 0.5, 0.8, 1.2]
    cols = np.array([(0.30, 0.09, 0.07), (0.62, 0.11, 0.05), (0.98, 0.34, 0.06), (1.0, 0.62, 0.14), (1.0, 0.86, 0.38), (1.0, 0.97, 0.78)], np.float32)
    lc = fc_lin(cols)
    rgb = np.stack([np.interp(heat, stops, lc[:, i]) for i in range(3)], -1)
    alpha = np.clip((a - 0.02) / 0.30, 0, 1)
    alpha = alpha * alpha * (3 - 2 * alpha)
    return np.concatenate([rgb * alpha[..., None], alpha[..., None]], -1).astype(np.float32)


def fc_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    name, out_dir = argv[0], argv[1]
    cache = argv[2] if len(argv) > 2 else os.path.join(os.environ.get("TEMP", "."), "ashes_vfx_cache")
    cache = os.path.join(cache, name)
    os.makedirs(cache, exist_ok=True)
    cfg = CFG[name]
    blend = os.path.join(cache, "sim.blend")
    if os.path.exists(blend) and "--rebake" not in argv:
        # Baked cache is only picked up when the .blend that owns it is opened (a fresh session
        # with a rebuilt domain does not read it), so the sim is stored as sim.blend next to it.
        print("BAKE cached, reusing", blend)
        bpy.ops.wm.open_mainfile(filepath=blend)
        scene = bpy.context.scene
    else:
        scene, d = build_sim(cfg, cache)
        print("BAKE start")
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        bpy.ops.fluid.bake_data()

        bpy.ops.wm.save_as_mainfile(filepath=blend)
        print("BAKE done")
    look(scene, cfg)
    n = cfg["cols"] * cfg["rows"]
    frames = []
    tmp = os.path.join(cache, "render.exr")
    scene.render.image_settings.file_format = "OPEN_EXR"
    scene.render.image_settings.color_depth = "32"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = tmp
    for i in range(n):
        fr = min(int(round(cfg["start"] + i * cfg["step"])), cfg["end"])
        scene.frame_set(fr)
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp, check_existing=False)
        px = np.empty(len(img.pixels), np.float32)
        img.pixels.foreach_get(px)
        sz = tuple(img.size)
        bpy.data.images.remove(img)
        px = px.reshape(sz[1], sz[0], 4)[::-1]      # Blender rows are bottom-up
        px = fc.box_down(px, SS)
        if cfg["kind"] == "fire":
            px = fire_gradient_map(px)
        fill = {"fire": (1.0, 0.45, 0.1), "smoke": (0.8, 0.75, 0.72), "dust": (0.8, 0.6, 0.4)}[cfg["kind"]]
        frames.append(fc.finish_frame(px, fill, 0.0 if cfg["kind"] == "fire" else cfg["toon"], cfg["bands"]))
        print("frame", i, "sim", fr, "alpha mean %.3f" % (frames[-1][..., 3].mean() / 255))
    path = os.path.join(out_dir, name + ".png")
    fc.write_atlas(path, frames, cfg["cols"], cfg["rows"])
    fc.report(path, frames, cfg["cols"], cfg["rows"])


if __name__ == "__main__":
    main()
