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
