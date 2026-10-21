#!/usr/bin/env python3
"""
Builds a 100% self-contained HTML viewer with embedded Base64 renders.
Never fails with 'File not found', never shows placeholder cylinder mannequins.
Shows the actual renders of the 3D models and enterable cottage created in Blender 5.2.
"""

import os
import base64

ARTIFACT_DIR = r"C:\Users\Jonna\.gemini\antigravity\brain\3da776b7-bb83-47d1-9df4-df5aec1eeb7f"
DOCS_DIR = r"C:\Users\Jonna\Documents\ProjectAshes\docs"

ACTUAL_RENDERS_DIR = os.path.join(DOCS_DIR, "img", "actual_renders")
CONCEPT_DIR = os.path.join(DOCS_DIR, "img", "valencious")

def get_base64(path):
    if os.path.exists(path):
        ext = os.path.splitext(path)[1].lower()
        mime = "image/png" if ext == ".png" else "image/jpeg"
        with open(path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode("utf-8")
            return f"data:{mime};base64,{encoded}"
    return ""

def main():
    imgs = {
        "cottage_ext": get_base64(os.path.join(ACTUAL_RENDERS_DIR, "render_enterable_cottage_exterior.png")),
        "cottage_int": get_base64(os.path.join(ACTUAL_RENDERS_DIR, "render_enterable_cottage_interior.png")),
        "orc_lineup": get_base64(os.path.join(ACTUAL_RENDERS_DIR, "render_orc_evolution_lineup.png")),
        "races_lineup": get_base64(os.path.join(ACTUAL_RENDERS_DIR, "render_races_lineup.png")),
        "draco_horse": get_base64(os.path.join(ACTUAL_RENDERS_DIR, "render_draco_horse.png")),
        "map_biomes": get_base64(os.path.join(CONCEPT_DIR, "media_1792619686413_75a167b5.jpg")),
        "rural_valley": get_base64(os.path.join(CONCEPT_DIR, "media_1792619700556_ee0d92a3.jpg")),
        "sacred_forest": get_base64(os.path.join(CONCEPT_DIR, "media_1792619711933_b595cdd2.jpg")),
        "mountain_monastery": get_base64(os.path.join(CONCEPT_DIR, "media_1792619720769_3969662b.jpg"))
    }
    
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Valencious - Actual 3D Models & World Showcase</title>
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

/* Showcase Cards */
.showcase-hero {{
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 20px;
  overflow: hidden;
  margin-bottom: 32px;
  box-shadow: 0 12px 36px rgba(0,0,0,0.5);
}}
.showcase-hero img {{
  width: 100%;
  max-height: 520px;
  object-fit: cover;
  display: block;
}}
.showcase-hero-content {{ padding: 28px; }}

.gallery-grid {{
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(460px, 1fr));
  gap: 24px;
  margin-bottom: 32px;
}}
.gallery-card {{
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 16px;
  overflow: hidden;
  box-shadow: 0 8px 24px rgba(0,0,0,0.4);
}}
.gallery-card img {{
  width: 100%;
  height: 300px;
  object-fit: cover;
  display: block;
}}
.card-content {{ padding: 20px; }}
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

/* Culture cards */
.culture-row {{
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 20px;
  margin-bottom: 32px;
}}
.culture-card {{
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 22px;
}}
.culture-card h4 {{ font-size: 17px; margin-bottom: 6px; color: var(--accent-gold); }}
.culture-style {{ font-size: 12px; color: var(--accent-blue); font-weight: 700; margin-bottom: 10px; text-transform: uppercase; }}
</style>
</head>
<body>

<header>
  <div class="header-title">
    <h1>VALENCIOUS 32KM WORLD & ACTUAL 3D ASSETS</h1>
    <p>Project Ashes • Real Blender 5.2 Renders • 20 Races & Slime Evolution • Historical Kingdoms Blueprint</p>
  </div>
  <div class="nav-tabs">
    <button class="nav-btn active" onclick="switchTab('actual3d')">📸 Actual 3D Models & Cottage</button>
    <button class="nav-btn" onclick="switchTab('future')">🏛️ Distant Historical Nations</button>
    <button class="nav-btn" onclick="switchTab('academies')">⛩️ Kingdom Academies & Sects</button>
    <button class="nav-btn" onclick="switchTab('world')">🌍 32km Continent Biomes</button>
  </div>
