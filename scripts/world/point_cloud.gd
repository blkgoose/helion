class_name PointCloud
## Unlit 1px points drawn before everything else, never writing depth: a pure backdrop.


static func make(positions: PackedVector3Array, colors: PackedColorArray, opacity: float, priority: int, size_px := 1.0) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	if colors.size() == positions.size():
		arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.use_point_size = true
	material.point_size = size_px
	material.vertex_color_use_as_albedo = colors.size() == positions.size()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 1, 1, opacity)
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = priority

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func random_sphere_points(count: int, radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in count:
		var theta := randf() * TAU
		var phi := acos(2.0 * randf() - 1.0)
		out.append(Vector3(sin(phi) * cos(theta), sin(phi) * sin(theta), cos(phi)) * radius)
	return out
