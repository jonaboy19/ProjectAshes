"""Comprehensive World Locations, Biomes, Cities, Arenas, and Walk-In Interiors Showcase for Project Ashes.
Injects:
- Valencious 15-Region World Atlas & AAA Panoramas (valencious_world_atlas_all_regions.jpg, ashford_vale_golden_hour_river_panorama.jpg, mount_taiyun_cultivation_cloud_citadel.jpg, duskbriar_sacred_forest_river_shrine.jpg)
- 3D PBR City & Settlement Renders (Kingsreach Keep & Gate, Ashford Square & Street, Forest Cottage, Orc Hut, Colosseum Arena)
- Regional World Dressing (Farmsteads, Mines, King's Highway Roads, Ancient Ruins)
- 10 Walk-In Enterable Interiors with PBR renders & zero-loading colliders
- Interactive 2D HTML5 Canvas Continent Radar Map
- 20 Races & Slime Evolution
All embedded via Base64 into docs/VALENCIOUS_WORLD_VIEWER.html.
"""
import os, sys, base64, shutil

ROOT = r"C:\Users\Jonna\Documents\ProjectAshes"
ACTUAL_DIR = os.path.join(ROOT, "docs", "img", "actual_renders")
BRAIN_IMG_DIR = r"C:\Users\Jonna\.gemini\antigravity\brain\3da776b7-bb83-47d1-9df4-df5aec1eeb7f\img\actual_renders"
OUT_HTML = os.path.join(ROOT, "docs", "VALENCIOUS_WORLD_VIEWER.html")
BRAIN_HTML = r"C:\Users\Jonna\.gemini\antigravity\brain\3da776b7-bb83-47d1-9df4-df5aec1eeb7f\interactive_valencious_world_viewer.html"

os.makedirs(ACTUAL_DIR, exist_ok=True)
os.makedirs(BRAIN_IMG_DIR, exist_ok=True)

def get_b64(path):
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")

def copy_and_b64(src_path, dst_filename):
    dst_path = os.path.join(ACTUAL_DIR, dst_filename)
    brain_path = os.path.join(BRAIN_IMG_DIR, dst_filename)
    if os.path.exists(dst_path):
        return get_b64(dst_path)
    if os.path.exists(src_path):
        try:
            if os.path.abspath(src_path) != os.path.abspath(dst_path):
                shutil.copy2(src_path, dst_path)
            if os.path.abspath(src_path) != os.path.abspath(brain_path):
                shutil.copy2(src_path, brain_path)
        except Exception:
            pass
        return get_b64(src_path)
    return ""

