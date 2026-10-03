# TripoSR local pipeline handoff

Installed outside the game at C:/Users/Jonna/Documents/Codex/3d-tools/TripoSR. Official source revision 107cefdc244c39106fa830359024f6a2f1c78871, MIT source and weights. Isolated .venv uses CUDA torch 2.11.0+cu128 on RTX 4070 Laptop, transformers 4.44.2 and numpy 1.26.4. No paid API or credential.

Read LOCAL_SETUP.md in that folder for commands and dependency notes. Local torchmcubes.py uses CPU scikit-image extraction in place of the compiled extension; neural inference uses CUDA. Local run.py creates the numbered output directory even for --no-remove-bg.

prepare_mobile_prop.py preserves imported vertex colors, corrects TripoSR Z-up orientation (Blender imported quaternion rotation must first switch to XYZ), decimates below 3,000 triangles and normalizes the maximum dimension to 0.8 metres. It refuses existing export destinations. It does not generate collision, rigging, LODs or a production character.

The only committed result is incoming/ai3d/crate.glb, reconstructed from a Blender render of the existing project crate. Existing source ownership/license still applies. The comparison remains rejected: soft edges and pale surfaces are inferior to the original. Setting the color attribute node explicitly did not improve the rendered pale surface. Do not assume the material issue is solved or replace existing game assets with this result.

Before producing characters: prove an unrelated prop can preserve visible colors and normals, then assess topology and multi-view consistency. TripoSR produces a mesh, not an animation-ready customizable humanoid. The existing rigged character pipeline remains authoritative. This experiment adds no runtime AI cost to the phone.
