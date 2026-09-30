class_name LoginPanel
extends Control

signal logged_in

var _panel: PanelContainer
var _status: Label
var _fields := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	_panel.add_child(box)

	var env_url := OS.get_environment("ION_SERVER_URL")
	_add_field(box, "server", "Server", env_url if env_url != "" else IonClient.server_url, false)
	_add_field(box, "ship", "Ship ID", "", false)
	_add_field(box, "component", "Component", "core", false)
	_add_field(box, "password", "Password", "", true)

	var button := Button.new()
	button.text = "Login"
	button.pressed.connect(submit)
	box.add_child(button)
	_status = Label.new()
	box.add_child(_status)


func set_status(message: String) -> void:
	_status.text = message


func _add_field(parent: Control, key: String, label_text: String, value: String, secret: bool) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.text = value
	edit.secret = secret
	edit.text_submitted.connect(func(_t): submit())
	if key != "server":
		edit.text_changed.connect(_on_credential_text_changed)
	parent.add_child(edit)
	_fields[key] = edit


## Parses a pasted "LOGIN id component pass" (LOGIN keyword optional) into its three fields.
static func parse_login_string(text: String) -> PackedStringArray:
	var normalized := text.replace("\t", " ").replace("\n", " ").replace("\r", " ")
	var tokens := normalized.split(" ", false)
	if not tokens.is_empty() and tokens[0].to_upper() == "LOGIN":
		tokens.remove_at(0)
	if tokens.size() != 3:
		return PackedStringArray()
	return tokens


func _on_credential_text_changed(text: String) -> void:
	var parsed := parse_login_string(text)
	if parsed.is_empty():
		return
	_fields.ship.text = parsed[0]
	_fields.component.text = parsed[1]
	_fields.password.text = parsed[2]
	submit()


func submit() -> void:
	IonClient.server_url = _fields.server.text.strip_edges()
	_status.text = "Connecting..."
	var result := await IonClient.login(
		_fields.ship.text.strip_edges(),
		_fields.component.text.strip_edges(),
		_fields.password.text,
	)
	if result.ok:
		logged_in.emit()
	else:
		_status.text = result.error
