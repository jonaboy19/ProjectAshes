"""Townhouse B: terracotta tile roof, red/cream striped awning over the door,
mirrored layout. See make_townhouses.py for the shared builder.
Run: python3 make_townhouse_b.py <out.glb> [preview.png]
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_townhouses import build

build(2)
