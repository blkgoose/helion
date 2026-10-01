class_name ModulesModal
extends Control
## M: tabs by module category, module list, live manifest detail with editable variables and action forms.

const REFRESH_S := 1.0

var _modules: Array = []
var _active_tab := "cargo"
var _selected := ""
var _tabs: HBoxContainer
var _list: ItemList
var _detail: VBoxContainer
var _listed: Array = []
var _timer: Timer
var _value_nodes := {}
var _health: Label
var _manifest_token := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(0.94, UiTheme.ACCENT))
	margin.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_tabs = HBoxContainer.new()
	box.add_child(_tabs)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(320, 0)
	_list.item_selected.connect(_on_module_selected)
	body.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail)
	body.add_child(scroll)
	_timer = Timer.new()
	_timer.wait_time = REFRESH_S
	_timer.timeout.connect(_refresh_detail)
	add_child(_timer)


func is_open() -> bool:
	return visible


func set_modules(modules: Array) -> void:
	var old := _signature()
	_modules = modules
	if visible and _signature() != old:
		_render_list()


func _signature() -> String:
	return ",".join(_modules.map(func(m): return "%s:%s" % [m.module_id, m.type]))


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	InputState.captured = true
	_render_list()


func close() -> void:
	visible = false
	InputState.captured = false
	_timer.stop()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_M and not key.ctrl_pressed and (visible or not InputState.captured):
		get_viewport().set_input_as_handled()
		toggle()
	elif visible and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
	elif visible and key.keycode >= KEY_1 and key.keycode <= KEY_6:
		get_viewport().set_input_as_handled()
		_set_tab(ModuleTabs.ORDER[key.keycode - KEY_1])


func _set_tab(tab: String) -> void:
	if tab == _active_tab:
		return
	_active_tab = tab
	_selected = ""
	_render_list()


func _render_list() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	for i in ModuleTabs.ORDER.size():
		var tab: String = ModuleTabs.ORDER[i]
		var button := Button.new()
		button.text = "%d. %s" % [i + 1, ModuleTabs.LABELS[tab]]
		button.flat = tab != _active_tab
		button.pressed.connect(_set_tab.bind(tab))
		_tabs.add_child(button)

	_listed = _modules.filter(func(m): return ModuleTabs.tab_for(m.type) == _active_tab)
	_list.clear()
	var selected_index := -1
	for i in _listed.size():
		_list.add_item("%s  %s" % [_listed[i].type, str(_listed[i].module_id).substr(0, 8)])
		_list.set_item_tooltip(i, _listed[i].module_id)
		if _listed[i].module_id == _selected:
			selected_index = i
	if selected_index < 0:
		_selected = ""
		_clear_detail()
		if _listed.is_empty():
			var empty := Label.new()
			empty.text = "No modules in this category."
			_detail.add_child(empty)
	else:
		_list.select(selected_index)
		_show_detail(_selected)


func _on_module_selected(index: int) -> void:
	_selected = _listed[index].module_id
	_show_detail(_selected)


func _clear_detail() -> void:
	_timer.stop()
	_value_nodes.clear()
	for child in _detail.get_children():
		child.queue_free()


func _show_detail(module_id: String) -> void:
	_clear_detail()
	var loading := Label.new()
	loading.text = "Loading..."
	_detail.add_child(loading)
	_manifest_token += 1
	var token := _manifest_token
	var result := await IonClient.man(module_id)
	if token != _manifest_token or _selected != module_id:
		return
	_clear_detail()
	if not result.ok:
		var err := Label.new()
		err.text = result.error
		err.add_theme_color_override("font_color", Color("e05555"))
		_detail.add_child(err)
		return
	_build_manifest(result.data)
	_timer.start()


