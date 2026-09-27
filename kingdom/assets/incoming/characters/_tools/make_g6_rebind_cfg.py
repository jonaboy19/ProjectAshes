import json
base=json.load(open('C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/_tools/cfg_g6_male.json'))['map']
for sex in ('male','female'):
  p='^human_%s_'%sex
  def v(name, parts): return dict(name=name, show=p+'('+'|'.join(parts)+')$')
  V=[v('villager_tunic',['head_default','hands_default','hair_2','light_armor_2','light_boots_2']),
     v('blacksmith_apron',['head_3' if sex=='female' else 'head_4','hands_default','hair_1' if sex=='female' else 'hair_4','light_armor_3','light_boots_2']),
     v('worker_apron',['head_2' if sex=='female' else 'head_6','hands_default','hair_3' if sex=='female' else 'hair_6','light_armor_4','light_boots']),
     v('hunter_leather',['head_default','hair_1','medium_armor','medium_boots','medium_gloves']),
     v('modular_all',['body_default','feet_default','hands_default','head_\w+','hair_\d','light_\w+','medium_(armor|boots|gloves)'])]
  json.dump(dict(source='C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/oga-system-g6-modular-rpg/modular_rpg_characters/human_%s.blend'%sex, ual=json.load(open('C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/_tools/cfg_g6_male.json'))['ual'],
    map=base, weights='map', merge={'heel_L':'foot_l','heel_R':'foot_r','wep_pos_L':'hand_l','wep_pos_R':'hand_r'},
    split={'torso':['spine_01','spine_02','spine_03'],'head':['neck_01','Head']}, variants=V, out_dir='C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/g6-ual', prefix='g6_%s_'%sex[0], autotex=True, max_tex=1024),
    open('C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/_tools/cfg_g6_rebind_%s.json'%sex,'w'), indent=1)
