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
const COMMAND_DEADBAND := 0.02
const POINTING_SETTLE_TIME_S := 12.0
const POINTING_SLEW_P := 3.0 / POINTING_SETTLE_TIME_S

# RCS calibration, per axis: a pulse ladder finds the weakest command that visibly moves the ship
# (power first at a short pulse, then longer pulses at full power), then a planned doublet measures it.
const PROBE_POWER_LADDER_PCT := [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]
const PROBE_BASE_PULSE_MS := 200.0
const PROBE_LONG_PULSE_MS := [400.0, 800.0, 1600.0, 3200.0]
const PROBE_OBSERVE_MS := 500.0
const PROBE_ABORT_RATE_DEG_S := 2.0
const BASELINE_MS := 500.0
const MIN_BASELINE_SAMPLES := 4
const TAIL_MS := 250.0
const MIN_TAIL_SAMPLES := 3
# A pulse "did something" when the rate or the orientation moved by more than the noise floor.
const RESPONSE_RATE_DEG_S := 0.03
const RESPONSE_ANGLE_DEG := 0.01
const RESPONSE_NOISE_SIGMAS := 4.0
# Doublet: burn, then invert at once for the same time, so the rate must return to where it started.
const DOUBLET_PEAK_RATE_DEG_S := 0.6
const DOUBLET_ABORT_RATE_DEG_S := 2.0
const DOUBLET_PREFERRED_BURN_S := 1.0
const DOUBLET_MIN_PCT := 1.0
const DOUBLET_MAX_PCT := 100.0
const DOUBLET_MIN_MS := 800.0
const DOUBLET_MAX_MS := 3000.0
const DOUBLET_SETTLE_MS := 600.0
const DOUBLET_MAX_RESIDUAL_FRACTION := 0.3
const MAX_MEASURE_FAILURES := 3
const MIN_FIT_SAMPLES := 3
const MIN_ACCEL_DEG_S2 := 0.005
const MAX_SEGMENT_MISMATCH := 1.5
const REQUIRED_RCS_AXES := ["yaw", "pitch"]


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




static func _mean_rate(samples: Array) -> float:
	var sum := 0.0
	for s in samples:
		sum += s.rate
	return sum / samples.size()


static func _std_rate(samples: Array) -> float:
	var mean := _mean_rate(samples)
	var sum := 0.0
	for s in samples:
		sum += (s.rate - mean) * (s.rate - mean)
	return sqrt(sum / samples.size())


static func _since(samples: Array, from_ms: float) -> Array:
	return samples.filter(func(s): return s.t >= from_ms)


## The doublet that stays well above sensor noise yet keeps the peak rate small: burn at `pct` for
## `on_ms`, then invert at once for the same time. Equal burn and inversion cancel exactly, so the
## ship ends at the rate it started with; `excursion_deg` is how far it swings meanwhile.
## Inversion time that also removes a leftover rate `rate_deg_s`: `inversion_extra_ms`.
static func plan_doublet(accel_per_pct: float) -> Dictionary:
	var accel := absf(accel_per_pct)
	var pct := clampf(DOUBLET_PEAK_RATE_DEG_S / (accel * DOUBLET_PREFERRED_BURN_S), DOUBLET_MIN_PCT, DOUBLET_MAX_PCT)
	var on_ms := clampf(DOUBLET_PEAK_RATE_DEG_S / (accel * pct) * 1000.0, DOUBLET_MIN_MS, DOUBLET_MAX_MS)
	var on_s := on_ms / 1000.0
	return {"pct": pct, "on_ms": on_ms, "peak_rate": accel * pct * on_s, "excursion_deg": accel * pct * on_s * on_s}


## Extra inversion time (ms) that brings a leftover rate to zero at `pct`.
static func inversion_extra_ms(leftover_rate_deg_s: float, accel_per_pct: float, pct: float) -> float:
	return absf(leftover_rate_deg_s) / (absf(accel_per_pct) * pct) * 1000.0


