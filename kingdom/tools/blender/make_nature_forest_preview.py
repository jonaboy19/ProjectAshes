"""Renders the composite "forest edge" preview from the exported nature GLBs (tests the real
files: relative texture URIs, COLOR_0, alpha MASK).

Run from the repo root after make_nature.py:
    python3 kingdom/tools/blender/make_nature_forest_preview.py [out.png]
Default out: docs/kingdom/blender_previews/nature/forest_edge.png (Cycles CPU, 800x600).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
import ra_nature as rn

OUT = next((a for a in sys.argv[1:] if a.endswith(".png")),
           os.path.join(rn.PREVIEWS, "forest_edge.png"))
WIND_ASSETS = ("grass_clump", "grass_clump_tall", "flowers_a")


def load(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(rn.NATURE, name + ".glb"))
    obs = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    ob = obs[0]
    ob.name = "SRC_" + name
    ob.location = (0, 0, -1000)         # hide the source far below
    if name in WIND_ASSETS:             # COLOR_0 is wind data, not albedo: bypass it
        for m in ob.data.materials:
            nt = m.node_tree
            img = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
            bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            for l in list(nt.links):
                if l.from_node.type == "VERTEX_COLOR":
                    sock = l.to_socket
                    nt.links.remove(l)
                    try:
                        sock.default_value = 1.0
                    except (TypeError, ValueError):
                        sock.default_value = (1.0,) * len(sock.default_value)
            nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    return ob


def inst(src, loc, rot_z=None, scale=1.0, rng=random):
    o = bpy.data.objects.new(src.name[4:] + "_i", src.data)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (0, 0, rng.uniform(0, 6.283) if rot_z is None else rot_z)
    o.scale = (scale, scale, scale)
    return o


def main():
    rn.reset_scene()
    rng = random.Random(42)
    names = ["oak_a", "oak_b", "birch_a", "pine_a", "pine_b", "sapling", "dead_tree", "bush_a", "bush_b",
             "grass_clump", "grass_clump_tall", "flowers_a"]
    src = {n: load(n) for n in names}
    # after import the scene is Z-up again (glTF importer converts back)
    rn.ground_plane(400, color=(0.20, 0.27, 0.11))

    # --- tree line: the forest edge runs along +Y ~ 22 m ahead, deeper rows behind
    rows = [
        # (y, x-range, spacing, species weights)
        (22, (-40, 40), 7.5, {"oak_a": 3, "oak_b": 2, "birch_a": 2, "pine_a": 1, "pine_b": 1, "dead_tree": 0.4}),
        (32, (-45, 45), 7.0, {"pine_a": 2, "pine_b": 2, "oak_a": 2, "oak_b": 1, "birch_a": 1}),
        (44, (-60, 60), 6.5, {"pine_b": 3, "pine_a": 2, "oak_a": 1}),
        (56, (-75, 75), 6.0, {"pine_b": 3, "pine_a": 2, "oak_b": 1}),
        (70, (-90, 90), 6.0, {"pine_b": 2, "pine_a": 2, "oak_a": 1}),
    ]
    for y, (x0, x1), sp, w in rows:
        x = x0
        keys, weights = list(w), list(w.values())
        while x < x1:
            n = rng.choices(keys, weights)[0]
            inst(src[n], (x + rng.uniform(-2, 2), y + rng.uniform(-3, 3), 0), scale=rng.uniform(0.85, 1.15), rng=rng)
            x += sp * rng.uniform(0.7, 1.2)
    # hero trees near the camera side of the edge
    inst(src["oak_a"], (-7.5, 15.5, 0), rot_z=0.4)
    inst(src["birch_a"], (5.5, 13.5, 0), rot_z=1.2)
    inst(src["birch_a"], (8.0, 16.0, 0), rot_z=2.9, scale=0.9)
    inst(src["dead_tree"], (15, 17, 0), rot_z=0.7)
    inst(src["pine_a"], (-17, 19, 0), rot_z=2.0)
    # understorey along the edge
    for i in range(26):
        x = rng.uniform(-30, 30)
        y = rng.uniform(12.5, 19)
        n = rng.choice(["bush_a", "bush_b", "bush_a", "sapling"])
        inst(src[n], (x, y, 0), scale=rng.uniform(0.8, 1.25), rng=rng)
    # meadow: grass and flowers, denser near the edge
    for i in range(2200):
        y = rng.uniform(-8, 20)
        k = (y + 8) / 28
        x = rng.uniform(-24, 24) * (0.3 + 0.7 * k)
        if rng.random() < 0.3 + 0.5 * k:
            n = "grass_clump_tall" if rng.random() < 0.15 + 0.45 * k else "grass_clump"
            inst(src[n], (x, y, 0), scale=rng.uniform(0.8, 1.3), rng=rng)
    for i in range(110):
        y = rng.uniform(-6, 14)
        x = rng.uniform(-14, 14) * (0.3 + 0.7 * (y + 8) / 28)
        inst(src["flowers_a"], (x, y, 0), scale=rng.uniform(0.9, 1.3), rng=rng)

    sc = bpy.context.scene
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 30
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    cam.location = (0.0, -12.0, 1.7)
    rn.look_at(cam, (0.0, 20.0, 5.5))
    cam_data.clip_end = 500
    sc.camera = cam
    rn.setup_world(sun_rot=(52, 0, -40), sun_energy=3.4)
    rn.preview_translucency()
    rn.render_setup(OUT, samples=64)
    bpy.ops.render.render(write_still=True)
    print("preview", OUT)


if __name__ == "__main__":
    main()
