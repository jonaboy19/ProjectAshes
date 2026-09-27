// Generates the build manifest for build.py.  node manifest.js out.json
const fs = require('fs');
const root = 'C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming';
const E = []; const e = (o) => E.push(o);

// ---- Quaternius Modular Character Outfits - Fantasy (skinned, UAL 65-bone) from the existing incoming pack
const QP = 'quaternius/modular-character-outfits-fantasy/Exports/glTF (Godot-Unreal)/Modular Parts/';
for (const f of fs.readdirSync(root + '/' + QP).filter(f => f.endsWith('.gltf'))) {
  const n = f.replace('.gltf', '');
  e({ src: QP + f, out: `armor/quaternius/modular-outfits-fantasy/${n}.glb`, exclude: ['Icosphere'],
      max_tris: n.includes('Feet') ? 2500 : (n.includes('Arms') ? 3200 : 3000), max_tex: 1024, img_format: 'JPEG' });
}
// ---- Quaternius knight + RPG items (rigid)
const QK = 'quaternius/lowpoly-animated-knight/FBX/';
for (const h of ['Helmet1', 'Helmet2', 'Helmet3'])
  e({ src: QK + h + '.fbx', out: `armor/quaternius/items/Knight_${h}.glb`, rigid: true, fit: { axis: 'x', size: 0.28 }, harmonise: true });
e({ src: QK + 'ShoulderPads.fbx', out: 'armor/quaternius/items/Knight_ShoulderPads.glb', rigid: true, fit: { axis: 'x', size: 0.52 }, origin: 'center', harmonise: true });
const QR = 'quaternius/ultimate-rpg-items/FBX/';
const rpg = { Armor_Black: ['x', 0.5], Armor_Golden: ['x', 0.5], Armor_Leather: ['x', 0.42], Armor_Metal: ['x', 0.5], Armor_Metal2: ['x', 0.5],
  Glove: ['max', 0.25], Pouch: ['max', 0.18], Bag: ['max', 0.45], Backpack: ['max', 0.55], Crown: ['x', 0.2], Crown2: ['x', 0.2] };
for (const [k, [a, s]] of Object.entries(rpg))
  e({ src: QR + k + '.fbx', out: `armor/quaternius/items/${k}.glb`, rigid: true, fit: { axis: a, size: s }, harmonise: true });

// ---- KayKit Adventurers
const KA = 'armor/kaykit/adventurers/';
const ks = { shield_badge: ['z', 0.8], shield_badge_color: ['z', 0.8], shield_round: ['max', 0.65], shield_round_barbarian: ['max', 0.65],
  shield_round_color: ['max', 0.65], shield_spikes: ['max', 0.7], shield_spikes_color: ['max', 0.7], shield_square: ['z', 0.9], shield_square_color: ['z', 0.9] };
for (const [k, [a, s]] of Object.entries(ks))
  e({ src: KA + 'Assets/gltf/' + k + '.gltf', out: KA + 'glb/' + k + '.glb', rigid: true, fit: { axis: a, size: s }, harmonise: true });
for (const [c, m, a, s] of [['Knight', 'Knight_Helmet', 'x', 0.28], ['Barbarian', 'Barbarian_Hat', 'z', 0.3], ['Mage', 'Mage_Hat', 'z', 0.45],
  ['Knight', 'Knight_Cape', 'z', 1.1], ['Barbarian', 'Barbarian_Cape', 'z', 1.1], ['Mage', 'Mage_Cape', 'z', 1.1], ['Rogue', 'Rogue_Cape', 'z', 1.1]])
  e({ src: KA + 'Characters/gltf/' + c + '.glb', out: KA + 'glb/' + m + '.glb', objects: [m], rigid: true, fit: { axis: a, size: s }, harmonise: true });

// ---- Poly Pizza "Knights Character Kit" (Jacques Fourie, CC-BY 3.0): split parts, one uniform scale so pieces stay a matched set
const names = { 2: 'fauld_ring', 3: 'plate_curved', 4: 'plume_red_a', 5: 'plume_red_b', 6: 'fauld_leather_strips', 7: 'chest_barrel_leather',
  8: 'helmet_round', 9: 'cape_fur_mantle', 10: 'cape_purple', 13: 'plume_wings_blue', 14: 'quiver_back', 15: 'pauldron_layered_a',
  16: 'pauldron_layered_b', 17: 'belt_plate', 18: 'helmet_visor_horned_a', 19: 'helmet_visor_b', 20: 'helmet_visor_horned_c',
  21: 'helmet_bascinet_round', 22: 'helmet_horned_viking', 25: 'shield_round_wood_boss', 27: 'gauntlet_l', 28: 'gauntlet_r',
  29: 'helmet_red_crest_cloak', 30: 'helmet_red_crest_roman', 31: 'couter_elbow', 32: 'helmet_barred_visor', 34: 'chest_plate_a',
  35: 'chest_plate_leather_b', 36: 'vambrace_square', 38: 'helmet_yellow_crest', 39: 'pauldron_red_a', 40: 'pauldron_red_b',
  41: 'bracer_fur_spikes', 42: 'helmet_conical_grille', 43: 'helmet_black_crest_a', 44: 'helmet_black_crest_b', 45: 'bevor_neckguard',
  46: 'crown_jewelled', 47: 'pauldron_round_c', 49: 'gauntlet_spiked', 50: 'bracer_fur', 51: 'sabaton_boot_a', 53: 'sabaton_boot_b',
  54: 'greave_plate_a', 56: 'greave_leather_straps', 57: 'chest_plate_dark_c', 58: 'chest_plate_d', 59: 'chest_plate_dark_e',
  60: 'pauldron_round_d', 61: 'plaque_jewelled', 62: 'greave_plate_b', 63: 'greave_plate_c', 66: 'greave_leather_b', 67: 'greave_plate_d', 68: 'bracer_leather' };
