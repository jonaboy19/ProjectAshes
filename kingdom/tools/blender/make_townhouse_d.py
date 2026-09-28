"""Townhouse D: royal-blue slate roof with a front gable dormer, mirrored
layout. See make_townhouses.py for the shared builder.
Run: python3 make_townhouse_d.py <out.glb> [preview.png]
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_townhouses import build

build(4)
