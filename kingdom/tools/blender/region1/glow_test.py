"""Glow readability test at 60 m, Godot-default 75 deg vertical FOV, 2400x1080.
blender -b --python glow_test.py -- <glb> <out.png> [dim=0.3] [bright=4.0]
Grid: top row noon (dim | bright), bottom row dusk (dim | bright). Each cell is a native-pixel crop.
A cheap bloom (threshold + gaussian) is applied in numpy to mimic Godot's glow."""
import bpy, math, os, sys
import numpy as np
from mathutils import Vector
sys.path.insert(0, os.path.dirname(__file__))
import r1lib as L
import paint as P
import stonekit as SK

a = L.args()
glb, out = a[0], a[1]
dim = float(a[2]) if len(a) > 2 else 0.3
bright = float(a[3]) if len(a) > 3 else 4.0
DIST = float(os.environ.get('GLOW_DIST', '60'))
cells = []
def readimg(path,h,w):
    img = bpy.data.images.load(path); img.colorspace_settings.name = 'Non-Color'
    px = np.array(img.pixels[:], np.float32).reshape(h, w, 4)[..., :3][::-1]
    bpy.data.images.remove(img)
    return px
for tod in ('noon', 'dusk'):
    for state, en in (('dim', dim), ('bright', bright)):
        sc = L.reset(); L.engine(sc); L.color_mgmt(sc)
        if tod == 'noon':
            L.storybook_world(sc, strength=1.1); L.sun(sc, 4.5, (52, 0, 35))
        else:
            L.storybook_world(sc, sky_top=(0.16, 0.16, 0.38), sky_hor=(0.95, 0.55, 0.35), strength=0.45)
            L.sun(sc, 2.2, (80, 0, 35), color=(1.0, 0.55, 0.28))
        L.ground(sc, 600, color=(0.36, 0.5, 0.18))
        objs = L.import_glb(glb)
        for m in bpy.data.materials:
            if m.use_nodes and m.name.endswith('_mat'):
                for n in m.node_tree.nodes:
                    if n.type == 'BSDF_PRINCIPLED':
                        n.inputs['Emission Strength'].default_value = en
        cam = bpy.data.cameras.new('c'); cam.sensor_fit = 'VERTICAL'; cam.angle = math.radians(75)
        co = bpy.data.objects.new('c', cam); sc.collection.objects.link(co); sc.camera = co
        co.location = (0, -DIST, 1.7)
        co.rotation_euler = (Vector((0, 0, 3.0)) - co.location).to_track_quat('-Z', 'Y').to_euler()
        sc.view_settings.exposure = -0.2
        path = out.replace('.png', f'_{tod}_{state}.png')
        L.render(sc, path, 2400, 1080, samples=16)
        px = readimg(path, 1080, 2400)
        # emission-only pass -> bloom source
        for m in bpy.data.materials:
            if m.use_nodes:
                for n in m.node_tree.nodes:
                    if n.type == 'BSDF_PRINCIPLED':
                        for l in list(n.inputs['Base Color'].links): m.node_tree.links.remove(l)
                        n.inputs['Base Color'].default_value = (0, 0, 0, 1)
                        n.inputs['Specular IOR Level'].default_value = 0
        sc.world.node_tree.nodes['Background'].inputs[1].default_value = 0
        for o in bpy.data.objects:
            if o.type == 'LIGHT': o.data.energy = 0
        for o in bpy.data.objects:
            if o.type == 'MESH' and o.name.startswith('Plane'): o.hide_render = True
        L.render(sc, path, 2400, 1080, samples=8)
        em = readimg(path, 1080, 2400)
        glow = P.blur(em, 4) * 1.4 + P.blur(em, 12) * 1.6 + P.blur(em, 30) * 1.2
        px2 = np.clip(px + glow, 0, 1)
        crop = px2[420:645, 950:1450]
        cells.append(np.kron(crop, np.ones((2, 2, 1), np.float32)))
        os.remove(path)
grid = np.concatenate([np.concatenate(cells[0:2], 1), np.concatenate(cells[2:4], 1)], 0)
SK.write_png(out, SK.to8(np.power(grid, 1.0)))
print("wrote", out)
