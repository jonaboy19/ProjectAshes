# Bake the horse clips (horse_clips.py) with the gait engine and export the animation library.
#   blender -b -P author_horse.py -- <out.glb> [Clip,Clip,...] [--preview DIR] [--every N]
# Output: <out.glb> (HorseSkeleton + stub mesh + one NLA track per clip; loops end in _Loop), <out.glb>.clips.json
# (footfalls, contacts, root motion, events, gait speeds) and <out.glb>.saddle.json (per frame saddle / rein grip / stirrup
# transforms in root space: the rider clip author reads it).
import bpy, sys, os, math, json
from mathutils import Vector, Matrix, Quaternion
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hb_common as H
import horse_gait as G
argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
ONLY = argv[1].split(",") if len(argv) > 1 and not argv[1].startswith("--") and argv[1] else None
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
EVERY = int(argv[argv.index("--every") + 1]) if "--every" in argv else 1

bpy.ops.wm.open_mainfile(filepath=H.BLEND)
scene = bpy.context.scene
scene.render.fps = G.FPS
ARM = bpy.data.objects["HorseSkeleton"]
ARM.animation_data_create()
ENG = G.Engine(ARM)
import horse_clips as HC
HC.setup(ENG)


def log(*a):
    print("AH", *a, flush=True)


# ------------------------------------------------------------------ bake
def frames_of(sc):
    n = int(round(sc.duration * G.FPS))
    return list(range(n + 1))


