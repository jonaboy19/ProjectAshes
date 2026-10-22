"""Clips derived from the hand-animated source clips by foot-locking (walk, run) and run-turns."""
import math
from mathutils import Vector
from gait import *
from clips_base import *
import lock

SRC = {}          # filled by author.py: {"walk_orig": sample(...), "run_orig": sample(...)}
RUN_TURN_RATE = 1.5     # rad/s heading change during run_turn (about 86 deg/s)


def walk_locked(E):
    s = SRC["walk_orig"]
    g = lock.source_ground_speed(E, s)
    n = len(s) - 1
    c = lock.lock_clip(E, "walk", s, n, g, 0.0, notes="source Quaternius walk, feet locked; ground speed %.3f m/s" % g)
    c.events["ground_speed"] = g
    return c


def run_locked(E):
    s = SRC["run_orig"]
    g = lock.source_ground_speed(E, s)
    n = len(s) - 1
    c = lock.lock_clip(E, "run", s, n, g, 0.0, notes="source Quaternius gallop, feet locked; ground speed %.3f m/s" % g)
    c.events["ground_speed"] = g
    return c


def run_turn(E, name, sg):
    s = SRC["run_orig"]
    g = lock.source_ground_speed(E, s)
    n = len(s) - 1

    def extras(t):
        Fx = {}
        Fx['br'] = sg * 0.22
        Fx['dz'] = -0.03
        Fx['bp'] = 0.03
        Fx['spine'] = {"Back": (-sg * 0.06, 0, 0), "Torso2": (sg * 0.08, 0, 0), "Torso3": (sg * 0.12, 0, 0)}
        Fx['neck'] = (sg * 0.35, 0.0)
        Fx['head'] = (0, 0, -sg * 0.10)
        Fx['tail'] = [(-sg * 0.25, 0.0) for i in range(8)]
        return Fx
    c = lock.lock_clip(E, name, s, n, g, sg * RUN_TURN_RATE, extras=extras,
                       notes="source gallop + lean %.2f rad, head leads; heading rate %.2f rad/s at %.2f m/s" % (0.22, RUN_TURN_RATE, g))
    c.events["ground_speed"] = g
    c.events["yaw_rate_rad_s"] = sg * RUN_TURN_RATE
    return c


def run_turn_l(E): return run_turn(E, "run_turn_l", 1.0)
def run_turn_r(E): return run_turn(E, "run_turn_r", -1.0)
