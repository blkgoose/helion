class_name IonMath

const SECTOR_SIZE_M := 1e11
const LIGHT_YEAR_M := 9.4607e15
const AU_M := 1.496e11
const EARTH_MASS_KG := 5.972e24
const SOLAR_MASS_KG := 1.989e30
const RAD_TO_DEG := 180.0 / PI


## `to` relative to `from` in meters, correct across sector boundaries. Kept as doubles (Array),
## not Vector3: distances to planets span many sectors and float32 would lose meters.
static func relative(from: Dictionary, to: Dictionary) -> Array:
	var fs: Dictionary = from.sector
	var ts: Dictionary = to.sector
	var fh: Dictionary = from.shift
	var th: Dictionary = to.shift
	return [
		(ts.x - fs.x) * SECTOR_SIZE_M + (th.x - fh.x),
		(ts.y - fs.y) * SECTOR_SIZE_M + (th.y - fh.y),
		(ts.z - fs.z) * SECTOR_SIZE_M + (th.z - fh.z),
	]


static func length(v: Array) -> float:
	return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


static func to_vec3(v: Array) -> Vector3:
	return Vector3(v[0], v[1], v[2])


static func format_distance(distance_m: float) -> String:
	if distance_m < AU_M * 0.01:
		return "%d km" % roundi(distance_m / 1000.0)
	if distance_m < LIGHT_YEAR_M * 0.1:
		return "%.3f AU" % (distance_m / AU_M)
	return "%.3f ly" % (distance_m / LIGHT_YEAR_M)


static func format_distance_short(distance_m: float) -> String:
	if distance_m < AU_M * 0.01:
		return "%d km" % roundi(distance_m / 1000.0)
	if distance_m < LIGHT_YEAR_M * 0.1:
		return "%.2f AU" % (distance_m / AU_M)
	return "%.2f ly" % (distance_m / LIGHT_YEAR_M)


static func format_mass(mass_kg: float) -> String:
	if mass_kg >= SOLAR_MASS_KG * 0.01:
		return "%.3f M☉" % (mass_kg / SOLAR_MASS_KG)
	return "%.2f M⊕" % (mass_kg / EARTH_MASS_KG)


static func contact_icon(kind: String) -> String:
	match kind:
		"ship":
			return "▲"
		"asteroid":
			return "◆"
		_:
			return "●"


## Integral floats as integers ("4000000", not "4000000.0") so they parse for integer variables too.
static func format_number(value: float) -> String:
	if is_finite(value) and value == floorf(value) and absf(value) < 1e15:
		return str(int(value))
	return str(value)


## Display/serialization of an arbitrary manifest value.
static func format_value(value) -> String:
	if value == null:
		return "-"
	if value is float:
		return format_number(value)
	if value is Dictionary or value is Array:
		return JSON.stringify(value)
	return str(value)


## "4k" / "2.5M" / "1g" -> plain number; anything that isn't strictly "<number><suffix>" passes through.
static func expand_numeric_suffix(value: String) -> String:
	var regex := RegEx.new()
	regex.compile("^(-?\\d+(?:\\.\\d+)?)\\s*([kmgKMG])$")
	var m := regex.search(value.strip_edges())
	if m == null:
		return value
	var multiplier := 1e3
	match m.get_string(2).to_lower():
		"m":
			multiplier = 1e6
		"g":
			multiplier = 1e9
	return format_number(float(m.get_string(1)) * multiplier)


static func format_duration(total_seconds: float) -> String:
	if not is_finite(total_seconds):
		return "-"
	var sign_str := "-" if total_seconds < 0 else ""
	var remaining := roundi(absf(total_seconds))
	var weeks := remaining / 604800
	remaining -= weeks * 604800
	var days := remaining / 86400
	remaining -= days * 86400
	var hours := remaining / 3600
	remaining -= hours * 3600
	var minutes := remaining / 60
	var seconds := remaining - minutes * 60
	var parts := PackedStringArray()
	if weeks: parts.append("%dw" % weeks)
	if days: parts.append("%dd" % days)
	if hours: parts.append("%dh" % hours)
	if minutes: parts.append("%dm" % minutes)
	if seconds or parts.is_empty(): parts.append("%ds" % seconds)
	return sign_str + " ".join(parts)


static func is_seconds_field(field_name: String, description: String) -> bool:
	return field_name.ends_with("_s") or field_name.ends_with("_time") or description.to_lower().contains("second")


static func now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0


## Fresh scans stay white, stale ones fade to red. `t` is 0 (fresh)..1 (stale).
static func age_color(t: float) -> Color:
	return Color.WHITE.lerp(Color("e03030"), clampf(t, 0.0, 1.0))
