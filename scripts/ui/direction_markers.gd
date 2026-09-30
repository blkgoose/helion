class_name DirectionMarkers
extends Control
## Compass labels for bodies/contacts: on-screen ones sit at their projected position, off-screen
## ones clamp to the view edge with an arrow.

const EDGE_MARGIN := 0.92

var _labels: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## entries: [{icon, world_position: Vector3, distance_m}]
func update_markers(camera: Camera3D, entries: Array) -> void:
	while _labels.size() < entries.size():
		var label := Label.new()
		label.add_theme_color_override("font_color", Color("ddddee"))
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_font_size_override("font_size", 11)
		add_child(label)
		_labels.append(label)
	var view := get_viewport_rect().size
	var inverse := camera.global_transform.affine_inverse()
	var tan_half := tan(deg_to_rad(camera.fov) / 2.0)
	var aspect := view.x / view.y
	for i in _labels.size():
		var label := _labels[i]
		if i >= entries.size():
			label.visible = false
			continue
		var entry: Dictionary = entries[i]
		var local: Vector3 = inverse * entry.world_position
		var depth := maxf(absf(local.z), 0.0001)
		var behind := local.z > 0.0
		var x := local.x / (depth * tan_half * aspect)
		var y := local.y / (depth * tan_half)
		var offscreen := behind or absf(x) > 1.0 or absf(y) > 1.0
		if offscreen:
			var angle := atan2(y, x)
			x = cos(angle) * EDGE_MARGIN
			y = sin(angle) * EDGE_MARGIN
		var text := "%s %s" % [entry.icon, IonMath.format_distance_short(entry.distance_m)]
		if offscreen:
			text = ("▶ " if x >= 0.0 else "◀ ") + text
		label.text = text
		label.visible = true
		var screen := Vector2((x * 0.5 + 0.5) * view.x, (1.0 - (y * 0.5 + 0.5)) * view.y)
		label.position = screen - label.size / 2.0
