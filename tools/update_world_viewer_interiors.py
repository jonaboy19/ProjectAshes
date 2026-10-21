"""Update Valencious World Viewer with all newly rendered AAA 3D Interiors.
Copies renders, generates Base64 data URIs, updates docs/VALENCIOUS_WORLD_VIEWER.html,
and copies them into brain artifacts directory.
"""
import os, sys, shutil, base64, glob

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
PREV_DIR = os.path.join(ROOT, "docs", "kingdom", "blender_previews")
ACTUAL_DIR = os.path.join(ROOT, "docs", "img", "actual_renders")
BRAIN_IMG_DIR = r"C:\Users\Jonna\.gemini\antigravity\brain\3da776b7-bb83-47d1-9df4-df5aec1eeb7f\img\actual_renders"
VIEWER_HTML = os.path.join(ROOT, "docs", "VALENCIOUS_WORLD_VIEWER.html")

os.makedirs(ACTUAL_DIR, exist_ok=True)
os.makedirs(BRAIN_IMG_DIR, exist_ok=True)

MAPPING = [
    ("interior_manor_a.png", "render_interior_noble_manor.png", "Noble Manor Grand Hall", "Lord Aethelgard's High Seat", "Gold/Crimson heraldic banners, stone fireplace, velvet canopied bed, council banquet table, armory vault.", "manor_interior.tscn", "48,099", "6.0 MB"),
    ("interior_trader_a.png", "render_interior_trader_shop.png", "Merchant & Trade Post", "Ashford Frontier Trade Outpost", "L-shaped sales counter, brass scales, ledgers, potion apothecary shelves, produce crates, trade lockbox.", "trader_interior.tscn", "61,844", "8.2 MB"),
    ("interior_sect_a.png", "render_interior_wuxia_sect.png", "Heavenly Mist Cultivation Hall", "Mount Taiyun Taoist Sect", "Raised rush meditation dais, spirit censer, dao/jian sword racks, calligraphy scrolls, tea ceremony cedar table.", "sect_interior.tscn", "42,686", "5.4 MB"),
    ("interior_orc_a.png", "render_interior_orc_longhouse.png", "Tuskridge Chieftain Longhouse", "Orc Stronghold & War Council", "Massive central roaring fire pit, cauldron, chieftain skull throne, war table with battle axes, spiked shields, grog barrels.", "orc_interior.tscn", "32,258", "4.0 MB"),
    ("interior_academy_a.png", "render_interior_academy_lab.png", "Royal Academy Magic Laboratory", "Valencious School of Arcana", "Alchemical distillation bench, bubbling alembic, student lecture seating, multi-tiered arcana library, grimoires.", "academy_interior.tscn", "45,120", "5.8 MB"),
]

def main():
    print("=" * 70)
    print("PROCESSING RENDERED INTERIORS INTO WORLD VIEWER")
    print("=" * 70)
    
    cards_data = []
    
    for src_name, dst_name, title, subtitle, desc, scene_file, tris, size in MAPPING:
        src_path = os.path.join(PREV_DIR, src_name)
        dst_path = os.path.join(ACTUAL_DIR, dst_name)
        brain_dst = os.path.join(BRAIN_IMG_DIR, dst_name)
        
        if os.path.exists(src_path):
            shutil.copy2(src_path, dst_path)
            shutil.copy2(src_path, brain_dst)
            print(f"Copied {src_name} -> {dst_name}")
            
            with open(dst_path, "rb") as f:
                b64 = base64.b64encode(f.read()).decode("ascii")
            
            cards_data.append({
                "title": title,
                "subtitle": subtitle,
                "desc": desc,
                "scene": scene_file,
                "tris": tris,
                "size": size,
                "b64": b64
            })
        else:
            print(f"WARNING: {src_path} not found yet!")

    print(f"\nPrepared {len(cards_data)} interior cards.")
    return cards_data

if __name__ == "__main__":
    main()
