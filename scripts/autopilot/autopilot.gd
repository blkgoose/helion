class_name Autopilot
extends RefCounted
## Client-side autopilot: one-way state machine (tuning -> pointing -> burning -> stoppingBurner ->
## reverse -> stopping -> fineStop) driving the RCS and thrusters through SET commands.
## "stop" mode (full stop in place) skips from tuning straight to reverse/stopping.
## Distances are measured to the target's surface. "orbit" chases a point revolving around the target.

signal failed(reason: String)

const RAD_TO_DEG := 180.0 / PI
const MAX_CALIBRATION_ATTEMPTS := 4
const TIMING_SMOOTHING := 0.2
const ALIGNMENT_TOLERANCE_DEG := 25.0
const DEFAULT_MAX_CRUISE_SPEED := 1000.0
const SPEED_GAIN := 20.0
const SPEED_DEADBAND := 0.3
const RETRO_HANDOFF_SPEED_MPS := 3.0
const FINE_STOP_MAIN_ENGINE_CAP_PCT := 1.0
const POINTING_ANGLE_TOLERANCE_DEG := 3.0
const POINTING_RATE_TOLERANCE_DEG_S := 1.0
const POINTING_SETTLE_MS := 400.0
const ASSUMED_MAX_DECEL_MPS2 := 2.0
const BRAKE_MARGIN := 1.3
const ACCEL_SMOOTHING := 0.15
const ACCEL_SAMPLE_MIN_FORWARD_PCT := 80.0
const ACCEL_SAMPLE_MAX_DT_S := 0.3
const ACCEL_SAMPLE_MIN_MPS2 := 0.01
const ACCEL_SAMPLE_MAX_MPS2 := 100.0
const ASSUMED_TURN_RATE_DEG_S := 20.0
const MANEUVER_SETTLE_S := 1.5
const STOPPING_BURNER_DWELL_MS := 300.0
const RCS_DELAY_SAFETY_MARGIN := 1.5
const MASS_TOLERANCE_FRACTION := 0.05

const ORBIT_ANGULAR_SPEED := 0.05
const GRAVITATIONAL_CONSTANT := 6.674e-11
const ORBIT_MAX_GRAVITY_ACCEL_MPS2 := 0.2
const ORBIT_GRAVITY_BUDGET_FRACTION := 0.4

var phase := "idle"
var label := ""