func _build_manifest(m: Dictionary) -> void:
	var title := Label.new()
	title.text = "%s  [%s]" % [m.get("module_id", ""), m.get("type", "")]
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_detail.add_child(title)
	var desc := Label.new()
	desc.text = str(m.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(desc)
	var health_row := HBoxContainer.new()
	var health_label := Label.new()
	health_label.text = "Health  "
	_health = Label.new()
	_health.text = "%d%%" % float(m.get("health_pct", 0))
	health_row.add_child(health_label)
	health_row.add_child(_health)
	_detail.add_child(health_row)

	var module_id: String = m.module_id
	for v in m.get("variables", []):
		var name: String = v.name
		var row := VBoxContainer.new()
		var label := Label.new()
		label.text = "%s — %s" % [name, v.get("description", "")]
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color("8899aa"))
		row.add_child(label)
		if v.get("type") == "array":
			var cargo := Label.new()
			cargo.text = _format_cargo(v.get("value"))
			row.add_child(cargo)
			_value_nodes[name] = {"kind": "cargo", "node": cargo}
		elif v.get("mutable", false):
			var edit := LineEdit.new()
			edit.text = _plain(v.get("value"))
			edit.text_submitted.connect(func(text: String):
				IonClient.set_variable(module_id, name, IonMath.expand_numeric_suffix(text)))
			row.add_child(edit)
			_value_nodes[name] = {"kind": "edit", "node": edit}
		else:
			var value := Label.new()
			value.text = _format_variable(v)
			row.add_child(value)
			_value_nodes[name] = {"kind": "label", "node": value, "variable": v}
		_detail.add_child(row)

	for a in m.get("actions", []):
		var action_name: String = a.name
		var cooldown := float(a.get("cooldown_s", 0))
		var row := VBoxContainer.new()
		var label := Label.new()
		label.text = "%s — %s%s" % [action_name, a.get("description", ""), " (cooldown %s)" % IonMath.format_duration(cooldown) if cooldown > 0 else ""]
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color("8899aa"))
		row.add_child(label)
		var controls := HBoxContainer.new()
		var inputs: Array[LineEdit] = []
		for p in a.get("params", []):
			var edit := LineEdit.new()
			edit.placeholder_text = p.name
			edit.tooltip_text = str(p.get("description", ""))
			edit.custom_minimum_size = Vector2(110, 0)
			controls.add_child(edit)
			inputs.append(edit)
		var run := Button.new()
		run.text = "Run"
		run.pressed.connect(func():
			var params := PackedStringArray()
			for edit in inputs:
				params.append(IonMath.expand_numeric_suffix(edit.text))
			IonClient.action(module_id, action_name, params))
		controls.add_child(run)
		row.add_child(controls)
		_detail.add_child(row)


func _refresh_detail() -> void:
	if _selected == "":
		return
	var module_id := _selected
	var result := await IonClient.man(module_id)
	if not result.ok or _selected != module_id:
		return
	var m: Dictionary = result.data
	if _health != null and is_instance_valid(_health):
		_health.text = "%d%%" % float(m.get("health_pct", 0))
	for v in m.get("variables", []):
		var entry = _value_nodes.get(v.name)
		if entry == null or not is_instance_valid(entry.node):
			continue
		match entry.kind:
			"cargo":
				entry.node.text = _format_cargo(v.get("value"))
			"label":
				entry.node.text = _format_variable(v)
			"edit":
				if not entry.node.has_focus():
					entry.node.text = _plain(v.get("value"))


static func _plain(value) -> String:
	if value == null:
		return ""
	return IonMath.format_value(value)


static func _format_variable(v: Dictionary) -> String:
	var value = v.get("value")
	if value == null:
		return "-"
	if (value is float or value is int) and IonMath.is_seconds_field(v.name, str(v.get("description", ""))):
		return "%s (%ss)" % [IonMath.format_duration(value), IonMath.format_value(value)]
	return IonMath.format_value(value)


# Cargo slots are externally-tagged Rust enums: {"Unit":["Iron",5]}, {"Weight":[..]}, {"Volume":[..]}.
static func _format_cargo(slots) -> String:
	if not (slots is Array) or slots.is_empty():
		return "Empty"
	var lines := PackedStringArray()
	for item in slots:
		var text := JSON.stringify(item)
		if item is Dictionary and item.size() == 1:
			var variant: String = item.keys()[0]
			var payload = item[variant]
			if payload is Array and payload.size() == 2:
				var unit := {"Unit": "units", "Weight": "kg", "Volume": "m³"}.get(variant, "") as String
				var amount: String = str(int(payload[1])) if variant == "Unit" else "%.2f" % float(payload[1])
				text = "%s: %s %s" % [payload[0], amount, unit]
		lines.append("• " + text)
	return "\n".join(lines)
