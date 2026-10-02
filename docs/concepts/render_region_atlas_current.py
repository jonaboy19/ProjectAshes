"""Render exported generator data; does not infer undiscovered gameplay knowledge."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
atlas = json.loads((HERE / 'region_atlas_current.json').read_text())
low, high_bound = atlas['bounds']
span = high_bound-low
grid = Image.new('RGB', (128, 128))
for z in range(128):
    for x in range(128):
        h = atlas['height_grid'][z][x]
        f = atlas['forest_grid'][z][x]
        slope = atlas['height_grid'][z][x+1] + atlas['height_grid'][z+1][x] - 2*h
        shade = max(-18, min(18, slope*.55))
        high = max(0, min(1, (h-60)/130))
        rgb = (98,154,174) if atlas['water_grid'][z][x] else (
            int(191+high*32-f*43-shade), int(196+high*15-f*37-shade), int(142+high*51-f*22-shade))
        grid.putpixel((x,z), tuple(max(0,min(255,v)) for v in rgb))
canvas = Image.new('RGB',(1320,1220),'#151923')
canvas.paste(grid.resize((1000,1000),Image.Resampling.BILINEAR),(80,125))
draw = ImageDraw.Draw(canvas)
def font(size, serif=False):
    return ImageFont.truetype('C:/Windows/Fonts/georgia.ttf' if serif else 'C:/Windows/Fonts/arial.ttf',size)
def point(pos):
    return (80+(pos[0]-low)/span*1000,125+(pos[1]-low)/span*1000)
draw.text((80,26),'THE ASHFORD VALE',font=font(32,True),fill='#eee4cd')
draw.text((80,75),f'Generator-backed authoring atlas | seed 1066 | {span/1000:.3f} km region | includes undiscovered towns',font=font(14),fill='#a9b4c5')
for river in atlas.get('rivers',[]):
    if len(river)>1:
        draw.line([point(p) for p in river],fill='#578ca4',width=3,joint='curve')
for site in atlas.get('sites',[]):
    x,y=point(site['pos'])
    draw.rectangle((x-1,y-1,x+1,y+1),fill='#947463')
for a,b in atlas['roads']:
    draw.line([point(atlas['towns'][a]['pos']),point(atlas['towns'][b]['pos'])],fill='#81694c',width=3)
labels=[]
for i,town in enumerate(atlas['towns']):
    x,y=point(town['pos']); r=8 if town['name']=='Kingsreach' else 5
    draw.ellipse((x-r,y-r,x+r,y+r),fill='#3c3429',outline='#f7edcf',width=2)
    label_font=font(14,True)
    for dx,dy in [(9,-18),(9,8),(9,-38),(-100,8),(9,28),(9,-58)]:
        lx,ly=x+dx,y+dy
        bbox=draw.textbbox((lx,ly),town['name'],font=label_font,stroke_width=2)
        if all(bbox[2]+4 < old[0] or old[2]+4 < bbox[0] or bbox[3]+4 < old[1] or old[3]+4 < bbox[1] for old in labels):
            break
    labels.append(bbox)
    if dy not in (-18,8):
        draw.line([(x,y),(lx,ly+8)],fill='#a9b4c5',width=1)
    draw.text((lx,ly),town['name'],font=label_font,fill='#302820',stroke_width=2,stroke_fill='#eee4cd')
    draw.text((1100,135+i*27),town['name'],font=font(13),fill='#eee4cd')
draw.line([(1040,215),(1040,160),(1030,178)],fill='#332b20',width=2)
draw.line([(1040,160),(1050,178)],fill='#332b20',width=2)
draw.text((1033,137),'N',font=font(18,True),fill='#332b20')
draw.line([(105,1095),(105+1000*1000/span,1095)],fill='#332b20',width=3)
draw.text((105,1070),'1 km',font=font(14),fill='#332b20')
draw.text((80,1150),f'{span/128:.0f} m relief/forest samples; river polylines. Brown: road connections. Small squares: generated sites.',font=font(13),fill='#a9b4c5')
draw.text((80,1176),'Design overview. Player map must retain discovery fog and dated intelligence reports.',font=font(13),fill='#a9b4c5')
canvas.save(HERE/'region_atlas_current.png')
print('ATLAS_RENDERED',len(atlas['towns']),'towns;',len(atlas['roads']),'road links')
