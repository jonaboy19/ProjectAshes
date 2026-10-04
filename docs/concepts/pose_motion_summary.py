"""Summarize QA pose.csv against telemetry.csv. Metrics are diagnostics, not pass gates."""
import csv, json, math, sys
from pathlib import Path
folder = Path(sys.argv[1])
body = {int(r['frame']): r for r in csv.DictReader((folder/'telemetry.csv').open())}
previous = {}
summary = {}
for row in csv.DictReader((folder/'pose.csv').open()):
    frame = int(row['frame'])
    if frame not in body:
        continue
    key = (row['scenario'], row['bone'])
    stats = summary.setdefault('|'.join(key), {'samples':0,'max_relative_step_m':0,'max_rotation_step_deg':0,'min_ankle_terrain_gap_m':None})
    stats['samples'] += 1
    position = tuple(float(row[a])-float(body[frame][a]) for a in ('x','y','z'))
    rotation = tuple(float(row[a]) for a in ('qx','qy','qz','qw'))
    yaw = math.radians(float(body[frame]['model_yaw_deg']))
    cosine, sine = math.cos(yaw), math.sin(yaw)
    local_position = (cosine*position[0]-sine*position[2],position[1],sine*position[0]+cosine*position[2])
    half_sine, half_cosine = math.sin(-yaw/2), math.cos(-yaw/2)
    x,y,z,w = rotation
    local_rotation = (half_cosine*x+half_sine*z,half_cosine*y+half_sine*w,half_cosine*z-half_sine*x,half_cosine*w-half_sine*y)
    stats.setdefault('max_body_local_step_m',0)
    stats.setdefault('max_body_local_rotation_step_deg',0)
    old = previous.get(key)
    if old and old[0]+1 == frame:
        step = math.dist(position, old[1])
        dot = abs(sum(a*b for a,b in zip(rotation,old[2])))
        angle = math.degrees(2*math.acos(min(1,max(0,dot))))
        if step > stats['max_relative_step_m']:
            stats['max_relative_step_m'], stats['step_frame'] = step, frame
        if angle > stats['max_rotation_step_deg']:
            stats['max_rotation_step_deg'], stats['rotation_frame'] = angle, frame
        local_step = math.dist(local_position,old[3])
        local_dot = abs(sum(a*b for a,b in zip(local_rotation,old[4])))
        local_angle = math.degrees(2*math.acos(min(1,max(0,local_dot))))
        if local_step > stats['max_body_local_step_m']:
            stats['max_body_local_step_m'],stats['body_local_step_frame'] = local_step,frame
        if local_angle > stats['max_body_local_rotation_step_deg']:
            stats['max_body_local_rotation_step_deg'],stats['body_local_rotation_frame'] = local_angle,frame
    previous[key] = (frame,position,rotation,local_position,local_rotation)
    if row['bone'].startswith('foot_'):
        gap = float(row['terrain_gap'])
        if stats['min_ankle_terrain_gap_m'] is None or gap < stats['min_ankle_terrain_gap_m']:
            stats['min_ankle_terrain_gap_m'] = gap
report = {'limitations':['Ankle joint height is not sole clearance or a contact state.','Analytic terrain height excludes props and collision support.','Final bone poses use interpolated skeleton transforms; bone-local interpolation is not exposed.','Rapid authored swings can have large steps; these numbers do not establish a pop.'], 'metrics':summary}
output = folder/'pose_summary.json'
output.write_text(json.dumps(report,indent=2))
print(output)
