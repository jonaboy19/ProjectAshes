import json
m={'pelvis':'pelvis','spine_01':'torso','Head':'head'}
for s,S in (('l','L'),('r','R')):
  m.update({f'clavicle_{s}':f'shoulder_{S}',f'upperarm_{s}':f'arm_upper_{S}',f'lowerarm_{s}':f'arm_lower_{S}',f'hand_{s}':f'palm_{S}',
    f'thigh_{s}':f'leg_upper_{S}',f'calf_{s}':f'leg_lower_{S}',f'foot_{s}':f'foot_{S}',f'ball_{s}':f'toes_{S}',
    f'thumb_01_{s}':f'thumb_upper_{S}',f'thumb_02_{s}':f'thumb_lower_{S}'})
  for fi in ('index','middle','ring','pinky'):
    m[f'{fi}_01_{s}']=f'{fi}_upper_{S}'; m[f'{fi}_02_{s}']=f'{fi}_lower_{S}'
for sex in ('male','female'):
  json.dump(dict(source='C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/oga-system-g6-modular-rpg/modular_rpg_characters/human_'+sex+'.blend', ual='C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb', out='C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/_library/UAL_Extra_G6_'+sex+'.glb', map=m,
   include='^human_'+sex+'_', strip_prefix='human_'+sex+'_', prefix='G6_', loop='^G6_(idle|run|channel)'), open('C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/_tools/cfg_g6_'+sex+'.json','w'), indent=1)
