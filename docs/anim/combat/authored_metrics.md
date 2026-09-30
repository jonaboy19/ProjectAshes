# Library attack clips - combat_studio metrics (sword+shield rig, rate 1.0, full body)

Columns and grading: `kingdom/tools_qa/combat_audit/metrics_table.py`. The "issues" column is written for strikes; ignore it for reactions/deaths.

| clip | len s | hits | windup_end | fast f | peak m/s | chain h/s/a/h/t | flat | arc | follow m | step m | slide cm l/r | issues |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Sword_Light_1 | 1.00 | 1 | 6 | 3 | 38 | 7/8/8/8/9 | 0.3 | 1.15 | 0.84 | 0.18 | 7/8 | foot slide |
| Sword_Light_2 | 1.00 | 1 | 4 | 5 | 30 | 6/7/9/9/6 | 0.28 | 1.51 | 0.31 | 0.23 | 5/9 | chain out of order; foot slide |
| Sword_Light_3 | 1.07 | 1 | 5 | 5 | 33 | 7/8/8/8/7 | 0.16 | 1.78 | 0.61 | 0.16 | 5/10 | chain out of order; foot slide |
| Sword_Light_4 | 1.37 | 3 | 1 | 4 | 15 | 3/3/4/3/4 | 0.67 | 1.04 | 1.38 | 0.02 | 8/22 | no anticipation; chain out of order; flat slap; straight path; foot slide |
| Sword_Light_1_Upper | 1.00 | 1 | 6 | 3 | 38 | 8/8/8/8/9 | 0.31 | 1.15 | 0.84 | 0.18 | 6/8 |  |
| Sword_Light_2_Upper | 1.00 | 1 | 4 | 5 | 30 | 7/7/9/9/6 | 0.28 | 1.52 | 0.31 | 0.23 | 5/8 | chain out of order |
| Sword_Light_3_Upper | 1.07 | 1 | 5 | 5 | 33 | 8/8/9/8/7 | 0.16 | 1.79 | 0.50 | 0.16 | 5/10 | chain out of order; foot slide |
| Sword_Light_4_Upper | 1.37 | 3 | 1 | 4 | 15 | 5/3/4/3/4 | 0.68 | 1.04 | 1.38 | 0.02 | 9/23 | no anticipation; chain out of order; flat slap; straight path; foot slide |
| Hit_Light_Front | 0.50 | 1 | 1 | 2 | 3 | 4/1/2/2/2 | 0.08 | 1.00 | 0.16 | 0.05 | 3/3 | no anticipation; chain out of order; straight path; no follow-through |
| Hit_Heavy_Front | 0.87 | 2 | 1 | 2 | 3 | 4/2/2/2/2 | 0.09 | 1.00 | 0.02 | 0.12 | 6/20 | no anticipation; chain out of order; straight path; no follow-through; foot slide |
| Hit_Light_Back | 0.50 | 1 | 1 | 2 | 3 | 4/4/2/2/2 | 0.49 | 1.00 | 0.16 | 0.05 | 2/2 | no anticipation; chain out of order; straight path; no follow-through |
| Hit_Heavy_Back | 0.87 | 2 | 1 | 3 | 3 | 2/2/2/2/2 | 0.35 | 1.00 | 0.02 | 0.12 | 20/4 | no anticipation; no overlap (all joints peak together); straight path; no follow-through; foot slide |
| Hit_Light_Left | 0.50 | 1 | 1 | 5 | 1 | 2/2/2/2/2 | 0.71 | 4.57 | 0.02 | 0.05 | 3/3 | no anticipation; no overlap (all joints peak together); flat slap; no follow-through |
| Hit_Heavy_Left | 0.87 | 2 | 6 | 3 | 1 | 11/11/3/12/12 | 0.41 | 1.02 | 0.02 | 0.12 | 7/18 | chain out of order; straight path; no follow-through; foot slide |
| Hit_Light_Right | 0.50 | 1 | 1 | 2 | 3 | 2/2/2/2/2 | 0.96 | 1.00 | 0.14 | 0.05 | 3/3 | no anticipation; no overlap (all joints peak together); flat slap; straight path; no follow-through |
| Hit_Heavy_Right | 0.87 | 2 | 1 | 2 | 2 | 2/2/2/2/2 | 0.88 | 1.00 | 0.01 | 0.12 | 19/5 | no anticipation; no overlap (all joints peak together); flat slap; straight path; no follow-through; foot slide |
| Stagger_Back | 1.33 | 4 | 1 | 2 | 4 | 2/2/1/1/1 | 0.23 | 1.00 | 0.01 | 0.06 | 15/12 | no anticipation; chain out of order; straight path; no follow-through; foot slide |
| Stagger_Forward | 1.33 | 4 | 19 | 2 | 4 | 18/19/16/23/23 | 0.44 | 1.00 | 0.01 | 0.06 | 15/15 | chain out of order; straight path; no follow-through; foot slide |
| Sword_Parry | 0.60 | 1 | 1 | 3 | 13 | 1/1/3/2/2 | 0.55 | 1.20 | 0.29 | 0.03 | 3/3 | no anticipation; chain out of order |
| Sword_Riposte | 1.10 | 2 | 1 | 2 | 15 | 4/4/2/2/2 | 0.38 | 1.00 | 1.95 | 0.0 | 6/9 | no anticipation; chain out of order; straight path; foot slide |
| Shield_Bash_Step | 0.90 | 2 | 6 | 2 | 8 | 6/6/10/10/10 | 0.02 | 1.00 | 1.02 | 0.25 | 4/10 | straight path; foot slide |
| Finisher_Stab_Through | 2.00 | 2 | 33 | 4 | 9 | 33/33/35/37/36 | 0.47 | 1.02 | 0.80 | 0.38 | 12/11 | chain out of order; straight path; foot slide |
| Finisher_Stab_Through_Victim | 2.00 | 1 | 11 | 2 | 7 | 16/11/15/15/15 | 0.27 | 1.00 | 0.11 | 0.12 | 24/24 | chain out of order; straight path; no follow-through; foot slide |
| Finisher_Overhead_Cleave | 1.80 | 1 | 14 | 2 | 39 | 17/18/21/21/20 | 0.01 | 1.00 | 0.51 | 0.32 | 11/8 | chain out of order; straight path; foot slide |
| Finisher_Overhead_Cleave_Victim | 1.80 | 1 | 18 | 2 | 5 | 22/20/20/21/21 | 0.68 | 1.00 | 0.53 | 0.08 | 8/5 | chain out of order; flat slap; straight path; foot slide |
| Finisher_Spin_Slash | 1.67 | 1 | 5 | 6 | 51 | 15/16/3/16/16 | 0.02 | 5.14 | 0.57 | 0.28 | 117/113 | floaty strike (6 fast f); chain out of order; foot slide |
| Finisher_Spin_Slash_Victim | 1.67 | 2 | 28 | 3 | 7 | 27/27/32/32/32 | 0.75 | 1.00 | 0.09 | 0.13 | 4/3 | flat slap; straight path; no follow-through |
| Sword_Heavy_Charge_Start | 0.33 | 1 | 1 | 3 | 19 | 4/4/4/3/4 | 0.77 | 1.04 | 0.64 | 0.09 | 5/8 | no anticipation; chain out of order; flat slap; straight path |
| Sword_Heavy_Charge_Hold | 1.00 | 2 | 1 | 6 | 0 | 1/5/4/3/3 | 0.55 | 2.48 | 0.26 | 0.0 | 3/2 | no anticipation; floaty strike (6 fast f); chain out of order |
| Sword_Heavy_Release | 1.20 | 1 | 1 | 3 | 40 | 4/4/5/5/5 | 0.04 | 1.16 | 0.37 | 0.42 | 8/7 | no anticipation; foot slide |
| Sword_Run_Attack | 1.00 | 1 | 3 | 2 | 43 | 7/7/8/8/8 | 0.11 | 1.00 | 0.90 | 1.36 | 88/108 | straight path; foot slide |
| TwoHand_Overhead | 1.50 | 1 | 12 | 2 | 45 | 16/16/17/17/17 | 0.04 | 1.00 | 0.73 | 0.28 | 12/9 | straight path; foot slide; blade through body x1 |
| Spear_Thrust_1 | 0.80 | 1 | 3 | 3 | 8 | 6/6/5/6/6 | 0.07 | 1.00 | 0.07 | 0.12 | 6/6 | chain out of order; straight path; no follow-through |
| Spear_Thrust_2 | 0.93 | 1 | 4 | 3 | 10 | 7/7/6/7/7 | 0.23 | 1.00 | 0.08 | 0.09 | 8/7 | chain out of order; straight path; no follow-through; foot slide |
| Spear_Thrust_3 | 1.33 | 1 | 5 | 4 | 10 | 8/8/7/7/7 | 0.35 | 1.85 | 0.72 | 0.02 | 9/10 | chain out of order; foot slide |
| Bow_Draw | 0.53 | 1 | 1 | 3 | 5 | 4/4/6/6/6 | 0.68 | 1.06 | 0.28 | 0.0 | 14/9 | no anticipation; flat slap; straight path; foot slide |
| Bow_Hold | 1.20 | 3 | 12 | 2 | 0 | 9/9/11/12/12 | 0.15 | 1.00 | 0.06 | 0.0 | 0/0 | straight path; no follow-through |
| Bow_Loose | 0.60 | 2 | 12 | 2 | 3 | 12/12/12/12/12 | 0.93 | 1.00 | 0.21 | 0.0 | 15/10 | no overlap (all joints peak together); flat slap; straight path; no follow-through; foot slide |
| Bow_Aim_Up | 0.10 | 1 | 1 | 4 | 0 | 0/0/1/0/0 | 0.0 | 0.00 | 0.00 | 0.0 | 0/0 | no anticipation; chain out of order; straight path; no follow-through; blade through body x5 |
| Bow_Aim_Down | 0.10 | 1 | 1 | 4 | 0 | 0/0/0/0/0 | 0.0 | 0.00 | 0.00 | 0.0 | 0/0 | no anticipation; no overlap (all joints peak together); straight path; no follow-through |
| Death_1H_Front | 1.60 | 1 | 1 | 2 | 20 | 2/2/2/2/1 | 0.39 | 1.00 | 1.42 | 0.06 | 16/13 | no anticipation; chain out of order; straight path; foot slide |
| Death_1H_Back | 1.80 | 1 | 1 | 2 | 26 | 2/2/2/1/1 | 0.4 | 1.00 | 2.58 | 0.02 | 19/20 | no anticipation; chain out of order; straight path; foot slide |
| Death_2H_Knees | 2.20 | 1 | 4 | 3 | 16 | 2/9/8/1/8 | 0.04 | 1.06 | 0.01 | 0.07 | 20/12 | chain out of order; straight path; no follow-through; foot slide |
| Death_Bow_Side | 1.50 | 2 | 1 | 3 | 6 | 4/2/2/2/2 | 0.75 | 1.00 | 1.61 | 0.08 | 12/76 | no anticipation; chain out of order; flat slap; straight path; foot slide |
