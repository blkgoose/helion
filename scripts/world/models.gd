class_name Models
## Ship/planet/asteroid glTF models, normalized once to a unit bounding sphere (radius 1, centered)
## so every spawn site just uniformly scales to the real radius.

const PATHS := {
	"ship": "res://assets/models/ship.glb",
	"planet": "res://assets/models/planet.glb",
	"asteroid": "res://assets/models/asteroid.glb",
}

# The ship model's forward axis doesn't match ION's local +X; +90 deg yaw fixes it.
const FORWARD_FIX := {"ship": Quaternion(Vector3.UP, PI / 2.0)}

static var _scenes := {}
static var _normalization := {}


static func preload_all() -> void:
	for kind in PATHS:
		ResourceLoader.load_threaded_request(PATHS[kind])


static func _scene(kind: String) -> PackedScene:
	if _scenes.has(kind):
		return _scenes[kind]
	var path: String = PATHS[kind]
	match ResourceLoader.load_threaded_get_status(path):
		ResourceLoader.THREAD_LOAD_LOADED:
			_scenes[kind] = ResourceLoader.load_threaded_get(path)
			return _scenes[kind]
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)
	return null


static func _collect_aabb(node: Node, xform: Transform3D, box: Array) -> void:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var aabb: AABB = t * (node as MeshInstance3D).mesh.get_aabb()
		box[0] = aabb if box[0] == null else (box[0] as AABB).merge(aabb)
	for child in node.get_children():
		_collect_aabb(child, t, box)


static func _normalization_for(kind: String, scene: PackedScene) -> Dictionary:
	if _normalization.has(kind):
		return _normalization[kind]
	var probe: Node = scene.instantiate()
	var box: Array = [null]
	_collect_aabb(probe, Transform3D.IDENTITY, box)
	probe.free()
	var result := {"scale": 1.0, "center": Vector3.ZERO}
	if box[0] != null:
		var aabb: AABB = box[0]
		var radius := aabb.size.length() / 2.0
		if radius > 0.0:
			result = {"scale": 1.0 / radius, "center": aabb.get_center()}
	_normalization[kind] = result
	return result


## A model of `kind` scaled to bounding-sphere radius `radius`, or null while it is still loading.
static func spawn(kind: String, radius: float) -> Node3D:
	var scene := _scene(kind)
	if scene == null:
		return null
	var norm := _normalization_for(kind, scene)
	var model: Node3D = scene.instantiate()
	var s: float = norm.scale
	model.scale = Vector3.ONE * s
	model.position = model.position - (norm.center as Vector3) * s
	var wrapper := Node3D.new()
	wrapper.add_child(model)
	if FORWARD_FIX.has(kind):
		wrapper.quaternion = FORWARD_FIX[kind]
	wrapper.scale = Vector3.ONE * radius
	return wrapper


static func is_ready(kind: String) -> bool:
	return _scene(kind) != null
