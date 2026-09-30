class_name Starfield
extends Node3D
## SystemMap entries (stars, planets, asteroids). The ship sits at the scene origin (floating origin).
##
## Distance trick: SystemMap's scan radius is 1 ly, so most entries are far too distant to render
## at true scale (and a planet 3 AU away would blow the depth range). Those are placed at a fixed
## stand-in distance (SKY_RADIUS_M) along their real direction, with their radius scaled in the
## same proportion so they keep their true angular size. Only a body whose surface is within
## NEAR_RENDER_M of the ship renders at its real position and real size, e.g. the planet an
## autopilot approach is arriving at.

const SKY_RADIUS_M := 30000.0
const MIN_VISUAL_RADIUS_M := 80.0
# ionizer uses a log depth buffer and can render true-scale out to 2e9 m; Godot's depth range
# can't, so true-scale rendering is limited to what fits inside the camera far plane.
const NEAR_RENDER_M := 60000.0
# A star is never flown up to, so true scale only makes sense within a handful of its own radii.
const STAR_NEAR_RENDER_RADII := 10.0
const STAR_COLOR := Color("fff4c2")
const PLANET_COLOR := Color("6699cc")

## Valid only against the entries passed to the last update(): {entry_index, kind, center, radius, position, distance_m}.
var pickables: Array = []

var _nodes := {}
var _light := DirectionalLight3D.new()
var _glow_texture: GradientTexture2D


func _ready() -> void:
	_light.light_color = Color("fff4e6")
	_light.light_energy = 0.0
	_light.shadow_enabled = true
	_light.directional_shadow_max_distance = 2000.0
	add_child(_light)

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 244 / 255.0, 194 / 255.0, 0.9), Color(1, 244 / 255.0, 194 / 255.0, 0.0)])
	_glow_texture = GradientTexture2D.new()
	_glow_texture.gradient = gradient
	_glow_texture.fill = GradientTexture2D.FILL_RADIAL
	_glow_texture.fill_from = Vector2(0.5, 0.5)
	_glow_texture.fill_to = Vector2(1.0, 0.5)
	_glow_texture.width = 128
	_glow_texture.height = 128


func update(ship_position: Dictionary, entries: Array) -> void:
	pickables = []
	var seen := {}
	var nearest_direction: Variant = null
	var nearest_distance := INF

	for entry_index in entries.size():
		var entry: Dictionary = entries[entry_index]
		var rel := IonMath.relative(ship_position, entry.position)
		var distance := IonMath.length(rel)
		if distance == 0.0:
			continue
		var direction := IonMath.to_vec3(rel).normalized()
		var kind: String = entry.kind
		var is_star := kind == "star"
		var real_radius := maxf(1.0, float(entry.diameter_m) / 2.0)
		var is_near := distance <= real_radius * STAR_NEAR_RENDER_RADII if is_star else (distance - real_radius) <= NEAR_RENDER_M

		var key := "%d:%s:%s" % [entry_index, kind, "near" if is_near else "far"]
		seen[key] = true
		var node: Node3D = _nodes.get(key)
		var position: Vector3
		var hit_radius: float

		if is_near:
			var model_kind := "asteroid" if kind == "asteroid" else "planet"
			if node != null and node.has_meta("fallback") and not is_star and Models.is_ready(model_kind):
				node.queue_free()
				node = null
				_nodes.erase(key)
			if node == null:
				node = _build_near(kind, is_star, real_radius, model_kind)
				add_child(node)
				_nodes[key] = node
			position = direction * distance
			node.position = position
			hit_radius = real_radius * 1.1
		else:
			var stand_in := SKY_RADIUS_M * (1.0 if is_star else 0.85)
			var visual_radius := maxf(MIN_VISUAL_RADIUS_M, (real_radius / distance) * stand_in)
			if node == null:
				node = _build_proxy(is_star)
				add_child(node)
				_nodes[key] = node
			if is_star:
				(node as MeshInstance3D).scale = Vector3.ONE * visual_radius * 3.0
			else:
				node.scale = Vector3.ONE * visual_radius
			position = direction * stand_in
			node.position = position
			hit_radius = visual_radius * 1.6

		pickables.append({
			"entry_index": entry_index,
			"kind": kind,
			"center": position,
			"radius": hit_radius,
			"position": position,
			"distance_m": distance,
		})

		if is_star and distance < nearest_distance:
			nearest_distance = distance
			nearest_direction = direction

	for key in _nodes.keys():
		if not seen.has(key):
			_nodes[key].queue_free()
			_nodes.erase(key)

	if nearest_direction != null:
		var up := Vector3.RIGHT if absf((nearest_direction as Vector3).y) > 0.99 else Vector3.UP
		_light.basis = Basis.looking_at(-(nearest_direction as Vector3), up)
		_light.light_energy = 1.4
	else:
		_light.light_energy = 0.0


func _build_near(kind: String, is_star: bool, real_radius: float, model_kind: String) -> Node3D:
	if not is_star:
		var model := Models.spawn(model_kind, real_radius)
		if model != null:
			return model
	# DoubleSide: "arrived" only needs distance-to-surface under the arrival radius, so the camera
	# can already be inside the sphere, and default backface culling would make it vanish.
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = STAR_COLOR if is_star else PLANET_COLOR
	if is_star:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := SphereMesh.new()
	mesh.radius = real_radius
	mesh.height = real_radius * 2.0
	mesh.radial_segments = 32
	mesh.rings = 24
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.set_meta("fallback", true)
	return instance


func _build_proxy(is_star: bool) -> Node3D:
	var instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = -1
	if is_star:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		instance.mesh = quad
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.albedo_texture = _glow_texture
		material.albedo_color = STAR_COLOR
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 16
		sphere.rings = 10
		instance.mesh = sphere
		material.albedo_color = PLANET_COLOR
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
