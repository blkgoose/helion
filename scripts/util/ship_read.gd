class_name ShipRead
## Readers for the shapes inside GET's entity JSON (confirmed against a running server).

const MAIN_THRUSTER_TYPES := ["LightThruster", "StandardThruster", "CapitalThruster"]
# fuelcell.rs's FUEL_CAPACITY_KG, mirrored to turn fuel_kg into a gauge percentage.
const FUEL_CAPACITY_KG := 50000.0


static func dig(root, path: Array):
	var node = root
	for key in path:
		if not (node is Dictionary) or not node.has(key):
			return null
		node = node[key]
	return node


## body.position.position: {sector, shift}, or {} when absent.
static func floating_position(entity: Dictionary) -> Dictionary:
	var pos = dig(entity, ["body", "position", "position"])
	if pos is Dictionary and pos.has("sector") and pos.has("shift"):
		return pos
	return {}


static func shift(entity: Dictionary) -> Vector3:
	var pos := floating_position(entity)
	if pos.is_empty():
		return Vector3.ZERO
	return Vector3(pos.shift.x, pos.shift.y, pos.shift.z)


static func _vec(v) -> Variant:
	if v is Dictionary and v.has("x"):
		return Vector3(v.x, v.y, v.z)
	return null


static func velocity(entity: Dictionary) -> Variant:
	return _vec(dig(entity, ["body", "position", "velocity"]))


## Angular velocity, rad/s per axis in the ship's local frame.
static func angular_velocity(entity: Dictionary) -> Variant:
	return _vec(dig(entity, ["body", "rotation", "velocity"]))


## body.rotation.orientation {q,x,y,z}, q is the scalar component.
static func orientation(entity: Dictionary) -> Variant:
	var o = dig(entity, ["body", "rotation", "orientation"])
	if o is Dictionary and o.has("q"):
		var quat := Quaternion(o.x, o.y, o.z, o.q)
		if quat.length() > 0.0:
			return quat.normalized()
	return null


static func size(entity: Dictionary) -> Variant:
	var s = dig(entity, ["body", "size"])
	return s if s is float or s is int else null


static func mass(entity: Dictionary) -> Variant:
	var m = dig(entity, ["body", "mass"])
	return m if m is float or m is int else null


static func module_field(entity: Dictionary, module_id: String, field: String) -> Variant:
	var v = dig(entity, ["modules", module_id, field])
	return v if v is float or v is int else null


## [{module_id, type}], sorted by type then id.
static func modules(entity: Dictionary) -> Array:
	var out := []
	var mods = entity.get("modules")
	if mods is Dictionary:
		for id in mods:
			var value = mods[id]
			if value is Dictionary and value.get("type") is String:
				out.append({"module_id": id, "type": value.type})
	out.sort_custom(func(a, b):
		if a.type != b.type:
			return a.type < b.type
		return a.module_id < b.module_id)
	return out


static func engine_activations(entity: Dictionary, mods: Array) -> Array:
	var out := []
	for m in mods:
		if m.type in MAIN_THRUSTER_TYPES or m.type == "SteeringThruster":
			out.append({
				"module_id": m.module_id,
				"type": m.type,
				"activation": module_field(entity, m.module_id, "activation") if module_field(entity, m.module_id, "activation") != null else 0.0,
			})
	return out


static func fuel_levels(entity: Dictionary, mods: Array) -> Array:
	var out := []
	for m in mods:
		if m.type == "FuelCell":
			var fuel = module_field(entity, m.module_id, "fuel_kg")
			out.append({"module_id": m.module_id, "fuel_kg": fuel if fuel != null else 0.0})
	return out


static func _nearest_yaw_bucket(yaw: float) -> int:
	var normalized := fposmod(yaw, 360.0)
	var best := 0
	var best_dist := INF
	for bucket in [0, 90, 180, 270]:
		var d := minf(absf(normalized - bucket), 360.0 - absf(normalized - bucket))
		if d < best_dist:
			best_dist = d
			best = bucket
	return best


## Sorts thrusters by role. SteeringThruster.yaw is the mount's fixed firing direction (deg, 0 = forward).
static func classify_thrusters(entity: Variant, mods: Array) -> Dictionary:
	var groups := {"rcs": [], "fixed": [], "retro": [], "lateral_q": [], "lateral_e": []}
	for m in mods:
		if m.type == "RcsThruster":
			groups.rcs.append(m)
		elif m.type in MAIN_THRUSTER_TYPES:
			groups.fixed.append(m)
		elif m.type == "SteeringThruster":
			var yaw = module_field(entity, m.module_id, "yaw") if entity != null else null
			match _nearest_yaw_bucket(yaw if yaw != null else 0.0):
				180:
					groups.retro.append(m)
				90:
					groups.lateral_q.append(m)
				270:
					groups.lateral_e.append(m)
	return groups
