class_name SystemMapPoller
extends Node
## SystemMap.scan: cached procedural data, only changes when the ship crosses a sector boundary.

signal updated(entries: Array)

const POLL_INTERVAL_S := 5.0

var module_id := ""
var latest: Array = []

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


func _scan() -> void:
	if _in_flight or module_id == "":
		return
	_in_flight = true
	var result := await IonClient.action_json(module_id, "scan")
	_in_flight = false
	if result.ok and result.data is Array:
		latest = result.data
		updated.emit(latest)
	elif not result.ok:
		push_warning("SystemMap scan failed: %s" % result.error)