var _thrusters := ShipRead.classify_thrusters(null, [])
var _get_target := Callable()
var _arrival_radius := 200.0
var _target_radius := 0.0
var _stop_mode := false
var _calibrator := Attitude.RcsCalibrator.new()
var _calibration_attempts := 0
var _gains: Variant = null
var _point_only := false
var _max_cruise_speed := DEFAULT_MAX_CRUISE_SPEED
var _rcs_ids := ""
var _size_m: Variant = null
var _mass_kg: Variant = null
var _cached_calibration: Variant = Persist.get_value("calibration")
var _last_sample_at_ms := 0.0
var _avg_tick_s := 0.066
var _avg_set_rtt_s := 0.05
var _in_flight := false
var _zero_pending := false
var _last_command := {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
var _sent := {}
var _settled_since_ms: Variant = null
var _phase_entered_at_ms := 0.0
var _measured_accel: Variant = null
var _prev_accel_sample_at_ms := 0.0
var _prev_closing_speed := 0.0
var _prev_forward := 0.0


func is_engaged() -> bool:
	return not _get_target.is_null() or _stop_mode


func get_measured_accel() -> Variant:
	return _measured_accel


func set_modules(modules: Array, entity: Variant) -> void:
	_thrusters = ShipRead.classify_thrusters(entity, modules)
	_size_m = ShipRead.size(entity) if entity != null else null
	_mass_kg = ShipRead.mass(entity) if entity != null else null
	var ids := PackedStringArray()
	for t in _thrusters.rcs:
		ids.append(t.module_id)
	var rcs_ids := ",".join(ids)
	if rcs_ids != _rcs_ids:
		_rcs_ids = rcs_ids
		if is_engaged() and not _try_use_cached_calibration():
			_start_calibration()


func _calibration_matches(stored: Dictionary) -> bool:
	if _size_m == null or _mass_kg == null:
		return false
	if stored.get("rcsIds") != _rcs_ids:
		return false
	if not is_equal_approx(float(stored.get("sizeM", -1.0)), float(_size_m)):
		return false
	var stored_mass := float(stored.get("massKg", 0.0))
	return stored_mass > 0.0 and absf(stored_mass - float(_mass_kg)) / stored_mass <= MASS_TOLERANCE_FRACTION


## Reuses a previously measured calibration if it matches the current RCS loadout/size/mass.
func _try_use_cached_calibration() -> bool:
	if not (_cached_calibration is Dictionary) or not _calibration_matches(_cached_calibration):
		return false
	_gains = _cached_calibration.gains
	_enter_phase("reverse" if _stop_mode else "pointing", IonMath.now_ms())
	return true


func _persist_calibration() -> void:
	if _gains == null or _size_m == null or _mass_kg == null:
		return
	_cached_calibration = {"rcsIds": _rcs_ids, "sizeM": _size_m, "massKg": _mass_kg, "gains": _gains}
	Persist.set_value("calibration", _cached_calibration)


func _start_calibration() -> void:
	_gains = null
	_calibration_attempts += 1
	phase = "tuning"
	Persist.set_value("phase", "tuning")
	_calibrator.start(IonMath.now_ms())


func _enter_phase(new_phase: String, now_ms: float) -> void:
	phase = new_phase
	if new_phase == "pointing" or new_phase == "reverse":
		_settled_since_ms = null
	elif new_phase == "stoppingBurner":
		_phase_entered_at_ms = now_ms
	Persist.set_value("phase", new_phase if new_phase != "idle" else null)


## Fast-forwards back to a phase stored before a restart, if reachable for the re-engaged goal and calibrated.
func resume_phase(stored_phase: Variant) -> void:
	if stored_phase == null or _gains == null:
		return
	var resumable: Array
	if _stop_mode:
		resumable = ["reverse", "stopping", "fineStop"]
	elif _point_only:
		resumable = ["pointing"]
	else:
		resumable = ["pointing", "burning", "stoppingBurner", "reverse", "stopping", "fineStop"]
	if stored_phase in resumable:
		_enter_phase(stored_phase, IonMath.now_ms())


func _disengage_with_reason(reason: String) -> void:
	disengage()
	failed.emit(reason)


func _track_settle(pointing_now: Variant, rates: Dictionary, now_ms: float) -> bool:
	var settled: bool = pointing_now != null \
		and pointing_now.angle_deg <= POINTING_ANGLE_TOLERANCE_DEG \
		and absf(rates.yaw) <= POINTING_RATE_TOLERANCE_DEG_S \
		and absf(rates.pitch) <= POINTING_RATE_TOLERANCE_DEG_S \
		and absf(rates.roll) <= POINTING_RATE_TOLERANCE_DEG_S
	if not settled:
		_settled_since_ms = null
		return false
	if _settled_since_ms == null:
		_settled_since_ms = now_ms
	return now_ms - _settled_since_ms >= POINTING_SETTLE_MS


## Live-measures the main engine's realized acceleration from how closing speed changed since the last tick.
func _measure_accel(closing_speed: float, forward: float, now_ms: float) -> void:
	var dt_s := (now_ms - _prev_accel_sample_at_ms) / 1000.0
	if _prev_accel_sample_at_ms != 0.0 and dt_s > 0.0 and dt_s <= ACCEL_SAMPLE_MAX_DT_S and _prev_forward >= ACCEL_SAMPLE_MIN_FORWARD_PCT:
		var realized := (closing_speed - _prev_closing_speed) / dt_s
		if realized >= ACCEL_SAMPLE_MIN_MPS2 and realized <= ACCEL_SAMPLE_MAX_MPS2:
			if _measured_accel == null:
				_measured_accel = realized
			else:
				_measured_accel = _measured_accel + ACCEL_SMOOTHING * (realized - _measured_accel)
	_prev_accel_sample_at_ms = now_ms
	_prev_closing_speed = closing_speed
	_prev_forward = forward


func _reset_for_engage() -> void:
	_last_sample_at_ms = 0.0
	_last_command = {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
	_sent.clear()
	_zero_pending = false
	_calibration_attempts = 0
	_settled_since_ms = null
	_prev_accel_sample_at_ms = 0.0
	_prev_forward = 0.0
	if not _try_use_cached_calibration():
		_start_calibration()


## `get_target` takes now_ms and returns a floating position Dictionary, or {} when the target is lost.
func engage(get_target: Callable, arrival_radius: float, target_radius_m: float, goal_label: String, point_only := false, max_cruise_speed := DEFAULT_MAX_CRUISE_SPEED) -> void:
	_get_target = get_target
	_arrival_radius = arrival_radius
	_target_radius = target_radius_m
	label = goal_label
	_stop_mode = false
	_point_only = point_only
	_max_cruise_speed = max_cruise_speed
	_reset_for_engage()


## Nulls out all velocity in place: turns retrograde and burns until closing speed reaches ~0, then disengages.
func engage_stop() -> void:
	_get_target = Callable()
	_arrival_radius = 0.0
	_target_radius = 0.0
	_stop_mode = true
	_point_only = false
	label = "Full stop"
	_reset_for_engage()


func disengage() -> void:
	_get_target = Callable()
	_stop_mode = false
	_point_only = false
	label = ""
	phase = "idle"
	_gains = null
	_settled_since_ms = null
	Persist.set_value("phase", null)
	# A tick's SETs may still be in flight; zeroing now could land before them and leave thrusters firing.
	if _in_flight:
		_zero_pending = true
	else:
		_send_zeros()


func _send_zeros() -> void:
	_zero_pending = false
	_sent.clear()
	_last_command = {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
	for t in _thrusters.rcs:
		for axis in Attitude.RCS_AXES:
			IonClient.set_variable(t.module_id, axis, 0)
	for group in ["fixed", "retro", "lateral_q", "lateral_e"]:
		for t in _thrusters[group]:
			IonClient.set_variable(t.module_id, "activation", 0)


func _queue_set(jobs: Array, module_id: String, variable: String, value: float) -> void:
	var rounded := roundf(value * 10.0) / 10.0
	var key := "%s:%s" % [module_id, variable]
	if _sent.get(key) == rounded:
		return
	_sent[key] = rounded
	jobs.append([module_id, variable, rounded])


signal _jobs_done

## Runs SETs in parallel; true when every one succeeded.
func _run_jobs(jobs: Array) -> bool:
	var state := {"pending": jobs.size(), "ok": true}
	for job in jobs:
		_run_job(job, state)
	if state.pending > 0:
		await _jobs_done
	return state.ok


func _run_job(job: Array, state: Dictionary) -> void:
	var result := await IonClient.set_variable(job[0], job[1], job[2])
	if not result.ok:
		state.ok = false
	state.pending -= 1
	if state.pending == 0:
		_jobs_done.emit()


func _aim_for(current_phase: String, world_direction: Variant, retrograde: Vector3, prograde: Vector3, has_retro: bool) -> Variant:
	match current_phase:
		"pointing", "burning", "stoppingBurner":
			return world_direction
		"reverse", "stopping":
			return retrograde
		"fineStop":
			# The retro mount fires opposite the nose, so it needs the nose pointed prograde to
			# decelerate; without one the main engine fires along the nose, so aim retrograde.
			return prograde if has_retro else retrograde
	return null


## Called on every ship-state poll (~15/s).
func tick(entity: Dictionary) -> void:
	if not is_engaged():
		return

	var orientation = ShipRead.orientation(entity)
	var velocity = ShipRead.velocity(entity)
	var angular = ShipRead.angular_velocity(entity)
	if orientation == null or velocity == null or angular == null:
		return

	var velocity_vec: Vector3 = velocity
	if _stop_mode and velocity_vec.length() <= SPEED_DEADBAND:
		disengage()
		return

	var inverse_orientation: Quaternion = (orientation as Quaternion).inverse()
	var ang: Vector3 = angular
	# Body-frame rates, right-handed: +Z (yaw) swings the nose towards +Y, +Y (pitch) towards -Z.
	var rates := {"yaw": ang.z * RAD_TO_DEG, "pitch": ang.y * RAD_TO_DEG, "roll": ang.x * RAD_TO_DEG}

	var now := IonMath.now_ms()
	if _last_sample_at_ms != 0.0:
		var dt := minf(0.5, (now - _last_sample_at_ms) / 1000.0)
		_avg_tick_s += TIMING_SMOOTHING * (dt - _avg_tick_s)
	_last_sample_at_ms = now

	var world_direction: Variant = null
	var remaining := 0.0
	var closing_speed: float
	if _stop_mode:
		closing_speed = velocity_vec.length()
	else:
		var ship_position := ShipRead.floating_position(entity)
		if ship_position.is_empty():
			return
		var target_position: Dictionary = _get_target.call(now)
		if target_position.is_empty():
			_disengage_with_reason("Bersaglio perso")
			return
		var rel := IonMath.relative(ship_position, target_position)
		var distance_to_center := IonMath.length(rel)
		if distance_to_center == 0.0:
			return
		world_direction = IonMath.to_vec3(rel).normalized()
		var distance_to_surface := maxf(0.0, distance_to_center - _target_radius)
		remaining = distance_to_surface - _arrival_radius
		closing_speed = velocity_vec.dot(world_direction)

	var retrograde: Vector3
	if velocity_vec.length_squared() > 0.0:
		retrograde = -velocity_vec.normalized()
	elif world_direction != null:
		retrograde = -(world_direction as Vector3)
	else:
		retrograde = Vector3(1, 0, 0)
	var prograde := -retrograde
	var has_retro: bool = _thrusters.retro.size() > 0

	if phase == "tuning":
		_calibrator.record(now, rates)

	# Ticks are fired without awaiting, so skip while the previous SETs are in flight.
	if _in_flight:
		return

	var commands := {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
	var forward := 0.0
	var retro_forward := 0.0

	if phase == "tuning":
		var probe := _calibrator.command(now)
		if not probe.done:
			commands = probe.values
		else:
			var gains := _calibrator.gains()
			if gains.yaw != null and gains.pitch != null:
				_gains = gains
				_persist_calibration()
				_enter_phase("reverse" if _stop_mode else "pointing", now)
			elif _calibration_attempts < MAX_CALIBRATION_ATTEMPTS:
				_start_calibration()
			else:
				push_warning("Autopilot: RCS calibration failed, yaw/pitch did not respond consistently")
				_disengage_with_reason("Calibrazione RCS fallita")
				return
	else:
		# State-exit checks use the CURRENT (pre-transition) phase's aim direction.
		var current_aim: Variant = _aim_for(phase, world_direction, retrograde, prograde, has_retro)
		var pointing_now: Variant = null
		if current_aim != null:
			pointing_now = Attitude.pointing_error(inverse_orientation * (current_aim as Vector3))
		var decel_estimate: float = _measured_accel if _measured_accel != null else ASSUMED_MAX_DECEL_MPS2

		match phase:
			"pointing":
				if _track_settle(pointing_now, rates, now) and not _point_only:
					_enter_phase("burning", now)
			"burning":
				var stopping_distance := (closing_speed * closing_speed) / (2.0 * decel_estimate) if closing_speed > 0.0 else 0.0
				var turn_angle_deg := rad_to_deg((world_direction as Vector3).angle_to(retrograde))
				var maneuver_time_s := turn_angle_deg / ASSUMED_TURN_RATE_DEG_S + MANEUVER_SETTLE_S
				var coast_during_maneuver := closing_speed * maneuver_time_s if closing_speed > 0.0 else 0.0
				var should_brake := closing_speed > SPEED_DEADBAND and stopping_distance * BRAKE_MARGIN + coast_during_maneuver >= remaining
				if should_brake:
					_enter_phase("stoppingBurner", now)
			"stoppingBurner":
				if now - _phase_entered_at_ms >= STOPPING_BURNER_DWELL_MS:
					_enter_phase("reverse", now)
			"reverse":
				if _track_settle(pointing_now, rates, now):
					_enter_phase("stopping", now)
			"stopping":
				if closing_speed <= RETRO_HANDOFF_SPEED_MPS:
					_enter_phase("fineStop", now)
			"fineStop":
				if closing_speed <= SPEED_DEADBAND:
					if _stop_mode or remaining <= 0.0:
						disengage()
						return
					_enter_phase("pointing", now)

		# RCS pointing + forward thrust for the (possibly just-updated) phase.
		var final_aim: Variant = _aim_for(phase, world_direction, retrograde, prograde, has_retro)
		if _gains != null and final_aim != null:
			var pointing := Attitude.pointing_error(inverse_orientation * (final_aim as Vector3))
			var delay_s := (_avg_set_rtt_s + _avg_tick_s) * RCS_DELAY_SAFETY_MARGIN
			var errors := {"yaw": pointing.yaw_deg, "pitch": pointing.pitch_deg, "roll": 0.0}
			for axis in Attitude.RCS_AXES:
				var gain = _gains.get(axis)
				commands[axis] = 0.0 if gain == null else Attitude.axis_command(errors[axis], rates[axis], gain, _last_command[axis], delay_s)

			if phase == "burning" and pointing.angle_deg < ALIGNMENT_TOLERANCE_DEG and remaining > 0.0:
				var desired_speed := minf(_max_cruise_speed, sqrt(2.0 * decel_estimate * remaining))
				var speed_error := desired_speed - closing_speed
				if speed_error > SPEED_DEADBAND:
					forward = minf(100.0, speed_error * SPEED_GAIN)
			elif phase == "stopping":
				forward = minf(100.0, closing_speed * SPEED_GAIN) if closing_speed > SPEED_DEADBAND else 0.0
			elif phase == "fineStop" and pointing.angle_deg < ALIGNMENT_TOLERANCE_DEG:
				var fine_speed_command := closing_speed * SPEED_GAIN if closing_speed > SPEED_DEADBAND else 0.0
				# 1% is only the floor: a fast approach (e.g. after a long trip) needs the power to
				# actually shed the speed within the remaining distance.
				var required_pct := 0.0
				if closing_speed > SPEED_DEADBAND and remaining > 0.0:
					required_pct = 100.0 * (closing_speed * closing_speed / (2.0 * remaining)) / decel_estimate * BRAKE_MARGIN
				if has_retro:
					retro_forward = minf(100.0, maxf(fine_speed_command, required_pct))
				else:
					forward = minf(100.0, minf(maxf(FINE_STOP_MAIN_ENGINE_CAP_PCT, required_pct), maxf(fine_speed_command, required_pct)))

	if phase == "burning" or phase == "stopping":
		_measure_accel(closing_speed, forward, now)

	_last_command = commands
	var jobs := []
	for t in _thrusters.rcs:
		for axis in Attitude.RCS_AXES:
			_queue_set(jobs, t.module_id, axis, commands[axis])
	for t in _thrusters.fixed:
		_queue_set(jobs, t.module_id, "activation", forward)
	for t in _thrusters.retro:
		_queue_set(jobs, t.module_id, "activation", retro_forward)
	if jobs.is_empty():
		return

	_in_flight = true
	var sent_at := Time.get_ticks_msec()
	var ok := await _run_jobs(jobs)
	if ok:
		_avg_set_rtt_s += TIMING_SMOOTHING * (minf(1.0, (Time.get_ticks_msec() - sent_at) / 1000.0) - _avg_set_rtt_s)
	else:
		_sent.clear()
		push_warning("Autopilot: SET failed, resending everything next tick")
	_in_flight = false
	if _zero_pending:
		_send_zeros()


## A safe orbit distance: far enough that gravity there is comfortably within the ship's thrust, never below the surface.
static func safe_orbit_radius_m(body_radius_m: float, mass_kg: float, measured_accel_mps2: Variant = null) -> float:
	var gravity_budget: float = measured_accel_mps2 * ORBIT_GRAVITY_BUDGET_FRACTION if measured_accel_mps2 != null else ORBIT_MAX_GRAVITY_ACCEL_MPS2
	var gravity_limited := sqrt((GRAVITATIONAL_CONSTANT * mass_kg) / gravity_budget) if mass_kg > 0.0 else 0.0
	return maxf(body_radius_m + 200.0, gravity_limited)


## A point revolving around `center` at `radius_m`; returns Callable(now_ms) -> floating position.
static func orbit_target_position(center: Dictionary, radius_m: float, started_at_ms: float) -> Callable:
	return func(now_ms: float) -> Dictionary:
		var t := ((now_ms - started_at_ms) / 1000.0) * ORBIT_ANGULAR_SPEED
		return {
			"sector": center.sector,
			"shift": {
				"x": center.shift.x + cos(t) * radius_m,
				"y": center.shift.y + sin(t) * radius_m,
				"z": center.shift.z,
			},
		}
