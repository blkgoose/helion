class_name UniverseMap
extends Control
## Flat top-down chart of the whole system map, shown at maximum zoom-out. Radial distance is
## log-compressed so both nearby and remote bodies are clickable.

signal body_selected(key: String)
signal exit_requested

const MARGIN := 70.0
const PICK_RADIUS := 16.0
const REF_DISTANCE_M := 1000.0

var _points: Array = []
var _hover := -1
var _heading: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_heading = Label.new()
	_heading.text = "// SYSTEM MAP — click a body to set a course, scroll forward to exit"
	_heading.add_theme_color_override("font_color", UiTheme.ACCENT)
	_heading.position = Vector2(24, 60)
	add_child(_heading)


## entries: SystemMap entries; ship_position: floating position dictionary.
func update_data(ship_position: Dictionary, orientation: Variant, entries: Array) -> void:
	var raw: Array = []
	var max_d := REF_DISTANCE_M * 10.0
	for i in entries.size():
		var e: Dictionary = entries[i]
		if e.kind != "star" and e.kind != "planet":
			continue
		var rel := IonMath.relative(ship_position, e.position)
		var d := IonMath.length(rel)
		var v := IonMath.to_vec3(rel)
		if orientation != null:
			v = (orientation as Quaternion).inverse() * v
		raw.append({"key": "%d:%s" % [i, e.kind], "kind": e.kind, "d": d, "dir": Vector2(v.y, -v.x).normalized() if Vector2(v.y, -v.x).length() > 1e-9 else Vector2.UP})
		max_d = maxf(max_d, d)
	var radius := minf(size.x, size.y) / 2.0 - MARGIN
	var c := size / 2.0
	var k := log(1.0 + max_d / REF_DISTANCE_M)
	_points = []
	for r in raw:
		var rr := radius * log(1.0 + r.d / REF_DISTANCE_M) / k
		_points.append({"key": r.key, "kind": r.kind, "d": r.d, "p": c + r.dir * rr})
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var best := _pick(event.position)
		if best != _hover:
			_hover = best
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var i := _pick(event.position)
			if i >= 0:
				body_selected.emit(_points[i].key)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			exit_requested.emit()
		accept_event()


func _pick(at: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS
	for i in _points.size():
		var d: float = at.distance_to(_points[i].p)
		if d < best_d:
			best_d = d
			best = i
	return best


func _draw() -> void:
	var c := size / 2.0
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.03, 0.07, 0.94))
	var radius := minf(size.x, size.y) / 2.0 - MARGIN
	for f in [0.25, 0.5, 0.75, 1.0]:
		draw_arc(c, radius * f, 0, TAU, 96, Color(0.4, 0.8, 1.0, 0.12), 1.0, true)
	draw_line(c + Vector2(0, -radius), c + Vector2(0, radius), Color(0.4, 0.8, 1.0, 0.1))
	draw_line(c + Vector2(-radius, 0), c + Vector2(radius, 0), Color(0.4, 0.8, 1.0, 0.1))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(-6, 7), c + Vector2(6, 7)]), UiTheme.ACCENT)
	var font := ThemeDB.fallback_font
	for i in _points.size():
		var p: Dictionary = _points[i]
		var star: bool = p.kind == "star"
		var col := Color("ffdd66") if star else Color("6fa8dc")
		var hovered := i == _hover
		draw_line(c, p.p, Color(col, 0.12), 1.0, true)
		draw_circle(p.p, (8.0 if star else 5.0) + (3.0 if hovered else 0.0), col)
		if hovered:
			draw_arc(p.p, 13.0, 0, TAU, 24, Color(1, 1, 1, 0.8), 1.2, true)
		var label := "%s %s" % ["☉" if star else "●", IonMath.format_distance_short(p.d)]
		draw_string(font, p.p + Vector2(12, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.92, 1.0, 0.9 if hovered else 0.65))
