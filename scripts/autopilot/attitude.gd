class_name Attitude
## Attitude control for a frictionless rigid body. An RCS command sets torque, so each axis is a
## pure double integrator with a hard +-100% limit and no drag. Each axis follows a square-root
## braking curve (the rate from which the measured deceleration stops exactly at the target) with a
## fast rate loop tracking it; a linear PD would overshoot any large slew once the RCS saturates.

const RCS_AXES := ["yaw", "pitch", "roll"]

const MAX_COMMAND := 100.0
const BRAKING_ACCEL_FRACTION := 0.6
const MAX_RATE_DEG_S := 45.0
const MIN_RATE_LOOP_TIME_S := 0.15
const COMMAND_DEADBAND := 0.1
const POINTING_SETTLE_TIME_S := 12.0
const POINTING_SLEW_P := 3.0 / POINTING_SETTLE_TIME_S

const MIN_PROBE_SEGMENT_MS := 400.0
const MAX_PROBE_SEGMENT_MS := 2500.0
const PROBE_RATE_CHANGE_DEG_S := 0.8
const MIN_FIT_SAMPLES := 3
const MIN_ACCEL_DEG_S2 := 0.02
const MAX_SEGMENT_MISMATCH := 5.0


## Desired rate towards the target: linear close in, then sqrt(2*a*|err|) once stopping needs more than `accel`.
static func braking_curve_rate(err_deg: float, accel_deg_s2: float, p: float) -> float:
	var linear_limit := accel_deg_s2 / (p * p)
	var abs_err := absf(err_deg)
	var rate := p * abs_err if abs_err <= linear_limit else sqrt(2.0 * accel_deg_s2 * (abs_err - linear_limit / 2.0))
	return signf(err_deg) * minf(MAX_RATE_DEG_S, rate)


## One RCS axis command. `gain` is signed deg/s^2 per % from calibration; `delay_s` is the estimated sample-to-actuation delay.
static func axis_command(err_deg: float, rate_deg_s: float, gain: float, last_command: float, delay_s: float) -> float:
	var max_accel := absf(gain) * MAX_COMMAND
	var predicted_rate := rate_deg_s + gain * last_command * delay_s
	var predicted_err := err_deg - ((rate_deg_s + predicted_rate) / 2.0) * delay_s

	var rate_loop_time_s := maxf(MIN_RATE_LOOP_TIME_S, 2.0 * delay_s)
	var desired_rate := braking_curve_rate(predicted_err, BRAKING_ACCEL_FRACTION * max_accel, POINTING_SLEW_P)

	var desired_accel := (desired_rate - predicted_rate) / rate_loop_time_s
	var command := clampf(desired_accel / gain, -MAX_COMMAND, MAX_COMMAND)
	return 0.0 if absf(command) < COMMAND_DEADBAND else command


## Rotation (deg) about body pitch (Y) and yaw (Z) turning body forward (+X) onto `local_dir` along the shortest arc.
static func pointing_error(local_dir: Vector3) -> Dictionary:
	var lateral := Vector2(local_dir.y, local_dir.z).length()
	var angle_deg := atan2(lateral, local_dir.x) * (180.0 / PI)
	if lateral < 1e-9:
		return {"yaw_deg": angle_deg if local_dir.x < 0 else 0.0, "pitch_deg": 0.0, "angle_deg": angle_deg}
	return {
		"yaw_deg": (angle_deg * local_dir.y) / lateral,
		"pitch_deg": (-angle_deg * local_dir.z) / lateral,
		"angle_deg": angle_deg,
	}


static func _slope(samples: Array) -> Variant:
	if samples.size() < MIN_FIT_SAMPLES:
		return null
	var t0: float = samples[0].t
	var n := samples.size()
	var st := 0.0
	var sr := 0.0
	var stt := 0.0
	var str_ := 0.0
	for s in samples:
		var t: float = (s.t - t0) / 1000.0
		st += t
		sr += s.rate
		stt += t * t
		str_ += t * s.rate
	var denom := n * stt - st * st
	return (n * str_ - st * sr) / denom if denom > 0.0 else null


