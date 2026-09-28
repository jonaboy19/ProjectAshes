"""Townhouse A: royal-blue slate roof, hanging shield sign, small red/gold
banner. See make_townhouses.py for the shared builder and scale/facing notes.
Run: python3 make_townhouse_a.py <out.glb> [preview.png]
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_townhouses import build

build(1)
