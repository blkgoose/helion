class_name Persist

const PATH := "user://helion_state.json"

static var _data: Dictionary = {}
static var _loaded := false


static func get_value(key: String, default = null):
	_ensure_loaded()
	return _data.get(key, default)


## Setting null removes the key.
static func set_value(key: String, value) -> void:
	_ensure_loaded()
	if value == null:
		if not _data.has(key):
			return
		_data.erase(key)
	else:
		_data[key] = value
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_data))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_data = parsed
