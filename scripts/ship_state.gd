extends Node
## Polls GET at the server's tick rate (15 Hz) without ever overlapping requests.

signal updated(entity: Dictionary)

const POLL_INTERVAL_S := 1.0 / 15.0

var latest: Dictionary = {}

var _elapsed := 0.0
var _in_flight := false


func _process(delta: float) -> void:
	if not IonClient.is_logged_in():
		return
	_elapsed += delta
	if _elapsed >= POLL_INTERVAL_S and not _in_flight:
		_elapsed = 0.0
		_poll()


func _poll() -> void:
	_in_flight = true
	var result := await IonClient.get_state()
	_in_flight = false
	if result.ok:
		latest = result.data
		updated.emit(latest)
	else:
		push_warning("GET poll failed: %s" % result.error)


## body.position.position: {sector:{x,y,z}, shift:{x,y,z}} (floating origin, sector = 1e11 m).
func floating_position(entity: Dictionary) -> Dictionary:
	var pos = _dig(entity, ["body", "position", "position"])
	if pos is Dictionary and pos.has("sector") and pos.has("shift"):
		return pos
	return {}


func velocity(entity: Dictionary) -> Vector3:
	return _vec(_dig(entity, ["body", "position", "velocity"]))


## Angular velocity, rad/s in the ship's local frame.
func angular_velocity(entity: Dictionary) -> Vector3:
	return _vec(_dig(entity, ["body", "rotation", "velocity"]))


## body.rotation.orientation is {q,x,y,z} with q the scalar component.
func orientation(entity: Dictionary) -> Quaternion:
	var o = _dig(entity, ["body", "rotation", "orientation"])
	if o is Dictionary and o.has("q"):
		return Quaternion(o.x, o.y, o.z, o.q)
	return Quaternion.IDENTITY


func _vec(v) -> Vector3:
	if v is Dictionary and v.has("x"):
		return Vector3(v.x, v.y, v.z)
	return Vector3.ZERO


func _dig(root, path: Array):
	var node = root
	for key in path:
		if not node is Dictionary or not node.has(key):
			return null
		node = node[key]
	return node
