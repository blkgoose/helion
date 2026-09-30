class_name RadarPoller
extends Node
## Radar.scan contacts: [entity_id, position, size (diameter), kind, velocity, orientation].

signal updated(entries: Array)

const POLL_INTERVAL_S := 1.0
# Beyond this a scan is too stale to trust linear extrapolation (e.g. after a stalled frame).
const MAX_EXTRAPOLATION_S := 3.0

var module_id := ""
var latest: Array = []

var _latest_at_ms := 0.0
var _elapsed := 0.0
var _in_flight := false


func set_module_id(id: String) -> void:
	if id == module_id:
		return
	module_id = id
	if id != "":
		_scan()


func _process(delta: float) -> void:
	if module_id == "" or not IonClient.is_logged_in():
		return
	_elapsed += delta
	if _elapsed >= POLL_INTERVAL_S:
		_elapsed = 0.0
		_scan()


## Contacts dead-reckoned forward by their own velocity, so they move smoothly between 1 Hz scans.
func get_predicted(now_ms: float) -> Array:
	var dt := minf((now_ms - _latest_at_ms) / 1000.0, MAX_EXTRAPOLATION_S)
	if dt <= 0.0:
		return latest
	var out := []
	for entry in latest:
		var pos: Dictionary = entry[1]
		var vel: Dictionary = entry[4]
		out.append([
			entry[0],
			{
				"sector": pos.sector,
				"shift": {
					"x": pos.shift.x + vel.x * dt,
					"y": pos.shift.y + vel.y * dt,
					"z": pos.shift.z + vel.z * dt,
				},
			},
			entry[2], entry[3], entry[4], entry[5],
		])
	return out


func _scan() -> void:
	if _in_flight or module_id == "":
		return
	_in_flight = true
	var result := await IonClient.action_json(module_id, "scan")
	_in_flight = false
	if result.ok and result.data is Array:
		latest = result.data
		_latest_at_ms = IonMath.now_ms()
		updated.emit(latest)
	elif not result.ok:
		push_warning("Radar scan failed: %s" % result.error)
