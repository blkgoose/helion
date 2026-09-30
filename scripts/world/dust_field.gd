class_name DustField
extends MeshInstance3D
## Motes of space dust in a box around the camera. The ship sits at the scene origin, so the dust is
## shifted by the ship's displacement each frame; that parallax is what sells speed. A second
## surface of line segments stretches each mote along the velocity into a streak.

const COUNT := 6000
const BOX_M := 400.0
# Apparent dust speed is log-compressed: real speeds span 1..60000+ m/s, but a 400 m box would alias to noise.
const VISUAL_SPEED_SCALE := 25.0
const STREAK_PER_VISUAL_MPS := 0.14
const STREAK_MIN_M := 3.0
const STREAK_MAX_M := 34.0

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, skip_vertex_transform;
uniform vec3 offset;
uniform vec3 cam;
uniform vec3 streak;
uniform float box = 400.0;
varying float fade;
void vertex() {
	vec3 p = mod(VERTEX - offset - cam, box) - 0.5 * box + cam;
	float d = length(p - cam);
	fade = clamp(1.0 - d / (0.5 * box), 0.0, 1.0);
	fade *= smoothstep(1.0, 6.0, d);
	float tail = COLOR.r;
	p -= streak * tail;
	fade *= mix(1.0, 0.05, tail);
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	POINT_SIZE = 2.5;
}
void fragment() {
	ALBEDO = vec3(0.75, 0.82, 1.0) * fade * 0.9;
	ALPHA = fade;
}
"""

var _material := ShaderMaterial.new()
var _offset := Vector3.ZERO


func _ready() -> void:
	var points := PackedVector3Array()
	for i in COUNT:
		points.append(Vector3(randf(), randf(), randf()) * BOX_M)

	var lines := PackedVector3Array()
	var line_colors := PackedColorArray()
	for p in points:
		lines.append(p)
		line_colors.append(Color(0, 0, 0, 1))
		lines.append(p)
		line_colors.append(Color(1, 0, 0, 1))

	var array_mesh := ArrayMesh.new()
	var point_arrays := []
	point_arrays.resize(Mesh.ARRAY_MAX)
	point_arrays[Mesh.ARRAY_VERTEX] = points
	point_arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color(0, 0, 0, 1)]).duplicate()
	var zero_colors := PackedColorArray()
	zero_colors.resize(points.size())
	zero_colors.fill(Color(0, 0, 0, 1))
	point_arrays[Mesh.ARRAY_COLOR] = zero_colors
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, point_arrays)
	var line_arrays := []
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX] = lines
	line_arrays[Mesh.ARRAY_COLOR] = line_colors
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)

	var shader := Shader.new()
	shader.code = SHADER
	_material.shader = shader
	_material.set_shader_parameter("box", BOX_M)
	mesh = array_mesh
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


func advance(_ship_delta: Vector3, camera_position: Vector3, velocity: Vector3) -> void:
	var speed := velocity.length()
	var direction := velocity / speed if speed > 0.5 else Vector3.ZERO
	var visual_speed := VISUAL_SPEED_SCALE * log(1.0 + speed / 10.0)
	_offset += direction * visual_speed * get_process_delta_time()
	_offset = Vector3(fposmod(_offset.x, BOX_M), fposmod(_offset.y, BOX_M), fposmod(_offset.z, BOX_M))
	_material.set_shader_parameter("offset", _offset)
	_material.set_shader_parameter("cam", camera_position)
	var length := clampf(visual_speed * STREAK_PER_VISUAL_MPS, STREAK_MIN_M, STREAK_MAX_M) if speed > 0.5 else 0.0
	_material.set_shader_parameter("streak", -direction * length)
