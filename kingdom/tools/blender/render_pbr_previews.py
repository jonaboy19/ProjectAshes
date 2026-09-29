"""Close-up previews of the baked PBR assets, rendered in Blender (Cycles CPU) from the EXPORTED glb files, so
the previews prove what the game gets (glTF normal / occlusion+metallicRoughness / COLOR_0 as the importer
sees them).

Run:  python3 render_pbr_previews.py [--before <dir with the old glbs>] [name ...]   (default: every asset below)
Output: docs/kingdom/blender_previews/pbr_<name>_close<N>.png (960x640)
Camera specs are (target xyz, direction from target, distance, lens) in Blender coordinates (front = -Y).
"""
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
import pbr_kit as P

GEN = os.path.join(P.ROOT, "kingdom", "assets", "generated")
OUT = os.path.join(P.ROOT, "docs", "kingdom", "blender_previews")

SPECS = {
    "townhouse_a": [((-1.2, -4.0, 1.7), (0.35, -1, 0.10), 5.0, 40),        # stone shopfront, shutters, arch
                    ((0.0, -4.4, 6.3), (0.25, -1, 0.05), 6.5, 40),         # timber frame + plaster, jetty joists
                    ((0.5, -1.0, 11.2), (0.15, -1, -0.30), 7.0, 40)],      # slate roof from the street
    "townhouse_b": [((-1.2, -4.0, 1.7), (0.35, -1, 0.10), 5.0, 40), ((0.0, -4.4, 6.3), (0.25, -1, 0.05), 6.5, 40)],
    "townhouse_c": [((-1.2, -4.0, 1.7), (0.35, -1, 0.10), 5.0, 40), ((0.0, -4.4, 6.3), (0.25, -1, 0.05), 6.5, 40)],
    "townhouse_d": [((-1.2, -4.0, 1.7), (0.35, -1, 0.10), 5.0, 40), ((0.0, -4.4, 6.3), (0.25, -1, 0.05), 6.5, 40)],
    "market_stall_red": [((0.0, -0.2, 1.4), (0.3, -1, 0.2), 4.2, 40), ((0.0, -0.9, 0.9), (0.5, -1, 0.3), 2.4, 40)],
    "market_stall_green": [((0.0, -0.2, 1.4), (0.3, -1, 0.2), 4.2, 40)],
    "town_gate": [((0.0, -4.0, 6.5), (0.4, -1, 0.15), 22.0, 40), ((-3.0, -4.5, 3.0), (0.6, -1, 0.12), 8.0, 40)],
    "town_wall": [((0.0, -1.7, 3.0), (0.5, -1, 0.15), 6.0, 40), ((1.5, -1.7, 6.6), (0.5, -1, 0.35), 3.5, 40)],
    "town_wall_tower": [((0.0, -3.0, 5.0), (0.6, -1, 0.2), 9.0, 40), ((0.0, -1.0, 11.0), (0.6, -1, 0.2), 6.5, 40)],
    "street_lamp": [((0.0, -0.3, 2.5), (0.6, -1, 0.1), 3.4, 40), ((0.0, 0.0, 0.4), (0.7, -1, 0.3), 1.5, 40)],
    "banner_pole": [((0.0, 0.0, 2.6), (0.4, -1, 0.05), 3.6, 40)],
}


def render(name, before_dir=None):
    """before_dir: a folder with the OLD glb of the asset (textures resolvable relative to it) -> *_before_close*."""
    glb = os.path.join(before_dir or GEN, name + ".glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    # the glTF importer converts to Y-up -> Blender Z-up again; front (Godot +Z) ends up at Blender -Y
    for i, (t, d, dist, lens) in enumerate(SPECS[name], 1):
        png = os.path.join(OUT, f"pbr_{name}_{'before_' if before_dir else ''}close{i}.png")
        P.render_closeup(png, t, d, dist, lens=lens, samples=96)
        print("wrote", png)


if __name__ == "__main__":
    args = sys.argv[1:]
    before = None
    if "--before" in args:
        i = args.index("--before")
        before = args[i + 1]
        del args[i:i + 2]
    names = args or list(SPECS)
    for n in names:
        render(n, before)