for (const [i, n] of Object.entries(names)) {
  const p = String(i).padStart(2, '0');
  e({ src: 'armor/polypizza/cc-by/knights-character-kit/_split/part_' + p + '.glb', out: `armor/polypizza/cc-by/knights-character-kit/${n}.glb`,
      rigid: true, scale: 0.45, harmonise: true });
}
// ---- Poly Pizza singles
const PP = 'armor/polypizza/';
const pp = [['cc-by/Armor_CreativeTechLab_tVYVQc.glb', 'x', 0.5], ['cc-by/Armor_Used_CreativeTechLab_EEtHhE.glb', 'x', 0.5],
  ['cc-by/Shield_CreativeTechLab_KtP3XC.glb', 'max', 0.65], ['cc-by/Boots_Poly_by_Google_7HbqG8.glb', 'z', 0.3],
  ['cc-by/Crown_Poly_by_Google_0seQ0m.glb', 'x', 0.2, 1500], ['cc-by/hat_Minh_Nguyen_Tri_4Tdb1s.glb', 'x', 0.36],
  ['cc0/Coin_Bag_Quaternius_iUpWtN.glb', 'max', 0.25], ['cc0/Coin_Pouch_Quaternius_pTZyPT.glb', 'max', 0.18],
  ['cc0/Bags_Quaternius_gzvyAQ.glb', 'max', 0.3], ['cc0/Bedroll_Kenney_12PaVp.glb', 'max', 0.7]];
