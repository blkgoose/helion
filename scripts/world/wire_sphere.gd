class_name WireSphere
## Three great circles as a faint wireframe sphere (Godot materials have no per-material wireframe).


static func make(radius: float, color: Color, segments := 24) -> MeshInstance3D:
	var verts := PackedVector3Array()
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		verts.append(Vector3(cos(a0), sin(a0), 0) * radius)
		verts.append(Vector3(cos(a1), sin(a1), 0) * radius)
		verts.append(Vector3(cos(a0), 0, sin(a0)) * radius)
		verts.append(Vector3(cos(a1), 0, sin(a1)) * radius)
		verts.append(Vector3(0, cos(a0), sin(a0)) * radius)
		verts.append(Vector3(0, cos(a1), sin(a1)) * radius)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
