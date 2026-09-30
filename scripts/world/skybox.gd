class_name Skybox
extends Node3D
## Procedural night sky standing in for the stars: dim, small, drawn first with no depth writes,
## plus one faint galaxy smudge for depth. Recentered on the camera so it reads as infinitely far.

const STAR_COUNT := 4000
const SKY_RADIUS := 95000.0
const STAR_OPACITY := 0.035


func _ready() -> void:
	var positions := PointCloud.random_sphere_points(STAR_COUNT, SKY_RADIUS)
	var colors := PackedColorArray()
	for i in STAR_COUNT:
		# Rough stellar-temperature spread: mostly white, a cool-blue and a warm-amber minority.
		var t := randf()
		var hue := 0.6 if t < 0.15 else (0.1 if t > 0.9 else 0.15)
		var saturation := 0.4 if (t < 0.15 or t > 0.9) else 0.05
		colors.append(Color.from_hsv(hue, saturation, 0.5 + randf() * 0.3))
	add_child(PointCloud.make(positions, colors, STAR_OPACITY, -2))


func follow(camera_position: Vector3) -> void:
	position = camera_position