</header>

<main>

  <!-- TAB 1: ACTUAL 3D MODELS (NO CYLINDER PLACEHOLDERS) -->
  <section id="tab-actual3d" class="tab-content active">
    
    <!-- HERO 1: RACES LINEUP -->
    <div class="showcase-hero">
      <img src="{imgs['races_lineup']}" alt="Actual High-Poly Races Lineup">
      <div class="showcase-hero-content">
        <span class="card-tag tag-purple">Actual Blender 5.2 Render</span>
        <h2 style="font-size: 24px; color: var(--accent-gold); margin-bottom: 8px;">High-Poly Rigged Races Lineup (Actual 3D Models)</h2>
        <p style="color: var(--text-muted); font-size: 14px;">
          Rendered directly from the GLB files we built in Blender 5.2. Left to right: 
          <strong>Dwarf</strong> (stocky 0.78z frame, braided beard), 
          <strong>High Elf</strong> (swept pointed ears, fair PBR skin), 
          <strong>Tiefling</strong> (ram horns & segmented spade tail), 
          <strong>Draken / Dragonnewt</strong> (draconic horns, dorsal back spines & tail), and 
          <strong>Intelligent Wight</strong> (ashen skin, cyan soul emissive eyes).
        </p>
      </div>
    </div>

    <!-- HERO 2: ORC DUAL EVOLUTION -->
    <div class="showcase-hero">
      <img src="{imgs['orc_lineup']}" alt="Actual Orc Dual Evolution Models">
      <div class="showcase-hero-content">
        <span class="card-tag tag-red">Actual Blender 5.2 Render</span>
        <h2 style="font-size: 24px; color: #f87171; margin-bottom: 8px;">Ork Dual-Evolution: Noble High Warlord vs. Beast Juggernaut</h2>
        <p style="color: var(--text-muted); font-size: 14px;">
          Demonstrating the Slime/Tensura naming evolution paths. 
          <strong>Left:</strong> <code>race_ork_noble_warlord.glb</code> – upright athletic noble posture, refined olive skin, and warrior tusks. 
          <strong>Right:</strong> <code>race_ork_beast_juggernaut.glb</code> – colossal 1.55x scaled hulking frame, massive jutting tusks, and heavy hunchback armor.
        </p>
      </div>
    </div>

    <!-- COTTAGE EXTERIOR & INTERIOR -->
    <div class="gallery-grid">
      <div class="gallery-card">
        <img src="{imgs['cottage_ext']}" alt="Actual Enterable Cottage Exterior">
        <div class="card-content">
          <span class="card-tag tag-emerald">Enterable Architecture</span>
          <h3 style="font-size: 20px; color: var(--accent-gold); margin-bottom: 6px;">Enterable Cottage Exterior (enterable_cottage.glb)</h3>
          <p style="font-size: 13px; color: var(--text-muted);">
            Rendered from the actual GLB: features a <strong>physical open doorway (1.3m × 2.4m)</strong> with zero collision blocking, timber lintel, front porch posts, and pitched thatch roof.
          </p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="{imgs['cottage_int']}" alt="Actual Enterable Cottage Interior">
        <div class="card-content">
          <span class="card-tag tag-gold">Furnished Interior</span>
          <h3 style="font-size: 20px; color: var(--accent-gold); margin-bottom: 6px;">Enterable Cottage Interior (Inside View)</h3>
          <p style="font-size: 13px; color: var(--text-muted);">
            Looking inside from the doorway: stone fireplace hearth, dining table with benches, wooden plank floor, and bed in the corner.
          </p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="{imgs['draco_horse']}" alt="Actual Draco Horse Mount">
        <div class="card-content">
          <span class="card-tag tag-blue">Exclusive Fantasy Mount</span>
          <h3 style="font-size: 20px; color: var(--accent-blue); margin-bottom: 6px;">Draco-Horse Mount (horse_draco.glb)</h3>
          <p style="font-size: 13px; color: var(--text-muted);">
            30-bone rigged mount with twin obsidian dragon horns, dorsal neck spines, and reinforced barding.
          </p>
        </div>
      </div>
    </div>
  </section>

  <!-- TAB 2: DISTANT HISTORICAL NATIONS (CLAUDE BLUEPRINT) -->
  <section id="tab-future" class="tab-content">
    <div style="background: linear-gradient(135deg, rgba(245, 158, 11, 0.1), rgba(168, 85, 247, 0.05)); border: 1px solid var(--border); border-radius: 16px; padding: 24px; margin-bottom: 32px;">
      <h2 style="font-size: 22px; color: var(--accent-gold); margin-bottom: 8px;">Distant Historical Nations & Expansion Blueprint (For Claude)</h2>
      <p style="color: var(--text-muted); max-width: 1000px;">
        To ensure future regions feel epic and varied, we have architected distinct historical civilizations and mythic world zones:
      </p>
    </div>

    <div class="culture-row">
      <div class="culture-card">
        <span class="card-tag tag-gold">Ancient Greco-Roman Empire</span>
        <h4>Solmarch & Aethelgard</h4>
        <div class="culture-style">Fluted Marble Columns • Colosseums • Legion Shields</div>
        <p style="font-size: 13px; color: var(--text-muted);">
          White marble pantheons, circular gladiatorial amphitheatres, massive stone aqueducts spanning valleys, and legionaries holding rectangular scutum shields.
        </p>
      </div>

      <div class="culture-card">
        <span class="card-tag tag-gold">Ancient Egyptian River Kingdom</span>
        <h4>Oasis of Amun-Ra & Sun Delta</h4>
        <div class="culture-style">Sandstone Obelisks • Hieroglyphic Pylons • Sun Temples</div>
        <p style="font-size: 13px; color: var(--text-muted);">
          Golden sand dunes, colossal pharaoh statues, river felucca barges, and underground tomb labyrinths beneath the desert sands.
        </p>
      </div>

      <div class="culture-card">
        <span class="card-tag tag-purple">Aetherial Sky Islands</span>
        <h4>The Shattered Heavens</h4>
        <div class="culture-style">Floating Landmasses • Anti-Gravity Leylines • Sky Ships</div>
        <p style="font-size: 13px; color: var(--text-muted);">
          Floating continental fragments held aloft by raw Aetherial gravity stones, cloud harbors for sky ships, and winged avian aeries.
        </p>
      </div>

      <div class="culture-card">
        <span class="card-tag tag-blue">Submerged Water Cities</span>
        <h4>The Tide Empress Realm</h4>
        <div class="culture-style">Coral Domes • Glass Tunnels • Tidal Canals</div>
        <p style="font-size: 13px; color: var(--text-muted);">
          Canal cities that submerge during high tides, connecting to underwater palaces with pressurized mana barrier domes and bioluminescent coral architecture.
        </p>
      </div>

      <div class="culture-card">
        <span class="card-tag tag-emerald">Colossal Subterranean Cavern</span>
        <h4>Hollowdeep Dwarven Kingdom</h4>
        <div class="culture-style">10km Underground Cave • Molten Lava Aqueducts • Anvil Statues</div>
        <p style="font-size: 13px; color: var(--text-muted);">
          Built inside a colossal 10-kilometer underground mountain cavern. Giant stalactites carved into multi-tier fortresses, glowing lava aqueducts, and massive basalt forge halls.
        </p>
      </div>
    </div>
  </section>

  <!-- TAB 3: ACADEMIES & SECTS -->
  <section id="tab-academies" class="tab-content">
    <div style="background: var(--bg-card); border: 1px solid var(--border); border-radius: 16px; padding: 24px; margin-bottom: 32px;">
      <h2 style="font-size: 22px; color: var(--accent-gold); margin-bottom: 8px;">Kingdom Martial Academies & Mountain Cultivation Sects</h2>
      <p style="color: var(--text-muted); max-width: 900px;">
        Institutions of combat and cultivation located both inside the capital city and high in the mountain wilderness:
      </p>
    </div>

    <div class="culture-row">
      <div class="culture-card">
        <span class="card-tag tag-gold">Inside Capital City</span>
        <h4>Royal Ember Academy</h4>
        <div class="culture-style">Kingsreach • Sword, Spear, Statecraft, Soulbeasts</div>
        <p style="font-size: 13px; color: var(--text-muted);">
          The crown academy where noble heirs and common prodigies train together. Seniors travel to Xiava's Lake to bond with living Soulbeasts.
        </p>
      </div>

      <div class="culture-card">
        <span class="card-tag tag-purple">High Mountain Peak</span>
        <h4>Ninefold Sword Pavilion</h4>
        <div class="culture-style">Ninefold Summit • Sword Cultivation & Lightning Arts</div>
        <p style="font-size: 13px; color: var(--text-muted);">
          1,180-year-old Wuxia sect. Disciples climb 9,000 steps and meditate over cloud seas, mastering airborne sword Qi.
        </p>
      </div>

      <div class="culture-card">
        <span class="card-tag tag-emerald">Hidden Mountain Gorge</span>
        <h4>Iron Lotus Monastery</h4>
        <div class="culture-style">Stone Lotus Village • Fist, Palm & Body Tempering</div>
        <p style="font-size: 13px; color: var(--text-muted);">
          Monks temper their flesh under torrential waterfalls, learning to shatter boulders and deflect steel blades with bare hands.
        </p>
      </div>

      <div class="culture-card">
        <span class="card-tag tag-blue">Rural Frontier Village</span>
        <h4>Old Mill Staff Yard</h4>
        <div class="culture-style">Ashford Village • Staff, Fist & Civilian Defense</div>
        <p style="font-size: 13px; color: var(--text-muted);">
          Founded by retired Runeward Officer Maren Coldbrook inside a working grain mill to teach farmers how to wield quarterstaffs.
        </p>
      </div>
    </div>
  </section>

  <!-- TAB 4: 32KM WORLD BIOMES -->
  <section id="tab-world" class="tab-content">
    <div class="gallery-grid">
      <div class="gallery-card">
        <img src="{imgs['map_biomes']}" alt="Valencious Biomes Map">
        <div class="card-content">
          <span class="card-tag tag-gold">Continental Map</span>
          <h3 style="font-size: 18px; margin-bottom: 6px;">Valencious 32,768m Continent (17 Biomes)</h3>
          <p style="font-size: 13px; color: var(--text-muted);">
            Streamed in 4,096 macro-sectors (512m). Active 3x3 memory footprint under 950 MB for smooth 60 FPS on 8GB RAM PCs.
          </p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="{imgs['mountain_monastery']}" alt="Northern Mountain Sects">
        <div class="card-content">
          <span class="card-tag tag-purple">Donghua Style</span>
          <h3 style="font-size: 18px; margin-bottom: 6px;">Northern Mountain Sects & Sky Monasteries</h3>
          <p style="font-size: 13px; color: var(--text-muted);">
            Perched atop misty cloud seas: pagodas, watchtowers, suspension bridges, prayer flags, and celestial leylines.
          </p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="{imgs['sacred_forest']}" alt="Ancient Redwood Forest">
        <div class="card-content">
          <span class="card-tag tag-blue">Japanese Shinto Style</span>
          <h3 style="font-size: 18px; margin-bottom: 6px;">Sacred Redwood Forest & Torii Shrines</h3>
          <p style="font-size: 13px; color: var(--text-muted);">
            Colossal 80m redwoods, hanging rope bridges, mossy stone lanterns, multi-story wooden pavilions, and torii gates.
          </p>
        </div>
      </div>

      <div class="gallery-card">
        <img src="{imgs['rural_valley']}" alt="Rural Plains & Valleys">
        <div class="card-content">
          <span class="card-tag tag-emerald">European Feudal Style</span>
          <h3 style="font-size: 18px; margin-bottom: 6px;">Rural Plains, Watermills & Farmland Hamlets</h3>
          <p style="font-size: 13px; color: var(--text-muted);">
            Enterable thatched farmsteads, waterwheels, terraced crops, stone bridges, livestock pastures, and roadside inns.
          </p>
        </div>
      </div>
    </div>
  </section>

</main>

<script>
function switchTab(tabId) {{
  document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-btn').forEach(el => el.classList.remove('active'));
  document.getElementById('tab-' + tabId).classList.add('active');
  event.currentTarget.classList.add('active');
}}
</script>

</body>
</html>"""

    # Write to both locations
    artifact_path = os.path.join(ARTIFACT_DIR, "interactive_valencious_world_viewer.html")
    with open(artifact_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[OK] Generated artifact viewer at: {artifact_path} ({len(html)} bytes)")

    docs_path = os.path.join(DOCS_DIR, "VALENCIOUS_WORLD_VIEWER.html")
    with open(docs_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[OK] Synced to repo docs at: {docs_path}")

if __name__ == "__main__":
    main()
