"""Townhouse C: royal-blue slate roof, hanging herbalist sign over the shop
window, ivy on the corner. See make_townhouses.py for the shared builder.
Run: python3 make_townhouse_c.py <out.glb> [preview.png]
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_townhouses import build

build(3)
