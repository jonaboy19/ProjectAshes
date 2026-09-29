src=open(r"C:/Users/Jonna/Documents/PA_wt_creature/kingdom/tools/anim/traversal/scan_motion.py").read().split("res = {}")[0]
exec(compile(src,"scan","exec"))
import os
CL=os.environ.get("DCLIP","Vault_Low"); F0=int(os.environ.get("DF0","24")); F1=int(os.environ.get("DF1","36")); BS=os.environ.get("DB","root,pelvis,thigh_l,calf_l,foot_l,upperarm_r,hand_r").split(",")
act=acts[CL]
arm.animation_data.action=act
arm.animation_data.action_slot=act.slots[0]
for f in range(F0,F1):
    sc.frame_set(f)
    print("F",f,*[ "%s(%.2f,%.2f,%.2f)"%(b,*(arm.matrix_world@arm.pose.bones[b].head)) for b in BS])
