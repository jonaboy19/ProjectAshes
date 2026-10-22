"""Clip registry."""
from clips_base import *
from clips2 import *
from clips3 import *

CLIPS = {"stalk": stalk, "turn_l90": turn_l90, "turn_r90": turn_r90, "turn_l180": turn_l180, "turn_r180": turn_r180,
         "circle_l": circle_l, "circle_r": circle_r, "limp": limp, "flinch": flinch, "howl": howl, "lunge": lunge, "walk": walk_locked, "run": run_locked, "run_turn_l": run_turn_l, "run_turn_r": run_turn_r}