def main():
    print("Compiling Master Valencious World, Cities, Biomes, Arenas & Interiors Viewer...")

    # AAA World Panoramas & Atlas
    b64_atlas = copy_and_b64(os.path.join(ACTUAL_DIR, "valencious_world_atlas_all_regions.jpg"), "valencious_world_atlas_all_regions.jpg")
    b64_ashford_pano = copy_and_b64(os.path.join(ACTUAL_DIR, "ashford_vale_golden_hour_river_panorama.jpg"), "ashford_vale_golden_hour_river_panorama.jpg")
    b64_taiyun_pano = copy_and_b64(os.path.join(ACTUAL_DIR, "mount_taiyun_cultivation_cloud_citadel.jpg"), "mount_taiyun_cultivation_cloud_citadel.jpg")
    b64_duskbriar_pano = copy_and_b64(os.path.join(ACTUAL_DIR, "duskbriar_sacred_forest_river_shrine.jpg"), "duskbriar_sacred_forest_river_shrine.jpg")

    # Real 3D City & Settlement Models
    b64_kingsreach_keep = copy_and_b64(os.path.join(ACTUAL_DIR, "render_kingsreach_castle_keep.png"), "render_kingsreach_castle_keep.png")
    b64_kingsreach_gate = copy_and_b64(os.path.join(ACTUAL_DIR, "render_kingsreach_town_gate.png"), "render_kingsreach_town_gate.png")
    b64_ashford_sq = copy_and_b64(os.path.join(ACTUAL_DIR, "render_ashford_village_square_pbr.png"), "render_ashford_village_square_pbr.png")
    b64_ashford_st = copy_and_b64(os.path.join(ACTUAL_DIR, "render_ashford_village_street.png"), "render_ashford_village_street.png")
    b64_forest_cottage = copy_and_b64(os.path.join(ACTUAL_DIR, "render_region_forest_cottage.png"), "render_region_forest_cottage.png")
    b64_orc_hut = copy_and_b64(os.path.join(ACTUAL_DIR, "render_tuskridge_orc_hut.png"), "render_tuskridge_orc_hut.png")
    b64_arena = copy_and_b64(os.path.join(ACTUAL_DIR, "render_valencious_tournament_arena.png"), "render_valencious_tournament_arena.png")

    # Regional Sheet Sets
    b64_farm_sheet = copy_and_b64(os.path.join(ACTUAL_DIR, "render_region_farm_sheet.png"), "render_region_farm_sheet.png")
    b64_mine_sheet = copy_and_b64(os.path.join(ACTUAL_DIR, "render_region_mine_sheet.png"), "render_region_mine_sheet.png")
    b64_road_sheet = copy_and_b64(os.path.join(ACTUAL_DIR, "render_region_road_sheet.png"), "render_region_road_sheet.png")
    b64_ruins_sheet = copy_and_b64(os.path.join(ACTUAL_DIR, "render_region_ruins_sheet.png"), "render_region_ruins_sheet.png")

    # 10 Walk-In Interiors
    b64_manor = copy_and_b64(os.path.join(ACTUAL_DIR, "render_interior_noble_manor.png"), "render_interior_noble_manor.png")
    b64_trader = copy_and_b64(os.path.join(ACTUAL_DIR, "render_interior_trader_shop.png"), "render_interior_trader_shop.png")
    b64_sect = copy_and_b64(os.path.join(ACTUAL_DIR, "render_interior_wuxia_sect.png"), "render_interior_wuxia_sect.png")
    b64_orc = copy_and_b64(os.path.join(ACTUAL_DIR, "render_interior_orc_longhouse.png"), "render_interior_orc_longhouse.png")
    b64_academy = copy_and_b64(os.path.join(ACTUAL_DIR, "render_interior_academy_lab.png"), "render_interior_academy_lab.png")
    b64_inn = copy_and_b64(os.path.join(ACTUAL_DIR, "render_interior_inn_tavern.png"), "render_interior_inn_tavern.png")
    b64_smith = copy_and_b64(os.path.join(ACTUAL_DIR, "render_interior_blacksmith_forge.png"), "render_interior_blacksmith_forge.png")
    b64_guild = copy_and_b64(os.path.join(ACTUAL_DIR, "render_interior_guild_hall.png"), "render_interior_guild_hall.png")
    b64_healer = copy_and_b64(os.path.join(ACTUAL_DIR, "render_interior_healer_house.png"), "render_interior_healer_house.png")
    b64_house = copy_and_b64(os.path.join(ACTUAL_DIR, "render_enterable_cottage_interior.png"), "render_enterable_cottage_interior.png")

    # Characters & Races
    b64_darkelf = copy_and_b64(os.path.join(ACTUAL_DIR, "render_dark_elf_aaa_hero.png"), "render_dark_elf_aaa_hero.png")
    b64_races_board = copy_and_b64(os.path.join(ACTUAL_DIR, "races_and_civilizations_of_valencious.jpg"), "races_and_civilizations_of_valencious.jpg")
    b64_races_3d = copy_and_b64(os.path.join(ACTUAL_DIR, "render_races_lineup.png"), "render_races_lineup.png")
    b64_orcs_3d = copy_and_b64(os.path.join(ACTUAL_DIR, "render_orc_evolution_lineup.png"), "render_orc_evolution_lineup.png")
    b64_horse = copy_and_b64(os.path.join(ACTUAL_DIR, "render_draco_horse.png"), "render_draco_horse.png")

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Valencious World Locations, Cities, Arenas & 10 Walk-In Interiors</title>
<style>
:root {{
  --bg-primary: #0a0b10;
  --bg-secondary: #12141f;
  --bg-card: #161927;
  --accent-gold: #f59e0b;
  --accent-blue: #38bdf8;
  --accent-purple: #a855f7;
  --accent-emerald: #10b981;
  --accent-red: #ef4444;
  --text-main: #f8fafc;
  --text-muted: #94a3b8;
  --border: #282f45;
}}
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  background: var(--bg-primary);
  color: var(--text-main);
  line-height: 1.6;
}}
header {{
  background: linear-gradient(180deg, #181c2e 0%, #0a0b10 100%);
  border-bottom: 1px solid var(--border);
  padding: 20px 32px;
  position: sticky;
  top: 0;
  z-index: 100;
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 16px;
}}
.header-title h1 {{
  font-size: 24px;
  font-weight: 800;
  letter-spacing: 1px;
  background: linear-gradient(135deg, #fef08a 0%, #f59e0b 50%, #d97706 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}}
.header-title p {{
  color: var(--text-muted);
  font-size: 13px;
}}
.nav-tabs {{
  display: flex;
  gap: 8px;
  background: #0d0f18;
  padding: 6px;
  border-radius: 12px;
  border: 1px solid var(--border);
  flex-wrap: wrap;
}}
.nav-btn {{
  background: transparent;
  border: none;
  color: var(--text-muted);
  padding: 10px 16px;
  border-radius: 8px;
  cursor: pointer;
  font-weight: 600;
  font-size: 13px;
  transition: all 0.2s ease;
  display: flex;
  align-items: center;
  gap: 6px;
}}
.nav-btn:hover {{ color: var(--text-main); background: #1e2337; }}
.nav-btn.active {{
  background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
  color: #fff;
  box-shadow: 0 4px 12px rgba(37, 99, 235, 0.4);
}}
main {{
  max-width: 1440px;
  margin: 0 auto;
  padding: 28px 24px;
}}
.tab-content {{ display: none; }}
.tab-content.active {{ display: block; }}

.section-banner {{
  background: linear-gradient(135deg, rgba(30, 58, 138, 0.35) 0%, rgba(15, 23, 42, 0.8) 100%);
  border: 1px solid #1e3a8a;
  border-radius: 16px;
  padding: 24px 28px;
  margin-bottom: 28px;
}}
.section-banner h2 {{ font-size: 22px; color: var(--accent-gold); margin-bottom: 8px; }}
.section-banner p {{ color: var(--text-muted); font-size: 14px; max-width: 950px; }}

.gallery-grid {{
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(440px, 1fr));
  gap: 24px;
  margin-bottom: 32px;
}}
.gallery-card {{
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 16px;
  overflow: hidden;
  box-shadow: 0 8px 24px rgba(0,0,0,0.4);
  display: flex;
  flex-direction: column;
}}
.gallery-card img {{
  width: 100%;
  height: 320px;
  object-fit: cover;
  display: block;
  border-bottom: 1px solid var(--border);
  background: #0f121d;
}}
.card-content {{ padding: 22px; flex-grow: 1; }}
.card-tag {{
  display: inline-block;
  padding: 4px 12px;
  border-radius: 20px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  margin-bottom: 10px;
}}
.tag-gold {{ background: rgba(245, 158, 11, 0.15); color: #fbbf24; border: 1px solid rgba(245, 158, 11, 0.3); }}
.tag-emerald {{ background: rgba(16, 185, 129, 0.15); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.3); }}
.tag-purple {{ background: rgba(168, 85, 247, 0.15); color: #c084fc; border: 1px solid rgba(168, 85, 247, 0.3); }}
.tag-blue {{ background: rgba(56, 189, 248, 0.15); color: #38bdf8; border: 1px solid rgba(56, 189, 248, 0.3); }}
.tag-red {{ background: rgba(239, 68, 68, 0.15); color: #f87171; border: 1px solid rgba(239, 68, 68, 0.3); }}

.stats-badge {{
  display: flex;
  gap: 12px;
  margin: 12px 0;
  padding: 8px 12px;
  background: #0e111a;
  border-radius: 8px;
  font-size: 12px;
  font-family: monospace;
  flex-wrap: wrap;
}}
.stats-badge span {{ color: var(--accent-blue); }}

/* Interactive Map Styling */
.map-container {{
  position: relative;
  width: 100%;
  height: 600px;
  background: #06080e;
  border: 1px solid var(--border);
  border-radius: 16px;
  overflow: hidden;
  margin-bottom: 24px;
}}
#worldCanvas {{
  width: 100%;
  height: 100%;
  cursor: grab;
}}
#worldCanvas:active {{
  cursor: grabbing;
}}
.map-controls {{
  position: absolute;
  top: 16px;
  right: 16px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  z-index: 10;
}}
.map-btn {{
  background: rgba(24, 27, 42, 0.9);
  border: 1px solid var(--border);
  color: #fff;
  width: 36px;
  height: 36px;
  border-radius: 8px;
  font-size: 18px;
  font-weight: bold;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
}}
.map-btn:hover {{ background: #2e354f; }}
.map-filters {{
  position: absolute;
  bottom: 16px;
  left: 16px;
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  z-index: 10;
  background: rgba(10, 11, 16, 0.85);
  padding: 8px;
  border-radius: 12px;
  border: 1px solid var(--border);
}}
.filter-btn {{
  background: #181b2a;
  border: 1px solid var(--border);
  color: var(--text-muted);
  font-size: 12px;
  padding: 6px 12px;
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.2s;
}}
.filter-btn.active {{
  background: #2563eb;
  color: #fff;
  border-color: #3b82f6;
}}
.poi-inspector {{
  position: absolute;
  top: 16px;
  left: 16px;
  max-width: 340px;
  background: rgba(18, 20, 31, 0.95);
  border: 1px solid #3b82f6;
  border-radius: 12px;
  padding: 16px;
  box-shadow: 0 12px 32px rgba(0,0,0,0.7);
  z-index: 15;
  display: none;
}}
.poi-inspector h4 {{ color: var(--accent-gold); font-size: 16px; margin-bottom: 4px; }}
.poi-inspector p {{ font-size: 12px; color: var(--text-muted); margin-bottom: 8px; }}
.poi-meta {{ font-size: 11px; font-family: monospace; color: var(--accent-blue); }}
.close-inspector {{
  position: absolute;
  top: 8px;
  right: 10px;
  background: none;
  border: none;
  color: var(--text-muted);
  cursor: pointer;
  font-size: 16px;
}}
</style>
</head>
<body>

<header>
  <div class="header-title">
    <h1>VALENCIOUS WORLD LOCATIONS, CITIES & AAA INTERIORS</h1>
    <p>Project Ashes • 15 Regional Biomes • Real 3D PBR Renders • 10 Enterable Interiors • Grand Tournament Arenas</p>
  </div>
  <div class="nav-tabs">
    <button class="nav-btn active" onclick="switchTab('locations')">🌄 World Locations & Biomes</button>
    <button class="nav-btn" onclick="switchTab('cities3d')">🏰 3D Cities & Settlements</button>
    <button class="nav-btn" onclick="switchTab('interiors')">🚪 10 Enterable Interiors</button>
    <button class="nav-btn" onclick="switchTab('arena')">⚔️ Grand Tournament Arenas</button>
    <button class="nav-btn" onclick="switchTab('map')">🗺️ Interactive 2D Radar Map</button>
    <button class="nav-btn" onclick="switchTab('races')">🧝 20 Races & Characters</button>
    <button class="nav-btn" onclick="switchTab('future')">🏛️ Distant Historical Nations</button>
  </div>
</header>

<main>

  <!-- TAB 0: WORLD LOCATIONS & REGIONAL BIOMES -->
  <section id="tab-locations" class="tab-content active">
    <div class="section-banner">
      <h2>🌄 Valencious Continent: 15 Regional Biomes & World Landmarks</h2>
      <p>The true AAA artistic standard for the 32km Valencious continent: rolling fertile plains, meandering rivers, misty redwood forests, snowy cultivation pinnacles, bustling market squares, and fortified mountain holds.</p>
    </div>

    <!-- MASTER ATLAS HERO -->
    <div class="gallery-card" style="margin-bottom: 28px;">
      <img src="data:image/jpeg;base64,{b64_atlas}" alt="Valencious 15-Region Comprehensive Geographic Atlas" style="height: 580px; object-fit: contain; background: #060810;">
      <div class="card-content">
        <span class="card-tag tag-gold">Continental Geographic Master Atlas • 15 Distinct Biomes</span>
        <h3>Valencious Continent: Comprehensive Regional Map & Visual Panoramas</h3>
        <p>The full cartographic and photographic breakdown of the Valencious continent: <strong>Plains & Farmlands</strong>, <strong>Forests</strong>, <strong>Hills & Countryside</strong>, <strong>Northern Mountains</strong>, <strong>Rivers & Lakes</strong>, <strong>Coastal Regions</strong>, <strong>Towns & Cities</strong>, <strong>Ruins & Ancient Sites</strong>, <strong>Rift Zones</strong>, and <strong>Borderlands</strong>.</p>
        <div class="stats-badge">
          <div>Scale: <span>32,768m x 32,768m</span></div>
          <div>Macro-Sectors: <span>4,096 (512m cells)</span></div>
          <div>Biome Count: <span>15 Biomes</span></div>
          <div>Active Memory: <span>&le; 4.2 GB RAM (PC Master Spec)</span></div>
        </div>
      </div>
    </div>

    <div class="gallery-grid">
      <!-- 1. ASHFORD VALE & RIVERWAY -->
      <div class="gallery-card">
        <img src="data:image/jpeg;base64,{b64_ashford_pano}" alt="Ashford Vale Golden Hour River Panorama">
        <div class="card-content">
          <span class="card-tag tag-emerald">Central River Valley • Starting Hub</span>
          <h3>Ashford Vale & Ashrun Riverway</h3>
          <p>Lush golden hour sunlight over rolling wheat fields, water wheels turning in the snowmelt river, stone bridges crossing the Ashrun, rustic roadside taverns with red banner poles, and distant snow peaks framed in cloud mist.</p>
          <div class="stats-badge">
            <div>Coords: <span>(0, 0)</span></div>
            <div>River: <span>The Ashrun (9m width)</span></div>
            <div>Lake: <span>Emberglass Mere</span></div>
            <div>Factions: <span>Caldrenn Folk & Free Farmers</span></div>
          </div>
        </div>
      </div>

      <!-- 2. MOUNT TAIYUN CULTIVATION PEAK -->
      <div class="gallery-card">
        <img src="data:image/jpeg;base64,{b64_taiyun_pano}" alt="Mount Taiyun Cultivation Cloud Citadel">
        <div class="card-content">
          <span class="card-tag tag-blue">Wuxia / Cultivation • Northern Mountains</span>
          <h3>Mount Taiyun & Heavenly Mist Sect</h3>
          <p>Towering snowy alpine spires crowned with curved pagoda monasteries, cascading mountain waterfalls, hanging suspension rope bridges, and high contemplation terraces where Daoist disciples cultivate sword intent.</p>
          <div class="stats-badge">
            <div>Coords: <span>(0, -1400)</span></div>
            <div>Altitude: <span>2,400m+</span></div>
            <div>Institution: <span>Heavenly Mist Daoist Sect</span></div>
            <div>Interiors: <span>Sect Meditation Hall, Hermit Cave</span></div>
          </div>
        </div>
      </div>

      <!-- 3. DUSKBRIAR SACRED REDWOOD FOREST -->
      <div class="gallery-card">
        <img src="data:image/jpeg;base64,{b64_duskbriar_pano}" alt="Duskbriar Sacred Forest River Shrine">
        <div class="card-content">
          <span class="card-tag tag-purple">Deep Redwood Wilderness • Ancient Mystery</span>
          <h3>Duskbriar Wood & Sacred River Shrine</h3>
          <p>Giant ancient moss-covered redwoods draped with shimenawa ropes and wind chimes, cascading crystal mountain brooks, stone lantern waymarkers, rustic timber lodges, and the hidden Celestial Runestone grove.</p>
          <div class="stats-badge">
            <div>Coords: <span>(380, 480)</span></div>
            <div>Flora: <span>Centennial Redwoods & Spirit Moss</span></div>
            <div>Danger: <span>Moderate (Wolves, Goblins, Spirits)</span></div>
            <div>Secrets: <span>Ancient Celestial Runestone</span></div>
          </div>
        </div>
      </div>

      <!-- 4. GUNDARAK DWARVEN MAGMA RIFT -->
      <div class="gallery-card">
        <div class="card-content" style="padding-top: 28px;">
          <span class="card-tag tag-red">Subterranean Deep Realm • Volcanic Rift</span>
          <h3>Gundarak Magma Cavern & Dwarven Holds</h3>
          <p>A colossal 10km subterranean cave network beneath Mount Taiyun's basalt crust. Lit by roaring rivers of molten magma, massive steam-powered hydraulic forge hammers, stalactite fortress bastions, and runic dwarven vault doors.</p>
          <div class="stats-badge">
            <div>Coords: <span>(-1100, -1350)</span></div>
            <div>Depth: <span>-850m Subterranean</span></div>
            <div>Faction: <span>Gundarak Deep Iron Clan</span></div>
            <div>Features: <span>Magma Forges, Obsidian Armory</span></div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- TAB 1: 3D CITIES & SETTLEMENTS -->
  <section id="tab-cities3d" class="tab-content">
    <div class="section-banner">
      <h2>🏰 Real 3D Settlements & Architectural Models (Cycles PBR)</h2>
      <p>Actual 3D models placed across the 32km continent: Kingsreach Royal Fortress Keep and Gatehouse, Ashford Village Square, Medieval Market Street, Forest Enterable Cottages, and Tuskridge Orc Bastion.</p>
    </div>

    <div class="gallery-grid">
      <!-- 1. KINGSREACH KEEP -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_kingsreach_keep}" alt="Kingsreach Royal Castle Keep">
        <div class="card-content">
          <span class="card-tag tag-gold">Royal Capital • High Keep</span>
          <h3>Kingsreach Royal Fortress Keep</h3>
          <p>The central stronghold of Caldrenn. Ashlar stone masonry, 4 corner defense towers with blue conical slate roofs, royal heraldic flags, crenellated battlements, and arched portcullis entrance.</p>
          <div class="stats-badge">
            <div>Asset: <span>castle_keep.glb</span></div>
            <div>Location: <span>Kingsreach Capital (560, -420)</span></div>
            <div>Interiors: <span>Lord Aethelgard's Manor Hall</span></div>
          </div>
        </div>
      </div>

      <!-- 2. KINGSREACH GATE -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_kingsreach_gate}" alt="Kingsreach Town Gate">
        <div class="card-content">
          <span class="card-tag tag-gold">Capital Fortifications • Gatehouse</span>
          <h3>Kingsreach Fortress Gate & Curtain Wall</h3>
          <p>Twin fortified defense bastions flanking an iron-banded timber portcullis gate, arrow loops, royal heraldic banners, and high patrol walkway connecting to the city curtain wall.</p>
          <div class="stats-badge">
            <div>Asset: <span>town_gate.glb</span></div>
            <div>Clearance: <span>8.0m Wagon Archway</span></div>
            <div>Guard: <span>Caldric Royal Sentinels</span></div>
          </div>
        </div>
      </div>

      <!-- 3. ASHFORD VILLAGE SQUARE -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_ashford_sq}" alt="Ashford Village Square PBR">
        <div class="card-content">
          <span class="card-tag tag-emerald">Village Core • Active Hub</span>
          <h3>Ashford Village Square</h3>
          <p>Cobblestone marketplace surrounded by half-timbered merchant houses, stone bell tower chapel, central village stone water well, street lanterns, and produce stalls with striped awnings.</p>
          <div class="stats-badge">
            <div>Asset: <span>village_square.glb / village_well.glb</span></div>
            <div>Location: <span>Ashford Center (0, 0)</span></div>
            <div>Services: <span>Inn, Blacksmith, Trader, Bulletin</span></div>
          </div>
        </div>
      </div>

      <!-- 4. ASHFORD STREET -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_ashford_st}" alt="Ashford Village Street">
        <div class="card-content">
          <span class="card-tag tag-emerald">Market Street • 6 Distinct Buildings</span>
          <h3>Ashford Main Market Street</h3>
          <p>Six distinct architectural house variants lining the thoroughfare: slate roofs, thatch roofs, wood dormers, timber framing, flower planters, side lean-to sheds, and customer benches.</p>
          <div class="stats-badge">
            <div>Assets: <span>village_house_a/b/c/d.glb</span></div>
            <div>Interiors: <span>100% Walk-in Accessible</span></div>
            <div>LODs: <span>LOD0 & LOD1 swap at 24m</span></div>
          </div>
        </div>
      </div>

      <!-- 5. FOREST COTTAGE -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_forest_cottage}" alt="Forest Cottage & Environment">
        <div class="card-content">
          <span class="card-tag tag-purple">Rural Countryside • Enterable Cottage</span>
          <h3>Woodland Peasant Homestead</h3>
          <p>Rural slate-roof cottage situated in dense woodland of painterly oaks, Scots pines, berry bushes, mossy boulders, fallen logs, and dirt footpaths. Features enterable doorway without loading screens.</p>
          <div class="stats-badge">
            <div>Asset: <span>enterable_cottage.glb</span></div>
            <div>Foliage: <span>oak_a, pine_scots, bush_berry</span></div>
            <div>Doorway: <span>1.3m x 2.4m Open Portal</span></div>
          </div>
        </div>
      </div>

      <!-- 6. ORC BASTION HUT -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_orc_hut}" alt="Tuskridge Orc Bastion Hut">
        <div class="card-content">
          <span class="card-tag tag-red">Monster Stronghold • Tuskridge</span>
          <h3>Tuskridge Clan War Hut & Palisade</h3>
          <p>Log stockade hut with hide-covered conical timber roof, mammoth tusk doorway arch, clan war banners, bone totems, and sharpened perimeter log palisade walls.</p>
          <div class="stats-badge">
            <div>Asset: <span>orc_hut.glb / orc_palisade.glb</span></div>
            <div>Location: <span>Tuskridge Hold (300, 930)</span></div>
            <div>Interiors: <span>Tuskridge Chieftain Longhouse</span></div>
          </div>
        </div>
      </div>
    </div>

    <!-- REGIONAL DRESSING SHEETS -->
    <div class="section-banner" style="margin-top: 32px;">
      <h2>🌾 Regional Infrastructure Sets: Farms, Mines, Roads & Ruins</h2>
      <p>Modular environmental kits placed across the 32km landscape by RegionSites.plan() to populate the wilderness between cities.</p>
    </div>

    <div class="gallery-grid">
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_farm_sheet}" alt="Farmsteads Kit">
        <div class="card-content">
          <span class="card-tag tag-gold">Agriculture Kit</span>
          <h3>Farms & Windmills Set</h3>
          <p>Working agricultural structures: rotating windmill, timber barn, granary, chicken coop, pig sty, scarecrow, hay wagon, wheat and cabbage crop rows, and rail fencing.</p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_mine_sheet}" alt="Mining Kit">
        <div class="card-content">
          <span class="card-tag tag-blue">Industry Kit</span>
          <h3>Northern Mines & Rails Set</h3>
          <p>Hillside mine entrance with heavy timber bracing, mine carts on iron rails, ore piles (iron, copper, coal), head-frame winch, and miner's log hut.</p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_road_sheet}" alt="Road Infrastructure Kit">
        <div class="card-content">
          <span class="card-tag tag-emerald">Travel Kit</span>
          <h3>King's Highway Roads & Bridges</h3>
          <p>Arched stone bridges, timber trestle bridges, roadside inns, toll booths, checkpoint boom barriers, waystone shrines, and covered merchant caravan wagons.</p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_ruins_sheet}" alt="Ruins & Bandit Camps Kit">
        <div class="card-content">
          <span class="card-tag tag-red">Adventure Kit</span>
          <h3>Ancient Ruins & Wilderness Camps</h3>
          <p>Collapsed stone watchtowers, overgrown ancient shrines, bandit canvas tents, lean-tos, roaring campfires, stolen loot stashes, and goblin shaman totems.</p>
        </div>
      </div>
    </div>
  </section>

  <!-- TAB 2: 10 ENTERABLE INTERIORS -->
  <section id="tab-interiors" class="tab-content">
    <div class="section-banner">
      <h2>🚪 100% Walk-In Enterable Interiors (PC Master Tier)</h2>
      <p>Every building features custom timber/stone architecture, baked ray-cast vertex lighting, physical box colliders, walk-in doorway triggers (no loading screens), and NPC markers. Rendered with Blender 5.2 Cycles AgX Punchy.</p>
    </div>

    <div class="gallery-grid">
      <!-- 1. NOBLE MANOR -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_manor}" alt="Noble Manor Interior">
        <div class="card-content">
          <span class="card-tag tag-gold">Noble Manor • High Seat</span>
          <h3>Lord Aethelgard's Manor Hall</h3>
          <p>Grand stone-trimmed hearth with heraldic shields, crimson and sapphire wall banners, master velvet canopied bed, long feast/council table with silver chalices, scholar library alcove, and an iron-banded treasury vault.</p>
          <div class="stats-badge">
            <div>Mesh: <span>48,099 tris</span></div>
            <div>File: <span>manor_interior.tscn (6.0 MB)</span></div>
            <div>Door: <span>(0.0, 1.4m x 2.4m)</span></div>
          </div>
        </div>
      </div>

      <!-- 2. TRADER SHOP -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_trader}" alt="Trader Shop Interior">
        <div class="card-content">
          <span class="card-tag tag-emerald">Commerce • Market Town</span>
          <h3>Ashford Frontier Trading Post</h3>
          <p>L-shaped merchant sales counter with gold coins, scales, ledgers, and trade keys. Back wall lined with healing potions, elixir flasks, spice bags, apple barrels, metal strongboxes, and customer benches.</p>
          <div class="stats-badge">
            <div>Mesh: <span>61,844 tris</span></div>
            <div>File: <span>trader_interior.tscn (8.2 MB)</span></div>
            <div>Door: <span>(0.0, 1.2m x 2.2m)</span></div>
          </div>
        </div>
      </div>

      <!-- 3. WUXIA SECT -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_sect}" alt="Heavenly Mist Sect Meditation Hall">
        <div class="card-content">
          <span class="card-tag tag-blue">Wuxia / Cultivation • Mount Taiyun</span>
          <h3>Heavenly Mist Sect Meditation Hall</h3>
          <p>Raised central rush mat dais with spirit incense censer, calligraphy scripture banners, training dao/jian weapon stands, low cedar tea table with porcelain bowls, and ethereal blue-gold qi mist illumination.</p>
          <div class="stats-badge">
            <div>Mesh: <span>42,686 tris</span></div>
            <div>File: <span>sect_interior.tscn (5.4 MB)</span></div>
            <div>Door: <span>(0.0, 1.4m x 2.4m)</span></div>
          </div>
        </div>
      </div>

      <!-- 4. ORC LONGHOUSE -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_orc}" alt="Orc Chieftain Longhouse">
        <div class="card-content">
          <span class="card-tag tag-red">Monster Stronghold • Tuskridge Hold</span>
          <h3>Tuskridge Chieftain Longhouse</h3>
          <p>Rough-hewn dark timber longhouse with a massive central roaring stone fire pit and cauldron. Features the Chieftain's pelt throne, heavy timber war planning table with bronze axes, spiked shields, and grog barrels.</p>
          <div class="stats-badge">
            <div>Mesh: <span>32,258 tris</span></div>
            <div>File: <span>orc_interior.tscn (4.0 MB)</span></div>
            <div>Door: <span>(0.0, 1.6m x 2.6m)</span></div>
          </div>
        </div>
      </div>

      <!-- 5. ACADEMY LAB -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_academy}" alt="Royal Academy Magic Laboratory">
        <div class="card-content">
          <span class="card-tag tag-purple">Kingdom School • Alchemy & Arcana</span>
          <h3>Valencious Royal Academy Laboratory</h3>
          <p>Master alchemist demonstration bench with bubbling glowing brew, specimen vials, and open grimoires. Student lecture amphitheater desks, multi-tiered arcana library stacks, and arcane violet/cerulean glow.</p>
          <div class="stats-badge">
            <div>Mesh: <span>54,654 tris</span></div>
            <div>File: <span>academy_interior.tscn (7.2 MB)</span></div>
            <div>Door: <span>(0.0, 1.4m x 2.4m)</span></div>
          </div>
        </div>
      </div>

      <!-- 6. INN & TAVERN -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_inn}" alt="Village Inn Tavern Interior">
        <div class="card-content">
          <span class="card-tag tag-gold">Settlement Hub • Ashford Vale</span>
          <h3>Ashford Village Inn & Tavern</h3>
          <p>Two-story tavern hall with bar counter, ale kegs, large back stone fireplace, wagon-wheel chandeliers, and staircase leading up to the upstairs guest bedroom with curtained windows and carved oak bed.</p>
          <div class="stats-badge">
            <div>Mesh: <span>58,412 tris</span></div>
            <div>File: <span>inn_interior.tscn (6.2 MB)</span></div>
            <div>Door: <span>(-1.2, 1.4m x 2.4m)</span></div>
          </div>
        </div>
      </div>

      <!-- 7. BLACKSMITH FORGE -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_smith}" alt="Blacksmith Forge Interior">
        <div class="card-content">
          <span class="card-tag tag-red">Crafting • Master Smith</span>
          <h3>Ashford Blacksmith Forge</h3>
          <p>Deep stone hearth with glowing coals and active bellows, heavy iron anvil on oak stump, water quenching trough, tool rack wall with tongs/hammers, and finished weapon display racks.</p>
          <div class="stats-badge">
            <div>Mesh: <span>49,356 tris</span></div>
            <div>File: <span>blacksmith_interior.tscn (5.9 MB)</span></div>
            <div>Door: <span>(2.6, 1.2m x 2.2m)</span></div>
          </div>
        </div>
      </div>

      <!-- 8. GUILD HALL -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_guild}" alt="Adventurer Guild Hall Interior">
        <div class="card-content">
          <span class="card-tag tag-blue">Factions • Adventurer Guild</span>
          <h3>Valencious Adventurer Guild Hall</h3>
          <p>Grand expedition briefing hall with quest bounty boards, map tables with compasses and scrolls, trophy beast heads, weapons lockers, and guildmaster's reception desk.</p>
          <div class="stats-badge">
            <div>Mesh: <span>52,190 tris</span></div>
            <div>File: <span>guild_interior.tscn (5.2 MB)</span></div>
            <div>Door: <span>(-1.0, 1.4m x 2.4m)</span></div>
          </div>
        </div>
      </div>

      <!-- 9. HEALER HOUSE -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_healer}" alt="Healer House Interior">
        <div class="card-content">
          <span class="card-tag tag-emerald">Medicine • Rural Healer</span>
          <h3>Herbalist & Healer House</h3>
          <p>Apothecary table with mortar and pestle, hanging bundles of lavender and sage, healing salve jars, patient recuperation cot, and warm hearth fire.</p>
          <div class="stats-badge">
            <div>Mesh: <span>36,440 tris</span></div>
            <div>File: <span>healer_interior.tscn (4.0 MB)</span></div>
            <div>Door: <span>(-0.7, 1.1m x 2.1m)</span></div>
          </div>
        </div>
      </div>

      <!-- 10. PEASANT COTTAGE -->
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_house}" alt="Peasant Cottage Interior">
        <div class="card-content">
          <span class="card-tag tag-gold">Residential • Family Home</span>
          <h3>Enterable Timber Cottage Interior</h3>
          <p>Traditional rural family home with central fireplace, dining table with benches and clay mugs, double master bed, child's trundle bed, storage barrels, and woven wool rag rug.</p>
          <div class="stats-badge">
            <div>Mesh: <span>22,810 tris</span></div>
            <div>File: <span>house_interior.tscn (2.4 MB)</span></div>
            <div>Door: <span>(1.8, 1.1m x 2.1m)</span></div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- TAB 3: GRAND TOURNAMENT ARENAS -->
  <section id="tab-arena" class="tab-content">
    <div class="section-banner">
      <h2>⚔️ Valencious Grand Tournament Colosseum & Arenas</h2>
      <p>Built with procedural ashlar masonry in Blender 5.2. Integrated into Kingsreach Royal Capital and regional tournament grounds along the King's Highway. Features sand dueling pit, spectator amphitheatre tiers, the Royal Box with crimson velvet canopy, dual iron-portcullis gladiator gates, and weapon armory.</p>
    </div>

    <div class="gallery-grid">
      <!-- ARENA HERO -->
      <div class="gallery-card" style="grid-column: 1 / -1;">
        <img src="data:image/png;base64,{b64_arena}" alt="Valencious Grand Tournament Colosseum" style="height: 480px;">
        <div class="card-content">
          <span class="card-tag tag-red">Major World Landmark • Tournament Grounds</span>
          <h3>Valencious Grand Colosseum & Combat Amphitheatre</h3>
          <p>The centerpiece of military prowess and martial tournaments in Valencious. Host to the Novice Trials, Knight's Joust, Champions' Clash, and Clash of the Immortals. Features an 18m diameter sand duel ring, 4-tier spectator bleachers, royal viewing box with gold thrones, 4 perimeter battle turrets, and gladiator staging tunnels.</p>
          <div class="stats-badge">
            <div>Footprint: <span>30.8m x 30.8m</span></div>
            <div>Height: <span>20.1m</span></div>
            <div>Mesh: <span>8,575 tris</span></div>
            <div>Asset: <span>arena_colosseum.glb</span></div>
            <div>Cities: <span>Kingsreach Capital, Ashford Regional Grounds</span></div>
          </div>
        </div>
      </div>

      <!-- FIGHTERS & BRACKETS -->
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-gold">Tournament Contenders</span>
          <h3>Ranked Arena Champions</h3>
          <ul style="margin-left: 20px; color: var(--text-muted); font-size: 14px; margin-top: 10px;">
            <li><strong>Sir Gareth the Iron Wall:</strong> Royal Paladin, sword & heavy shield, 850 HP.</li>
            <li><strong>Sylas Obsidian Fang:</strong> Dark Elf Shadowblade, dual venom daggers, 680 HP.</li>
            <li><strong>Gromkar Bonecleaver:</strong> Tuskridge Orc Warlord, two-handed battle axe, 1200 HP.</li>
            <li><strong>Elder Li Tian:</strong> Heavenly Mist Cultivator, flowing jian sword, 750 HP.</li>
            <li><strong>Lady Elowen:</strong> Royal Academy Spellblade, enchanted rapier, 920 HP.</li>
            <li><strong>Drogath Stonefist:</strong> Gundarak Dwarven Magma Smith, magma warhammer, 1050 HP.</li>
          </ul>
        </div>
      </div>

      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-purple">Tournament Rules & Stakes</span>
          <h3>4-Tier Championship Progression</h3>
          <ul style="margin-left: 20px; color: var(--text-muted); font-size: 14px; margin-top: 10px;">
            <li><strong>Bronze Tier (Novice Trial):</strong> 25 gold entry • 250 gold purse • Title "Arena Challenger"</li>
            <li><strong>Silver Tier (Knight's Joust):</strong> 100 gold entry • 1,000 gold purse • Full Caldric Knight Plate</li>
            <li><strong>Gold Tier (Champions' Clash):</strong> 500 gold entry • 5,000 gold purse • Obsidian Sunblade</li>
            <li><strong>Mythic Tier (Clash of Immortals):</strong> 2,500 gold entry • 25,000 gold purse • Title "Blade of Valencious" + Crown Dragon Relic</li>
          </ul>
        </div>
      </div>
    </div>
  </section>

  <!-- TAB 4: INTERACTIVE 2D RADAR MAP -->
  <section id="tab-map" class="tab-content">
    <div class="section-banner">
      <h2>🗺️ Interactive 32km Continent Radar Map & Inspector</h2>
      <p>Pan, zoom and click on any settlement, stronghold, sect, arena, or secret cache across the 32x32km region.</p>
    </div>

    <div class="map-container">
      <canvas id="worldCanvas"></canvas>
      <div class="map-controls">
        <button class="map-btn" onclick="zoomMap(1.2)">+</button>
        <button class="map-btn" onclick="zoomMap(0.8)">-</button>
        <button class="map-btn" onclick="resetMap()" title="Reset View">⟲</button>
      </div>
      <div class="map-filters">
        <button class="filter-btn active" onclick="filterMap('all')">All Sites</button>
        <button class="filter-btn" onclick="filterMap('settlement')">Capitals & Towns</button>
        <button class="filter-btn" onclick="filterMap('arena')">Tournament Arenas</button>
        <button class="filter-btn" onclick="filterMap('monster')">Monster Strongholds</button>
        <button class="filter-btn" onclick="filterMap('sect')">Sects & Academies</button>
        <button class="filter-btn" onclick="filterMap('secret')">Hidden Secrets</button>
      </div>
      <div id="poiInspector" class="poi-inspector">
        <button class="close-inspector" onclick="closeInspector()">✕</button>
        <h4 id="poiName">Settlement</h4>
        <span id="poiTag" class="card-tag tag-gold" style="margin: 6px 0;">Capital</span>
        <p id="poiDesc">Description</p>
        <div id="poiStats" class="poi-meta">Coords: [0, 0] • Radius: 60m</div>
      </div>
    </div>
  </section>

  <!-- TAB 5: 20 RACES & CHARACTERS -->
  <section id="tab-races" class="tab-content">
    <div class="section-banner">
      <h2>🧝 Races, Factions & Evolution Systems of Valencious</h2>
      <p>Comprehensive 20-race roster, branching slime/tensura naming evolution, and 3D humanoid rigs.</p>
    </div>

    <div class="gallery-card" style="margin-bottom: 28px;">
      <img src="data:image/jpeg;base64,{b64_races_board}" alt="Races of Valencious Chart" style="height: 520px; object-fit: contain; background: #060810;">
      <div class="card-content">
        <span class="card-tag tag-gold">20 Playable & NPC Races • Complete Lore</span>
        <h3>Races of Valencious and the Wider World</h3>
        <p>Humans, Elves, Dark Elves, Dwarves, Beastkin, Half-Breeds, Aetherborn, Draken Dragonkin, Orcs, Halflings, Gnomes, Tieflings, Aasimar, Lizardfolk, Serpentkin, Avian, Spiritkin, Giants, and Undead.</p>
      </div>
    </div>

    <div class="gallery-grid">
      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_darkelf}" alt="AAA Dark Elf Hero">
        <div class="card-content">
          <span class="card-tag tag-purple">Hero Tier • Rigged</span>
          <h3>AAA Dark Elf Hero (Obsidian Blade)</h3>
          <p>High-polygon dark elf hero model in shadow leather and silver filigree armor with twin runic blades.</p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_races_3d}" alt="3D Humanoid Lineup">
        <div class="card-content">
          <span class="card-tag tag-blue">3D Humanoid Lineup</span>
          <h3>Rigged Playable Races (3D Renders)</h3>
          <p>Human paladins, high elves, dark elf rogues, orc warriors, and mountain dwarves on the UAL rig.</p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_orcs_3d}" alt="Branching Orc Evolution">
        <div class="card-content">
          <span class="card-tag tag-red">Branching Evolution</span>
          <h3>Orc Evolution Lineup (Dual-Path)</h3>
          <p>From Goblin Forager to Brutal Warlord or Shamanic Mystic with custom bone armor and tusks.</p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_horse}" alt="Draco War Horse">
        <div class="card-content">
          <span class="card-tag tag-gold">Mounts & Beasts</span>
          <h3>Armored Draco War Horse</h3>
          <p>Fully rigged heavy cavalry war mount with plate barding, saddle gear, and dynamic gallop animation.</p>
        </div>
      </div>
    </div>
  </section>

  <!-- TAB 6: DISTANT HISTORICAL NATIONS -->
  <section id="tab-future" class="tab-content">
    <div class="section-banner">
      <h2>🏛️ Blueprint: Distant Civilizations & Fantasy Realms</h2>
      <p>Architectural and visual guidelines aligned with historical cultures and fantasy donghua/anime realms for world expansion.</p>
    </div>
    <div class="gallery-grid">
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-blue">Ancient Greece / Rome</span>
          <h3>Aethelgard High Colosseum & Marble Forum</h3>
          <p>Monumental Corinthian colonnades, white pentelic marble amphitheatres, sunlit public plazas, and aqueducts spanning deep gorges.</p>
        </div>
      </div>
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-gold">Pharaonic Egypt</span>
          <h3>Osoris Sun Ziggurat & Dune Necropolis</h3>
          <p>Massive sandstone pylons, obelisks inscribed with hieroglyphs, subterranean catacombs, and gold-capped sun temples.</p>
        </div>
      </div>
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-emerald">Feudal Japan & Shinto</span>
          <h3>White Heron Citadel & Torii Water Gate</h3>
          <p>Multi-tiered curved pagoda roofs, cedar wood joinery, vermilion torii gates over reflective lotus moats, and zen rock gardens.</p>
        </div>
      </div>
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-purple">High Fantasy / Donghua</span>
          <h3>Aetheria Floating Sky Islands</h3>
          <p>Anti-gravity landmasses suspended by celestial crystal leyline cores, cascading clouds, and skyship dock towers.</p>
        </div>
      </div>
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-red">Subterranean Deep Dwarves</span>
          <h3>Gundarak Magma Cavern & Obsidian Forge</h3>
          <p>Enormous subterranean cavern city carved out of basalt, powered by roaring magma channels, giant hydraulic hammers, and rune-carved gates.</p>
        </div>
      </div>
    </div>
  </section>

