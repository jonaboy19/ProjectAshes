import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_lib import *
f, out = [os.path.abspath(x) for x in sys.argv[-2:]]
bpy.ops.wm.open_mainfile(filepath=f)
sc, cam = setup_scene((560, 460), engine='BLENDER_EEVEE')
ms = [o for o in sc.objects if o.type == 'MESH' and o.name not in ('ground',)]
mn, mx = bbox(ms); ctr = (mn + mx) / 2; rad = (mx - mn).length / 2
tiles = []
for i, ang in enumerate([-35, 55, 145, 235]):
    aim(cam, ctr, ang, rad * 2.5, 10)
    p = f"{out}_{i}.png"; sc.render.filepath = p; bpy.ops.render.render(write_still=True); tiles.append(p)
imgs = [bpy.data.images.load(p) for p in tiles]
W, H = imgs[0].size; big = bpy.data.images.new("strip", W * 4, H)
buf = [0.0] * (W * 4 * H * 4)
for k, im in enumerate(imgs):
    px = list(im.pixels)
    for y in range(H):
        s = y * W * 4; d = (y * W * 4 + k * W) * 4
        buf[d:d + W * 4] = px[s:s + W * 4]
big.pixels = buf; big.filepath_raw = out + "_strip.png"; big.file_format = 'PNG'; big.save()
for p in tiles: os.remove(p)
