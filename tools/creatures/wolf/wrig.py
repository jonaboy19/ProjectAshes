"""FK/IK model of the wolf rig used to author poses in ARMATURE space (rig units, Z up, wolf faces -Y, +X = wolf left).
A pose is described as world-axis rotations about pivots (default: the bone head) plus optional root translation; the
Blender pose-bone basis (loc + quaternion) is derived analytically:  basis_b = rest_b^-1 * A_parent^-1 * A_b * rest_b.
Legs are solved with analytic IK (2-link front, 3-link hind with a chosen metatarsal direction)."""
import math
from mathutils import Vector, Matrix, Quaternion

LEG = {  # leg -> (chain bones, bone whose head is the paw point at rest)
    "FL": (["FrontShoulder.L", "FrontUpperLeg.L", "FrontLowerLeg.L"], "IKFrontLeg.L"),
    "FR": (["FrontShoulder.R", "FrontUpperLeg.R", "FrontLowerLeg.R"], "IKFrontLeg.R"),
    "BL": (["BackShoulder.L", "BackLeg.L", "BackUpperLeg.L", "BackLowerLeg.L"], "IKBackLeg.L"),
    "BR": (["BackShoulder.R", "BackLeg.R", "BackUpperLeg.R", "BackLowerLeg.R"], "IKBackLeg.R"),
}


def T(v):
    return Matrix.Translation(v)


def rot_about(q, p):
    """rotation q (Quaternion, armature axes) about point p"""
    return T(p) @ q.to_matrix().to_4x4() @ T(-p)


def yaw(a):
    return Quaternion((0, 0, 1), a)      # + = turn to the wolf's LEFT


def pitch(a):
    return Quaternion((1, 0, 0), a)      # about lateral axis; + = nose UP for a wolf facing -Y (verified in test_rig)


def roll(a):
    return Quaternion((0, 1, 0), a)


class WRig:
    def __init__(self, arm):
        self.arm = arm
        bones = arm.data.bones
        self.names = []

        def walk(b):
            self.names.append(b.name)
            for c in b.children:
                walk(c)
        for b in bones:
            if b.parent is None:
                walk(b)
        self.par = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.rest = {b.name: b.matrix_local.copy() for b in bones}
        self.head = {n: self.rest[n].translation.copy() for n in self.names}
        self.s = arm.matrix_world.to_scale()[0]          # metres per rig unit
        self.leg = {}
        for k, (chain, endb) in LEG.items():
            joints = [self.head[n] for n in chain[1:]] + [self.head[endb]]
            self.leg[k] = dict(chain=chain, joints=joints)
        self.pelvis = (self.head["BackShoulder.L"] + self.head["BackShoulder.R"]) * 0.5
        self.com = Vector((0.0, 0.25, 1.45))

    # ---- forward kinematics ------------------------------------------------------------
    def fk(self, rots, trans=None):
        """rots: {bone: Quaternion | (Quaternion, pivot)}; trans: {bone: Vector} (rig units, added before the rotation)
        returns A: {bone: 4x4 cumulative deform in armature space}"""
        A = {}
        for n in self.names:
            p = self.par[n]
            Ap = A[p] if p else Matrix.Identity(4)
            r = rots.get(n)
            own = Matrix.Identity(4)
            if isinstance(r, Matrix):
                own = r
            elif r is not None:
                q, piv = (r if isinstance(r, tuple) else (r, self.head[n]))
                own = rot_about(q, piv)
            if trans and n in trans:
                own = T(trans[n]) @ own
            A[n] = Ap @ own
        return A

    def basis(self, A):
        """{bone: (loc Vector, rot Quaternion)} pose-bone basis realising the cumulative deforms A"""
        out = {}
        for n in self.names:
            p = self.par[n]
            Ap = A[p] if p else Matrix.Identity(4)
            rb = self.rest[n]
            M = rb.inverted() @ Ap.inverted() @ A[n] @ rb
            loc, rot, _sc = M.decompose()
            out[n] = (loc, rot)
        return out

    # ---- leg IK ------------------------------------------------------------------------
    def solve_leg(self, k, A, rots, target, foot_dir=None, pole=None, trans=None):
        """Aim the bones of leg k so the paw point reaches `target` (armature space). `A` must hold the cumulative deforms
        of every bone above the leg chain (spine + pelvis/blade parents). Adds (quat, pivot) rotations for the leg bones
        (all but the first chain bone, which keeps whatever rots holds) to `rots`. Returns (paw position, miss distance)."""
        L = self.leg[k]
        chain = L["chain"]
        J = L["joints"]
        front = k[0] == "F"
        first = chain[0]
        Ap = A[self.par[first]]
        r0 = rots.get(first)
        if r0 is None:
            Ab_first = Ap
        elif isinstance(r0, Matrix):
            Ab_first = Ap @ r0
        else:
            q0, p0 = (r0 if isinstance(r0, tuple) else (r0, self.head[first]))
            Ab_first = Ap @ rot_about(q0, p0)
        hip = (Ab_first @ J[0].to_4d()).to_3d()
        tgt = Vector(target)
        lens = [(J[i + 1] - J[i]).length for i in range(len(J) - 1)]
        if front:
            want = self._ik2(hip, tgt, lens[0], lens[1], pole or Vector((0, 1, 0)))
        else:
            L3 = lens[2]
            fd = foot_dir if foot_dir is not None else (J[2] - J[3]).normalized()      # paw -> hock (up), armature space
            hk = tgt + fd * L3
            for da in (0.0, 0.05, -0.05, 0.1, -0.1, 0.2, -0.2, 0.3, -0.3, 0.45, -0.45, 0.6, -0.6, 0.8, -0.8):
                fd2 = Quaternion((1, 0, 0), da) @ fd
                hk = tgt + fd2 * L3
                if (hk - hip).length <= (lens[0] + lens[1]) * 0.985:
                    break
            mid = self._ik2(hip, hk, lens[0], lens[1], pole or Vector((0, -1, 0)))
            want = [mid[0], mid[1], mid[2], tgt]
        bones = chain[1:]
        Ain = Ab_first
        for i, bn in enumerate(bones):
            a_rest, b_rest = J[i], J[i + 1]
            inv = Ain.inverted()
            b_t = (inv @ want[i + 1].to_4d()).to_3d()
            q = (b_rest - a_rest).normalized().rotation_difference((b_t - a_rest).normalized())
            rots[bn] = (q, a_rest.copy())
            Ain = Ain @ rot_about(q, a_rest)
        pos = (Ain @ J[-1].to_4d()).to_3d()
        return pos, (pos - tgt).length

    @staticmethod
    def _ik2(root, target, l1, l2, pole):
        """2-link IK. returns [root, mid, end]; pole = direction the mid joint bulges toward"""
        d = target - root
        dist = d.length
        if dist < 1e-6:
            d = Vector((0, 0, -1))
            dist = 1.0
        dist_c = min(max(dist, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
        dn = d / dist
        end = root + dn * dist_c
        a = (l1 * l1 - l2 * l2 + dist_c * dist_c) / (2 * dist_c)
        h = math.sqrt(max(l1 * l1 - a * a, 0.0))
        pv = pole - dn * pole.dot(dn)
        if pv.length < 1e-6:
            pv = Vector((0, 1, 0)) - dn * dn[1]
        pv.normalize()
        return [root, root + dn * a + pv * h, end]