## Measures one RCS axis in isolation. Stages: wait for a baseline, fire ladder pulses until the
## ship visibly responds, then run a planned doublet to measure the torque and check that the
## inversion stops the rotation without overshoot. Never responding means the axis is offline.
class AxisCalibration:
	const BASELINE := 0
	const PULSE := 1
	const OBSERVE := 2
	const BURN := 3
	const REVERSE := 4
	const SETTLE := 5
	const DONE := 6
	const OFFLINE := 7

	var _stage := BASELINE
	var _stage_started_ms := 0.0
	var _recent: Array = []
	var _stage_samples: Array = []
	var _ladder: Array = []
	var _step := 0
	var _failures := 0
	var _rate0 := 0.0
	var _sigma := 0.0
	var _baseline_n := 1
	var _pulse_pct := 0.0
	var _pulse_ms := 0.0
	var _pulse_actual_ms := 0.0
	var _pulse_start_angle := 0.0
	var _pulse_start_ms := 0.0
	var _sign := 1.0
	var _plan: Dictionary = {}
	var _rate_before := 0.0
	var _inversion_extra_ms := 0.0
	var _burn_actual_ms := 0.0
	var _up_fit: Array = []
	var _down_fit: Array = []
	var _gain: Variant = null

	func _init(now_ms: float) -> void:
		_stage_started_ms = now_ms
		for pct in Attitude.PROBE_POWER_LADDER_PCT:
			_ladder.append({"pct": pct, "ms": Attitude.PROBE_BASE_PULSE_MS})
		for ms in Attitude.PROBE_LONG_PULSE_MS:
			_ladder.append({"pct": Attitude.PROBE_POWER_LADDER_PCT.back(), "ms": ms})

	func is_done() -> bool:
		return _stage >= DONE

	func is_offline() -> bool:
		return _stage == OFFLINE

	func gain() -> Variant:
		return _gain

	func record(now_ms: float, rate: float, angle_deg: float) -> void:
		var sample := {"t": now_ms, "rate": rate, "angle": angle_deg}
		_recent.append(sample)
		while _recent.size() > 0 and _recent[0].t < now_ms - 2.0 * Attitude.BASELINE_MS:
			_recent.pop_front()
		if _stage != DONE and _stage != OFFLINE:
			_stage_samples.append(sample)

	## Command (%) to send now; call only when it will actually be sent, since stage timing starts at send.
	func command(now_ms: float) -> float:
		var elapsed := now_ms - _stage_started_ms
		match _stage:
			BASELINE:
				return _begin_pulse(now_ms) if elapsed >= Attitude.BASELINE_MS else 0.0
			PULSE:
				var aborted: bool = absf(_recent.back().rate - _rate0) >= Attitude.PROBE_ABORT_RATE_DEG_S
				if elapsed >= _pulse_ms or aborted:
					_pulse_actual_ms = elapsed
					_enter(OBSERVE, now_ms)
					return 0.0
				return _pulse_pct
			OBSERVE:
				return _judge_pulse(now_ms) if elapsed >= Attitude.PROBE_OBSERVE_MS else 0.0
			BURN:
				var over: bool = absf(_recent.back().rate - _rate_before) >= Attitude.DOUBLET_ABORT_RATE_DEG_S
				if elapsed >= _plan.on_ms or over:
					_burn_actual_ms = elapsed
					_up_fit = _second_half(now_ms)
					_enter(REVERSE, now_ms)
					return -_plan.pct
				return _plan.pct
			REVERSE:
				if elapsed >= _burn_actual_ms + _inversion_extra_ms:
					_down_fit = _second_half(now_ms)
					_enter(SETTLE, now_ms)
					return 0.0
				return -_plan.pct
			SETTLE:
				if elapsed >= Attitude.DOUBLET_SETTLE_MS:
					_judge_doublet(now_ms)
		return 0.0

	func _enter(stage: int, now_ms: float) -> void:
		_stage = stage
		_stage_started_ms = now_ms
		_stage_samples = []

	## Fit only the second half of a segment; the first half absorbs command latency.
	func _second_half(now_ms: float) -> Array:
		return Attitude._since(_stage_samples, _stage_started_ms + (now_ms - _stage_started_ms) / 2.0)

	func _begin_pulse(now_ms: float) -> float:
		var window := Attitude._since(_recent, now_ms - Attitude.BASELINE_MS)
		if window.size() < Attitude.MIN_BASELINE_SAMPLES:
			_enter(BASELINE, now_ms)
			return 0.0
		if _step >= _ladder.size():
			_enter(OFFLINE, now_ms)
			return 0.0
		_rate0 = Attitude._mean_rate(window)
		_sigma = Attitude._std_rate(window)
		_baseline_n = window.size()
		_pulse_pct = _ladder[_step].pct
		_pulse_ms = _ladder[_step].ms
		_pulse_start_angle = _recent.back().angle
		_pulse_start_ms = _recent.back().t
		_enter(PULSE, now_ms)
		return _pulse_pct

	## Did the pulse move the ship? Compares rate and orientation against the pre-pulse baseline.
	func _judge_pulse(now_ms: float) -> float:
		var tail := Attitude._since(_stage_samples, now_ms - Attitude.TAIL_MS)
		if tail.size() < Attitude.MIN_TAIL_SAMPLES:
			return 0.0
		var rate_delta := Attitude._mean_rate(tail) - _rate0
		var elapsed_s: float = (_stage_samples.back().t - _pulse_start_ms) / 1000.0
		var angle_delta: float = _stage_samples.back().angle - _pulse_start_angle - _rate0 * elapsed_s
		var rate_floor := maxf(Attitude.RESPONSE_RATE_DEG_S, Attitude.RESPONSE_NOISE_SIGMAS * _sigma)
		var angle_floor := maxf(Attitude.RESPONSE_ANGLE_DEG, Attitude.RESPONSE_NOISE_SIGMAS * _sigma / sqrt(_baseline_n) * elapsed_s)
		var rate_moved := absf(rate_delta) >= rate_floor
		if not rate_moved and absf(angle_delta) < angle_floor:
			_step += 1
			return _begin_pulse(now_ms)

		var pulse_s := _pulse_actual_ms / 1000.0
		var accel_per_pct: float
		if rate_moved:
			_sign = signf(rate_delta)
			accel_per_pct = absf(rate_delta) / (pulse_s * _pulse_pct)
		else:
			# Only the orientation moved: the pulse's rate kick drifted for pulse/2 + the coast after it.
			_sign = signf(angle_delta)
			accel_per_pct = absf(angle_delta) / (pulse_s * (pulse_s / 2.0 + elapsed_s - pulse_s) * _pulse_pct)
		_plan = Attitude.plan_doublet(accel_per_pct)
		_rate_before = Attitude._mean_rate(tail)
		# The probing pulse left the ship turning; lengthen the inversion so it ends where it started.
		_inversion_extra_ms = Attitude.inversion_extra_ms(_rate_before - _rate0, accel_per_pct, _plan.pct)
		_enter(BURN, now_ms)
		return _plan.pct

	## Both halves of the doublet must agree, point the way the pulse did, and the inversion must stop the ship.
	func _judge_doublet(now_ms: float) -> void:
		var up = Attitude._slope(_up_fit)
		var down = Attitude._slope(_down_fit)
		var tail := Attitude._since(_stage_samples, now_ms - Attitude.TAIL_MS)
		var good := up != null and down != null and tail.size() >= Attitude.MIN_TAIL_SAMPLES
		var up_gain := 0.0
		var down_gain := 0.0
		if good:
			up_gain = up / float(_plan.pct)
			down_gain = down / -float(_plan.pct)
			var pct: float = _plan.pct
			var weak := minf(absf(up_gain), absf(down_gain))
			var peak := absf(up_gain) * pct * _burn_actual_ms / 1000.0
			var residual := absf(Attitude._mean_rate(tail) - _rate0)
			var noise_floor := maxf(Attitude.RESPONSE_RATE_DEG_S, Attitude.RESPONSE_NOISE_SIGMAS * _sigma)
			good = (
				signf(up_gain) == _sign and signf(down_gain) == _sign
				and weak * pct >= Attitude.MIN_ACCEL_DEG_S2
				and maxf(absf(up_gain), absf(down_gain)) <= Attitude.MAX_SEGMENT_MISMATCH * weak
				and residual <= Attitude.DOUBLET_MAX_RESIDUAL_FRACTION * peak + noise_floor
			)
		if good:
			_gain = (up_gain + down_gain) / 2.0
			_enter(DONE, now_ms)
			return
		# Treat the detection as unreliable and climb to the next, stronger ladder step.
		_failures += 1
		_step += 1
		if _failures >= Attitude.MAX_MEASURE_FAILURES:
			_enter(OFFLINE, now_ms)
		else:
			_enter(BASELINE, now_ms)


