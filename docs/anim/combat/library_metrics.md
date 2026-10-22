# Library attack clips - combat_studio metrics (sword+shield rig, rate 1.0, full body)

Columns and grading: `kingdom/tools_qa/combat_audit/metrics_table.py`. The "issues" column is written for strikes; ignore it for reactions/deaths.

| clip | len s | hits | windup_end | fast f | peak m/s | chain h/s/a/h/t | flat | arc | follow m | step m | slide cm l/r | issues |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Sword_Regular_A | 0.43 | 1 | 1 | 7 | 28 | 7/7/8/8/8 | 0.55 | 2.18 | 0.69 | 0.05 | 107/115 | no anticipation; floaty strike (7 fast f); foot slide |
| Sword_Regular_A_Rec | 0.97 | 1 | 1 | 18 | 9 | 9/9/9/9/7 | 0.67 | 1.59 | 0.36 | 0.04 | 26/44 | no anticipation; floaty strike (18 fast f); chain out of order; flat slap; foot slide |
| Sword_Regular_B | 0.53 | 1 | 1 | 3 | 21 | 7/7/8/8/8 | 0.36 | 1.32 | 0.21 | 0.02 | 34/25 | no anticipation; no follow-through; foot slide |
| Sword_Regular_B_Rec | 1.03 | 1 | 1 | 9 | 3 | 9/9/11/15/13 | 0.96 | 1.02 | 0.59 | 0.05 | 47/54 | no anticipation; floaty strike (9 fast f); chain out of order; flat slap; straight path; foot slide |
| Sword_Regular_C | 2.00 | 2 | 19 | 3 | 27 | 18/19/20/20/20 | 0.37 | 1.15 | 0.32 | 0.16 | 29/124 | foot slide |
| Sword_Attack | 1.53 | 1 | 7 | 3 | 33 | 11/11/12/12/12 | 0.58 | 1.20 | 1.23 | 0.1 | 105/88 | foot slide |
| Sword_Regular_Combo | 3.00 | 3 | 1 | 7 | 28 | 7/7/8/8/8 | 0.55 | 2.18 | 0.69 | 0.05 | 178/144 | no anticipation; floaty strike (7 fast f); foot slide |
| Sword_Heavy_Combo | 4.33 | 4 | 49 | 4 | 30 | 54/55/55/54/54 | 0.5 | 1.74 | 0.74 | 0.07 | 415/59 | chain out of order; foot slide; blade through body x1 |
| Sword_Dash | 1.57 | 2 | 1 | 2 | 35 | 2/2/2/3/2 | 0.22 | 1.00 | 0.79 | 0.07 | 132/117 | chain out of order; straight path; foot slide |
| Sword_Attack_Air_Vertical | 4.79 | 2 | 26 | 2 | 36 | 24/23/26/26/26 | 0.74 | 1.00 | 1.15 | 0.02 | 19/0 | chain out of order; flat slap; straight path; foot slide |
| Souls_Light_Attack_1 | 0.67 | 3 | 9 | 4 | 17 | 11/9/9/9/9 | 0.71 | 1.19 | 2.07 | 0.08 | 36/23 | chain out of order; flat slap; foot slide |
| Souls_Light_Attack_2 | 0.60 | 2 | 7 | 3 | 16 | 8/8/9/8/7 | 0.78 | 1.07 | 2.59 | 0.02 | 30/26 | chain out of order; flat slap; straight path; foot slide |
| Souls_Light_Special_1 | 1.50 | 1 | 21 | 4 | 24 | 25/23/25/26/26 | 0.91 | 1.34 | 0.06 | 0.18 | 44/114 | chain out of order; flat slap; no follow-through; foot slide |
| Souls_Light_Special_2 | 1.67 | 2 | 21 | 3 | 24 | 19/19/19/18/24 | 0.51 | 1.19 | 4.02 | 0.29 | 38/153 | chain out of order; foot slide; blade through body x1 |
| Souls_Heavy_Attack_1 | 1.27 | 2 | 11 | 2 | 28 | 12/11/11/11/11 | 0.98 | 1.00 | 2.16 | 0.34 | 71/186 | chain out of order; flat slap; straight path; foot slide |
| Souls_Heavy_Attack_2 | 1.27 | 2 | 13 | 6 | 18 | 20/16/18/20/20 | 0.63 | 1.51 | 0.41 | 0.05 | 49/108 | floaty strike (6 fast f); chain out of order; flat slap; foot slide |
| Souls_Heavy_Stab | 1.83 | 5 | 5 | 4 | 14 | 14/11/10/11/12 | 0.57 | 1.16 | 0.06 | 0.12 | 186/66 | chain out of order; no follow-through; foot slide |
| Souls_Heavy_Special | 1.90 | 2 | 34 | 4 | 24 | 41/41/42/41/41 | 0.78 | 1.12 | 1.15 | 0.02 | 125/127 | chain out of order; flat slap; foot slide |
| Souls_Visceral_Attack | 2.17 | 2 | 16 | 2 | 13 | 19/19/19/18/18 | 0.98 | 1.00 | 0.24 | 0.03 | 147/49 | chain out of order; flat slap; straight path; no follow-through; foot slide |
| Souls_Fall_Attack_Start | 0.57 | 1 | 1 | 7 | 16 | 2/2/2/2/2 | 0.8 | 2.74 | 1.25 | 0.08 | 4/7 | floaty strike (7 fast f); no overlap (all joints peak together); flat slap |
| Parry_Quick | 0.50 | 1 | 1 | 5 | 3 | 3/4/2/2/3 | 0.48 | 1.07 | 0.35 | 0.01 | 14/14 | no anticipation; chain out of order; straight path; foot slide |
| Shield_Bash | 0.77 | 2 | 14 | 4 | 7 | 16/13/15/14/14 | 0.09 | 1.00 | 0.32 | 0.37 | 72/26 | chain out of order; straight path; foot slide |
| Shield_Dash | 1.10 | 2 | 1 | 2 | 12 | 2/2/2/2/2 | 0.9 | 1.00 | 0.06 | 0.21 | 77/65 | no anticipation; no overlap (all joints peak together); flat slap; straight path; no follow-through; foot slide |
| Shield_OneShot | 0.83 | 1 | 1 | 3 | 9 | 3/2/2/3/3 | 0.82 | 1.01 | 0.31 | 0.0 | 1/2 | no anticipation; chain out of order; flat slap; straight path |
| G6_cast_main_hand_melee | 0.38 | 1 | 5 | 3 | 7 | 2/8/7/8/7 | 0.94 | 1.02 | 0.29 | 0.0 | 0/0 | chain out of order; flat slap; straight path |
| G6_cast_main_hand_melee_2 | 0.38 | 1 | 1 | 3 | 7 | 0/10/10/10/10 | 0.19 | 1.02 | 0.13 | 0.0 | 0/0 | no anticipation; straight path; no follow-through |
| G6_cast_main_hand_melee_3 | 0.38 | 1 | 5 | 4 | 6 | 2/6/10/10/10 | 0.98 | 1.06 | 0.03 | 0.0 | 0/0 | flat slap; straight path; no follow-through |
| G6_cast_off_hand_shield | 0.38 | 1 | 1 | 4 | 1 | 0/11/11/11/11 | 0.56 | 1.00 | 0.00 | 0.0 | 0/0 | no anticipation; straight path; no follow-through |
| G6_cast_two_handed_melee | 0.38 | 1 | 1 | 7 | 7 | 0/5/7/10/10 | 0.88 | 1.07 | 0.05 | 0.0 | 0/0 | no anticipation; floaty strike (7 fast f); flat slap; straight path; no follow-through |
| G6_cast_two_handed_melee_2 | 0.38 | 1 | 1 | 10 | 14 | 5/5/5/5/5 | 0.6 | 5.35 | 0.15 | 0.0 | 120/48 | floaty strike (10 fast f); no overlap (all joints peak together); no follow-through; foot slide |
| G6_cast_two_handed_melee_3 | 0.38 | 1 | 7 | 3 | 12 | 9/11/6/10/10 | 0.29 | 1.00 | 0.01 | 0.11 | 0/0 | chain out of order; straight path; no follow-through |
| G6_cast_two_handed_melee_4 | 0.38 | 1 | 1 | 3 | 10 | 0/11/11/11/11 | 0.93 | 1.02 | 0.07 | 0.0 | 0/0 | no anticipation; flat slap; straight path; no follow-through |
| G6_cast_two_handed_melee_5 | 0.38 | 1 | 1 | 4 | 6 | 0/9/11/11/11 | 0.95 | 1.00 | 0.06 | 0.0 | 0/0 | no anticipation; flat slap; straight path; no follow-through |
| G6_cast_dual_wield_melee | 0.38 | 1 | 1 | 4 | 23 | 0/7/5/7/5 | 0.93 | 1.21 | 0.83 | 0.0 | 0/0 | no anticipation; chain out of order; flat slap |
| G6_cast_dual_wield_melee_2 | 0.38 | 1 | 6 | 3 | 8 | 3/6/10/10/10 | 0.28 | 1.01 | 0.04 | 0.0 | 0/0 | straight path; no follow-through |
| G6_cast_dual_wield_melee_3 | 0.42 | 1 | 4 | 6 | 8 | 1/11/11/11/11 | 0.31 | 1.24 | 0.06 | 0.0 | 0/0 | floaty strike (6 fast f); no follow-through |
| G6_cast_dual_wield_melee_4 | 0.38 | 1 | 3 | 6 | 7 | 0/10/10/10/10 | 0.95 | 1.12 | 0.03 | 0.0 | 0/0 | floaty strike (6 fast f); flat slap; no follow-through |
| Weapon_1H_Chop | 1.07 | 2 | 18 | 2 | 2 | 19/19/19/18/19 | 0.26 | 1.00 | 0.38 | 0.0 | 12/20 | chain out of order; straight path; foot slide |
| Weapon_1H_Slice_Diagonal | 1.00 | 2 | 1 | 3 | 11 | 3/3/4/3/3 | 0.99 | 1.02 | 0.31 | 0.07 | 36/57 | no anticipation; chain out of order; flat slap; straight path; foot slide |
| Weapon_1H_Slice_Horizontal | 1.37 | 1 | 1 | 4 | 15 | 4/3/5/4/4 | 0.96 | 1.07 | 1.01 | 0.13 | 28/54 | no anticipation; chain out of order; flat slap; straight path; foot slide |
| Weapon_1H_Stab | 1.60 | 1 | 9 | 3 | 14 | 12/12/12/12/12 | 0.94 | 1.00 | 0.09 | 0.0 | 44/36 | no overlap (all joints peak together); flat slap; straight path; no follow-through; foot slide |
| Weapon_Block_Attack | 1.07 | 1 | 8 | 3 | 7 | 12/10/10/11/13 | 0.96 | 1.01 | 0.49 | 0.01 | 4/4 | chain out of order; flat slap; straight path |
| Weapon_2H_Chop | 1.63 | 1 | 17 | 5 | 11 | 22/24/25/22/25 | 0.88 | 1.12 | 0.02 | 0.09 | 60/65 | chain out of order; flat slap; no follow-through; foot slide |
| Weapon_2H_Slice | 1.10 | 1 | 9 | 3 | 22 | 12/12/12/12/12 | 0.9 | 1.06 | 0.55 | 0.07 | 84/78 | no overlap (all joints peak together); flat slap; straight path; foot slide |
| Weapon_2H_Spin | 2.40 | 1 | 16 | 11 | 7 | 23/22/20/24/25 | 0.87 | 1.81 | 4.87 | 0.03 | 317/196 | floaty strike (11 fast f); chain out of order; flat slap; foot slide |
| Weapon_2H_Stab | 1.60 | 2 | 1 | 3 | 10 | 2/2/2/2/2 | 0.96 | 1.00 | 0.21 | 0.11 | 36/34 | no anticipation; no overlap (all joints peak together); flat slap; straight path; no follow-through; foot slide |
| Weapon_DW_Chop | 1.27 | 4 | 1 | 4 | 9 | 4/4/4/4/3 | 0.98 | 1.02 | 4.41 | 0.0 | 45/57 | no anticipation; chain out of order; flat slap; straight path; foot slide |
| Weapon_DW_Slice | 1.17 | 1 | 13 | 3 | 12 | 10/10/17/18/18 | 0.92 | 1.04 | 2.42 | 0.03 | 22/53 | flat slap; straight path; foot slide |
| Weapon_DW_Stab | 1.60 | 1 | 9 | 3 | 11 | 6/6/12/12/12 | 0.97 | 1.00 | 0.04 | 0.05 | 18/52 | flat slap; straight path; no follow-through; foot slide |
| Kay_Block_Counter | 1.07 | 2 | 8 | 3 | 4 | 8/10/10/11/11 | 0.73 | 1.00 | 0.77 | 0.01 | 4/4 | flat slap; straight path |
| Kay_Attack_2H_Spin_Long | 1.60 | 1 | 8 | 9 | 12 | 14/13/11/16/16 | 0.81 | 2.37 | 2.83 | 0.15 | 100/64 | floaty strike (9 fast f); chain out of order; flat slap; foot slide |
| Swordplay_A | 18.43 | 7 | 488 | 5 | 4 | 486/487/488/489/487 | 0.55 | 1.02 | 0.22 | 0.01 | 142/96 | chain out of order; straight path; no follow-through; foot slide |
| Swordplay_B | 12.20 | 7 | 156 | 10 | 4 | 153/155/157/157/156 | 0.62 | 1.16 | 0.62 | 0.01 | 159/84 | floaty strike (10 fast f); chain out of order; flat slap; foot slide; blade through body x53 |
| Swordplay_C | 8.30 | 7 | 51 | 8 | 3 | 49/51/53/53/50 | 0.72 | 1.12 | 0.26 | 0.04 | 161/126 | floaty strike (8 fast f); chain out of order; flat slap; foot slide; blade through body x41 |
| Souls_Thrust_Attack_1 | 0.67 | 2 | 6 | 3 | 12 | 3/9/8/8/8 | 0.88 | 1.00 | 2.28 | 0.02 | 11/10 | chain out of order; flat slap; straight path; foot slide |
| Souls_Thrust_Attack_2 | 0.97 | 3 | 16 | 3 | 12 | 18/16/15/16/16 | 0.8 | 1.00 | 0.57 | 0.1 | 35/50 | chain out of order; flat slap; straight path; foot slide |
| Souls_Thrust_Special | 1.33 | 1 | 11 | 3 | 26 | 18/18/20/18/18 | 0.96 | 1.00 | 0.35 | 0.11 | 86/110 | chain out of order; flat slap; straight path; foot slide |
| Attack_Ground_Pound | 2.67 | 1 | 40 | 5 | 23 | 37/37/47/45/46 | 0.4 | 2.07 | 0.07 | 0.02 | 8/5 | chain out of order; no follow-through; foot slide |
| Melee_Hook | 0.47 | 1 | 5 | 3 | 38 | 2/7/8/8/8 | 0.18 | 1.02 | 0.84 | 0.35 | 41/28 | straight path; foot slide |
| Punch_Jab | 0.87 | 1 | 1 | 2 | 5 | 5/5/5/6/6 | 0.34 | 1.00 | 0.03 | 0.07 | 1/2 | no anticipation; straight path; no follow-through |
| Punch_Cross | 1.00 | 1 | 1 | 2 | 18 | 7/7/6/6/7 | 0.59 | 1.00 | 0.06 | 0.03 | 2/11 | no anticipation; chain out of order; straight path; no follow-through; foot slide |
| Souls_Fist_Attack | 0.80 | 2 | 4 | 3 | 14 | 9/7/6/7/7 | 0.26 | 1.00 | 2.45 | 0.24 | 30/23 | chain out of order; straight path; foot slide |
| MA_KK_Punch | 1.17 | 1 | 9 | 3 | 18 | 13/13/13/13/13 | 0.53 | 1.00 | 0.35 | 0.1 | 45/37 | no overlap (all joints peak together); straight path; foot slide |
| MA_KK_Kick | 0.93 | 2 | 5 | 7 | 2 | 4/4/9/9/7 | 0.59 | 2.01 | 0.36 | 0.06 | 39/26 | floaty strike (7 fast f); chain out of order; foot slide |
| Karate_Mae_Geri | 1.70 | 3 | 17 | 3 | 2 | 18/18/15/18/17 | 0.74 | 1.00 | 0.53 | 0.01 | 75/33 | chain out of order; flat slap; straight path; foot slide; blade through body x1 |
| Karate_Oi_Zuki | 2.00 | 1 | 10 | 6 | 8 | 15/16/16/16/15 | 0.66 | 2.17 | 0.15 | 0.07 | 89/53 | floaty strike (6 fast f); chain out of order; flat slap; no follow-through; foot slide |
