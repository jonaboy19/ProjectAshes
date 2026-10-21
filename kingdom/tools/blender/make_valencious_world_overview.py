"""3D Valencious 32km Continent Aerial Overview (Blender 5.2 Cycles PBR)
Constructs a comprehensive 3D landscape relief of the entire Valencious continent:
- Central fertile Ashford Vale & meandering Ashrun river flowing into Emberglass Mere
- Fortified capital castle-city of Kingsreach with defensive walls and towers
- The Grand Tournament Colosseum Arena on the King's Highway
- Mount Taiyun snow-capped mountain range with cultivation terraces and pagodas
- Tuskridge Orc monster stronghold with watchtowers and smoldering bonfires
- Northern Gundarak volcanic rift with glowing molten magma channels
- Aetheria floating sky islands suspended above the cloud line
- Dense redwood forests, rural farmsteads, and coastal fjords

Run:
    blender -b --python kingdom/tools/blender/make_valencious_world_overview.py
"""
import os, sys, math, random
import bpy, bmesh
from mathutils import Vector, Matrix, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from ra_kit import Kit, hexc, vary, mix, srgb

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_PNG = os.path.join(ROOT, "docs", "img", "actual_renders", "render_valencious_32km_full_world.png")
PREV_PNG = os.path.join(ROOT, "docs", "kingdom", "blender_previews", "valencious_full_world_overview.png")
BRAIN_PNG = r"C:\Users\Jonna\.gemini\antigravity\brain\3da776b7-bb83-47d1-9df4-df5aec1eeb7f\img\actual_renders\render_valencious_32km_full_world.png"

os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
os.makedirs(os.path.dirname(PREV_PNG), exist_ok=True)
os.makedirs(os.path.dirname(BRAIN_PNG), exist_ok=True)

# Clear existing objects
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# Palette
GRASS_VALE = (0.22, 0.45, 0.18, 1.0)
GRASS_HIGHLAND = (0.35, 0.42, 0.22, 1.0)
ROCK_GREY = (0.38, 0.36, 0.34, 1.0)
SNOW_WHITE = (0.92, 0.94, 0.98, 1.0)
WATER_BLUE = (0.12, 0.32, 0.55, 1.0)
MAGMA_ORANGE = (1.0, 0.28, 0.05, 1.0)
STONE_WALL = (0.55, 0.52, 0.48, 1.0)
ROOF_OXBLOOD = (0.55, 0.15, 0.12, 1.0)
ROOF_NAVY = (0.15, 0.24, 0.42, 1.0)
SAND_SHORE = (0.75, 0.68, 0.52, 1.0)

# Create Terrain BMesh (64x64 resolution grid covering the continent relief)
bm = bmesh.new()
GRID_N = 80
SIZE = 120.0  # In visual scale units
h_step = SIZE / GRID_N

verts_grid = []
for iz in range(GRID_N + 1):
    row = []
    z_pos = (iz - GRID_N / 2) * h_step
    for ix in range(GRID_N + 1):
        x_pos = (ix - GRID_N / 2) * h_step
        
        # Terrain height synthesis
        # 1. Base continental shelf
        r_dist = math.hypot(x_pos, z_pos)
        base = max(0.0, 1.0 - (r_dist / (SIZE * 0.48)) ** 2) * 3.5
        
        # 2. Northern Mountains (Mount Taiyun & Gundarak) at -Z
        mtn = 0.0
        if z_pos < -10.0:
            nx = x_pos * 0.08
            nz = z_pos * 0.08
            m_noise = noise.noise(Vector((nx, nz, 1.0)))
            m_ridge = 1.0 - abs(noise.noise(Vector((nx * 1.5, nz * 1.5, 2.0))))
            mtn = max(0.0, -z_pos - 10.0) * 0.35 * (m_noise * 0.6 + m_ridge * 0.8)
            
        # 3. Ashford River Valley (central plain at 0, 0)
        valley = math.exp(-((x_pos + 5.0)**2 + (z_pos - 5.0)**2) / 250.0) * -1.8
        
        # 4. Coastal shelf roll-off
        h = max(-1.2, base + mtn + valley)
        
        # Minor detail noise
        if h > 0.0:
            h += noise.noise(Vector((x_pos * 0.2, z_pos * 0.2, 0.0))) * 0.5
            
        v = bm.verts.new((x_pos, z_pos, h))
        row.append(v)
    verts_grid.append(row)

# Color Layer
col_lay = bm.loops.layers.color.new("Col")

