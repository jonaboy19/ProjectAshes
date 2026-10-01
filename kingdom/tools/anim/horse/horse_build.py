# Rising Ashes riding horse: rig + model build (Blender 5.2, headless).
#   tools/external/blender.sh kingdom/tools/anim/horse/horse_build.py -- [--no-bake] [--proof DIR]
# 1. Mesh2Motion horse (CC0) is the body. Its joints place the Rigify horse metarig (fit_metarig).
# 2. Rigify generates the 454-bone authoring rig (kept in source/horse_rig.blend, collection "rigify").
# 3. extract_game_skeleton(): OWN deform-bone extraction (Expy Kit fails on horses): Rigify DEF bones -> one-root game skeleton
#    of 58 deform bones (twist halves merged) + socket bones. bake_rigify_action() retargets any Rigify action onto it.
# 4. Body: old stick-out tail removed, new hanging tail + chunky storybook mane modelled procedurally, skinned
#    (heat weights on the body, chain weights on hair), region colour attribute for the coat painter (horse_coats.py).
import bpy, bmesh, sys, os, math
from mathutils import Vector, Matrix, Quaternion
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "tools", "external")))
import hb_common as H
import addon_utils

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PROOF = argv[argv.index("--proof") + 1] if "--proof" in argv else None
V = lambda x, y, z: Vector((x, y, z))


def log(*a):
    print("HB", *a, flush=True)


# ------------------------------------------------------------------ source
def load_source():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = H.FPS
    bpy.ops.import_scene.gltf(filepath=H.SRC_GLB)
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    body = bpy.data.objects["Horse"]
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o is not body:
            bpy.data.objects.remove(o)
    if arm.animation_data:
        arm.animation_data.action = None
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    # the body in its REST shape (the import leaves the first clip's pose on the armature)
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix()
    for m in list(body.modifiers):
        body.modifiers.remove(m)
    body.parent = None
    J = {}
    for b in arm.data.bones:
        J[b.name] = ((arm.matrix_world @ b.head_local).copy(), (arm.matrix_world @ b.tail_local).copy())
    return arm, body, J


_BVH = {}


def _bvh(body):
    from mathutils.bvhtree import BVHTree
    if body.name not in _BVH:
        dg = bpy.context.evaluated_depsgraph_get()
        _BVH[body.name] = BVHTree.FromObject(body, dg)
    return _BVH[body.name]


def surface_z(body, x, y, top=True):
    """z of the body surface hit by a vertical ray at (x, y): the first hit from above (top) or from below"""
    t = _bvh(body)
    inv = body.matrix_world.inverted()
    o = inv @ V(x, y, 4.0 if top else -1.0)
    d = (inv.to_3x3() @ V(0, 0, -1 if top else 1)).normalized()
    hit = t.ray_cast(o, d)
    if hit[0] is None:
        return None
    return (body.matrix_world @ hit[0]).z


def crest_line(body, ys):
    return [V(0, y, surface_z(body, 0.0, y)) for y in ys]


def body_extent(body, y0, y1, xmax=0.08):
    """lowest bottom and highest top of the body along the midline between y0 and y1"""
    zs_t, zs_b = [], []
    for i in range(7):
        y = y0 + (y1 - y0) * i / 6.0
        a, b = surface_z(body, 0.0, y, True), surface_z(body, 0.0, y, False)
        if a is not None:
            zs_t.append(a)
        if b is not None:
            zs_b.append(b)
    return (min(zs_b) if zs_b else None), (max(zs_t) if zs_t else None)


