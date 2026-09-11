"""Sostituto puro-Python di `torchmcubes` (che richiede compilazione C++/CUDA).

TripoSR importa `from torchmcubes import marching_cubes`; qui la stessa firma
e' servita da scikit-image sulla CPU. Il volume e' 256^3 al massimo: meno di
un secondo. Aggiunto al PYTHONPATH dagli script in tools/ai3d.
"""
import numpy as np
import torch
from skimage import measure


def marching_cubes(volume: torch.Tensor, threshold: float = 0.0):
    vol = volume.detach().cpu().float().numpy()
    if vol.min() >= threshold or vol.max() <= threshold:
        raise ValueError("Marching cubes: nessuna superficie al livello %.3f" % threshold)
    verts, faces, _normals, _values = measure.marching_cubes(vol, level=threshold)
    # skimage restituisce gli indici (i, j, k) del volume, come torchmcubes.
    v = torch.from_numpy(np.ascontiguousarray(verts, dtype=np.float32))
    f = torch.from_numpy(np.ascontiguousarray(faces, dtype=np.int64))
    return v, f