for (const [f, a, s, mt] of pp)
  e({ src: PP + f, out: PP + f.replace(/^(cc0|cc-by)\//, '$1/glb/'), rigid: true, fit: { axis: a, size: s }, harmonise: true, max_tris: mt || 3000 });

// ---- OpenGameArt
const O = 'armor/opengameart/';
const IT = O + 'cc-by/iron-armor-set/ironarmor_difusospecular_512x512.tga';
e({ src: O + 'cc-by/iron-armor-set/iron_armor.blend', out: O + 'cc-by/iron-armor-set/glb/iron_armor_full.glb', scale: 0.0724, tex: IT });
for (const p of ['iron_chest', 'iron_helmet', 'iron_gloves', 'iron_legs', 'iron_boots'])
  e({ src: O + 'cc-by/iron-armor-set/iron_armor.blend', out: O + `cc-by/iron-armor-set/glb/${p}.glb`, objects: [p], scale: 0.0724, tex: IT });
e({ src: O + 'cc-by/leather-breastplate/starbp.blend', out: O + 'cc-by/leather-breastplate/leather_breastplate.glb', rigid: true, fit: { axis: 'x', size: 0.42 }, tex_map: { 'Material.001': 'Leather-Armor-Star.jp' } });
e({ src: O + 'cc-by/leather-forearm-armor/starforearmoga.blend', out: O + 'cc-by/leather-forearm-armor/leather_forearm_guard.glb', rigid: true, fit: { axis: 'max', size: 0.28 }, tex_map: { 'Material.002': 'Leather-Armor-Star.jp' } });
e({ src: O + 'cc-by/tower-shield/towershield.blend', out: O + 'cc-by/tower-shield/tower_shield.glb', rigid: true, fit: { axis: 'z', size: 1.2 },
    tex_map: { 'Material.002': 'WoodPlanksBareWindmil', 'Material.003': 'BronzeCopper0011_7_S.', 'Material.004': 'BarrelRingsUV.jpg' } });
e({ src: O + 'cc-by/poleaxe-and-shield/shield_1.blend', out: O + 'cc-by/poleaxe-and-shield/round_shield.glb', rigid: true, fit: { axis: 'max', size: 0.65 }, tex_map: { 'Material': 'armor/opengameart/cc-by/poleaxe-and-shield/shield_1.png' } });
const W = ['Axe', 'GreatSword', 'Hammer', 'Hellebard', 'Sword', 'Bow'];
e({ src: O + 'cc-by/orc-barbarian/ork.blend', out: O + 'cc-by/orc-barbarian/orc_barbarian_full.glb', exclude: W, fit: { axis: 'z', size: 1.95 } });
e({ src: O + 'cc-by/orc-barbarian/ork.blend', out: O + 'cc-by/orc-barbarian/orc_shoulder_armor.glb', objects: ['ShoulderArmor'], rigid: true, fit: { axis: 'x', size: 0.45 }, origin: 'center' });
e({ src: O + 'cc-by/orc-barbarian/ork.blend', out: O + 'cc-by/orc-barbarian/orc_armor_skinned.glb', objects: ['Ork', 'Schaerpe', 'ShoulderArmor'], fit_ref: 'Ork', fit: { axis: 'z', size: 1.95 },
    keep_materials: ['plates', 'plates2', 'plates3', 'belt', 'skirt', 'skirt2', 'shoes'] });
e({ src: O + 'cc0/heater-shield/Heater_Shield.blend', out: O + 'cc0/heater-shield/heater_shield.glb', rigid: true, mat_colors: { woodenPart: [0.42, 0.26, 0.13], ironEdges: [0.35, 0.35, 0.34], leatherFittings: [0.3, 0.16, 0.07] }, fit: { axis: 'z', size: 0.75 } });
e({ src: O + 'cc0/great-kite-shield/kiteshield.obj', out: O + 'cc0/great-kite-shield/kite_shield.glb', rigid: true, rot: [90, 0, 0], fit: { axis: 'z', size: 1.0 } });
e({ src: O + 'cc0/spiked-shield/spiked_shield.obj', out: O + 'cc0/spiked-shield/spiked_shield.glb', rigid: true, mat_colors: { '*': [0.4, 0.4, 0.39] }, fit: { axis: 'max', size: 0.7 } });
e({ src: O + 'cc0/basic-shield/Sheild01.fbx', out: O + 'cc0/basic-shield/basic_round_shield.glb', rigid: true, mat_colors: { '*': [0.45, 0.28, 0.14] }, rot: [90, 0, 0], fit: { axis: 'max', size: 0.6 } });
e({ src: O + 'cc0/bucket-helmet/Bucket Helmet.fbx', out: O + 'cc0/bucket-helmet/great_helm_bucket.glb', rigid: true, fit: { axis: 'x', size: 0.26 } });
e({ src: O + 'cc0/helmet-olexanders/untitled_0.blend', out: O + 'cc0/helmet-olexanders/kettle_morion_helmet.glb', rigid: true, fit: { axis: 'x', size: 0.42 }, max_tris: 2000, flat_color: [0.42, 0.42, 0.40] });
e({ src: O + 'cc0/viking-helmet/VikingHelmet/VikingHelmet.obj', out: O + 'cc0/viking-helmet/viking_helmet.glb', rigid: true, fit: { axis: 'x', size: 0.26 }, tex: O + 'cc0/viking-helmet/VikingHelmet/Mat_Base_Color.png' });
e({ src: O + 'cc0/iron-crown/Iron_Crown/Iron_Crown.obj', out: O + 'cc0/iron-crown/iron_crown.glb', rigid: true, fit: { axis: 'x', size: 0.2 }, tex: O + 'cc0/iron-crown/Iron_Crown/Iron_Crown_Diffuse.tif' });
e({ src: O + 'cc0/hats-clothing-props/straw hat.fbx', out: O + 'cc0/hats-clothing-props/straw_hat.glb', rigid: true, fit: { axis: 'x', size: 0.45 },
    tex: O + 'cc0/hats-clothing-props/Basket_weave_001_COLOR  by João Paulo via 3dtextures.me CC0.png' });
e({ src: O + 'cc0/low-poly-knight/knightStanding.blend', out: O + 'cc0/low-poly-knight/plate_knight_armor_set.glb', rigid: true, fit: { axis: 'z', size: 1.85 } });
e({ src: O + 'cc0/cartoon-medieval-knight/Knight.blend', out: O + 'cc0/cartoon-medieval-knight/cartoon_knight_skinned.glb', objects: ['Knight'], fit: { axis: 'z', size: 1.8 }, tex_map: { 'Knight': 'Knight.png' } });

// existing CC-BY Anglo-Saxon helmets (re-exported with their painted textures, real scale)
const AS = 'opengameart/cc-by/models/anglo-saxons-helmets-and-spears/';
for (let i = 1; i <= 6; i++) e({ src: AS + 'helm' + i + '.glb', out: 'armor/opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm' + i + '.glb', rigid: true, fit: { axis: 'x', size: 0.24 }, tex: AS + 'helm' + Math.min(i, 3) + '.png' });
E.forEach(x => { if (x.out.includes('opengameart')) x.img_format = 'JPEG'; });
const only = process.argv[3];
const out = only ? E.filter(x => x.out.includes(only)) : E;
fs.writeFileSync(process.argv[2], JSON.stringify({ root, entries: out }, null, 1));
console.log(out.length, 'entries');