</main>

<script>
function switchTab(tabId) {{
  document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-btn').forEach(el => el.classList.remove('active'));
  
  const target = document.getElementById('tab-' + tabId);
  if (target) target.classList.add('active');
  
  const btn = Array.from(document.querySelectorAll('.nav-btn')).find(b => b.getAttribute('onclick').includes(tabId));
  if (btn) btn.classList.add('active');

  if (tabId === 'map') {{
    setTimeout(initMap, 50);
  }}
}}

// ============================================================================
// INTERACTIVE CONTINENT MAP
// ============================================================================
const POIS = [
  {{ id: 'kingsreach', name: 'Kingsreach Royal Capital', kind: 'settlement', tag: 'Royal Castle-City', x: 560, z: -420, r: 175, desc: 'Fortified seat of Caldrenn. Triple stone walls, Royal Arcana Academy, Grand Colosseum, and High Council Keep.', color: '#fbbf24' }},
  {{ id: 'ashford', name: 'Ashford Village', kind: 'settlement', tag: 'River Valley Hub', x: 0, z: 0, r: 60, desc: 'Central starting village on the Ashrun. River water mill, timber houses, tavern inn, blacksmith forge, and frontier trader.', color: '#34d399' }},
  {{ id: 'arena', name: 'Valencious Grand Colosseum', kind: 'arena', tag: 'Tournament Grounds', x: 280, z: -210, r: 40, desc: 'Grand tournament amphitheatre along the King\\'s Ember Road. Host to 4-tier championship combats and royal betting.', color: '#ef4444' }},
  {{ id: 'emberglass', name: 'Emberglass Mere', kind: 'water', tag: 'Deep Lake', x: -420, z: 300, r: 90, desc: 'Still, deep glacial lake fed by snowmelt rivers. At sunset the surface turns into liquid amber fire.', color: '#38bdf8' }},
  {{ id: 'tuskridge', name: 'Tuskridge Hold', kind: 'monster', tag: 'Orc Stronghold', x: 300, z: 930, r: 50, desc: 'Sharpened log bastion and chieftain longhouse of the exiled Tuskridge clan under Chief Harrok Ashmaw.', color: '#f87171' }},
  {{ id: 'mossfang', name: 'Mossfang Warren', kind: 'monster', tag: 'Goblin Tunnels', x: 560, z: 250, r: 35, desc: 'Subterranean burrow labyrinth under Duskbriar forest roots filled with snares, scavenged loot, and goblin scouts.', color: '#fb923c' }},
  {{ id: 'taiyun', name: 'Mount Taiyun Cultivation Peak', kind: 'sect', tag: 'Daoist Sect', x: 0, z: -1400, r: 80, desc: 'Snowy alpine monastery with curved pagoda roofs, qi cultivation terraces, meditation halls, and sword training yards.', color: '#c084fc' }},
  {{ id: 'academy', name: 'Royal Academy of Arcana', kind: 'sect', tag: 'Kingdom Magic School', x: 850, z: -650, r: 65, desc: 'High spires of magical study, alchemy demonstration laboratories, runic archives, and spellblade training amphitheatre.', color: '#a855f7' }},
  {{ id: 'gundarak', name: 'Gundarak Magma Cavern', kind: 'secret', tag: 'Dwarven Portal', x: -1100, z: -1350, r: 55, desc: 'Carved basalt gateway leading to the deep volcanic magma caverns and legendary dwarven blacksmith halls.', color: '#f97316' }},
  {{ id: 'aetheria', name: 'Aetheria Sky Islands', kind: 'sect', tag: 'Floating Islands', x: 1300, z: -1100, r: 70, desc: 'Suspended celestial sky landmasses floating above the clouds, anchored by ancient crystal leylines.', color: '#60a5fa' }},
  {{ id: 'cove', name: 'Smuggler\\'s Hidden Cove', kind: 'secret', tag: 'Hidden Water Cache', x: -460, z: 340, r: 25, desc: 'Secret cavern behind the Emberglass waterfall concealing contraband gems, stolen manifests, and escape boat.', color: '#10b981' }},
  {{ id: 'runestone', name: 'Celestial Runestone Grove', kind: 'secret', tag: 'Ancient Ward', x: 410, z: 520, r: 25, desc: 'Glowing ancient monolith inside Duskbriar Wood radiating mystical qi and surrounded by luminous spirit flora.', color: '#818cf8' }},
  {{ id: 'hermit', name: 'Daoist Hermit Sanctuary', kind: 'secret', tag: 'Cultivation Cache', x: -50, z: -1650, r: 20, desc: 'Secluded pinnacle terrace above the cloudline where an ancient master left legendary cultivation manuals.', color: '#e879f9' }},
  {{ id: 'strongbox', name: 'Bandit Lord Strongbox', kind: 'secret', tag: 'Buried Vault', x: 720, z: 110, r: 20, desc: 'Stone trapdoor hidden under watchtower rubble leading to a cellar with weapons, gold bars, and regional charts.', color: '#facc15' }},
  {{ id: 'cinderpost', name: 'Cinderpost Waystation', kind: 'settlement', tag: 'Highway Waystation', x: 288, z: -199, r: 25, desc: 'Walled halfway outpost with horse stables, bunkhouse, and royal bulletin board on the King\\'s Ember Road.', color: '#94a3b8' }}
];

let canvas, ctx;
let mapScale = 0.16;
let mapOffsetX = 0;
let mapOffsetY = 0;
let isDragging = false;
let startX, startY;
let activeFilter = 'all';

function initMap() {{
  canvas = document.getElementById('worldCanvas');
  if (!canvas) return;
  const rect = canvas.parentElement.getBoundingClientRect();
  canvas.width = rect.width;
  canvas.height = rect.height;
  ctx = canvas.getContext('2d');
  
  mapOffsetX = canvas.width / 2;
  mapOffsetY = canvas.height / 2 + 50;
  
  canvas.onmousedown = (e) => {{
    isDragging = true;
    startX = e.clientX - mapOffsetX;
    startY = e.clientY - mapOffsetY;
  }};
  window.onmousemove = (e) => {{
    if (!isDragging) return;
    mapOffsetX = e.clientX - startX;
    mapOffsetY = e.clientY - startY;
    drawMap();
  }};
  window.onmouseup = () => {{ isDragging = false; }};
  canvas.onwheel = (e) => {{
    e.preventDefault();
    const factor = e.deltaY < 0 ? 1.15 : 0.85;
    mapScale = Math.max(0.04, Math.min(1.2, mapScale * factor));
    drawMap();
  }};
  canvas.onclick = handleMapClick;
  
  drawMap();
}}

function drawMap() {{
  if (!ctx) return;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  
  ctx.fillStyle = '#080a14';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  
  ctx.save();
  ctx.translate(mapOffsetX, mapOffsetY);
  ctx.scale(mapScale, mapScale);
  
  // Continent Landmass
  ctx.fillStyle = '#141c2b';
  ctx.strokeStyle = '#1e2e4a';
  ctx.lineWidth = 4 / mapScale;
  ctx.beginPath();
  ctx.ellipse(0, -200, 1800, 1600, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();
  
  // Mountains
  ctx.fillStyle = '#1e2638';
  ctx.beginPath();
  ctx.ellipse(0, -1200, 1300, 450, 0, 0, Math.PI * 2);
  ctx.fill();
  
  // Roads
  ctx.strokeStyle = '#64748b';
  ctx.lineWidth = 6;
  ctx.setLineDash([8, 6]);
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.lineTo(288, -199);
  ctx.lineTo(560, -420);
  ctx.stroke();
  
  // River
  ctx.strokeStyle = '#0284c7';
  ctx.lineWidth = 14;
  ctx.setLineDash([]);
  ctx.beginPath();
  ctx.moveTo(-150, -900);
  ctx.bezierCurveTo(-250, -400, -330, -150, -400, 220);
  ctx.lineTo(-420, 300);
  ctx.bezierCurveTo(-600, 500, -1000, 800, -1500, 1200);
  ctx.stroke();
  
  // Lake
  ctx.fillStyle = '#0369a1';
  ctx.beginPath();
  ctx.arc(-420, 300, 95, 0, Math.PI * 2);
  ctx.fill();
  
  // POIs
  const filtered = POIS.filter(p => activeFilter === 'all' || p.kind === activeFilter);
  
  filtered.forEach(p => {{
    ctx.strokeStyle = p.color;
    ctx.lineWidth = 2 / mapScale;
    ctx.beginPath();
    ctx.arc(p.x, p.z, p.r * 0.8, 0, Math.PI * 2);
    ctx.stroke();
    
    ctx.fillStyle = p.color;
    ctx.beginPath();
    ctx.arc(p.x, p.z, Math.max(8, p.r * 0.25), 0, Math.PI * 2);
    ctx.fill();
    
    ctx.fillStyle = '#f1f5f9';
    ctx.font = `bold ${{Math.max(12, 14 / mapScale)}}px 'Segoe UI', sans-serif`;
    ctx.textAlign = 'center';
    ctx.fillText(p.name, p.x, p.z - (p.r * 0.8 + 8 / mapScale));
  }});
  
  ctx.restore();
}}

function zoomMap(factor) {{
  mapScale = Math.max(0.04, Math.min(1.2, mapScale * factor));
  drawMap();
}}

function resetMap() {{
  mapScale = 0.16;
  mapOffsetX = canvas.width / 2;
  mapOffsetY = canvas.height / 2 + 50;
  drawMap();
}}

function filterMap(category) {{
  activeFilter = category;
  document.querySelectorAll('.filter-btn').forEach(btn => btn.classList.remove('active'));
  event.currentTarget.classList.add('active');
  drawMap();
}}

function handleMapClick(e) {{
  const rect = canvas.getBoundingClientRect();
  const mouseX = e.clientX - rect.left;
  const mouseY = e.clientY - rect.top;
  
  const worldX = (mouseX - mapOffsetX) / mapScale;
  const worldZ = (mouseY - mapOffsetY) / mapScale;
  
  let closest = null;
  let minDist = 40 / mapScale;
  
  POIS.forEach(p => {{
    const dist = Math.hypot(p.x - worldX, p.z - worldZ);
    if (dist < minDist) {{
      minDist = dist;
      closest = p;
    }}
  }});
  
  if (closest) {{
    showInspector(closest);
  }} else {{
    closeInspector();
  }}
}}

function showInspector(poi) {{
  const inspector = document.getElementById('poiInspector');
  document.getElementById('poiName').innerText = poi.name;
  document.getElementById('poiTag').innerText = poi.tag;
  document.getElementById('poiDesc').innerText = poi.desc;
  document.getElementById('poiStats').innerText = `World Coords: [${{poi.x.toFixed(0)}}, ${{poi.z.toFixed(0)}}] • Radius: ${{poi.r}}m`;
  inspector.style.display = 'block';
}}

function closeInspector() {{
  document.getElementById('poiInspector').style.display = 'none';
}}

window.addEventListener('load', () => {{
  initMap();
}});
window.addEventListener('resize', () => {{
  if (canvas) initMap();
}});
</script>

</body>
</html>
"""
    with open(OUT_HTML, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Wrote {OUT_HTML} ({len(html)} bytes)")

    with open(BRAIN_HTML, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Wrote {BRAIN_HTML}")

if __name__ == "__main__":
    main()
