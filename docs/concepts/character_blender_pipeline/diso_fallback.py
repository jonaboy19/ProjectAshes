"""Local inference-only fallback; NOT upstream differentiable dual marching cubes.
CPU Lewiner marching cubes changes extracted geometry. Validate outputs visually.
"""
import numpy as np
import torch
from skimage.measure import marching_cubes
class DiffDMC(torch.nn.Module):
 def __init__(self,dtype=torch.float32):
  super().__init__();self.dtype=dtype
 def forward(self,sdf,deform=None,return_quads=False,normalize=False):
  if deform is not None or return_quads or normalize:raise NotImplementedError('Local fallback supports plain triangle inference only')
  field=sdf.detach().float().cpu().numpy()
  valid=np.isfinite(field)
  field=np.nan_to_num(field,nan=1.0,posinf=1.0,neginf=-1.0)
  v,f,_,_=marching_cubes(field,level=0.0,gradient_direction='ascent',mask=valid)
  return torch.from_numpy(v.copy()).to(sdf.device),torch.from_numpy(f.astype(np.int64).copy()).to(sdf.device)