# ------------------------------------------------------------------ metarig fit
def fit_metarig(J, body):
    addon_utils.enable("rigify", default_set=True, persistent=False)
    bpy.ops.object.armature_horse_metarig_add()
    meta = bpy.context.object
    meta.name = "metarig"
    bpy.ops.object.mode_set(mode="EDIT")
    eb = meta.data.edit_bones
    was_connected = {b.name: b.use_connect for b in eb}
    for b in eb:
        b.use_connect = False
    h = lambda n: J[n][0]
    t = lambda n: J[n][1]
    # spine (rear -> front), Rigify chain spine.001..006, neck.001..004, head
    top_rump = body_extent(body, 0.55, 0.70)[1]
    sp = [V(0, 0.64, top_rump - 0.10), h("hips"), V(0, 0.20, 1.285), V(0, -0.06, 1.283), h("spine_3") * 0.5 + h("spine_2") * 0.5,
          V(0, -0.47, 1.355), h("spine_5")]
    sp[3] = V(0, h("spine_2").y, h("spine_2").z)
    sp[4] = V(0, h("spine_3").y, h("spine_3").z)
    sp[5] = V(0, h("spine_4").y, h("spine_4").z)
    sp[6] = V(0, (h("spine_5").y + t("spine_4").y) * 0.5, (h("spine_5").z + t("spine_4").z) * 0.5)
    poll = h("head")
    nk = [sp[6], sp[6].lerp(poll, 0.30), sp[6].lerp(poll, 0.56), sp[6].lerp(poll, 0.80), poll]
    # bow the neck slightly upward along its top line (m2m spine_5/spine_6 joint)
    nk[2] = (nk[2] + h("spine_6")) * 0.5
    chain = [("spine.00%d" % (i + 1), sp[i], sp[i + 1]) for i in range(6)] + [("neck.00%d" % (i + 1), nk[i], nk[i + 1]) for i in range(4)]
    for n, a, b in chain:
        eb[n].head, eb[n].tail = a, b
    muzzle = t("head_leaf")
    eb["head"].head, eb["head"].tail = poll, V(0, (h("nose").y + h("head_leaf").y) * 0.5, (h("nose").z + h("head_leaf").z) * 0.5)
    for n in ("skull", "skull.L", "skull.R"):
        d = eb[n].tail - eb[n].head
        eb[n].head = poll + V(0, -0.02, 0.05)
        eb[n].tail = eb[n].head + d * 0.9
    # jaw: hinge behind the eye, to the chin
    hinge = V(0, poll.y - 0.10, poll.z - 0.13)
    chin = V(0, t("mouth_tip").y - 0.02, t("mouth_tip").z - 0.01)
    eb["jaw"].head, eb["jaw"].tail = hinge, hinge.lerp(chin, 0.55)
    eb["jaw.001"].head, eb["jaw.001"].tail = hinge.lerp(chin, 0.55), chin
    for s, sx in (("L", 1), ("R", -1)):
        e = s.lower()
        eb["ear." + s].head, eb["ear." + s].tail = h("ear_1_" + e), t("ear_2_" + e)
        eb["ear.%s.001" % s].head, eb["ear.%s.001" % s].tail = t("ear_2_" + e), t("ear_leaf_" + e)
        eye = eb["eye." + s]
        eye.head = V(sx * 0.10, poll.y - 0.19, poll.z - 0.03); eye.tail = eye.head + V(sx * 0.08, 0, 0)
        nose = eb["nose." + s]
        nose.head = V(sx * 0.04, muzzle.y + 0.07, muzzle.z + 0.03); nose.tail = nose.head + V(sx * 0.05, -0.02, 0)
        # front leg: scapula top -> shoulder joint -> elbow -> knee -> fetlock -> coronet -> toe (ground)
        fl = "front_%s_" % "%s"
        sc0, sc1 = h("front_scapula_" + e), t("front_scapula_" + e)
        eb["shoulder." + s].head, eb["shoulder." + s].tail = sc0, sc1
        eb["upper_arm." + s].head, eb["upper_arm." + s].tail = sc1, t("front_humerus_" + e)
        eb["forearm." + s].head, eb["forearm." + s].tail = t("front_humerus_" + e), t("front_leg_upper_" + e)
        eb["forefoot." + s].head, eb["forefoot." + s].tail = t("front_leg_upper_" + e), t("front_leg_lower_" + e)
        eb["f_toe." + s].head, eb["f_toe." + s].tail = t("front_leg_lower_" + e), t("front_leg_ankle_" + e)
        toe = t("front_leg_leaf_" + e)
        eb["f_hoof." + s].head, eb["f_hoof." + s].tail = t("front_leg_ankle_" + e), V(toe.x, toe.y + 0.01, 0.0)
        eb["breast." + s].head = V(sx * 0.09, sc1.y - 0.03, 1.05); eb["breast." + s].tail = V(sx * 0.09, sc1.y - 0.20, 0.93)
        # hind leg: hip joint -> stifle -> hock -> fetlock -> coronet -> toe
        hj = t("back_leg_pelvis_" + e)
        eb["pelvis." + s].head, eb["pelvis." + s].tail = h("back_leg_pelvis_" + e), hj
        eb["thigh." + s].head, eb["thigh." + s].tail = hj, t("back_leg_upper_" + e)
        eb["lower_leg." + s].head, eb["lower_leg." + s].tail = t("back_leg_upper_" + e), t("back_leg_lower_" + e)
        eb["hind_foot." + s].head, eb["hind_foot." + s].tail = t("back_leg_lower_" + e), t("back_leg_ankle_" + e)
        eb["r_toe." + s].head, eb["r_toe." + s].tail = t("back_leg_ankle_" + e), t("back_leg_foot_" + e)
        toe = t("back_leg_leaf_" + e)
        eb["r_hoof." + s].head, eb["r_hoof." + s].tail = t("back_leg_foot_" + e), V(toe.x, toe.y + 0.01, 0.0)
    eb["hip"].head, eb["hip"].tail = sp[0], sp[0] + V(0, -0.30, -0.35)
    # belly / chest (muscle jiggle bone): mid-barrel, hanging
    lo, hi = body_extent(body, -0.15, 0.05)
    eb["chest"].head, eb["chest"].tail = V(0, -0.08, hi - 0.16), V(0, -0.06, lo + 0.08)
    eb["abdomen"].head, eb["abdomen"].tail = V(0, 0.20, hi - 0.16), V(0, 0.22, lo + 0.10)
    # tail: hanging relaxed tail from the dock (the rest pose of the game rig)
    dock = V(0, h("tail_1").y + 0.02, h("tail_1").z - 0.02)
    tp = [dock, dock + V(0, 0.10, -0.06), dock + V(0, 0.17, -0.22), dock + V(0, 0.205, -0.42), dock + V(0, 0.215, -0.62), dock + V(0, 0.22, -0.84)]
    for i in range(5):
        eb["tail.00%d" % (i + 1)].head, eb["tail.00%d" % (i + 1)].tail = tp[i], tp[i + 1]
    # mane: 5 tufts on the crest from the poll back to the withers + forelock, hanging to the horse's right (-X)
    ys = [poll.y + 0.02 + (sp[5].y + 0.02 - poll.y - 0.02) * k / 4.0 for k in range(5)]
    crest = crest_line(body, ys)
    for i, (k, c) in enumerate(zip(("01", "02", "03", "04", "05"), crest)):
        base = c + V(0, 0, -0.035)
        eb["mane_base." + k].head = base
        eb["mane_base." + k].tail = base + V(-0.075, 0.02, -0.045)
        eb["mane_top." + k].head = eb["mane_base." + k].tail
        eb["mane_top." + k].tail = eb["mane_base." + k].tail + V(-0.05, 0.03, -0.14 - 0.02 * i)
    fb = poll + V(0, -0.03, 0.06)
    eb["mane_base.06"].head, eb["mane_base.06"].tail = fb, fb + V(0, -0.07, -0.02)
    eb["mane_top.06"].head, eb["mane_top.06"].tail = fb + V(0, -0.07, -0.02), fb + V(0.0, -0.13, -0.12)
    # reconnect the chains Rigify expects to be connected
    for b in eb:
        if was_connected[b.name]:
            if (b.head - b.parent.tail).length > 1e-4:
                log("WARN reconnect moves", b.name, (b.head - b.parent.tail).length)
            b.use_connect = True
    bpy.ops.object.mode_set(mode="OBJECT")
    return meta


