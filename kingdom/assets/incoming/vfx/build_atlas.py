import numpy as np
from PIL import Image
import shutil, os
S='/tmp/claude-0/src/'
K=S+'kenney-particle-pack/addons/kenney_particle_pack/'
R=S+'Godot-particle-and-vfx-textures/textures/256/'
OUT='/home/user/ProjectAshes/kingdom/assets/incoming/vfx/'
cells=[('k','flame_05'),('k','muzzle_02'),('k','smoke_04'),('k','fire_01'),
       ('k','spark_05'),('k','spark_01'),('k','star_06'),('k','star_08'),
       ('k','twirl_02'),('k','slash_02'),('k','scorch_02'),('k','dirt_02'),
       ('k','trace_06'),('k','light_03'),('r','effect_1'),('r','effect_4')]
C=256; PAD=8
atlas=np.zeros((C*4,C*4),np.float32)
for i,(src,name) in enumerate(cells):
    if src=='k':
        p=K+name+'.png'; shutil.copy(p, OUT+'kenney_particle_pack/'+name+'.png')
        im=Image.open(p).convert('RGBA').resize((C-2*PAD,C-2*PAD),Image.LANCZOS)
        a=np.asarray(im,np.float32)/255.0
        v=a[...,:3].mean(-1)*a[...,3]
    else:
        p=R+name+'.png'; shutil.copy(p, OUT+'rpicster_vfx_textures/'+name+'.png')
        im=Image.open(p).convert('L').resize((C-2*PAD,C-2*PAD),Image.LANCZOS)
        v=np.asarray(im,np.float32)/255.0
    v=v/max(v.max(),1e-3)
    r,c=divmod(i,4)
    atlas[r*C+PAD:(r+1)*C-PAD, c*C+PAD:(c+1)*C-PAD]=v
Image.fromarray((atlas*255).clip(0,255).astype(np.uint8),'L').save(OUT+'atlas/vfx_atlas.png',optimize=True)
# Tileable fractal noise (own work): band-limited random field via FFT is periodic by construction.
rng=np.random.default_rng(7)
N=256
def field(power):
    f=np.fft.fftfreq(N)
    fx,fy=np.meshgrid(f,f)
    k=np.sqrt(fx**2+fy**2); k[0,0]=1
    spec=(rng.normal(size=(N,N))+1j*rng.normal(size=(N,N)))/k**power
    spec[0,0]=0
    x=np.real(np.fft.ifft2(spec)); x=(x-x.min())/(x.max()-x.min()); return x
n1=field(1.6); n2=field(1.1)
# R: soft fbm, G: finer fbm, B: cellular-ish ridges for cracks/energy
ridge=1-np.abs(field(1.4)*2-1)
img=np.stack([n1,n2,ridge**2],-1)
Image.fromarray((img*255).astype(np.uint8),'RGB').save(OUT+'atlas/vfx_noise.png',optimize=True)
print('ok')
