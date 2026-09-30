class_name RadarPoller
extends Node
## One Radar module. Scans exactly when the module's own cooldown_remaining_s reaches zero (read
## from GET), so a slow deep scanner is never polled into "cooldown" errors.
## Contacts: [entity_id, position, size (diameter), kind, velocity, orientation].

const FALLBACK_INTERVAL_S := 1.0
const ERROR_BACKOFF_MS := 500.0
# Beyond this a scan is too stale to trust linear extrapolation (e.g. after a stalled frame).
const MAX_EXTRAPOLATION_S := 3.0
const DEFAULT_RADIUS_M := 1e4

var module_id := ""
var radius_m := DEFAULT_RADIUS_M
var latest: Array = []
var latest_at_ms := 0.0

var _in_flight := false
var _retry_after_ms := 0.0


func tick(entity: Dictionary) -> void:
	var r = ShipRead.module_field(entity, module_id, "radius_m")
	if r != null:
		radius_m = float(r)
	if _in_flight or not IonClient.is_logged_in():
		return
	var now := IonMath.now_ms()
	if now < _retry_after_ms:
		return
	var cooldown = ShipRead.module_field(entity, module_id, "cooldown_remaining_s")
	if cooldown != null:
		if float(cooldown) <= 0.0:
			_scan()
	elif now - latest_at_ms >= FALLBACK_INTERVAL_S * 1000.0:
		_scan()


## Contacts dead-reckoned forward by their own velocity, so they move smoothly between scans.
func get_predicted(now_ms: float) -> Array:
	var dt := minf((now_ms - latest_at_ms) / 1000.0, MAX_EXTRAPOLATION_S)
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
	_in_flight = true
	var result := await IonClient.action_json(module_id, "scan")
	_in_flight = false
	if result.ok and result.data is Array:
		latest = result.data
		latest_at_ms = IonMath.now_ms()
	elif not result.ok:
		_retry_after_ms = IonMath.now_ms() + ERROR_BACKOFF_MS
		push_warning("Radar scan failed: %s" % result.error)
