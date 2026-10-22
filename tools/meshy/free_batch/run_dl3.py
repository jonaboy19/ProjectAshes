import sys,subprocess,os,time
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0,os.path.dirname(__file__))
import spec_dl3 as spec
S='C:/Users/Jonna/Documents/ProjectAshes_art_staging'
B='C:/Program Files/Blender Foundation/Blender 5.2/blender.exe'
T=os.path.abspath(os.path.join(os.path.dirname(__file__),'..','optimize_free.py'))
only=set(int(x) for x in sys.argv[1:] if x.isdigit()) or None
for x in sys.argv[1:]:
    if ':' in x: k,v=x.split(':'); spec.VARIANT[int(k)]=v; only=(only or set())|{int(k)}
OUT=os.environ.get('OUTDIR','out')
os.makedirs(S+'/work3/logs',exist_ok=True)
def run(e):
    i,f,n,t,x,m,s,ac,sm,l1=e
    pre=f'{S}/work3/{OUT}/{f}/{n}'; t0=time.time()
    try:
        r=subprocess.run([B,'-b','--python',T,'--',f'{S}/work3/raw/{i:03d}.glb',pre,str(t),str(x),m,str(s),str(ac),str(sm),str(l1),spec.VARIANT.get(i,'vox'),os.environ.get('ISLAND_PCT','0')],capture_output=True,text=True,timeout=1500)
        out=r.stdout+r.stderr
    except subprocess.TimeoutExpired:
        out='TIMEOUT'
    open(f'{S}/work3/logs/{i:03d}.log','w').write(out)
    ok=[l for l in out.splitlines() if l.startswith('BAKED')]
    print(i,n,'OK' if ok else 'FAIL',f'{time.time()-t0:.0f}s',ok[0] if ok else out[-200:],flush=True)
with ThreadPoolExecutor(3) as ex: list(ex.map(run,[e for e in spec.B if only is None or e[0] in only]))
print('ALLDONE')