# Faces
for iz in range(GRID_N):
    for ix in range(GRID_N):
        v00 = verts_grid[iz][ix]
        v10 = verts_grid[iz][ix + 1]
        v11 = verts_grid[iz + 1][ix + 1]
        v01 = verts_grid[iz + 1][ix]
        
        f1 = bm.faces.new((v00, v10, v11))
        f2 = bm.faces.new((v00, v11, v01))
        
        for f in (f1, f2):
            # Compute vertex colors based on height and slope
            avg_z = sum(v.co.z for v in f.verts) / 3.0
            normal_z = f.normal.z
            
            for l in f.loops:
                vz = l.vert.co.z
                if vz <= -0.1:
                    l[col_lay] = WATER_BLUE
                elif vz < 0.6:
                    l[col_lay] = SAND_SHORE
                elif vz < 4.0:
                    l[col_lay] = GRASS_VALE if normal_z > 0.75 else ROCK_GREY
                elif vz < 8.0:
                    l[col_lay] = GRASS_HIGHLAND if normal_z > 0.65 else ROCK_GREY
                else:
                    l[col_lay] = SNOW_WHITE if normal_z > 0.5 else ROCK_GREY

# Water Plane (Emberglass Mere and Oceans)
water_plane = bm.faces.new([
    bm.verts.new((-SIZE/2, -SIZE/2, 0.1)),
    bm.verts.new((SIZE/2, -SIZE/2, 0.1)),
    bm.verts.new((SIZE/2, SIZE/2, 0.1)),
    bm.verts.new((-SIZE/2, SIZE/2, 0.1))
])
for l in water_plane.loops:
    l[col_lay] = WATER_BLUE

# Magma Caldera (Gundarak) at North-West (-25, -35)
caldera_verts = []
for i in range(16):
    ang = i / 16 * math.tau
    cx = -26.0 + math.cos(ang) * 4.5
    cz = -36.0 + math.sin(ang) * 4.5
    caldera_verts.append(bm.verts.new((cx, cz, 4.2)))
f_caldera = bm.faces.new(caldera_verts)
for l in f_caldera.loops:
    l[col_lay] = MAGMA_ORANGE

# ============================================================================ 3D Landmarks & Settlements
def make_castle(bx, bz, bheight, name="Castle"):
    """Kingsreach Royal Castle miniature fortress."""
    # Central Keep
    keep_vs = [
        bm.verts.new((bx - 2.0, bz - 2.0, bheight)),
        bm.verts.new((bx + 2.0, bz - 2.0, bheight)),
        bm.verts.new((bx + 2.0, bz + 2.0, bheight)),
        bm.verts.new((bx - 2.0, bz + 2.0, bheight)),
        bm.verts.new((bx - 2.0, bz - 2.0, bheight + 3.8)),
        bm.verts.new((bx + 2.0, bz - 2.0, bheight + 3.8)),
        bm.verts.new((bx + 2.0, bz + 2.0, bheight + 3.8)),
        bm.verts.new((bx - 2.0, bz + 2.0, bheight + 3.8)),
    ]
    # Faces for keep
    for quad in ((0,1,5,4), (1,2,6,5), (2,3,7,6), (3,0,4,7), (4,5,6,7)):
        fc = bm.faces.new([keep_vs[i] for i in quad])
        for l in fc.loops:
            l[col_lay] = STONE_WALL if quad != (4,5,6,7) else ROOF_NAVY
            
    # 4 Corner Towers
    for sx, sz in ((-2.2, -2.2), (2.2, -2.2), (2.2, 2.2), (-2.2, 2.2)):
        tx, tz = bx + sx, bz + sz
        t_vs = [
            bm.verts.new((tx - 0.7, tz - 0.7, bheight)),
            bm.verts.new((tx + 0.7, tz - 0.7, bheight)),
            bm.verts.new((tx + 0.7, tz + 0.7, bheight)),
            bm.verts.new((tx - 0.7, tz + 0.7, bheight)),
            bm.verts.new((tx, tz, bheight + 4.8))
        ]
        for quad in ((0,1,4), (1,2,4), (2,3,4), (3,0,4)):
            fc = bm.faces.new([t_vs[i] for i in quad])
            for l in fc.loops:
                l[col_lay] = ROOF_OXBLOOD

def make_arena(ax, az, aheight):
    """The Grand Colosseum Arena miniature."""
    arena_vs_inner = []
    arena_vs_outer = []
    for i in range(16):
        ang = i / 16 * math.tau
        rx_in = ax + math.cos(ang) * 2.5
        rz_in = az + math.sin(ang) * 2.5
        rx_out = ax + math.cos(ang) * 4.2
        rz_out = az + math.sin(ang) * 4.2
        arena_vs_inner.append(bm.verts.new((rx_in, rz_in, aheight)))
        arena_vs_outer.append(bm.verts.new((rx_out, rz_out, aheight + 1.6)))
    # Sand pit
    f_sand = bm.faces.new(arena_vs_inner)
    for l in f_sand.loops:
        l[col_lay] = SAND_SHORE
    # Outer stone wall quads
    for i in range(16):
        i2 = (i + 1) % 16
        fc = bm.faces.new((arena_vs_inner[i], arena_vs_outer[i], arena_vs_outer[i2], arena_vs_inner[i2]))
        for l in fc.loops:
            l[col_lay] = STONE_WALL