def evaluate_clip(sc):
    """evaluate every frame (plus warm-up cycles for loops so the secondary chains are in steady state)"""
    fr = frames_of(sc)
    n = len(fr) - 1
    warm = (2 * n) if sc.loop else 12
    times = [(f - warm) / G.FPS for f in range(0, warm)] + [f / G.FPS for f in fr]
    if not sc.loop:
        times = [0.0] * warm + [f / G.FPS for f in fr]      # hold the first pose while the hair settles
    # pass 1: raw support corrections (body lowered / pitched where a planted leg cannot reach), then smooth them in
    # time so the saddle never jumps (a correction that switches on in one frame gave 4 cm saddle pops), keeping at
    # least the required lowering (running max over +-2 frames, then a Gaussian of sigma 1.5 frames; periodic for loops)
    if sc.support:
        fr_t = [f / G.FPS for f in fr]
        raw = [ENG.evaluate(sc, t)[2]["_support"] for t in fr_t]
        m = len(raw)

        def at(i):
            if sc.loop:
                return raw[i % (m - 1)]
            return raw[max(0, min(m - 1, i))]
        mx = []
        for i in range(m):
            win = [at(i + k) for k in range(-2, 3)]
            mx.append((min(w[0] for w in win), max(win, key=lambda w: abs(w[1]))[1]))
        ker = [math.exp(-0.5 * (k / 1.5) ** 2) for k in range(-4, 5)]
        ks = sum(ker)
        sm = []
        for i in range(m):
            dz = dp = 0.0
            for j, kw in zip(range(-4, 5), ker):
                ii = (i + j) % (m - 1) if sc.loop else max(0, min(m - 1, i + j))
                dz += mx[ii][0] * kw
                dp += mx[ii][1] * kw
            sm.append((dz / ks, dp / ks))
        if sc.loop:
            sm[-1] = sm[0]
        dur = sc.duration

        def fixed(t, sm=sm, n=n, loop=sc.loop):
            x = (t % dur if loop else max(0.0, min(dur, t))) * G.FPS
            i = min(int(x), n - 1)
            u = x - i
            a, b = sm[i], sm[min(i + 1, n)]
            return (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u)
        sc.support_fixed = fixed
    Ws, Bs, infos = [], [], []
    for t in times:
        W, B, info = ENG.evaluate(sc, t)
        Ws.append(W); Bs.append(B); infos.append(info)
    if sc.sim_secondary:
        sim = G.simulate_secondary(ENG, sc, Ws, 1.0 / G.FPS)
        for W, B, tg in zip(Ws, Bs, sim):
            for chain in G.CHAINS:
                for nm in chain:
                    M = ENG.S.aim(W, nm, tg[nm])
                    W[nm] = M
                    B[nm] = ENG.S.basis_from_world(W, nm, M)
                    # children re-follow (FK) in the next chain element through W
    Ws, Bs, infos = Ws[warm:], Bs[warm:], infos[warm:]
    if sc.loop and sc.sim_secondary:
        # seamless loop for the hair: blend the last frames toward the first pose (the rest of the body loops exactly)
        k = min(6, n // 3)
        hair = [nm for ch in G.CHAINS for nm in ch]
        for i in range(k):
            f = n - k + 1 + i
            w = (i + 1) / (k + 1)
            for nm in hair:
                q = Bs[f][nm].to_quaternion().slerp(Bs[0][nm].to_quaternion(), w)
                Bs[f][nm] = q.to_matrix().to_4x4()
        for nm in hair:
            Bs[n][nm] = Bs[0][nm].copy()
    return Ws, Bs, infos


def bake(sc, Bs):
    act = bpy.data.actions.new(sc.name)
    act.use_fake_user = True
    ARM.animation_data.action = act
    if hasattr(ARM.animation_data, "action_slot") and len(act.slots):
        ARM.animation_data.action_slot = act.slots[0]
    pbs = ARM.pose.bones
    prevq = {}
    for f, B in enumerate(Bs):
        for n in ENG.rig.order:
            pb = pbs[n]
            q = B[n].to_quaternion()
            if n in prevq and prevq[n].dot(q) < 0:
                q.negate()
            prevq[n] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if n in ("root", "hips"):
                pb.location = B[n].to_translation()
                pb.keyframe_insert("location", frame=f)
    ARM.animation_data.action = None
    return act


# ------------------------------------------------------------------ measurement on the baked action
TOES = {"FL": "hoof_F_L", "FR": "hoof_F_R", "HL": "hoof_H_L", "HR": "hoof_H_R"}


def measure(sc, act):
    """evaluate the baked action with Blender and measure hoof drift inside every stance window (the real proof)."""
    ARM.animation_data.action = act
    if hasattr(ARM.animation_data, "action_slot") and len(act.slots):
        ARM.animation_data.action_slot = act.slots[0]
    n = len(frames_of(sc)) - 1
    toes = {leg: [] for leg in G.LEGS}
    saddle = []
    for f in range(n + 1):
        scene.frame_set(f)
        for leg, hb in TOES.items():
            pb = ARM.pose.bones[hb]
            toes[leg].append((ARM.matrix_world @ pb.tail).copy())
        rootm = ARM.matrix_world @ ARM.pose.bones["root"].matrix
        rinv = rootm.inverted()
        rec = {}
        for s in ("saddle", "rein_grip_L", "rein_grip_R", "stirrup_L", "stirrup_R", "bit", "head", "withers"):
            m = rinv @ ARM.matrix_world @ ARM.pose.bones[s].matrix
            rec[s] = [round(x, 5) for x in m.translation] + [round(x, 6) for x in m.to_quaternion()]
        rec["root"] = [round(x, 5) for x in rootm.translation] + [round(x, 6) for x in rootm.to_quaternion()]
        saddle.append(rec)
    ARM.animation_data.action = None
    slide = {}
    windows = {}
    for leg in G.LEGS:
        worst = 0.0
        win = []
        for (tl, tu, p) in sc.stances[leg]:
            f0, f1 = math.ceil(tl * G.FPS - 1e-6), math.floor(tu * G.FPS + 1e-6)
            # breakover frames (heel lifting about the toe) keep the toe fixed as well
            f0, f1 = max(f0, 0), min(f1, n)
            if f1 - f0 < 1:
                continue
            win.append([f0, f1])
            ov = sc.leg_override.get(leg)
            fr = [f for f in range(f0, f1 + 1) if not (ov and ov(f / G.FPS) is not None)]
            if len(fr) < 2:
                continue
            ref = toes[leg][fr[0]]
            for f in fr:
                d = toes[leg][f] - ref
                worst = max(worst, math.hypot(d.x, d.y))
        slide[leg] = round(worst, 4)
        windows[leg] = win
    return slide, windows, toes, saddle


# ------------------------------------------------------------------ export
def export(made, report, out):
    ARM.animation_data.action = None
    for pb in ARM.pose.bones:
        pb.rotation_quaternion = Quaternion(); pb.location = Vector()
    for tr in list(ARM.animation_data.nla_tracks):
        ARM.animation_data.nla_tracks.remove(tr)
    me = bpy.data.meshes.new("HorseAnimStub")
    me.from_pydata([(0, 0, 1.2), (0.01, 0, 1.2), (0, 0.01, 1.2)], [], [(0, 1, 2)])
    ob = bpy.data.objects.new("HorseAnimStub", me)
    scene.collection.objects.link(ob)
    ob.parent = ARM
    vg = ob.vertex_groups.new(name="spine_2")
    vg.add([0, 1, 2], 1.0, "REPLACE")
    ob.modifiers.new("Armature", "ARMATURE").object = ARM
    loops = {r["name"]: r["loop"] for r in report}
    for name, a in made:
        tr = ARM.animation_data.nla_tracks.new()
        tr.name = name + ("_Loop" if loops[name] else "")
        st = tr.strips.new(tr.name, 0, a)
    bpy.ops.object.select_all(action="DESELECT")
    ARM.select_set(True); ob.select_set(True)
    bpy.context.view_layer.objects.active = ARM
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=1,
                              export_optimize_animation_size=False, export_materials="NONE", export_apply=False, export_yup=True,
                              export_def_bones=False, export_anim_single_armature=True, export_reset_pose_bones=True)
    bpy.data.objects.remove(ob)
    log("EXPORTED", out, len(made))


