class_name Hud
extends Control
## POS/VEL/ACC/ANG readout, FPS, Logout / Full stop buttons, module hint, autopilot status, toasts.

signal logout_pressed
signal full_stop_pressed
signal disengage_pressed

const PHASE_LABELS := {
	"idle": "",
	"tuning": "Calibrazione RCS…",
	"pointing": "Puntamento",
	"burning": "Accelerazione",
	"stoppingBurner": "Arresto propulsore",
	"reverse": "Inversione di rotta",
	"stopping": "Frenata",
	"fineStop": "Frenata di precisione",
}

var _status_label: RichTextLabel
var _fps_label: Label
var _last_velocity: Variant = null
var _last_ts := 0.0
var _acc := Vector3.ZERO
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _ang := Vector3.ZERO
var _autopilot_panel: PanelContainer
var _autopilot_label: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_timer: Timer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var status := PanelContainer.new()
	status.position = Vector2(16, 16)
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.custom_minimum_size = Vector2(470, 0)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "monospace"])
	_status_label.add_theme_font_override("normal_font", mono)
	_status_label.add_theme_font_override("bold_font", mono)
	_status_label.add_theme_font_size_override("normal_font_size", 13)
	_status_label.add_theme_font_size_override("bold_font_size", 13)
	status.add_child(_status_label)
	add_child(status)

	var fps := PanelContainer.new()
	_fps_label = Label.new()
	fps.add_child(_fps_label)
	fps.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var top_right := HBoxContainer.new()
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.add_theme_constant_override("separation", 8)
	top_right.add_child(fps)
	add_child(top_right)

	var logout := Button.new()
	logout.text = "Logout"
	var buttons := VBoxContainer.new()
	top_right.add_child(buttons)
	buttons.add_child(logout)
	logout.pressed.connect(func(): logout_pressed.emit())

	var stop := Button.new()
	stop.text = "Full stop"
	stop.add_theme_color_override("font_color", Color("ee8888"))
	stop.pressed.connect(func(): full_stop_pressed.emit())
	buttons.add_child(stop)
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)

	var hint := PanelContainer.new()
	var hint_label := Label.new()
	hint_label.text = "[M] Moduli   [Ctrl+K] Comandi"
	hint.add_child(hint_label)
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)

	_autopilot_panel = PanelContainer.new()
	_autopilot_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(0.6, Color("44cc66")))
	var row := HBoxContainer.new()
	_autopilot_label = Label.new()
	row.add_child(_autopilot_label)
	var disengage := Button.new()
	disengage.text = "Disengage"
	disengage.pressed.connect(func(): disengage_pressed.emit())
	row.add_child(disengage)
	_autopilot_panel.add_child(row)
	_autopilot_panel.visible = false
	add_child(_autopilot_panel)
	_autopilot_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	_autopilot_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", UiTheme.panel_style(0.8, Color("cc5555")))
	_toast_label = Label.new()
	_toast.add_child(_toast_label)
	_toast.visible = false
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 70)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast.visible = false)
	add_child(_toast_timer)


func _process(_delta: float) -> void:
	_fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	_status_label.text = "%s\n%s\n%s\n%s" % [_row("POS", _pos, ""), _row("VEL", _vel, "m/s"), _row("ACC", _acc, "m/s²"), _row("ANG", _ang, "°/s")]


static func _fmt(v: Vector3) -> String:
	return "%10.4f / %10.4f / %10.4f" % [v.x, v.y, v.z]


func update_state(entity: Dictionary) -> void:
	_pos = ShipRead.shift(entity)
	var velocity = ShipRead.velocity(entity)
	if velocity == null:
		return
	_vel = velocity
	var now := IonMath.now_ms()
	if _last_velocity != null:
		var dt := (now - _last_ts) / 1000.0
		if dt > 0.0:
			_acc = (_vel - (_last_velocity as Vector3)) / dt
	_last_velocity = _vel
	_last_ts = now
	var angular = ShipRead.angular_velocity(entity)
	if angular != null:
		_ang = (angular as Vector3) * IonMath.RAD_TO_DEG


func update_autopilot(engaged: bool, label: String, phase: String, distance_m: Variant = null) -> void:
	_autopilot_panel.visible = engaged
	if engaged:
		var text := "%s — %s" % [label, PHASE_LABELS.get(phase, "")]
		if distance_m != null:
			text += " — %s" % IonMath.format_distance(distance_m)
		_autopilot_label.text = text


func notify(message: String) -> void:
	_toast_label.text = message
	_toast.visible = true
	_toast_timer.start(6.0)


static func _row(label: String, v: Vector3, unit: String) -> String:
	return "[color=#66ccff][b]%s[/b][/color]  %s  [color=#6f8396]%s[/color]" % [label, _fmt(v), unit]
