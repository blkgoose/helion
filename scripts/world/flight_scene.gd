class_name FlightScene
extends Node3D
## The tactical 3D scene. The own ship sits at the origin (floating origin): every other position
## is relative to it, so float32 rendering never sees sector-scale coordinates.

# Shown only once another ship is genuinely close; up close it's the only cheap way to judge
# clearance against a ship's true collision envelope.
const BOUNDING_SPHERE_RANGE_M := 10000.0
const SHIP_EMITTER_DISTANCE_MULT := 30.0

var camera: TacticalCamera
var starfield: Starfield

var _skybox: Skybox
var _cage: OrientationCage
var _own_ship: ShipVisual
var _own_light: OmniLight3D
var _contacts := {}
var _contact_pickables: Array = []
var _hover: MeshInstance3D


class ShipVisual:
	extends Node3D

	var radius: float
	var _placeholder: MeshInstance3D
	var _bounding: MeshInstance3D
	var _upgraded := false

	func _init(r: float, color: Color) -> void:
		radius = r
		var mesh := SphereMesh.new()
		mesh.radius = r
		mesh.height = r * 2.0
		mesh.radial_segments = 16
		mesh.rings = 12
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(color, 0.2)
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_placeholder = MeshInstance3D.new()
		_placeholder.mesh = mesh
		_placeholder.material_override = material
		add_child(_placeholder)

		_bounding = WireSphere.make(r, Color(1, 1, 1, 0.15))
		_bounding.visible = false
		add_child(_bounding)

	func set_bounding_sphere_visible(value: bool) -> void:
		_bounding.visible = value

	## Cheap to call every frame: a no-op once upgraded, or while the model is still loading.
	func upgrade() -> void:
		if _upgraded:
			return
		var model := Models.spawn("ship", radius)
		if model == null:
			return
		remove_child(_placeholder)
		_placeholder.queue_free()
		add_child(model)
		_upgraded = true


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.15
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	_cage = OrientationCage.new()
	add_child(_cage)
	_skybox = Skybox.new()
	add_child(_skybox)
	starfield = Starfield.new()
	add_child(starfield)

	# Unit radius 0.5 (diameter 1), scaled to the real size from GET's body.size.
	_own_ship = ShipVisual.new(0.5, Color("66ccff"))
	add_child(_own_ship)
	# The ship's own weak emitter, at the nose (local +X).
	_own_light = OmniLight3D.new()
	_own_light.light_color = Color("9fd0ff")
	_own_light.light_energy = 2.0
	_own_light.position = Vector3(0.5, 0, 0)
	_own_ship.add_child(_own_light)

	_hover = WireSphere.make(1.0, Color("7ac4dd", 0.18), 16)
	_hover.visible = false
	add_child(_hover)

	# Near 0.5 / far 1e5: a far/near ratio in the hundreds of millions breaks the light culler's frustum.
	camera = TacticalCamera.new()
	camera.near = 0.5
	camera.far = 1.0e5
	add_child(camera)
	camera.make_current()


func _process(_delta: float) -> void:
	_cage.follow(camera.position)
	_skybox.follow(camera.position)
	_own_ship.upgrade()
	for contact in _contacts.values():
		contact.visual.upgrade()


func set_own_ship_orientation(orientation: Quaternion) -> void:
	_own_ship.quaternion = orientation


## `size_m` is the ship's real diameter, from GET's body.size.
func set_own_ship_size(size_m: float) -> void:
	var s := maxf(0.1, size_m)
	_own_ship.scale = Vector3.ONE * s
	_own_light.omni_range = SHIP_EMITTER_DISTANCE_MULT * s


## contacts: [{entity_id, size (diameter), position (Vector3 relative to the ship)}].
func sync_contacts(contacts: Array) -> void:
	var seen := {}
	_contact_pickables = []
	for contact in contacts:
		var id: String = contact.entity_id
		seen[id] = true
		var entry: Dictionary = _contacts.get(id, {})
		if entry.is_empty():
			var radius := maxf(1.0, float(contact.size) / 2.0)
			var visual := ShipVisual.new(radius, Color("cc3333"))
			var node := Node3D.new()
			node.add_child(visual)
			add_child(node)
			entry = {"node": node, "visual": visual, "radius": radius}
			_contacts[id] = entry
		var position: Vector3 = contact.position
		entry.node.position = position
		entry.visual.set_bounding_sphere_visible(position.length() <= BOUNDING_SPHERE_RANGE_M)
		# Oversized invisible hit target: the visual body is often too small to click reliably.
		_contact_pickables.append({
			"kind": "ship",
			"entity_id": id,
			"center": position,
			"radius": maxf(30.0, entry.radius * 4.0),
		})

	for id in _contacts.keys():
		if not seen.has(id):
			_contacts[id].node.queue_free()
			_contacts.erase(id)


## Nearest pickable under the screen position: {kind:"ship", entity_id, ...} or {kind:"body", entry_index, body_kind, ...}, or {}.
func pick(screen_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var best := {}
	var best_t := INF
	for p in _contact_pickables:
		var t := _ray_sphere(origin, direction, p.center, p.radius)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = p
	for p in starfield.pickables:
		var t := _ray_sphere(origin, direction, p.center, p.radius)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"kind": "body", "entry_index": p.entry_index, "body_kind": p.kind, "center": p.center, "radius": p.radius}
	return best


func show_hover(target: Dictionary) -> void:
	if target.is_empty():
		_hover.visible = false
		return
	_hover.position = target.center
	# The hit targets are deliberately oversized; shrink the highlight so it hugs the object.
	_hover.scale = Vector3.ONE * float(target.radius) * 0.6
	_hover.visible = true


static func _ray_sphere(origin: Vector3, direction: Vector3, center: Vector3, radius: float) -> float:
	var oc := origin - center
	var b := oc.dot(direction)
	var c := oc.dot(oc) - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var root := sqrt(disc)
	var t := -b - root
	if t < 0.0:
		t = -b + root
	return t
