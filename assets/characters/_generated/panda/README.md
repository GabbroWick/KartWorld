# panda — Hunyuan3D 2.1 shape

Input: `C:\Users\gabri\Progetti\KartWorld\assets\characters\_source\panda\panda_front.png`

model_raw.glb: geometria grezza, nessuna texture.

```json
{
  "tool": "Hunyuan3D-2.1 shape (fork mac-rocm, rasterizer non usato)",
  "input": "C:\\Users\\gabri\\Progetti\\KartWorld\\assets\\characters\\_source\\panda\\panda_front.png",
  "params": {
    "steps": 40,
    "octree": 256,
    "guidance": 5.0,
    "seed": 1234
  },
  "errors": [],
  "backend": {
    "kind": "rocm",
    "device": "cuda",
    "dtype": "torch.float16",
    "gpu": "AMD Radeon RX 9060 XT"
  },
  "t_preprocess_s": 2.2,
  "t_load_s": 36.9,
  "t_generate_s": 323.7,
  "vram_peak_gb": 12.32,
  "vram_reserved_gb": 12.5,
  "ram_peak_gb": 20.56,
  "vertices": 139689,
  "faces": 279376,
  "extents": [
    1.459,
    1.986,
    0.878
  ],
  "watertight": false,
  "glb_bytes": 5029568,
  "t_total_s": 363.1,
  "valid": true
}
```
