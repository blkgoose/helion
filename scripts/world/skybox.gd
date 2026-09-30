class_name Skybox
extends Node3D
## Procedural night sky standing in for the stars: dim, small, drawn first with no depth writes,
## plus one faint galaxy smudge for depth. Recentered on the camera so it reads as infinitely far.

const STAR_COUNT := 4000
const SKY_RADIUS := 50000.0
const STAR_OPACITY := 0.35
const GALAXY_DIRECTION := Vector3(0.4, 0.22, 0.89)


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

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([
		Color(200 / 255.0, 205 / 255.0, 1.0, 0.35),
		Color(160 / 255.0, 170 / 255.0, 225 / 255.0, 0.16),
		Color(160 / 255.0, 170 / 255.0, 225 / 255.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = texture
	material.albedo_color = Color(1, 1, 1, 0.5)
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.render_priority = -2

	var quad := QuadMesh.new()
	quad.size = Vector2(SKY_RADIUS * 0.9, SKY_RADIUS * 0.45)
	var galaxy := MeshInstance3D.new()
	galaxy.mesh = quad
	galaxy.material_override = material
	galaxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	galaxy.position = GALAXY_DIRECTION.normalized() * SKY_RADIUS * 0.98
	add_child(galaxy)


func follow(camera_position: Vector3) -> void:
	position = camera_position
