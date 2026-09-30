class_name ManualControl
extends Node
## Direct keyboard flight: W/S pitch, A/D yaw, Q/E roll on the RCS; K/J raise/lower the main thruster.
## RCS and main thruster can each be handed to the pilot independently.

signal changed

const RCS_PCT := 50.0
const THRUST_RATE_PCT_S := 60.0
const SEND_INTERVAL_MS := 66.0

var active := false
var rcs_enabled := true
var main_enabled := true
var thrust_pct := 0.0
var axes := {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
var keys_down := {}

var _thrusters := ShipRead.classify_thrusters(null, [])
var _sent := {}
var _in_flight := false
var _last_send_ms := 0.0


func set_modules(modules: Array, entity: Variant) -> void:
	_thrusters = ShipRead.classify_thrusters(entity, modules)


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if not active:
		_release_all()
	changed.emit()


func set_rcs_enabled(value: bool) -> void:
	if rcs_enabled and not value and active:
		_zero_group("rcs")
	rcs_enabled = value
	changed.emit()


func set_main_enabled(value: bool) -> void:
	if main_enabled and not value and active:
		thrust_pct = 0.0
		_zero_group("fixed")
	main_enabled = value
	changed.emit()


func _process(delta: float) -> void:
	keys_down = {}
	if not active or InputState.captured:
		axes = {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
		return
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_K, KEY_J]:
		keys_down[k] = Input.is_key_pressed(k) and not ctrl
	# Right-handed body frame: +yaw swings the nose left, +pitch down, +roll right.
	axes = {
		"yaw": (float(keys_down[KEY_A]) - float(keys_down[KEY_D])) * RCS_PCT,
		"pitch": (float(keys_down[KEY_W]) - float(keys_down[KEY_S])) * RCS_PCT,
		"roll": (float(keys_down[KEY_E]) - float(keys_down[KEY_Q])) * RCS_PCT,
	}
	if main_enabled:
		thrust_pct = clampf(thrust_pct + (float(keys_down[KEY_K]) - float(keys_down[KEY_J])) * THRUST_RATE_PCT_S * delta, 0.0, 100.0)
	_send()


func _send() -> void:
	var now := Time.get_ticks_msec()
	if _in_flight or now - _last_send_ms < SEND_INTERVAL_MS or not IonClient.is_logged_in():
		return
	var jobs := []
	if rcs_enabled:
		for t in _thrusters.rcs:
			for axis in Attitude.RCS_AXES:
				_queue(jobs, t.module_id, axis, axes[axis])
	if main_enabled:
		for t in _thrusters.fixed:
			_queue(jobs, t.module_id, "activation", thrust_pct)
	if jobs.is_empty():
		return
	_last_send_ms = now
	_in_flight = true
	for job in jobs:
		var result := await IonClient.set_variable(job[0], job[1], job[2])
		if not result.ok:
			_sent.clear()
	_in_flight = false


func _queue(jobs: Array, module_id: String, variable: String, value: float) -> void:
	var rounded := roundf(value * 10.0) / 10.0
	var key := "%s:%s" % [module_id, variable]
	if _sent.get(key) == rounded:
		return
	_sent[key] = rounded
	jobs.append([module_id, variable, rounded])


func _zero_group(group: String) -> void:
	for t in _thrusters[group]:
		if group == "rcs":
			for axis in Attitude.RCS_AXES:
				IonClient.set_variable(t.module_id, axis, 0)
				_sent["%s:%s" % [t.module_id, axis]] = 0.0
		else:
			IonClient.set_variable(t.module_id, "activation", 0)
			_sent["%s:activation" % t.module_id] = 0.0


func _release_all() -> void:
	axes = {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
	keys_down = {}
	thrust_pct = 0.0
	if rcs_enabled:
		_zero_group("rcs")
	if main_enabled:
		_zero_group("fixed")