# ------------------------------------------------------------------ preview renders (Blender workbench, side view following the root)
def preview(sc, act, outdir, every=1, toes=None, views=("side",)):
    os.makedirs(outdir, exist_ok=True)
    body = bpy.data.objects.get("Horse_LOD0")
    for o in bpy.data.objects:
        o.hide_render = o.type == "MESH" and o is not body
    sc_ = scene
    sc_.render.engine = "BLENDER_WORKBENCH"
    sc_.render.resolution_x, sc_.render.resolution_y = 640, 400
    sc_.display.shading.light = "STUDIO"
    sc_.display.shading.color_type = "SINGLE"
    sc_.display.shading.single_color = (0.55, 0.36, 0.22)
    sc_.display.shading.show_shadows = False
    sc_.world = sc_.world or bpy.data.worlds.new("w")
    sc_.world.color = (0.93, 0.9, 0.82)
    # ground grid: stripes every 0.5 m so sliding is visible
    if "PreviewGround" not in bpy.data.objects:
        bpy.ops.mesh.primitive_plane_add(size=1)
        g = bpy.context.object
        g.name = "PreviewGround"
        g.scale = (0.02, 60, 1)
        mat = bpy.data.materials.new("gnd"); mat.diffuse_color = (0.35, 0.3, 0.25, 1)
        g.data.materials.append(mat)
        for k in range(-60, 61):
            m = bpy.data.objects.new("tick%d" % k, g.data)
            scene.collection.objects.link(m)
            m.location = (0.3, k * 0.5, 0.001)
            m.scale = (0.4, 0.02, 1)
    cam = bpy.data.objects.get("PrevCam") or bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 4.4
    scene.camera = cam
    ARM.animation_data.action = act
    if hasattr(ARM.animation_data, "action_slot") and len(act.slots):
        ARM.animation_data.action_slot = act.slots[0]
    n = len(frames_of(sc)) - 1
    for v in views:
        for f in range(0, n + 1, every):
            scene.frame_set(f)
            r = ARM.matrix_world @ ARM.pose.bones["root"].head
            if v == "side":
                cam.location = (7.0 + r.x, r.y - 0.2, 1.05)
                cam.rotation_euler = (math.radians(90), 0, math.radians(90))
            elif v == "front":
                cam.location = (r.x, r.y - 7.0, 1.2)
                cam.rotation_euler = (math.radians(90), 0, 0)
            else:
                cam.location = (r.x + 5.0, r.y - 5.0, 2.8)
                cam.rotation_euler = (math.radians(68), 0, math.radians(45))
            scene.render.filepath = os.path.join(outdir, "%s_%s_%04d.png" % (sc.name, v, f))
            bpy.ops.render.render(write_still=True)
    ARM.animation_data.action = None


if __name__ == "__main__":
    report, made, sad = [], [], {}
    for name, fn in HC.CLIPS.items():
        if ONLY and name not in ONLY:
            continue
        sc = fn()
        Ws, Bs, infos = evaluate_clip(sc)
        act = bake(sc, Bs)
        slide, windows, toes, saddle = measure(sc, act)
        n = len(Bs) - 1
        over = max((infos[f][leg][0] for f in range(len(infos)) for leg in G.LEGS), default=0.0)
        r0 = sc.root_pos(0.0); r1 = sc.root_pos(sc.duration)
        y0, y1 = sc.root_yaw(0.0), sc.root_yaw(sc.duration)
        entry = {"name": name, "loop": sc.loop, "frames": n + 1, "fps": G.FPS, "seconds": round(n / G.FPS, 3),
                 "root_delta_m": [round(r1.x - r0.x, 3), round(r1.y - r0.y, 3), round(r1.z - r0.z, 3)],
                 "root_yaw_deg": round(math.degrees(y1 - y0), 2),
                 "speed_mps": round((r1 - r0).length / max(sc.duration, 1e-6), 3),
                 "hoof_slide_m": slide, "stance_frames": windows, "leg_overreach_m": round(over, 4)}
        entry.update(sc.meta)
        if sc.events:
            entry["events"] = sc.events
        report.append(entry)
        sad[name] = saddle
        made.append((name, act))
        for sname, f0, f1 in sc.meta.get("splits", []):
            sub = [B.copy() for B in Bs[f0:f1 + 1]]
            r0 = Bs[f0]["root"].to_translation()
            for B in sub:
                B["root"] = Matrix.Translation(-r0) @ B["root"]
            sact = bake(type("S", (), {"name": sname})(), sub)
            rr = [ENG.rig.L["root"] @ B["root"] for B in (sub[0], sub[-1])]
            d = rr[1].translation - rr[0].translation
            report.append({"name": sname, "loop": False, "frames": len(sub), "fps": G.FPS, "seconds": round((len(sub) - 1) / G.FPS, 3),
                           "root_delta_m": [round(d.x, 3), round(d.y, 3), round(d.z, 3)], "split_of": name, "source_frames": [f0, f1],
                           "events": {k: [x - f0 for x in v if f0 <= x <= f1] for k, v in sc.events.items()}})
            sad[sname] = saddle[f0:f1 + 1]
            made.append((sname, sact))
        log("CLIP", name, "frames", n + 1, "slide", slide, "overreach %.3f" % over)
        if PREVIEW:
            preview(sc, act, PREVIEW, EVERY)
    export(made, report, OUT)
    json.dump(report, open(OUT + ".clips.json", "w"), indent=1)
    json.dump(sad, open(OUT + ".saddle.json", "w"))
    log("DONE", len(made))
