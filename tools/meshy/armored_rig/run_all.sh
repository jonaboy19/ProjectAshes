#!/bin/sh
# rig + stress preview for the given characters (default: all six)
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
Q=C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/quaternius
U1=$Q/universal-animation-library/Unreal-Godot/UAL1_Standard.glb
U2=$Q/universal-animation-library-2/Unreal-Godot/UAL2_Standard.glb
A=C:/Users/Jonna/Documents/ProjectAshes/kingdom/assets/incoming/ai3d/meshy/armored
cd "$(dirname "$0")"
for n in ${@:-guard knight mercenary bandit noble orc_warchief}; do
  "$B" -b --python armored_rig.py -- cfg_$n.json --debug 2>&1 | grep -E "SHOULD|REPORT|Error|rigid box|skirt|pauldron" 
  PW=300 PH=460 "$B" -b --python render_anim.py -- $A/$n.glb $A/_work/stress_$n.png 6 $U1::Idle_Loop::0.5 $U1::Walk_Loop::0.25 $U1::Sprint_Loop::0.3 $U2::Sword_Regular_A::0.45 $U1::Sword_Attack::0.5 $U2::Sword_Block::0.5 $U1::Sitting_Idle_Loop::0.5 $U1::Crouch_Idle_Loop::0.5 $U1::Roll::0.4 $U1::Death01::0.95 $U1::Walk_Loop::0.75 $U1::Jump_Loop::0.5 2>&1 | grep -E "POSES|MISSING|Error"
done
