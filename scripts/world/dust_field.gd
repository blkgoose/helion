class_name DustField
extends MeshInstance3D
## Motes of space dust in a box around the camera. The ship sits at the scene origin, so the dust is
## shifted by the ship's displacement each frame; that parallax is what sells speed.

const COUNT := 1800
const BOX_M := 400.0

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, skip_vertex_transform;
uniform vec3 offset;
uniform vec3 cam;
uniform float box = 400.0;
varying float fade;
void vertex() {
	vec3 p = mod(VERTEX - offset - cam, box) - 0.5 * box + cam;
	float d = length(p - cam);
	fade = clamp(1.0 - d / (0.5 * box), 0.0, 1.0);
	fade *= smoothstep(1.0, 6.0, d);
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	POINT_SIZE = 2.0;
}
void fragment() {
	ALBEDO = vec3(0.75, 0.82, 1.0) * fade * 0.55;
	ALPHA = fade;
}
"""

var _material := ShaderMaterial.new()
var _offset := Vector3.ZERO


func _ready() -> void:
	var positions := PackedVector3Array()
	for i in COUNT:
		positions.append(Vector3(randf(), randf(), randf()) * BOX_M)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var shader := Shader.new()
	shader.code = SHADER
	_material.shader = shader
	_material.set_shader_parameter("box", BOX_M)
	mesh = array_mesh
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


## `ship_delta`: how far the ship moved (world frame) since the last call.
func advance(ship_delta: Vector3, camera_position: Vector3) -> void:
	_offset += ship_delta
	_offset = Vector3(fposmod(_offset.x, BOX_M), fposmod(_offset.y, BOX_M), fposmod(_offset.z, BOX_M))
	_material.set_shader_parameter("offset", _offset)
	_material.set_shader_parameter("cam", camera_position)
