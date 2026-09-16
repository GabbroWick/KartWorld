"""Generates scenes/levels/level_03_volcano.tscn from a few numbers.
Run: python tools/gen_volcano.py (then reimport). Edit numbers here, not the .tscn."""
import math, os
os.chdir(r"C:\Users\gabri\Progetti\KartWorld")

C = (0.0, -150.0)          # volcano centre (x, z)
TURN_POINTS = 12
R0, R1 = 135.0, 85.0
H0, H1 = 3.2, 17.0

pts = [(135.0, 3.2, -168.0)]
for k in range(TURN_POINTS + 1):
    th = 2 * math.pi * k / TURN_POINTS
    r = R0 + (R1 - R0) * k / TURN_POINTS
    h = H0 + (H1 - H0) * k / TURN_POINTS
    pts.append((C[0] + r * math.cos(th), h, C[1] + r * math.sin(th)))
pts[-1] = (84.0, 17.0, -150.0)
flat = ", ".join("%.2f, %.2f, %.2f" % p for p in pts)
star_a = pts[8]

def block(name, x, top, z, sx, sy, sz, col, rot=None):
    t = "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, %g, %g)" % (x, top - sy / 2, z)
    return '''[node name="%s" parent="." instance=ExtResource("1_block")]
%s
size = Vector3(%g, %g, %g)
color = Color(%g, %g, %g, 1)

''' % (name, t, sx, sy, sz, *col)

ROCK = (0.42, 0.36, 0.36)
ROCK2 = (0.48, 0.42, 0.4)
scene = '''[gd_scene load_steps=19 format=3]

[ext_resource type="PackedScene" path="res://scenes/world/props/placeholder_block.tscn" id="1_block"]
[ext_resource type="PackedScene" path="res://scenes/world/props/placeholder_cone.tscn" id="2_cone"]
[ext_resource type="PackedScene" path="res://scenes/world/props/portal.tscn" id="3_portal"]
[ext_resource type="PackedScene" path="res://scenes/gameplay/star.tscn" id="4_star"]
[ext_resource type="PackedScene" path="res://scenes/gameplay/checkpoint.tscn" id="5_checkpoint"]
[ext_resource type="Script" path="res://scripts/levels/level_controller.gd" id="6_controller"]
[ext_resource type="Script" path="res://scripts/levels/reach_destination_objective.gd" id="7_reach"]
[ext_resource type="Script" path="res://scripts/levels/collect_objective.gd" id="8_collect"]
[ext_resource type="PackedScene" path="res://scenes/enemies/enemy.tscn" id="9_enemy"]
[ext_resource type="Resource" path="res://resources/enemies/slime.tres" id="10_slime"]
[ext_resource type="Script" path="res://scripts/levels/defeat_enemies_objective.gd" id="11_defeat"]
[ext_resource type="PackedScene" path="res://scenes/enemies/boss_slime.tscn" id="16_boss"]
[ext_resource type="PackedScene" path="res://scenes/world/props/track_ribbon.tscn" id="12_ribbon"]
[ext_resource type="PackedScene" path="res://scenes/gameplay/hazard.tscn" id="13_hazard"]
[ext_resource type="PackedScene" path="res://scenes/gameplay/moving_platform.tscn" id="14_platform"]
[ext_resource type="PackedScene" path="res://scenes/gameplay/spring.tscn" id="15_spring"]

[sub_resource type="ProceduralSkyMaterial" id="sky_material"]
sky_top_color = Color(0.35, 0.18, 0.2, 1)
sky_horizon_color = Color(0.95, 0.6, 0.4, 1)
ground_horizon_color = Color(0.5, 0.3, 0.25, 1)
ground_bottom_color = Color(0.15, 0.1, 0.1, 1)

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
fog_light_color = Color(0.85, 0.5, 0.35, 1)
fog_sun_scatter = 0.0
fog_density = 0.0025
fog_aerial_perspective = 0.4
fog_sky_affect = 0.0

[node name="Volcano" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("environment")

[node name="SunLight" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-45, 40, 0)
light_energy = 0.72
light_color = Color(1, 0.9, 0.8, 1)
shadow_enabled = true
shadow_opacity = 0.7
directional_shadow_max_distance = 160.0

[node name="PlayerSpawn" type="Marker3D" parent="." groups=["player_spawn"]]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 135, 3.4, -174)

[node name="LevelController" type="Node" parent="." groups=["level_controller"]]
script = ExtResource("6_controller")
completion_delay = 3.5

[node name="DefeatSlimes" type="Node" parent="LevelController"]
script = ExtResource("11_defeat")
description = "OBJ_DEFEAT_SLIMES"
required = 3
optional = true

[node name="DefeatBoss" type="Node" parent="LevelController"]
script = ExtResource("11_defeat")
description = "OBJ_DEFEAT_BOSS"
required = 1
boss_only = true

[node name="ReachCrater" type="Node" parent="LevelController"]
script = ExtResource("7_reach")
description = "OBJ_REACH_CRATER"
goal_zone = NodePath("../../GoalPortal")

[node name="CollectStars" type="Node" parent="LevelController"]
script = ExtResource("8_collect")
description = "OBJ_COLLECT_STARS"
optional = true
kind = &"star"
required = 0

[node name="Mound" parent="." instance=ExtResource("2_cone")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -150)
radius = 130.0
height = 17.0
sides = 24
color = Color(0.36, 0.28, 0.27, 1)

[node name="Ground" parent="." instance=ExtResource("1_block")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -1, -150)
size = Vector3(420, 2, 420)
color = Color(0.3, 0.22, 0.2, 1)

[node name="Track" parent="." instance=ExtResource("12_ribbon")]
points = PackedVector3Array(%s)
width = 10.0
subdivisions = 8
kerb_height = 0.8
ramp_at = PackedFloat32Array(0.3, 0.55, 0.8)

''' % flat

