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


def _bbox():
    """world bbox (Blender coords) of every mesh in the scene, before the preview ground is added."""
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ P.Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def auto_specs(lo, hi, overall=False):
    """generic camera set for assets without hand-made SPECS: overall 3/4 view, lower front, upper/roof."""
    w, d, h = hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    if overall:
        r = max(w, d, h * 0.9)
        return [((cx, cy, h * 0.42), (1.0, -1.45, 0.62), r * 1.9, 40)]
    out = [((cx - w * 0.12, lo[1], min(1.6, 0.3 * h)), (0.35, -1, 0.12), max(2.2, min(9.0, 0.75 * min(w, 9))), 40)]
    if h > 3.0:
        out.append(((cx, cy - d * 0.2, h * 0.72), (0.2, -1, -0.28), max(3.5, min(13.0, 0.9 * min(w, 12))), 40))
    if h > 12:
        out.append(((cx, lo[1], h * 0.45), (0.5, -1, 0.15), min(30.0, 0.9 * h), 40))
    return out


OPTS = []


def render(name, before_dir=None):
    """before_dir: a folder with the OLD glb of the asset (textures resolvable relative to it) -> *_before_close*.
    Options: --overall also writes pbr_<name>.png (3/4 view); --only-overall skips the close-ups."""
    glb = os.path.join(before_dir or GEN, name + ".glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    # the glTF importer converts to Y-up -> Blender Z-up again; front (Godot +Z) ends up at Blender -Y
    lo, hi = _bbox()
    specs = [] if "--only-overall" in OPTS else (SPECS.get(name) or auto_specs(lo, hi))
    tag = "before_" if before_dir else ""
    for i, (t, d, dist, lens) in enumerate(specs, 1):
        png = os.path.join(OUT, f"pbr_{name}_{tag}close{i}.png")
        P.render_closeup(png, t, d, dist, lens=lens, samples=int(os.environ.get("RA_PBR_SAMPLES", "96")))
        print("wrote", png)
    if "--overall" in OPTS or "--only-overall" in OPTS:
        (t, d, dist, lens), = auto_specs(lo, hi, overall=True)
        png = os.path.join(OUT, f"pbr_{name}{'_before' if before_dir else ''}.png")
        P.render_closeup(png, t, d, dist, lens=lens, samples=int(os.environ.get("RA_PBR_SAMPLES", "96")), res=(800, 600))
        print("wrote", png)


if __name__ == "__main__":
    args = sys.argv[1:]
    OPTS = [a for a in args if a.startswith("--") and a != "--before"]
    args = [a for a in args if a not in OPTS]
    before = None
    if "--before" in args:
        i = args.index("--before")
        before = args[i + 1]
        del args[i:i + 2]
    names = args or list(SPECS)
    for n in names:
        render(n, before)