def generate(meta):
    bpy.ops.object.select_all(action="DESELECT")
    meta.select_set(True)
    bpy.context.view_layer.objects.active = meta
    bpy.ops.pose.rigify_generate()
    rig = bpy.data.objects["rig"]
    log("rigify bones", len(rig.data.bones), "DEF", sum(1 for b in rig.data.bones if b.name.startswith("DEF-")))
    return rig


# ------------------------------------------------------------------ own DEF extraction
def extract_game_skeleton(rig, name="HorseSkeleton"):
    """One-root game skeleton from the Rigify DEF bones: merged twist halves, renamed, re-parented (GAME_BONES)."""
    rb = rig.data.bones
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    for gname, parent, defs, deform in H.GAME_BONES:
        b = eb.new(gname)
        if defs is None:
            b.head, b.tail, b.roll = V(0, 0, 0), V(0, -0.35, 0), 0.0
        else:
            first, last = rb[defs[0]], rb[defs[-1]]
            b.head = rig.matrix_world @ first.head_local
            b.tail = rig.matrix_world @ last.tail_local
            # keep Rigify's roll: align the new bone's Z axis with the first DEF bone's Z axis
            b.align_roll((rig.matrix_world.to_3x3() @ first.matrix_local.to_3x3()).col[2])
        b.use_deform = deform
        if parent:
            b.parent = eb[parent]
            b.use_connect = (b.head - eb[parent].tail).length < 1e-4
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def bake_rigify_action(rig, game, frame_start, frame_end, name="rigify_bake"):
    """Retarget the rig's current animation onto the game skeleton: every game bone copies the world rotation (and location)
    of its first DEF bone, then nla.bake with visual keying bakes plain FK keys and removes the constraints. For hand-keyed
    Rigify clips; the gait engine (horse_gait.py) poses the game skeleton directly."""
    for gname, parent, defs, deform in H.GAME_BONES:
        if not defs:
            continue
        pb = game.pose.bones[gname]
        pb.rotation_mode = "QUATERNION"
        c = pb.constraints.new("COPY_ROTATION")
        c.target, c.subtarget = rig, defs[0]
        c2 = pb.constraints.new("COPY_LOCATION")
        c2.target, c2.subtarget = rig, defs[0]
    bpy.ops.object.select_all(action="DESELECT")
    game.select_set(True)
    bpy.context.view_layer.objects.active = game
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(frame_start=frame_start, frame_end=frame_end, only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=False, bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    act = game.animation_data.action
    act.name = name
    return act


def extraction_selftest(rig, game):
    """Pose the Rigify rig (rear: fore feet IK up, torso pitched), bake onto the game skeleton, compare joint positions."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    pb = rig.pose.bones
    rig.animation_data_create()
    sc = bpy.context.scene
    for f, k in ((1, 0.0), (10, 1.0)):
        for s in "LR":
            pb["forefoot_ik." + s].location = (0, -0.2 * k, 0.55 * k)
            pb["forefoot_ik." + s].keyframe_insert("location", frame=f)
        pb["torso"].rotation_mode = "XYZ"
        pb["torso"].rotation_euler = (-0.35 * k, 0, 0)
        pb["torso"].keyframe_insert("rotation_euler", frame=f)
        pb["head"].rotation_mode = "XYZ" if pb["head"].rotation_mode != "QUATERNION" else "QUATERNION"
    bpy.ops.object.mode_set(mode="OBJECT")
    bake_rigify_action(rig, game, 1, 10, "selftest")
    worst = 0.0
    for f in (1, 5, 10):
        sc.frame_set(f)
        for gname, parent, defs, deform in H.GAME_BONES:
            if not defs:
                continue
            a = game.matrix_world @ game.pose.bones[gname].head
            b = rig.matrix_world @ rig.pose.bones[defs[0]].head
            worst = max(worst, (a - b).length)
            if len(defs) > 1 or gname.startswith("hoof"):
                a = game.matrix_world @ game.pose.bones[gname].tail
                b = rig.matrix_world @ rig.pose.bones[defs[-1]].tail
                worst = max(worst, (a - b).length)
    log("EXTRACT selftest worst joint error %.4f m" % worst)
    game.animation_data.action = None
    rig.animation_data.action = None
    for p in rig.pose.bones:
        p.location = (0, 0, 0); p.rotation_quaternion = (1, 0, 0, 0); p.rotation_euler = (0, 0, 0)
    for p in game.pose.bones:
        p.location = (0, 0, 0); p.rotation_quaternion = (1, 0, 0, 0)
    return worst


def place_sockets(game, body):
    """Saddle seat, stirrups, rein grips, bit, tugs and cart hitch from the body surface."""
    bpy.context.view_layer.objects.active = game
    bpy.ops.object.mode_set(mode="EDIT")
    eb = game.data.edit_bones
    lo, hi = body_extent(body, -0.30, -0.18)
    seat_y = -0.24
    top = surface_z(body, 0.0, seat_y)
    seat = V(0, seat_y, top + 0.075)          # saddle top (tree + pad) above the back at the lowest point of the seat
    S = {}
    S["saddle"] = (seat, seat + V(0, -0.25, 0))
    # stirrup tread (ball of the rider's foot): heel under the hip, about 0.57 m below the seat (rider posting room), lower leg on the barrel
    st = V(0.31, seat_y - 0.06, seat.z - 0.57)
    S["stirrup_L"] = (st, st + V(0, -0.15, 0))
    S["stirrup_R"] = (V(-st.x, st.y, st.z), V(-st.x, st.y - 0.15, st.z))
    # rein grip: the rider's hands, just in front of the pommel, about 0.36 m ahead of and 0.16 m above the seat
    g = V(0.09, seat_y - 0.36, seat.z + 0.16)
    S["rein_grip_L"] = (g, g + V(0, -0.12, 0))
    S["rein_grip_R"] = (V(-g.x, g.y, g.z), V(-g.x, g.y - 0.12, g.z))
    hj = eb["jaw"]
    bit = hj.head.lerp(hj.tail, 0.72) + V(0, 0, 0.05)
    S["bit"] = (bit, bit + V(0, -0.08, 0))
    blo, bhi = body_extent(body, -0.02, 0.10)
    S["tug_L"] = (V(0.27, 0.02, 1.10), V(0.27, -0.18, 1.10))
    S["tug_R"] = (V(-0.27, 0.02, 1.10), V(-0.27, -0.18, 1.10))
    rump = body_extent(body, 0.62, 0.72)
    S["cart_hitch"] = (V(0, 0.80, rump[1] - 0.30), V(0, 0.95, rump[1] - 0.30))
    for name, parent, deform in H.SOCKETS:
        b = eb.new(name)
        b.head, b.tail = S[name]
        b.roll = 0.0
        b.use_deform = deform
        b.parent = eb[parent]
    bpy.ops.object.mode_set(mode="OBJECT")


def build_body(body, game):
    import horse_mesh as HM
    HM.prepare_body(body)
    tail = HM.build_tail(game)
    mane = HM.build_mane(game, body)
    HM.skin_body(body, game)
    for ob in (tail, mane):
        HM.attach(ob, game)
    for ob in (tail, mane):
        HM.region_colors(ob)
    # one mesh, one material, one draw call
    bpy.ops.object.select_all(action="DESELECT")
    for ob in (body, tail, mane):
        ob.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "Horse_LOD0"
    body.data.name = "Horse_LOD0"
    HM.finalize_weights(body)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.shade_smooth()
    log("LOD0 tris", sum(len(p.vertices) - 2 for p in body.data.polygons))
    return body


def pose_test(game, pose):
    """quick FK test poses for deformation proofs: dict bone -> (x, y, z) euler degrees"""
    for pb in game.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0, 0, 0)
    for n, e in pose.items():
        game.pose.bones[n].rotation_euler = tuple(math.radians(x) for x in e)
    bpy.context.view_layer.update()


if __name__ == "__main__":
    arm, body, J = load_source()
    meta = fit_metarig(J, body)
    rig = generate(meta)
    game = extract_game_skeleton(rig)
    place_sockets(game, body)
    extraction_selftest(rig, game)
    horse = build_body(body, game)
    log("game bones", len(game.data.bones), "deform", sum(1 for b in game.data.bones if b.use_deform))
    if PROOF:
        os.makedirs(PROOF, exist_ok=True)
        import bl_common as C
        C.setup_render(1400, 900)
        sc = bpy.context.scene
        sc.display.shading.light = "STUDIO"
        sc.display.shading.color_type = "VERTEX"
        for o in (arm, meta, rig):
            o.hide_render = True
        horse.data.color_attributes.active_color = horse.data.color_attributes["regions"]
        tests = {
            "rest": {},
            "pose": {"humerus_L": (-35, 0, 0), "forearm_L": (60, 0, 0), "cannon_F_L": (-70, 0, 0), "neck_1": (25, 0, 0), "neck_2": (15, 0, 0),
                     "head": (20, 0, 0), "thigh_R": (30, 0, 0), "gaskin_R": (-40, 0, 0), "cannon_H_R": (50, 0, 0), "tail_1": (30, 0, 20),
                     "tail_2": (10, 0, 15), "jaw": (12, 0, 0), "ear_1_L": (0, 0, 40), "spine_2": (0, 8, 0)},
        }
        for tn, pose in tests.items():
            pose_test(game, pose)
            for nm, loc in (("side", (6, -0.2, 1.1)), ("q", (4, -4.5, 2.2)), ("rear", (-2.5, 5.5, 1.8))):
                C.camera(loc, target=(0, -0.2, 0.95), ortho=3.4)
                C.render(os.path.join(PROOF, "%s_%s.png" % (tn, nm)))
        pose_test(game, {})
    bpy.ops.wm.save_as_mainfile(filepath=H.BLEND)
    log("saved", H.BLEND)