## Measures yaw, pitch and roll torque authority one axis at a time. Yaw and pitch are required;
## a ship whose required axis never responds has an offline RCS.
class RcsCalibrator:
	var _current: AxisCalibration = null
	var _axis_index := 0
	var _results: Dictionary = {}
	var _offline: Array = []
	var _failed := false
	var _prev_orientation: Variant = null
	var _angles := {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}

	func start(now_ms: float) -> void:
		_results = {"yaw": null, "pitch": null, "roll": null}
		_offline = []
		_failed = false
		_axis_index = 0
		_prev_orientation = null
		_angles = {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
		_current = AxisCalibration.new(now_ms)

	## `orientation` is the ship's Quaternion; its per-sample rotation is accumulated into per-axis angles.
	func record(now_ms: float, rates: Dictionary, orientation: Variant) -> void:
		if _current == null:
			return
		if orientation != null:
			_accumulate_rotation(orientation)
		var axis: String = Attitude.RCS_AXES[_axis_index]
		_current.record(now_ms, rates[axis], _angles[axis])

	func _accumulate_rotation(orientation: Quaternion) -> void:
		if _prev_orientation != null:
			# Body-frame rotation since the previous sample; x/y/z map to roll/pitch/yaw like the rates.
			var delta: Quaternion = (_prev_orientation as Quaternion).inverse() * orientation
			var sign_w := 1.0 if delta.w >= 0.0 else -1.0
			var vec := Vector3(delta.x, delta.y, delta.z) * sign_w
			var s := vec.length()
			var rotation := vec * 2.0 if s < 1e-9 else vec / s * (2.0 * atan2(s, absf(delta.w)))
			_angles.roll += rad_to_deg(rotation.x)
			_angles.pitch += rad_to_deg(rotation.y)
			_angles.yaw += rad_to_deg(rotation.z)
		_prev_orientation = orientation

	## Commands to send now; call only when they will actually be sent, since stage timing starts at send.
	func command(now_ms: float) -> Dictionary:
		var values := {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
		if _current == null:
			return {"values": values, "done": true}
		var axis: String = Attitude.RCS_AXES[_axis_index]
		values[axis] = _current.command(now_ms)
		if _current.is_done():
			_results[axis] = _current.gain()
			if _current.is_offline():
				_offline.append(axis)
				if axis in Attitude.REQUIRED_RCS_AXES:
					_failed = true
			_axis_index += 1
			if _failed or _axis_index >= Attitude.RCS_AXES.size():
				_current = null
				return {"values": values, "done": true}
			_current = AxisCalibration.new(now_ms)
		return {"values": values, "done": false}

	func gains() -> Dictionary:
		return _results if not _results.is_empty() else {"yaw": null, "pitch": null, "roll": null}

	## Axes that never responded, in calibration order.
	func offline_axes() -> Array:
		return _offline
