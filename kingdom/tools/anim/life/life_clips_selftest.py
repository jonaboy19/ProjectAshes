# Framework self-test (not shipped): one walk loop, one two-handed hold, one enter transition.
from mathutils import Vector
from combat_common import V
from life_common import life_clip, neutral, walk_cycle, hold, to_from, two_hand, breathe, speed_of

@life_clip("Test_Walk", loop=True, category="test", speed_mps=speed_of(0.30, 40))
def _w():
    return walk_cycle(40)

HOE = neutral()
HOE.update(two_hand(V(-0.12, -0.30, 0.95), (0.0, -0.55, -0.83), (0.0, -0.8, 0.5), 0.45))
HOE.update({"tor": (18.0, 0.0, 0.0), "pel": V(0, 0.04, -0.04)})

@life_clip("Test_Hold_Hoe", loop=True, category="test", props=[{"id": "hoe", "hand": "r"}], ik_l_on_prop=0.45)
def _h():
    return hold(HOE, 60, post=breathe())

@life_clip("Test_Hoe_Enter", category="test", props=[{"id": "hoe", "hand": "r"}])
def _e():
    return to_from(neutral(), HOE, 14)