class AxisProbe:
	var _segment := 0  # 0: +100%, 1: -100%, 2: done
	var _segment_started_at := 0.0
	var _plus_segment_ms := Attitude.MAX_PROBE_SEGMENT_MS
	var _start_rate: Variant = null
	var _latest_rate: Variant = null
	var _current: Array = []
	var _fitted: Array = [[], []]

	func _init(now_ms: float) -> void:
		_segment_started_at = now_ms

	func is_done() -> bool:
		return _segment > 1

	func record(now_ms: float, rate: float) -> void:
		if is_done():
			return
		if _start_rate == null:
			_start_rate = rate
		_latest_rate = rate
		_current.append({"t": now_ms, "rate": rate})

	func command(now_ms: float) -> float:
		var elapsed := now_ms - _segment_started_at
		if _segment == 0 and elapsed >= Attitude.MIN_PROBE_SEGMENT_MS:
			var moved: bool = _start_rate != null and _latest_rate != null and absf(_latest_rate - _start_rate) >= Attitude.PROBE_RATE_CHANGE_DEG_S
			if moved or elapsed >= Attitude.MAX_PROBE_SEGMENT_MS:
				_plus_segment_ms = elapsed
				_end_segment(now_ms)
		elif _segment == 1 and elapsed >= _plus_segment_ms:
			_end_segment(now_ms)
		if _segment == 0:
			return Attitude.MAX_COMMAND
		if _segment == 1:
			return -Attitude.MAX_COMMAND
		return 0.0

	func _end_segment(now_ms: float) -> void:
		# Fit only the second half of each segment; the first half absorbs command latency.
		var halfway := _segment_started_at + (now_ms - _segment_started_at) / 2.0
		_fitted[_segment] = _current.filter(func(s): return s.t >= halfway)
		_current = []
		_segment += 1
		_segment_started_at = now_ms

	func gain() -> Variant:
		var up = Attitude._slope(_fitted[0])
		var down = Attitude._slope(_fitted[1])
		if up == null or down == null:
			return null
		var up_gain: float = up / Attitude.MAX_COMMAND
		var down_gain: float = down / -Attitude.MAX_COMMAND
		var small := minf(absf(up_gain), absf(down_gain))
		var consistent := (
			signf(up_gain) == signf(down_gain)
			and minf(absf(up), absf(down)) >= Attitude.MIN_ACCEL_DEG_S2
			and maxf(absf(up_gain), absf(down_gain)) <= Attitude.MAX_SEGMENT_MISMATCH * small
		)
		return (up_gain + down_gain) / 2.0 if consistent else null


## Measures each axis's torque authority directly with a +100% / -100% doublet per RCS axis.
class RcsCalibrator:
	var _probes: Dictionary = {}

	func start(now_ms: float) -> void:
		_probes = {"yaw": AxisProbe.new(now_ms), "pitch": AxisProbe.new(now_ms), "roll": AxisProbe.new(now_ms)}

	func record(now_ms: float, rates: Dictionary) -> void:
		if _probes.is_empty():
			return
		for axis in Attitude.RCS_AXES:
			_probes[axis].record(now_ms, rates[axis])

	## Commands to send now; call only when they will actually be sent, since segment timing starts at send.
	func command(now_ms: float) -> Dictionary:
		var values := {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
		if _probes.is_empty():
			return {"values": values, "done": true}
		var all_done := true
		for axis in Attitude.RCS_AXES:
			values[axis] = _probes[axis].command(now_ms)
			if not _probes[axis].is_done():
				all_done = false
		return {"values": values, "done": all_done}

	func gains() -> Dictionary:
		if _probes.is_empty():
			return {"yaw": null, "pitch": null, "roll": null}
		return {"yaw": _probes.yaw.gain(), "pitch": _probes.pitch.gain(), "roll": _probes.roll.gain()}
