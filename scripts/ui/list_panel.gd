class_name ListPanel
extends PanelContainer
## Titled, clickable list; rows are reused across updates (keyed) so a click is never lost to a rebuild.

signal row_selected(key: String)

var _list: VBoxContainer
var _rows := {}


func _init(title: String) -> void:
	var box := VBoxContainer.new()
	var heading := Label.new()
	heading.text = "// " + title.to_upper()
	heading.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(heading)
	box.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	box.add_child(_list)
	add_child(box)
	visible = false


## rows: [{key, text}] in display order.
func set_rows(rows: Array) -> void:
	visible = not rows.is_empty()
	var seen := {}
	for i in rows.size():
		var key: String = rows[i].key
		seen[key] = true
		var button: Button = _rows.get(key)
		if button == null:
			button = Button.new()
			button.flat = true
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.pressed.connect(func(): row_selected.emit(key))
			_rows[key] = button
			_list.add_child(button)
		if button.text != rows[i].text:
			button.text = rows[i].text
		_list.move_child(button, i)
	for key in _rows.keys():
		if not seen.has(key):
			_rows[key].queue_free()
			_rows.erase(key)
