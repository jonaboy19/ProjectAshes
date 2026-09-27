// Writes one contact-sheet spec per category from build_report.jsonl.  node sheets.js <specdir>
const fs = require('fs'), path = require('path');
const inc = 'C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/';
const prev = inc + 'armor/_previews/';
const rep = fs.readFileSync(path.join(__dirname, 'build_report.jsonl'), 'utf8').trim().split('\n').map(JSON.parse).filter(r => !r.error);
const lab = (o) => {
  const src = o.replace('armor/', '').split('/')[0];
  return `${path.basename(o, '.glb').slice(0, 30)}  [${src}]`;
};
const cats = {
  helmets: /helm|Helmet|Hat|hat_|crown|Crown|visor|bevor|plume|Hood|great_helm|kettle|viking|bascinet|morion|conical|crest/,
  chest: /chest|Armor_|breastplate|fauld|Body|belt_plate|plaque|iron_armor_full|plate_knight/,
  arms: /pauldron|Pauldron|ShoulderPads|shoulder|gauntlet|Glove|gloves|bracer|vambrace|couter|forearm|Arms/,
  legs: /greave|sabaton|Boots|boots|Feet|Legs|legs/,
  shields: /shield/i,
  gear: /cape|Cape|Bag|bag|Pouch|pouch|Backpack|bedroll|Bedroll|quiver|mantle/,
};
const specs = {};
for (const [k, re] of Object.entries(cats)) specs[k] = [];
for (const r of rep) {
  for (const [k, re] of Object.entries(cats)) {
    if (re.test(path.basename(r.out))) {
      specs[k].push({ file: inc + r.out, label: lab(r.out), note: `${r.tris} tris${r.skinned ? ' skinned ' + r.bones + 'b' : ''}${r.images.length ? ' tex ' + Math.max(...r.images.map(i => i[0])) : ''}` });
      break;
    }
  }
}
// existing packs already in incoming (reference, not rebuilt)
const ex = (f, l) => ({ file: inc + f, label: l + '  [existing]' });
for (let i = 1; i <= 6; i++) specs.helmets.push(ex(`opengameart/cc-by/models/anglo-saxons-helmets-and-spears/helm${i}.glb`, `anglo_saxon_helm${i}`));
specs.helmets.push(ex('polypizza/cc-by/Helmet_CreativeTechLab_uSCGe4.glb', 'Helmet_CreativeTechLab'));
specs.helmets.push(ex('polypizza/cc-by/Viking_Helmet_Michael_Fuchs_apPuLb.glb', 'Viking_Helmet_Fuchs'));
for (const f of fs.readdirSync(inc + 'polypizza/cc0').filter(f => /Shield/.test(f))) specs.shields.push(ex('polypizza/cc0/' + f, f.slice(0, 26)));
for (const f of ['Shield_J_Toastie_eEkc80.glb', 'Small_Round_Shield_Thardoc_nolastname_3FINhn.glb', 'shield_abdallah_hegazy_0ssZec.glb']) specs.shields.push(ex('polypizza/cc-by/' + f, f.slice(0, 26)));
specs.chest.push(ex('3dassets-dev-ai/blacksmith-forge-and-armoury/breastplate-on-a-torso-form-1-45-m.glb', 'breastplate_on_form (AI)'));
specs.helmets.push(ex('3dassets-dev-ai/blacksmith-forge-and-armoury/helm-on-a-shaping-form-1-05-m.glb', 'helm_on_form (AI)'));
const dir = process.argv[2];
for (const [k, items] of Object.entries(specs)) {
  const cols = items.length > 40 ? 9 : items.length > 20 ? 7 : 6;
  fs.writeFileSync(path.join(dir, k + '.json'), JSON.stringify({ out: prev + `armor_${k}.jpg`, cols, px: 300, items }));
  console.log(k, items.length);
}
