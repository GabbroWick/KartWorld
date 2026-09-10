# Meshy characters

AI-generated character models (Meshy, text-to-3D, stylized preset). Generated
by the project owners; see the Meshy terms for the plan in use.

* `leopard.glb` — the player character. Static mesh (no rig), 89k triangles,
  three 2048² JPEG textures (base colour, metallic-roughness, normal), pivot
  at the model centre, faces +Z.

`MeshyCharacterVisual` (scenes/characters/visuals/leopard_meshy.tscn) puts
the feet on the ground, flips the model to -Z, flattens the PBR material
(no metallic / normal map, so it reads like the flat Kenney props on the
Compatibility renderer) and adds whole-body procedural motion.

For real limb animation the mesh needs a rig: Meshy's auto-rig is a paid
feature; Mixamo (free) auto-rigs bipeds from an FBX/OBJ export and provides
walk/run/jump clips, which Godot 4.7 imports natively.
