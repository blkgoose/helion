class_name ManualPanel
extends PanelContainer
## On-screen key set for manual flight; keycaps light up while held.

var _manual: ManualControl
var _caps := {}
var _thrust_label: Label
var _rcs_toggle: CheckButton
var _main_toggle: CheckButton


func _init(manual: ManualControl) -> void:
	_manual = manual
	visible = false


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_style(0.7, Color("ffb347")))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "// MANUALE  [T]   [P] PRIMA PERSONA"
	title.add_theme_color_override("font_color", Color("ffb347"))
	box.add_child(title)

	var toggles := HBoxContainer.new()
	box.add_child(toggles)
	_rcs_toggle = CheckButton.new()
	_rcs_toggle.text = "RCS"
	_rcs_toggle.button_pressed = _manual.rcs_enabled
	_rcs_toggle.toggled.connect(_manual.set_rcs_enabled)
	toggles.add_child(_rcs_toggle)
	_main_toggle = CheckButton.new()
	_main_toggle.text = "THRUSTER"
	_main_toggle.button_pressed = _manual.main_enabled
	_main_toggle.toggled.connect(_manual.set_main_enabled)
	toggles.add_child(_main_toggle)
	for toggle in [_rcs_toggle, _main_toggle]:
		toggle.focus_mode = Control.FOCUS_NONE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	row.add_child(_cluster("ROT", [["Q", KEY_Q, "roll-"], ["W", KEY_W, "muso"], ["E", KEY_E, "roll+"]], [["A", KEY_A, "lato"], ["S", KEY_S, "muso"], ["D", KEY_D, "lato"]]))
	var thrust := VBoxContainer.new()
	thrust.add_theme_constant_override("separation", 4)
	var thrust_title := Label.new()
	thrust_title.text = "THRUST"
	thrust.add_child(thrust_title)
	thrust.add_child(_cap("K", KEY_K, "su"))
	thrust.add_child(_cap("J", KEY_J, "giù"))
	_thrust_label = Label.new()
	thrust.add_child(_thrust_label)
	row.add_child(thrust)


func _cluster(title_text: String, top: Array, bottom: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = title_text
	col.add_child(title)
	for keys in [top, bottom]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		for k in keys:
			line.add_child(_cap(k[0], k[1], k[2]))
		col.add_child(line)
	return col


func _cap(text_: String, keycode: int, hint: String) -> Control:
	var cap := PanelContainer.new()
	cap.custom_minimum_size = Vector2(56, 34)
	var label := Label.new()
	label.text = "%s\n%s" % [text_, hint]
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(label)
	_caps[keycode] = cap
	_style(cap, false)
	return cap


func _style(cap: PanelContainer, down: bool) -> void:
	cap.add_theme_stylebox_override("panel", UiTheme.panel_style(0.85 if down else 0.35, Color("ffb347") if down else Color("4a6a80")))


func _process(_delta: float) -> void:
	visible = _manual.active
	if not visible:
		return
	for k in _caps:
		_style(_caps[k], _manual.keys_down.get(k, false))
	_thrust_label.text = "%d%%" % roundi(_manual.thrust_pct)
