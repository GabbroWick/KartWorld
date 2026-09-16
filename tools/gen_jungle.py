"""Generates scenes/levels/level_04_jungle.tscn ("Ponti della Giungla").
Run: python tools/gen_jungle.py (then reimport). Edit the numbers here.

On foot only, along -Z: start pad -> plank bridge over the river (gaps to
jump) -> jungle clearing with slimes -> log ferries across the wide river
-> vine swing over the gorge -> tree platform with a star -> second
bridge -> goal door. Lethal water below every crossing (checkpoints on
each bank). Palms from the Kenney nature kit as ModelProps.
"""
import os, random
os.chdir(r"C:\Users\gabri\Progetti\KartWorld")

ROCK = (0.45, 0.4, 0.34)
GRASS = (0.36, 0.62, 0.3)
WOOD = (0.55, 0.38, 0.22)

def block(name, x, top, z, sx, sy, sz, col, extra=""):
    return '''[node name="%s" parent="." instance=ExtResource("1_block")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, %g, %g)
size = Vector3(%g, %g, %g)
color = Color(%g, %g, %g, 1)
%s
''' % (name, x, top - sy / 2, z, sx, sy, sz, *col, extra)

def palm(name, x, y, z, model_id, scale=2.6, yaw=0.0):
    import math
    c, s_ = math.cos(yaw), math.sin(yaw)
    return '''[node name="%s" parent="." instance=ExtResource("16_tree")]
transform = Transform3D(%g, 0, %g, 0, 1, 0, %g, 0, %g, %g, %g, %g)
model = ExtResource("%s")
model_scale = %g
apply_palette = true

''' % (name, c, s_, -s_, c, x, y, z, model_id, scale)

parts = []
scene = '''[gd_scene load_steps=21 format=3]

[ext_resource type="PackedScene" path="res://scenes/world/props/placeholder_block.tscn" id="1_block"]
[ext_resource type="PackedScene" path="res://scenes/world/props/portal.tscn" id="3_portal"]
[ext_resource type="PackedScene" path="res://scenes/gameplay/star.tscn" id="4_star"]
[ext_resource type="PackedScene" path="res://scenes/gameplay/checkpoint.tscn" id="5_checkpoint"]
[ext_resource type="Script" path="res://scripts/levels/level_controller.gd" id="6_controller"]
[ext_resource type="Script" path="res://scripts/levels/reach_destination_objective.gd" id="7_reach"]
[ext_resource type="Script" path="res://scripts/levels/collect_objective.gd" id="8_collect"]
[ext_resource type="PackedScene" path="res://scenes/enemies/enemy.tscn" id="9_enemy"]
[ext_resource type="Resource" path="res://resources/enemies/slime.tres" id="10_slime"]
[ext_resource type="Script" path="res://scripts/levels/defeat_enemies_objective.gd" id="11_defeat"]
[ext_resource type="PackedScene" path="res://scenes/gameplay/hazard.tscn" id="13_hazard"]
[ext_resource type="PackedScene" path="res://scenes/gameplay/moving_platform.tscn" id="14_platform"]
[ext_resource type="PackedScene" path="res://scenes/gameplay/vine.tscn" id="15_vine"]
[ext_resource type="PackedScene" path="res://scenes/world/props/kenney_tree.tscn" id="16_tree"]
[ext_resource type="PackedScene" path="res://assets/models/kenney/nature-kit/tree_palm.glb" id="17_palm1"]
[ext_resource type="PackedScene" path="res://assets/models/kenney/nature-kit/tree_palmBend.glb" id="17_palm2"]
[ext_resource type="PackedScene" path="res://assets/models/kenney/nature-kit/tree_palmDetailedTall.glb" id="17_palm3"]
[ext_resource type="PackedScene" path="res://assets/models/kenney/nature-kit/tree_palmShort.glb" id="17_palm4"]

[sub_resource type="ProceduralSkyMaterial" id="sky_material"]
sky_top_color = Color(0.2, 0.5, 0.8, 1)
sky_horizon_color = Color(0.75, 0.9, 0.85, 1)
ground_horizon_color = Color(0.3, 0.5, 0.35, 1)
ground_bottom_color = Color(0.1, 0.2, 0.12, 1)

[sub_resource type="Sky" id="sky"]
sky_material = SubResource("sky_material")

[sub_resource type="Environment" id="environment"]
background_mode = 2
sky = SubResource("sky")
ambient_light_source = 1
reflected_light_source = 1
tonemap_mode = 0
fog_enabled = true
fog_mode = 0
fog_light_color = Color(0.6, 0.8, 0.65, 1)
fog_sun_scatter = 0.0
fog_density = 0.004
fog_aerial_perspective = 0.3
fog_sky_affect = 0.0

[node name="Jungle" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("environment")

[node name="SunLight" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-55, 25, 0)
light_energy = 0.72
light_color = Color(1, 0.98, 0.9, 1)
shadow_enabled = true
shadow_opacity = 0.7
directional_shadow_max_distance = 120.0

[node name="PlayerSpawn" type="Marker3D" parent="." groups=["player_spawn"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.6, 0)

[node name="LevelController" type="Node" parent="." groups=["level_controller"]]
script = ExtResource("6_controller")
completion_delay = 3.5

[node name="ReachEnd" type="Node" parent="LevelController"]
script = ExtResource("7_reach")
description = "OBJ_CROSS_JUNGLE"
goal_zone = NodePath("../../GoalPortal")

[node name="DefeatSlimes" type="Node" parent="LevelController"]
script = ExtResource("11_defeat")
description = "OBJ_DEFEAT_SLIMES"
optional = true
required = 0

[node name="CollectStars" type="Node" parent="LevelController"]
script = ExtResource("8_collect")
description = "OBJ_COLLECT_STARS"
optional = true
kind = &"star"
required = 0

[node name="River" parent="." instance=ExtResource("13_hazard")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -3.5, -120)
size = Vector3(160, 1, 300)
color = Color(0.2, 0.5, 0.75, 1)
glow = 0.0
lethal = true

'''
# start pad and first bridge (planks with gaps) from z=0 to z=-40
scene += block("StartPad", 0, 0, 4, 14, 1, 14, GRASS)
scene += '''[node name="ReturnPortal" parent="." instance=ExtResource("3_portal")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 0, 8)
rotation_degrees = Vector3(0, -150, 0)

'''
z = -4.0
i = 0
while z > -40:
    scene += block("Plank%d" % i, 0, 0, z - 1.7, 2.2, 0.25, 3.4, WOOD)
    z -= 4.8   # 3.4 m plank, 1.4 m gap: a walking jump clears it
    i += 1
