"""Comprehensive World, Interiors, Tournament Arenas and Hidden Secrets Viewer Generator for Project Ashes.
Injects all 10 enterable interiors, the Grand Tournament Colosseum, hidden secret caches,
races lineup, orc evolution, dark elf hero, ashford village square, 32km regional map,
and historical kingdoms blueprint into docs/VALENCIOUS_WORLD_VIEWER.html with full Base64 embeds.
"""
import os, sys, base64, shutil

ROOT = r"C:\Users\Jonna\Documents\ProjectAshes"
PREV_DIR = os.path.join(ROOT, "docs", "kingdom", "blender_previews")
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
    print("Building Comprehensive Valencious World, Arena & Secrets Showcase HTML...")
    
    # Interiors
    b64_manor = copy_and_b64(os.path.join(PREV_DIR, "interior_manor_a.png"), "render_interior_noble_manor.png")
    b64_trader = copy_and_b64(os.path.join(PREV_DIR, "interior_trader_a.png"), "render_interior_trader_shop.png")
    b64_sect = copy_and_b64(os.path.join(PREV_DIR, "interior_sect_a.png"), "render_interior_wuxia_sect.png")
    b64_orc = copy_and_b64(os.path.join(PREV_DIR, "interior_orc_a.png"), "render_interior_orc_longhouse.png")
    b64_academy = copy_and_b64(os.path.join(PREV_DIR, "interior_academy_a.png"), "render_interior_academy_lab.png")
    
    b64_inn = copy_and_b64(os.path.join(PREV_DIR, "interior_inn_a.png"), "render_interior_inn_tavern.png")
    b64_smith = copy_and_b64(os.path.join(PREV_DIR, "interior_blacksmith_a.png"), "render_interior_blacksmith_forge.png")
    b64_guild = copy_and_b64(os.path.join(PREV_DIR, "interior_guild_a.png"), "render_interior_guild_hall.png")
    b64_healer = copy_and_b64(os.path.join(PREV_DIR, "interior_healer_a.png"), "render_interior_healer_house.png")
    b64_house = copy_and_b64(os.path.join(PREV_DIR, "interior_house_a.png"), "render_enterable_cottage_interior.png")
    
    # Arena & Landmarks
    b64_arena = copy_and_b64(os.path.join(PREV_DIR, "arena_colosseum_a.png"), "render_valencious_tournament_arena.png")
    
    # Heroes & World
    b64_darkelf = copy_and_b64(os.path.join(ACTUAL_DIR, "render_dark_elf_aaa_hero.png"), "render_dark_elf_aaa_hero.png")
    b64_races = copy_and_b64(os.path.join(ACTUAL_DIR, "render_races_lineup.png"), "render_races_lineup.png")
    b64_orcs = copy_and_b64(os.path.join(ACTUAL_DIR, "render_orc_evolution_lineup.png"), "render_orc_evolution_lineup.png")
    b64_horse = copy_and_b64(os.path.join(ACTUAL_DIR, "render_draco_horse.png"), "render_draco_horse.png")
    b64_square = copy_and_b64(os.path.join(ACTUAL_DIR, "render_ashford_village_square.png"), "render_ashford_village_square.png")
    b64_map = copy_and_b64(os.path.join(ACTUAL_DIR, "render_ashford_vale_regional_map.png"), "render_ashford_vale_regional_map.png")
    b64_cottage_ext = copy_and_b64(os.path.join(ACTUAL_DIR, "render_enterable_cottage_exterior.png"), "render_enterable_cottage_exterior.png")

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Valencious 32km World, Arenas & AAA 3D Interiors</title>
<style>
:root {{
  --bg-primary: #0a0b10;
  --bg-secondary: #12141f;
  --bg-card: #181b2a;
  --accent-gold: #f59e0b;
  --accent-blue: #38bdf8;
  --accent-purple: #a855f7;
  --accent-emerald: #10b981;
  --accent-red: #ef4444;
  --text-main: #f1f5f9;
  --text-muted: #94a3b8;
  --border: #2e354f;
}}
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  background: var(--bg-primary);
  color: var(--text-main);
  line-height: 1.6;
}}
header {{
  background: linear-gradient(180deg, #16192b 0%, #0a0b10 100%);
  border-bottom: 1px solid var(--border);
  padding: 24px 32px;
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
  font-size: 26px;
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
  padding: 10px 18px;
  border-radius: 8px;
  cursor: pointer;
  font-weight: 600;
  font-size: 14px;
  transition: all 0.2s ease;
  display: flex;
  align-items: center;
  gap: 8px;
}}
.nav-btn:hover {{ color: var(--text-main); background: #1e2337; }}
.nav-btn.active {{
  background: linear-gradient(135deg, #3b82f6 0%, #1d4ed8 100%);
  color: #fff;
  box-shadow: 0 4px 12px rgba(37, 99, 235, 0.35);
}}
main {{
  max-width: 1440px;
  margin: 0 auto;
  padding: 32px 24px;
}}
.tab-content {{ display: none; }}
.tab-content.active {{ display: block; }}

.section-banner {{
  background: linear-gradient(135deg, rgba(30, 58, 138, 0.4) 0%, rgba(15, 23, 42, 0.8) 100%);
  border: 1px solid #1e3a8a;
  border-radius: 16px;
  padding: 24px 28px;
  margin-bottom: 32px;
}}
.section-banner h2 {{ font-size: 22px; color: var(--accent-gold); margin-bottom: 8px; }}
.section-banner p {{ color: var(--text-muted); font-size: 14px; max-width: 900px; }}

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
  background: #0f121d;
  border-radius: 8px;
  font-size: 12px;
  font-family: monospace;
}}
.stats-badge span {{ color: var(--accent-blue); }}
</style>
</head>
<body>

<header>
  <div class="header-title">
    <h1>VALENCIOUS 32KM WORLD, ARENAS & AAA INTERIORS</h1>
    <p>Project Ashes • Blender 5.2 Cycles PBR Renders • Grand Tournament Arenas • 10 Enterable Interiors • Hidden Secrets</p>
  </div>
  <div class="nav-tabs">
    <button class="nav-btn active" onclick="switchTab('arena')">⚔️ Grand Tournament Arenas</button>
    <button class="nav-btn" onclick="switchTab('interiors')">🏰 Enterable 3D Interiors</button>
    <button class="nav-btn" onclick="switchTab('secrets')">🗝️ Hidden Secrets & Dungeons</button>
    <button class="nav-btn" onclick="switchTab('actual3d')">📸 Hero Models & Ashford</button>
    <button class="nav-btn" onclick="switchTab('future')">🏛️ Distant Historical Nations</button>
  </div>
</header>

<main>

  <!-- TAB 0: TOURNAMENT ARENAS -->
  <section id="tab-arena" class="tab-content active">
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
          <p>The centerpiece of military prowess and martial tournaments in Valencious. Host to the Novice Trials, Knight's Joust, Champions' Clash, and Clash of the Immortals. Features a 18m diameter sand duel ring, 4-tier spectator bleachers, royal viewing box with gold thrones, 4 perimeter battle turrets, and gladiator staging tunnels.</p>
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

  <!-- TAB 1: ENTERABLE 3D INTERIORS -->
  <section id="tab-interiors" class="tab-content">
    <div class="section-banner">
      <h2>🏰 100% Walk-In Enterable Interiors (PC Master Tier)</h2>
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

  <!-- TAB 2: HIDDEN SECRETS & DUNGEONS -->
  <section id="tab-secrets" class="tab-content">
    <div class="section-banner">
      <h2>🗝️ Hidden Secrets, Caches & Subterranean Dungeons</h2>
      <p>Hidden throughout the 32x32km Valencious wilderness for players to discover through exploration, quest rumors, and environmental clues.</p>
    </div>
    <div class="gallery-grid">
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-emerald">Water Secret • Hidden Cove</span>
          <h3>Smuggler's Cove & Waterfall Cache</h3>
          <p>Concealed behind the roaring waterfall cascade on Emberglass Mere. Contains waterlogged iron-banded chests with illicit smuggled gemstones, stolen Caldric customs manifests, and a rowboat dock.</p>
        </div>
      </div>
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-blue">Arcane Mystery • Deep Woods</span>
          <h3>Ancient Celestial Runestone Grove</h3>
          <p>Hidden deep within the heart of Duskbriar Wood where the forest canopy blocks the sun. A glowing cyan runestone pulsating with celestial mana, surrounded by rare spirit herbs and glowing butterflies.</p>
        </div>
      </div>
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-red">Subterranean Dungeon • Northern Crags</span>
          <h3>Gundarak Dwarven Magma Portal</h3>
          <p>Carved directly into the volcanic basalt cliff-face of Mount Taiyun. An ancient stone gate surrounded by runic ward stones, leading down into the subterranean magma forges and deep dwarven realm.</p>
        </div>
      </div>
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-purple">Wuxia Cultivation • Mountain Peak</span>
          <h3>Hermit Daoist Cultivation Sanctuary</h3>
          <p>A secluded stone terrace perched on an inaccessible pinnacle above the cloud line. Features an ancient stone meditation slab, cedar tea table, and scrolls containing forgotten martial arts cultivation manuals.</p>
        </div>
      </div>
      <div class="gallery-card">
        <div class="card-content">
          <span class="card-tag tag-gold">Ruins Cache • Watchtower Vault</span>
          <h3>Buried Bandit Lord Strongbox</h3>
          <p>Underneath the rubble and timber debris of the Old Watchtower knoll lies a hidden stone trapdoor into an underground smuggler cellar with weapons, gold bars, and regional map markings.</p>
        </div>
      </div>
    </div>
  </section>

  <!-- TAB 3: HERO MODELS & ASHFORD -->
  <section id="tab-actual3d" class="tab-content">
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
        <img src="data:image/png;base64,{b64_races}" alt="20 Races Lineup">
        <div class="card-content">
          <span class="card-tag tag-gold">20 Playable & NPC Races</span>
          <h3>Comprehensive Races Lineup</h3>
          <p>Full 3D rigged humanoid lineup across Humans, High Elves, Dark Elves, Orcs, Dwarves, Beastkin, and Dragonkin.</p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_orcs}" alt="Orc Evolution Lineup">
        <div class="card-content">
          <span class="card-tag tag-red">Branching Evolution</span>
          <h3>Orc Evolution Lineup (Dual-Path)</h3>
          <p>From Goblin Forager to Brutal Warlord or Shamanic Mystic with custom bone armor and tusks.</p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_square}" alt="Ashford Village Square">
        <div class="card-content">
          <span class="card-tag tag-emerald">World Hub • Ashford</span>
          <h3>Ashford Village Square (PBR Ground View)</h3>
          <p>Active settlement with stone well, marketplace stalls, timber houses, and perimeter palisade walls.</p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="data:image/png;base64,{b64_map}" alt="Valencious Regional Map">
        <div class="card-content">
          <span class="card-tag tag-blue">32km Continent</span>
          <h3>Ashford Vale & 32km Regional Map</h3>
          <p>High-altitude cartographic render of the 32x32km Valencious continent showing rivers, valleys, roads and biomes.</p>
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

  <!-- TAB 4: DISTANT HISTORICAL NATIONS -->
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
  
  event.currentTarget.classList.add('active');
}}
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
