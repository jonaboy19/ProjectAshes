import bpy, sys, os, math
sys.path.insert(0, r"C:\Users\Jonna\Documents\PA_wt_horse\kingdom\tools\anim\horse")
import hx_common as X, horse_coats as HC, horse_tack as T, hx_atlas as A
TMP = os.environ.get("TEMP", "/tmp")
arm, lod0 = X.open_rig()
HC.build_all(lod0, only=["bay"])
img = X.load_png(os.path.join(X.OUT, "horse_coat_bay.png"), "img_bay")
X.set_material(lod0, X.textured_material("m_bay", img))
A.write_atlas()
aimg = X.load_png(os.path.join(X.OUT, "horse_tack_atlas.png"), "img_atlas", True)
tmat = X.textured_material("horse_tack", aimg, 0.7)
tmat.use_backface_culling = False
T.setup(arm, lod0)
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
which = [a for a in args if not a.startswith("pose")] or ["saddle", "bridle", "reins"]
obs = []
for n in which:
    ob = getattr(T, "build_" + n)()
    X.set_material(ob, tmat)
    print("HX built", n, X.tris(ob))
    obs.append(ob)
for o in obs:
    for p in o.data.polygons:
        p.use_smooth = True
X.setup_scene_render(1200, 800)
X.ground()
if "pose1" in args:
    X.pose(arm, {"neck_1": (25, 0, 0), "neck_2": (15, 0, 0), "humerus_L": (-35, 0, 0), "forearm_L": (60, 0, 0), "cannon_F_L": (-70, 0, 0),
                 "thigh_R": (30, 0, 0), "gaskin_R": (-40, 0, 0), "head": (15, 0, 0)})
views = [("side", (7, -0.3, 1.3), (0, -0.3, 1.2), 70), ("head", (2.2, -3.0, 1.9), (0.0, -1.25, 1.6), 85),
         ("front3q", (3.5, -4.5, 2.4), (0, -0.3, 1.3), 60), ("top", (0.6, -0.2, 5.0), (0, -0.3, 1.4), 60)]
only = [a[5:] for a in args if a.startswith("view=")]
for n, loc, tg, lens in views:
    X.camera(loc, tg, lens=lens)
    X.render(os.path.join(TMP, "hxt_%s.png" % n))
