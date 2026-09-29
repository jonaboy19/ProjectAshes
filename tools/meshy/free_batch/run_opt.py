import sys,subprocess,os,time
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0,os.path.dirname(__file__))
R2=os.environ.get('ROUND')=='2'
import importlib
spec=importlib.import_module('spec_r2' if R2 else 'spec')
OUT=os.environ.get('OUTDIR')
S='C:/Users/Jonna/Documents/ProjectAshes_art_staging'
B='C:/Program Files/Blender Foundation/Blender 5.2/blender.exe'
T='C:/Users/Jonna/Documents/ProjectAshes/tools/meshy/optimize_free.py'
WORK='work2' if R2 else 'work'
only=set(int(x) for x in sys.argv[1:] if x.isdigit()) if len(sys.argv)>1 else None
for x in sys.argv[1:]:
    if ':' in x: k,v=x.split(':'); spec.VARIANT[int(k)]=v; only=(only or set())|{int(k)}
os.makedirs(S+'/'+WORK+'/logs',exist_ok=True)
def run(e):
    i,f,n,t,x,m,s,ac,sm,l1=e
    pre=f'{S}/{WORK}/'+(OUT or 'out')+f'/{f}/{n}'
    log=f'{S}/{WORK}/logs/{i:03d}.log'
    t0=time.time()
    r=subprocess.run([B,'-b','--python',T,'--',f'{S}/{WORK}/raw/{i:03d}.glb',pre,str(t),str(x),m,str(s),str(ac),str(sm),str(l1),spec.VARIANT.get(i,'vox')],capture_output=True,text=True)
    open(log,'w').write(r.stdout+r.stderr)
    ok=[l for l in r.stdout.splitlines() if l.startswith('BAKED')]
    print(i,n,'OK' if ok else 'FAIL',f'{time.time()-t0:.0f}s',ok[0] if ok else r.stderr[-200:],flush=True)
todo=[e for e in spec.B if only is None or e[0] in only]
with ThreadPoolExecutor(4) as ex: list(ex.map(run,todo))
print('ALLDONE')
