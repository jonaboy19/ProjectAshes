import json
ual=json.load(open('C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/_tools/cfg_g6_male.json'))['ual']
def fingers(m, side, S, fmt):
    for fi in ('index','middle','ring','pinky'):
        for i in (1,2,3): m[f'{fi}_0{i}_{side}']=fmt(fi,i,S)
    for i in (1,2,3): m[f'thumb_0{i}_{side}']=f'thumb.0{i}.{S}'
monk={'pelvis':'Hips','spine_01':'ToSpine','spine_02':'Spine','spine_03':'Spine1','neck_01':'Neck','Head':'Head'}
lady={'pelvis':'hips','spine_01':'Bone','spine_02':'chest','spine_03':'chest-1','neck_01':'neck','Head':'head'}
for s,S in (('l','L'),('r','R')):
    monk.update({f'clavicle_{s}':f'Shoulder_{S}',f'upperarm_{s}':f'Arm_{S}',f'lowerarm_{s}':f'ForeArm_{S}',f'hand_{s}':f'Hand_{S}',
      f'thigh_{s}':f'UpLeg_{S}',f'calf_{s}':f'Leg_{S}',f'foot_{s}':f'Foot_{S}',f'ball_{s}':f'ToeBase_{S}'})
    fingers(monk,s,S,lambda fi,i,S: f'f_{fi}.0{i}.{S}')
    lady.update({f'clavicle_{s}':f'shoulder.{S}',f'upperarm_{s}':f'upper_arm.{S}',f'lowerarm_{s}':f'forearm.{S}',f'hand_{s}':f'hand.{S}',
      f'thigh_{s}':f'thigh.{S}',f'calf_{s}':f'shin.{S}',f'foot_{s}':f'foot.{S}',f'ball_{s}':f'toe.{S}'})
    fingers(lady,s,S,lambda fi,i,S: f'f_{fi}.0{i}.{S}')
for name,src,m,show in (('monk','MONK_1.blend',monk,'^(Body|Head|Hair)$'),('old_lady','oldlady-v2.blend',lady,'^(OldLady|Hair)$')):
    json.dump(dict(source='C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/oga-cdmir-kelgar/'+src, ual=ual, map=m, weights='auto', variants=[dict(name=name, show=show)],
      out_dir='C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/cdmir-ual', prefix='cdmir_', autotex=True, max_tex=1024), open('C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/characters/_tools/cfg_cdmir_'+name+'.json','w'), indent=1)
