class_name Models
## CDN glTF models, normalized once to a unit bounding sphere (radius 1, centered)
## so every spawn site just uniformly scales to the real radius.

# The ship model's forward axis doesn't match ION's local +X; +90 deg yaw fixes it.
const FORWARD_FIX := {"ship": Quaternion(Vector3.UP, PI / 2.0)}

static var _normalization := {}


static func _collect_aabb(node: Node, xform: Transform3D, box: Array) -> void:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var aabb: AABB = t * (node as MeshInstance3D).mesh.get_aabb()
		box[0] = aabb if box[0] == null else (box[0] as AABB).merge(aabb)
	for child in node.get_children():
		_collect_aabb(child, t, box)


static func _normalization_for(key: String, scene: Node) -> Dictionary:
	if _normalization.has(key):
		return _normalization[key]
	var box: Array = [null]
	_collect_aabb(scene, Transform3D.IDENTITY, box)
	var result := {"scale": 1.0, "center": Vector3.ZERO}
	if box[0] != null:
		var aabb: AABB = box[0]
		var radius := aabb.size.length() / 2.0
		if radius > 0.0:
			result = {"scale": 1.0 / radius, "center": aabb.get_center()}
	_normalization[key] = result
	return result


## The CDN model of `kind` for entity `id` scaled to bounding-sphere radius `radius`, or null while it downloads.
static func spawn(kind: String, id: String, radius: float, distance_m: float = 0.0) -> Node3D:
	var scene := Cdn.get_model(kind, id, distance_m)
	if scene == null:
		return null
	var norm := _normalization_for("%s:%s" % [kind, id], scene)
	var model: Node3D = scene.duplicate()
	var s: float = norm.scale
	model.scale = Vector3.ONE * s
	model.position = model.position - (norm.center as Vector3) * s
	var wrapper := Node3D.new()
	wrapper.add_child(model)
	if FORWARD_FIX.has(kind):
		wrapper.quaternion = FORWARD_FIX[kind]
	wrapper.scale = Vector3.ONE * radius
	return wrapper


## Also keeps the download queued (and its distance fresh) while the model is not there yet.
static func is_ready(kind: String, id: String, distance_m: float = 0.0) -> bool:
	return Cdn.get_model(kind, id, distance_m) != null


## SystemMap entries carry a stable UUID v5 `id` (kind, id, position, diameter_m, mass_kg); it matches the CDN id pattern as is.
static func body_id(entry: Dictionary) -> String:
	return str(entry.id)