scene += block("Bank1", 0, 0, -48, 30, 1, 16, GRASS)
scene += '''[node name="Checkpoint1" parent="." instance=ExtResource("5_checkpoint")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -4, 0, -48)

[node name="Slime1" parent="." instance=ExtResource("9_enemy")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 6, 0.3, -46)
definition = ExtResource("10_slime")

[node name="Slime2" parent="." instance=ExtResource("9_enemy")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -8, 0.3, -52)
definition = ExtResource("10_slime")

'''
# log ferries across a wide river: z from -56 to -84
scene += '''[node name="Log1" parent="." instance=ExtResource("14_platform")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.4, -62)
size = Vector3(3.5, 0.8, 2.2)
color = Color(0.5, 0.33, 0.18, 1)
travel = Vector3(9, 0, 0)
period = 3.5
pause = 0.6

[node name="Log2" parent="." instance=ExtResource("14_platform")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 9, -0.4, -70)
size = Vector3(3.5, 0.8, 2.2)
color = Color(0.5, 0.33, 0.18, 1)
travel = Vector3(-9, 0, 0)
period = 3.5
pause = 0.6
phase = 0.5

[node name="Log3" parent="." instance=ExtResource("14_platform")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.4, -78)
size = Vector3(3.5, 0.8, 2.2)
color = Color(0.5, 0.33, 0.18, 1)
travel = Vector3(9, 0, 0)
period = 3.5
pause = 0.6
phase = 0.25

[node name="StarRiver" parent="." instance=ExtResource("4_star")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 4.5, 2.5, -70)

'''
scene += block("Bank2", 0, 0, -92, 30, 1, 14, GRASS)
scene += '''[node name="Checkpoint2" parent="." instance=ExtResource("5_checkpoint")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 0, -92)

[node name="Slime3" parent="." instance=ExtResource("9_enemy")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -6, 0.3, -95)
definition = ExtResource("10_slime")

'''
# vine swing over the gorge: from bank2 edge (z -99) to the tree platform at z -122
scene += '''[node name="Vine1" parent="." instance=ExtResource("15_vine")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -99)
height = 6.0
forward_boost = 13.0

'''
scene += block("TreePlatform", 0, 3, -124, 10, 1, 10, WOOD)
scene += block("TreeTrunk", 0, 2.5, -124, 1.6, 5, 1.6, (0.4, 0.28, 0.16))
scene += '''[node name="StarTree" parent="." instance=ExtResource("4_star")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 6.5, -124)

[node name="Checkpoint3" parent="." instance=ExtResource("5_checkpoint")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 3, 3, -124)

'''
# second vine down to bank 3
scene += '''[node name="Vine2" parent="." instance=ExtResource("15_vine")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3, -129)
height = 4.0
forward_boost = 14.0

'''
scene += block("Bank3", 0, 0, -152, 26, 1, 20, GRASS)
# second plank bridge, narrower
z = -162.0
i = 20
while z > -196:
    scene += block("Plank%d" % i, 0, 0, z - 1.7, 1.6, 0.25, 3.4, WOOD)
    z -= 4.9
    i += 1
scene += block("EndPad", 0, 0, -205, 14, 1, 14, GRASS)
scene += '''[node name="StarEnd" parent="." instance=ExtResource("4_star")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -4, 2.2, -203)

[node name="GoalPlinth" parent="." instance=ExtResource("1_block")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.05, -207)
size = Vector3(6, 0.1, 6)
color = Color(1, 0.85, 0.3, 1)

[node name="GoalPortal" parent="." instance=ExtResource("3_portal")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -209)
completes_level = true

'''
# palms on the banks
rng = random.Random(4)
palms = ["17_palm1", "17_palm2", "17_palm3", "17_palm4"]
k = 0
for (cx, cz, w, d) in [(0, 4, 14, 14), (0, -48, 30, 16), (0, -92, 30, 14), (0, -152, 26, 20), (0, -205, 14, 14)]:
    for n in range(4):
        px = cx + rng.uniform(-w * 0.45, w * 0.45)
        pz = cz + rng.uniform(-d * 0.45, d * 0.45)
        if abs(px) < 3.0 and (cz in (4, -205) or abs(pz - cz) > 5):
            px += 6.0 if px >= 0 else -6.0
        scene += palm("Palm%d" % k, round(px, 1), 0.0, round(pz, 1), palms[k % 4], rng.uniform(2.2, 3.0), rng.uniform(0, 6.28))
        k += 1
open("scenes/levels/level_04_jungle.tscn", "w", encoding="utf-8", newline="\n").write(scene)
print("ok", i, "planks,", k, "palms")
