class_name TacticalCamera
extends Camera3D
## CAD-style orbit camera: wheel zooms, right-drag orbits, WASD/arrows pan, Space recenters.

const ZOOM_FACTOR := 1.15
const MIN_DISTANCE := 20.0
const MAX_DISTANCE := 20000.0
const ROTATE_SPEED := 0.005
const PAN_SPEED_AT_UNIT_DISTANCE := 0.08
const AUTO_DISTANCE_LERP := 2.0
const AUTO_ORIENT_YAW_OFFSET := PI / 6.0
const AUTO_ORIENT_PITCH_LIFT := 0.35
const AUTO_ORIENT_LERP := 3.0

var center := Vector3.ZERO
var input_captured := false

var _ship_position := Vector3.ZERO
var _aim_point = null
var _following := true
var _auto_distance := true
var _auto_orient := true
var _distance := MIN_DISTANCE
var _yaw := 0.0
var _pitch := 0.6
var _dragging := false


func set_ship_position(position_: Vector3) -> void:
	_ship_position = position_
	if _following:
		center = position_


## World-space autopilot target, or null when idle; drives auto-orient.
func set_aim_point(point) -> void:
	_aim_point = point


func resume_auto_orient() -> void:
	_auto_orient = true


func recenter() -> void:
	center = _ship_position
	_following = true
	_auto_distance = true
	_auto_orient = true


func _unhandled_input(event: InputEvent) -> void:
	if input_captured:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(ZOOM_FACTOR)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.0 / ZOOM_FACTOR)
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_auto_orient = false
		_yaw -= motion.relative.x * ROTATE_SPEED
		_pitch = clampf(_pitch - motion.relative.y * ROTATE_SPEED, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		recenter()


func _zoom(factor: float) -> void:
	_auto_distance = false
	_distance = clampf(_distance * factor, MIN_DISTANCE, MAX_DISTANCE)


func _process(delta: float) -> void:
	_pan(delta)

	if _auto_distance:
		_distance += (MIN_DISTANCE - _distance) * minf(1.0, AUTO_DISTANCE_LERP * delta)

	if _auto_orient and _aim_point != null:
		_orient_towards_aim(delta)

	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw),
	) * _distance
	position = center + offset
	look_at(center, Vector3.UP)


func _pan(delta: float) -> void:
	if input_captured:
		return
	var amount := PAN_SPEED_AT_UNIT_DISTANCE * _distance * delta
	var moved := false
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		center.y += amount
		moved = true
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		center.y -= amount
		moved = true
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		center.x -= amount
		moved = true
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		center.x += amount
		moved = true
	if moved:
		_following = false


func _orient_towards_aim(delta: float) -> void:
	var d: Vector3 = _aim_point - center
	var horizontal := Vector2(d.x, d.z).length()
	if horizontal <= 1e-6 and absf(d.y) <= 1e-6:
		return
	var target_yaw := atan2(d.x, d.z)
	var desired_yaw := target_yaw + PI + AUTO_ORIENT_YAW_OFFSET
	var target_pitch := atan2(d.y, horizontal)
	var desired_pitch := clampf(-target_pitch + AUTO_ORIENT_PITCH_LIFT, -1.5, 1.5)
	var yaw_diff := atan2(sin(desired_yaw - _yaw), cos(desired_yaw - _yaw))
	var t := minf(1.0, AUTO_ORIENT_LERP * delta)
	_yaw += yaw_diff * t
	_pitch += (desired_pitch - _pitch) * t
