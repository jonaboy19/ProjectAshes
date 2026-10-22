r"""Generate an eroded terrain heightfield headlessly with A.N.T.Landscape + its Eroder.
Run: tools/external/blender.sh tools/external/ant_terrain.py -- <out_dir> [seed] [grid]
Outputs: <out>/ant_before.png, ant_after.png (angled renders), ant_after_r16.raw
(uint16 LE, grid x grid, Terrain3D 'r16' import), ant_after.glb (mesh).
"""
import sys, os, bpy, numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import bl_common as C
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["."]
out = args[0]
seed = int(args[1]) if len(args) > 1 else 3
grid = int(args[2]) if len(args) > 2 else 129
os.makedirs(out, exist_ok=True)
C.clear_scene()
C.enable("bl_ext.user_default.antlandscape")
bpy.ops.mesh.landscape_add(
    ant_terrain_name="Valley", subdivision_x=grid, subdivision_y=grid, mesh_size_x=40.0, mesh_size_y=40.0,
    random_seed=seed, noise_type="hybrid_multi_fractal", noise_size=14.0, noise_depth=8,
    height=6.0, maximum=9.0, minimum=-2.0, smooth_mesh=True, at_cursor=True,
    edge_falloff="0", refresh=True)
ob = bpy.context.active_object
print("LANDSCAPE verts", len(ob.data.vertices), "dims", tuple(round(x,2) for x in ob.dimensions), "loc", tuple(ob.location))


def heights():
    return np.array([v.co.z for v in ob.data.vertices], dtype=np.float64)

h0 = heights()
sc = C.setup_render(w=800, h=520, bg=(0.85, 0.87, 0.9))
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "SINGLE"
sc.display.shading.single_color = (0.62, 0.6, 0.5)
C.camera((38, -46, 30), target=(0, 0, 0), lens=45)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
bpy.context.scene.collection.objects.link(sun)
C.render(os.path.join(out, "ant_before.png"))
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.mesh.eroder(Iterations=2)
h1 = heights()
print("ERODER dims after", tuple(round(x,2) for x in ob.dimensions)); print("ERODER max_abs_height_change", float(np.abs(h1 - h0).max()), "mean", float(np.abs(h1 - h0).mean()))
assert np.abs(h1 - h0).max() > 0.05
C.render(os.path.join(out, "ant_after.png"))
# 16-bit heightmap from the vertex grid (rows sorted by y then x)
co = np.array([tuple(v.co) for v in ob.data.vertices])
order = np.lexsort((co[:, 0], co[:, 1]))
z = co[order, 2].reshape(grid, grid)
z = (z - z.min()) / max(z.max() - z.min(), 1e-9)
(z * 65535).astype("<u2").tofile(os.path.join(out, "ant_after_r16.raw"))
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "ant_after.glb"), export_format="GLB")
print("OK", grid, "grid; glb bytes", os.path.getsize(os.path.join(out, "ant_after.glb")))
