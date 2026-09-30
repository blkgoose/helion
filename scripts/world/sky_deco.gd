class_name SkyDeco
extends Node3D
## Stylised, deliberately unrealistic backdrop: a Milky Way band, coloured nebulae, spiral galaxies
## and a few bright stars. All additive billboards at sky distance, behind every planet proxy.

const RADIUS := 92000.0

const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform sampler2D noise : repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float intensity = 0.5;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float mask = smoothstep(1.0, 0.15, r);
	float n = clamp(texture(noise, UV).r, 0.0, 1.0);
	float d = pow(n, 1.6) * mask * intensity;
	ALBEDO = tint.rgb;
	ALPHA = clamp(d, 0.0, 1.0);
}
"""

const GALAXY_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float intensity = 1.0;
uniform float rotation = 0.0;
uniform float squash = 0.45;
uniform float twist = 5.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float c = cos(rotation); float s = sin(rotation);
	p = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
	p.y /= squash;
	float r = length(p);
	float theta = atan(p.y, p.x);
	float arms = 0.5 + 0.5 * cos(2.0 * theta - twist * log(r + 0.05));
	float disc = exp(-r * 2.6) * (0.35 + 0.65 * pow(arms, 2.0));
	float core = exp(-r * 14.0) * 1.0;
	float edge = smoothstep(1.0, 0.7, r);
	float d = (disc + core) * edge * intensity;
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.95, 0.85), clamp(core, 0.0, 1.0));
	ALPHA = clamp(d, 0.0, 1.0);
}
"""

var _rng := RandomNumberGenerator.new()
var _noises: Array[ImageTexture] = []
var _cloud_shader := Shader.new()
var _galaxy_shader := Shader.new()


func _ready() -> void:
	_rng.seed = 20260930
	_cloud_shader.code = CLOUD_SHADER
	_galaxy_shader.code = GALAXY_SHADER
	for i in 4:
		_noises.append(_make_noise(i))
	_milky_way()
	_nebulae()
	_galaxies()
	_bright_stars()


func _make_noise(seed_value: int) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 100 + seed_value * 37
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.frequency = 0.012
	var image := noise.get_image(256, 256)
	# FBM noise is centred on mid-grey; stretch it so the clouds have real gaps.
	for y in 256:
		for x in 256:
			var v := image.get_pixel(x, y).r
			v = clampf((v - 0.3) * 1.6, 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v, v, 1))
	return ImageTexture.create_from_image(image)


func _random_direction() -> Vector3:
	return Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()).normalized()


func _cloud(direction: Vector3, size: float, tint: Color, intensity: float, roll: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := ShaderMaterial.new()
	material.shader = _cloud_shader
	material.set_shader_parameter("noise", _noises[_rng.randi() % _noises.size()])
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("intensity", intensity)
	_billboard(quad, material, direction, roll)


func _billboard(quad: QuadMesh, material: ShaderMaterial, direction: Vector3, _roll: float) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = direction * RADIUS
	add_child(instance)


func _milky_way() -> void:
	var axis := Vector3(0.3, 1.0, 0.25).normalized()
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	for i in 70:
		var angle := _rng.randf() * TAU
		var spread := _rng.randfn(0.0, 0.07)
		var direction := (u * cos(angle) + v * sin(angle) + axis * spread).normalized()
		var warm := _rng.randf()
		var tint := Color(0.75, 0.8, 1.0).lerp(Color(1.0, 0.85, 0.65), warm * 0.6)
		_cloud(direction, _rng.randf_range(24000.0, 42000.0), tint, _rng.randf_range(0.05, 0.11), 0.0)


func _nebulae() -> void:
	# EVE-style: one dominant regional colour wash made of a few huge soft clouds, plus a couple of warm accents.
	var wash := Color("5a8fb0")
	for i in 5:
		_cloud(_random_direction(), _rng.randf_range(70000.0, 100000.0), wash.lerp(Color("7a6ab0"), _rng.randf() * 0.5), _rng.randf_range(0.08, 0.15), 0.0)
	for i in 2:
		_cloud(_random_direction(), _rng.randf_range(30000.0, 45000.0), Color("c08a60"), _rng.randf_range(0.05, 0.09), 0.0)


func _galaxies() -> void:
	var palette := [Color("a8c4ff"), Color("ffd6a0"), Color("d8b0ff"), Color("ffb0c8")]
	for i in 6:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * _rng.randf_range(9000.0, 20000.0)
		var material := ShaderMaterial.new()
		material.shader = _galaxy_shader
		material.set_shader_parameter("tint", palette[i % palette.size()])
		material.set_shader_parameter("intensity", _rng.randf_range(0.02, 0.045))
		material.set_shader_parameter("rotation", _rng.randf() * TAU)
		material.set_shader_parameter("squash", _rng.randf_range(0.3, 0.8))
		material.set_shader_parameter("twist", _rng.randf_range(3.0, 7.0))
		_billboard(quad, material, _random_direction(), 0.0)


func _bright_stars() -> void:
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	for i in 700:
		positions.append(_random_direction() * RADIUS * 0.99)
		colors.append(Color.from_hsv(_rng.randf_range(0.05, 0.65), _rng.randf_range(0.0, 0.5), 1.0))
	add_child(PointCloud.make(positions, colors, 0.22, -3, 1.5))
