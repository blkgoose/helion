class_name CommandPalette
extends Control
## Ctrl+K grouped command palette. Nodes: {kind: list|picker|run|edit|info, ...}.
##   list/picker: load: Callable() -> Array[item] (may be async)
##   run: run: Callable()
##   edit: value: String, commit: Callable(String)
## item = {label, node}. Backspace-on-empty / Escape go back a level.

var _is_open := false
var _root_items: Callable
var _stack: Array = []
var _selected := 0
var _editing: Variant = null
var _token := 0
var _breadcrumb: Label
var _field: LineEdit
var _list: ItemList
var _shown: Array = []


func _init(root_items: Callable) -> void:
	_root_items = root_items


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(0.94, UiTheme.ACCENT))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)
	_breadcrumb = Label.new()
	_breadcrumb.add_theme_color_override("font_color", Color("8899aa"))
	box.add_child(_breadcrumb)
	_field = LineEdit.new()
	_field.text_changed.connect(func(_t):
		if _editing == null:
			_selected = 0
		_render())
	_field.gui_input.connect(_on_input_key)
	box.add_child(_field)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 320)
	_list.item_activated.connect(func(i): _activate(i))
	_list.item_clicked.connect(func(i, _p, button): if button == MOUSE_BUTTON_LEFT: _activate(i))
	box.add_child(_list)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.ctrl_pressed and key.keycode == KEY_K:
		get_viewport().set_input_as_handled()
		close() if _is_open else open()


func _input(event: InputEvent) -> void:
	# Ctrl+K must also work while a LineEdit (e.g. the palette's own field) holds focus.
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.ctrl_pressed and key.keycode == KEY_K and _is_open:
		get_viewport().set_input_as_handled()
		close()


func is_open() -> bool:
	return _is_open


func open() -> void:
	_open_with([{"title": "Commands", "items": _root_items.call()}])


func open_list(title: String, items: Array) -> void:
	_open_with([{"title": title, "items": items}])


func _open_with(stack: Array) -> void:
	_is_open = true
	visible = true
	InputState.captured = true
	_editing = null
	_stack = stack
	_selected = 0
	_field.text = ""
	_render()
	_field.grab_focus()


func close() -> void:
	_is_open = false
	visible = false
	InputState.captured = false
	_editing = null
	_field.release_focus()


func _frame() -> Dictionary:
	return _stack[_stack.size() - 1]


func _filtered() -> Array:
	var items = _frame().items
	if items == null:
		return []
	var query := "" if _editing != null else _field.text.strip_edges().to_lower()
	if query == "":
		return items
	return items.filter(func(item): return item.label.to_lower().contains(query))


func _on_input_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_ESCAPE:
			_field.accept_event()
			if _editing != null:
				_editing = null
				_field.text = ""
				_render()
			elif _stack.size() > 1:
				_pop()
			else:
				close()
		KEY_ENTER, KEY_KP_ENTER:
			_field.accept_event()
			if _editing != null:
				_commit_edit()
			else:
				_activate(_selected)
		KEY_DOWN:
			_field.accept_event()
			if _editing == null:
				_move(1)
		KEY_UP:
			_field.accept_event()
			if _editing == null:
				_move(-1)
		KEY_BACKSPACE:
			if _editing == null and _field.text == "" and _stack.size() > 1:
				_field.accept_event()
				_pop()


func _move(delta: int) -> void:
	var items := _filtered()
	if items.is_empty():
		return
	_selected = (_selected + delta + items.size()) % items.size()
	_render()


func _pop() -> void:
	_stack.pop_back()
	_selected = 0
	_field.text = ""
	_render()


func _activate(index: int) -> void:
	if _editing != null:
		return
	var items := _filtered()
	if index < 0 or index >= items.size():
		return
	var item: Dictionary = items[index]
	var node: Dictionary = item.node
	match node.kind:
		"info":
			return
		"run":
			if _frame().get("pop_on_run", false):
				_pop()
			else:
				close()
			node.run.call()
		"edit":
			_editing = {"item": item, "node": node}
			_field.text = node.value
			_render()
			_field.grab_focus()
			_field.select_all()
		"list", "picker":
			_token += 1
			var token := _token
			_stack.append({"title": item.label, "items": null, "pop_on_run": node.kind == "picker"})
			_selected = 0
			_field.text = ""
			_render()
			var loaded = await node.load.call()
			if token != _token:
				return
			_frame().items = loaded
			_render()


func _commit_edit() -> void:
	var node: Dictionary = _editing.node
	var value := _field.text
	_editing = null
	_field.text = ""
	_render()
	node.commit.call(value)


func _render() -> void:
	var titles := PackedStringArray()
	for frame in _stack:
		titles.append(frame.title)
	var crumb := " › ".join(titles)
	if _editing != null:
		crumb += " › " + _editing.item.label
	_breadcrumb.text = crumb

	_list.clear()
	if _frame().items == null:
		_list.add_item("Loading…", null, false)
		return
	_shown = _filtered()
	if _shown.is_empty():
		_list.add_item("No results.", null, false)
		return
	for i in _shown.size():
		var item: Dictionary = _shown[i]
		var suffix := " ›" if item.node.kind in ["list", "picker"] else ""
		_list.add_item(item.label + suffix)
		if item.node.kind == "info":
			_list.set_item_custom_fg_color(i, Color("778899"))
	_selected = clampi(_selected, 0, _shown.size() - 1)
	_list.select(_selected)
	_list.ensure_current_is_visible()