scene += block("StartPad", 135, 3.2, -172, 20, 1, 24, ROCK2)
scene += '''[node name="ReturnPortal" parent="." instance=ExtResource("3_portal")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 142, 3.2, -182)
rotation_degrees = Vector3(0, 30, 0)
returns_to_hub = true

[node name="StarTrack" parent="." instance=ExtResource("4_star")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.2f, %.2f, %.2f)

''' % (star_a[0], star_a[1] + 3.5, star_a[2])
scene += block("TopPad", 74, 17.05, -150, 24, 1, 24, ROCK2)
scene += '''[node name="Checkpoint1" parent="." instance=ExtResource("5_checkpoint")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 70, 17.05, -150)

[node name="LavaLake" parent="." instance=ExtResource("13_hazard")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 48, 11.5, -150)
size = Vector3(28, 1, 30)
lethal = true

[node name="Ferry1" parent="." instance=ExtResource("14_platform")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 58, 16.5, -150)
size = Vector3(4, 0.6, 4)
travel = Vector3(-8, 0, 0)
period = 3.0
pause = 0.8

[node name="Ferry2" parent="." instance=ExtResource("14_platform")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 46, 16.5, -150)
size = Vector3(4, 0.6, 4)
travel = Vector3(-8, 0, 0)
period = 3.0
pause = 0.8
phase = 0.5

[node name="StarLake" parent="." instance=ExtResource("4_star")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 48, 20.5, -150)

'''
scene += block("LavaBank", 31, 17.05, -150, 8, 1, 24, ROCK2)
scene += block("Walkway", 18, 17.05, -150, 20, 1, 8, ROCK)
scene += '''[node name="Spikes" parent="." instance=ExtResource("13_hazard")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 18, 17.25, -150)
size = Vector3(3, 0.4, 8)
color = Color(0.85, 0.85, 0.9, 1)
glow = 0.0
damage = 1.0
lethal = false

[node name="Spring1" parent="." instance=ExtResource("15_spring")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 9, 17.05, -150)
height = 10.0

'''
scene += block("Cliff1", 0, 25, -150, 12, 8, 12, ROCK)
scene += '''[node name="Spring2" parent="." instance=ExtResource("15_spring")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -3, 25, -150)
height = 10.0

'''
scene += block("Cliff2", -16, 33, -150, 12, 16, 12, ROCK)
scene += '''[node name="Checkpoint2" parent="." instance=ExtResource("5_checkpoint")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -16, 33, -150)

'''
scene += block("Crater", -46, 33, -150, 36, 2, 36, ROCK2)
scene += '''[node name="CraterLava" parent="." instance=ExtResource("13_hazard")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -46, 33.2, -150)
size = Vector3(8, 0.5, 8)
lethal = true

[node name="StarCrater" parent="." instance=ExtResource("4_star")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -46, 36.5, -150)

[node name="Slime1" parent="." instance=ExtResource("9_enemy")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -38, 33.3, -160)
definition = ExtResource("10_slime")

[node name="Slime2" parent="." instance=ExtResource("9_enemy")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -54, 33.3, -140)
definition = ExtResource("10_slime")

[node name="Slime3" parent="." instance=ExtResource("9_enemy")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -50, 33.3, -162)
definition = ExtResource("10_slime")

[node name="SlimeKing" parent="." instance=ExtResource("16_boss")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -46, 33.3, -136)

[node name="GoalPlinth" parent="." instance=ExtResource("1_block")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -60, 33.05, -150)
size = Vector3(6, 0.1, 6)
color = Color(1, 0.85, 0.3, 1)

[node name="GoalPortal" parent="." instance=ExtResource("3_portal")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -61, 33, -150)
rotation_degrees = Vector3(0, 90, 0)
completes_level = true
'''
open("scenes/levels/level_03_volcano.tscn", "w", encoding="utf-8", newline="\n").write(scene)
print("ok", len(pts), "track points; star A at", star_a)
