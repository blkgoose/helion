class_name Minimap
extends Control
## Ship-relative radar disc: up is where the nose points. Radar contacts at real scale inside 10 km;
## system bodies are pinned to the rim (only their direction matters at that range).

const RADAR_RANGE_M := 10e3
const SIZE_PX := 160.0

var _ship_position: Dictionary = {}
var _orientation: Variant = null
var _system: Array = []
var _contacts: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	size = Vector2(SIZE_PX, SIZE_PX)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func update_data(ship_position: Dictionary, orientation: Variant, system_entries: Array, contacts: Array) -> void:
	_ship_position = ship_position
	_orientation = orientation
	_system = system_entries
	_contacts = contacts
	queue_redraw()


func _draw() -> void:
	var c := Vector2(SIZE_PX, SIZE_PX) / 2.0
	var max_r := SIZE_PX / 2.0 - 8.0
	draw_circle(c, SIZE_PX / 2.0, Color(0.03, 0.05, 0.09, 0.62))
	draw_arc(c, SIZE_PX / 2.0 - 1.0, 0, TAU, 64, Color(0.4, 0.8, 1.0, 0.35), 2.0)
	draw_arc(c, max_r, 0, TAU, 64, Color(0.4, 0.8, 1.0, 0.2), 1.0)
	draw_arc(c, max_r * 0.66, 0, TAU, 64, Color(0.4, 0.8, 1.0, 0.1), 1.0)
	draw_arc(c, max_r * 0.33, 0, TAU, 64, Color(0.4, 0.8, 1.0, 0.1), 1.0)
	draw_line(c + Vector2(0, -max_r), c + Vector2(0, max_r), Color(0.4, 0.8, 1.0, 0.08))
	draw_line(c + Vector2(-max_r, 0), c + Vector2(max_r, 0), Color(0.4, 0.8, 1.0, 0.08))
	if _orientation == null or _ship_position.is_empty():
		draw_circle(c, 3, UiTheme.ACCENT)
		return
	var inverse: Quaternion = (_orientation as Quaternion).inverse()
	for contact in _contacts:
		_plot(inverse, contact[1], false, IonMath.age_color(float(contact[6]) if contact.size() > 6 else 0.0), 3.0, c, max_r)
	for entry in _system:
		var is_star: bool = entry.kind == "star"
		_plot(inverse, entry.position, true, Color("ffdd66") if is_star else Color("6699cc"), 3.0 if is_star else 2.0, c, max_r)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(-4, 4), c + Vector2(4, 4)]), UiTheme.ACCENT)


func _plot(inverse: Quaternion, position: Dictionary, pin_to_rim: bool, color: Color, radius: float, c: Vector2, max_r: float) -> void:
	var local: Vector3 = inverse * IonMath.to_vec3(IonMath.relative(_ship_position, position))
	var distance := Vector2(local.x, local.y).length()
	if distance == 0.0:
		return
	var screen_r := max_r if pin_to_rim else minf(1.0, distance / RADAR_RANGE_M) * max_r
	var k := screen_r / distance
	draw_circle(c + Vector2(local.y * k, -local.x * k), radius, color)
