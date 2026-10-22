# Two-wheel market cart (static, storybook wood + blue paint), shares the tack atlas.
# Cart space (Blender): origin on the ground under the axle centre, cart faces -Y, +Z up.
# Shaft tips (where they meet the horse's tug_L / tug_R): SHAFT_TIP = (+-0.27, -2.03, 1.10) from the cart origin.
# Hitched: cart origin = horse tug - tip = (0, +2.05, 0) in horse space (Blender), i.e. 2.05 m behind the horse's origin.
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import horse_tack as T
from hx_common import V

SHAFT_TIP = (0.27, -2.03, 1.10)
R = 0.55


def build_cart():
    m = T.M("horse_cart")
    X_ = V(1, 0, 0)
    az = R                       # axle height
    # wheels
    for side in (1.0, -1.0):
        x = 0.80 * side
        c = V(x, 0, az)
        T.torus(m, c, V(0, 1, 0), V(0, 0, 1), X_, 0.50, 0.50, 0.040, "WOODD", seg=20, sides=4)
        T.torus(m, c, V(0, 1, 0), V(0, 0, 1), X_, 0.552, 0.552, 0.012, "IRON", seg=20, sides=4)
        T.tube(m, [c - X_ * 0.085, c + X_ * 0.085], 0.075, "WOODD", sides=8, up=V(0, 0, 1))
        for k in range(8):
            a = 2 * math.pi * k / 8 + 0.2
            rd = V(0, math.cos(a), math.sin(a))
            pd = V(0, -math.sin(a), math.cos(a))
            T.box(m, c + rd * 0.29, (0.045, 0.43, 0.05) if False else (0.045, 0.05, 0.43), "WOOD", axes=(X_, pd, rd))
    T.tube(m, [V(-0.88, 0, az), V(0.88, 0, az)], 0.038, "IRON", sides=6, up=V(0, 1, 0))
    # bed
    T.box(m, V(0, 0, 0.80), (1.30, 1.74, 0.05), "WOOD")
    for sx in (1.0, -1.0):
        for z in (0.91, 1.04):
            T.box(m, V(0.64 * sx, 0, z), (0.04, 1.74, 0.11), "PAINT")
        for y in (-0.82, -0.27, 0.27, 0.82):
            T.box(m, V(0.64 * sx, y, 0.98), (0.06, 0.06, 0.40), "WOODD")
    for y in (-0.87, 0.87):
        for z in (0.91, 1.04):
            T.box(m, V(0, y, z), (1.30, 0.04, 0.11), "PAINT")
    T.box(m, V(0, -0.52, 1.16), (1.22, 0.30, 0.045), "WOOD")                   # driver's bench
    for sx in (1.0, -1.0):
        T.box(m, V(0.50 * sx, -0.52, 1.03), (0.05, 0.26, 0.26), "WOODD")
    # cargo: two sacks, a barrel with hoops, a crate
    T.sphere(m, V(0.26, 0.42, 0.98), 0.22, 0.20, 0.17, "CREAM", 8, 4)
    T.sphere(m, V(-0.30, 0.52, 0.98), 0.20, 0.22, 0.16, "STRAW", 8, 4)
    T.tube(m, [V(-0.28, -0.05, 0.825), V(-0.28, -0.05, 1.22)], 0.17, "WOODD", sides=8, up=V(1, 0, 0))
    for z in (0.90, 1.14):
        T.torus(m, V(-0.28, -0.05, z), X_, V(0, 1, 0), V(0, 0, 1), 0.175, 0.175, 0.012, "IRON", seg=8, sides=4)
    T.box(m, V(0.30, -0.05, 0.93), (0.34, 0.34, 0.22), "WOOD")
    # shafts: from the bed side frame forward, converging on the tug positions; cross bar
    tx, ty, tz = SHAFT_TIP
    for sx in (1.0, -1.0):
        a = V(0.55 * sx, 0.40, 0.87)
        b = V(tx * sx, ty, tz)
        pts = [a.lerp(b, k / 6.0) for k in range(7)]
        T.tube(m, pts, 0.04, "WOODD", sides=6, up=V(0, 0, 1), r_fn=lambda i: 0.045 - 0.016 * i / 6.0)
        T.sphere(m, b + V(0, -0.02, 0), 0.028, 0.028, 0.028, "IRON", 6, 3)
    T.tube(m, [V(-0.39, -1.0, 1.0), V(0.39, -1.0, 1.0)], 0.022, "WOODD", sides=6, up=V(0, 0, 1))
    return m.finish("horse_cart", parent=False)