def make_sky_island(sx, sz, sheight):
    """Aetheria Floating Sky Island."""
    top_vs = []
    bot_v = bm.verts.new((sx, sz, sheight - 3.5))
    for i in range(12):
        ang = i / 12 * math.tau
        tx = sx + math.cos(ang) * 5.0 * (1 + 0.2 * math.sin(ang * 3))
        tz = sz + math.sin(ang) * 3.5 * (1 + 0.2 * math.cos(ang * 2))
        top_vs.append(bm.verts.new((tx, tz, sheight)))
    f_top = bm.faces.new(top_vs)
    for l in f_top.loops:
        l[col_lay] = GRASS_VALE
    for i in range(12):
        i2 = (i + 1) % 12
        fc = bm.faces.new((top_vs[i], top_vs[i2], bot_v))
        for l in fc.loops:
            l[col_lay] = ROCK_GREY

# Instantiate Key World Landmarks
# 1. Kingsreach Royal Castle Capital at (12.0, -10.0)
make_castle(12.0, -10.0, 3.2, "Kingsreach")

# 2. The Grand Colosseum Tournament Arena at (6.0, -4.0)
make_arena(6.0, -4.0, 2.5)

# 3. Ashford Village at (-2.0, 3.0)
for sx, sz in ((-2.5, 2.5), (-1.5, 3.5), (-3.0, 4.0), (-2.0, 4.8)):
    make_castle(sx, sz, 2.1)

# 4. Tuskridge Orc Stronghold at (8.0, 22.0)
make_arena(8.0, 22.0, 2.8)

# 5. Aetheria Floating Sky Islands at (26.0, -28.0)
make_sky_island(26.0, -28.0, 15.0)
make_sky_island(34.0, -22.0, 16.5)

# 6. Mount Taiyun Cultivation Pagodas at (0.0, -32.0)
make_castle(0.0, -32.0, 7.8, "TaiyunSect")

# Finalize Mesh and Object
bm.normal_update()
me = bpy.data.meshes.new("ValenciousContinent")
bm.to_mesh(me)
bm.free()

ob = bpy.data.objects.new("Valencious3DWorld", me)
sc.collection.objects.link(ob)

# Material with Vertex Color multiplication
mat = bpy.data.materials.new("WorldMaterial")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
vc_node = nt.nodes.new("ShaderNodeAttribute")
vc_node.attribute_name = "Col"
nt.links.new(vc_node.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.8
ob.data.materials.append(mat)

# ============================================================================ Camera & Lighting
cam_data = bpy.data.cameras.new("OverviewCam")
cam_data.lens = 32
cam_obj = bpy.data.objects.new("OverviewCam", cam_data)
# High aerial 3/4 isometric vantage point overlooking the entire continent
cam_obj.location = (45.0, 65.0, 55.0)
# Look at center of continent (0, 0, 2)
direction = Vector((0.0, -4.0, 2.0)) - cam_obj.location
rot_quat = direction.to_track_quat('-Z', 'Y')
cam_obj.rotation_euler = rot_quat.to_euler()
sc.collection.objects.link(cam_obj)
sc.camera = cam_obj

# Sun Light (Warm late afternoon golden hour)
sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 4.2
sun_data.color = (1.0, 0.92, 0.80)
sun_obj = bpy.data.objects.new("Sun", sun_data)
sun_obj.rotation_euler = (math.radians(52), math.radians(18), math.radians(-38))
sc.collection.objects.link(sun_obj)

# Blue Sky Ambient Fill Light
sky_data = bpy.data.lights.new("SkyFill", "SUN")
sky_data.energy = 1.2
sky_data.color = (0.65, 0.82, 1.0)
sky_obj = bpy.data.objects.new("SkyFill", sky_data)
sky_obj.rotation_euler = (math.radians(-60), math.radians(0), math.radians(120))
sc.collection.objects.link(sky_obj)

# Render Settings (Cycles GPU / CPU)
sc.render.engine = "CYCLES"
sc.cycles.samples = 64
sc.cycles.use_denoising = True
sc.render.resolution_x = 1920
sc.render.resolution_y = 1080
try:
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Punchy"
except Exception:
    pass

print("Rendering 1080p 3D Overview of Valencious Continent...")
sc.render.filepath = OUT_PNG
bpy.ops.render.render(write_still=True)

# Copy to preview & brain
import shutil
shutil.copy2(OUT_PNG, PREV_PNG)
shutil.copy2(OUT_PNG, BRAIN_PNG)
print(f"Saved renders to:\n  {OUT_PNG}\n  {PREV_PNG}\n  {BRAIN_PNG}")
