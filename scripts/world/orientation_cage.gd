class_name OrientationCage
extends Node3D
## Deliberately fake attitude reference: fixed background stars plus two world-axis rings that only
## translate with the camera, never rotate, so turning is visible even with nothing else in view.

const STAR_COUNT := 3000
const STAR_RADIUS_M := 90000.0
const RING_RADIUS_M := 3000.0
const RING_SEGMENTS := 128


func _ready() -> void:
	add_child(PointCloud.make(PointCloud.random_sphere_points(STAR_COUNT, STAR_RADIUS_M), PackedColorArray(), 1.0, -1, 2.0))
	add_child(_ring(Color("2266aa"), true))
	add_child(_ring(Color("225533"), false))


func _ring(color: Color, horizontal: bool) -> MeshInstance3D:
	var points := PackedVector3Array()
	for i in RING_SEGMENTS + 1:
		var angle := float(i) / RING_SEGMENTS * TAU
		var a := cos(angle) * RING_RADIUS_M
		var b := sin(angle) * RING_RADIUS_M
		points.append(Vector3(a, 0, b) if horizontal else Vector3(a, b, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.5)
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = -1

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func follow(camera_position: Vector3) -> void:
	position = camera_position
