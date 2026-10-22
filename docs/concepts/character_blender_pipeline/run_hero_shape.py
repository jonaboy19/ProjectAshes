"""Local image-to-shape attempt: native Blender alpha input, no BRIA model."""
import sys,torch,numpy as np,trimesh
from pathlib import Path
sys.path.append(str(Path(__file__).parent/'scripts'))
from image_process import prepare_image
from triposg.pipelines.pipeline_triposg import TripoSGPipeline
p=Path(__file__).parent
image=prepare_image(str(p.parent/'TripoSR'/'hero_triposg_alpha.png'),bg_color=np.array([1.,1.,1.]),rmbg_net=None)
pipe=TripoSGPipeline.from_pretrained(str(p/'pretrained_weights/TripoSG'),torch_dtype=torch.float16,local_files_only=True)
pipe.enable_model_cpu_offload()
with torch.inference_mode():
 out=pipe(image=image,generator=torch.Generator(device='cuda').manual_seed(42),num_inference_steps=30,guidance_scale=7.,dense_octree_depth=7,hierarchical_octree_depth=8).samples[0]
if out[0] is None:raise RuntimeError('Geometry extraction failed; no usable mesh')
mesh=trimesh.Trimesh(out[0].astype(np.float32),np.ascontiguousarray(out[1]))
mesh.export(str(p/'hero_shape_attempt.glb'))
print('HERO_SHAPE_EXPORTED',len(mesh.faces),'triangles')
