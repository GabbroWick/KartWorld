# Leopard (Meshy + Mixamo)

* `leopard.glb` — Meshy text-to-3D export with textures (static mesh, faces +Z,
  pivot at the centre, metallic 1.0). Kept for the material and as the
  unrigged fallback (`leopard_meshy.tscn`).
* `leopard_rig.fbx` — the same mesh auto-rigged by Mixamo, exported "with
  skin" together with the Breathing Idle clip. Mixamo read the metre-sized
  model as centimetres, so Godot imports it 100x too small: the visual scene
  applies `model_scale = 100`.
* `anim_walk/run/jump/fall.fbx` — Mixamo clips exported "without skin"; same
  skeleton (`mixamorig_*`, 41 bones). Walk and run are not "in place": the
  hips move forward, `RiggedCharacterVisual` strips that at load time.

Rebuilding: upload the **untextured** FBX to Mixamo (the textured one makes
the auto-rigger fail with "unable to map your existing skeleton"), rig with
the standard skeleton, download clips as FBX Binary 30 fps.
