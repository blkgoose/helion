extends Node3D
## Tactical view: ship at the scene origin (floating origin), orbit camera, login + HUD overlays.

var _camera: TacticalCamera
var _ship: MeshInstance3D
var _hud_label: Label
var _hud_panel: PanelContainer
var _login_panel: PanelContainer
var _login_status: Label
var _fields := {}


func _ready() -> void:
	_build_world()
	_build_hud()
	_build_login()
	ShipState.updated.connect(_on_state_updated)
	IonClient.disconnected.connect(_on_disconnected)
	_show_login("")


func _process(_delta: float) -> void:
	if _hud_panel.visible:
		_hud_label.text = _hud_text(ShipState.latest)


func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.09, 0.12)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Placeholder hull: local +X is forward, like ION's ship frame.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8, 2, 3)
	_ship = MeshInstance3D.new()
	_ship.mesh = mesh
	add_child(_ship)

	_camera = TacticalCamera.new()
	# A huge far/near ratio makes the light culler's frustum intersection fail (black screen).
	_camera.near = 0.5
	_camera.far = 1.0e5
	add_child(_camera)
	_camera.make_current()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_panel = PanelContainer.new()
	_hud_panel.position = Vector2(12, 12)
	_hud_label = Label.new()
	_hud_panel.add_child(_hud_label)
	layer.add_child(_hud_panel)


func _build_login() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	_login_panel = PanelContainer.new()
	center.add_child(_login_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	_login_panel.add_child(box)

	var env_url := OS.get_environment("ION_SERVER_URL")
	_add_field(box, "server", "Server", env_url if env_url != "" else IonClient.server_url, false)
	_add_field(box, "ship", "Ship ID", "", false)
	_add_field(box, "component", "Component", "", false)
	_add_field(box, "password", "Password", "", true)

	var button := Button.new()
	button.text = "Login"
	button.pressed.connect(_on_login_pressed)
	box.add_child(button)

	_login_status = Label.new()
	box.add_child(_login_status)


func _add_field(parent: Control, key: String, label_text: String, value: String, secret: bool) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.text = value
	edit.secret = secret
	edit.text_submitted.connect(func(_t): _on_login_pressed())
	parent.add_child(edit)
	_fields[key] = edit


func _show_login(message: String) -> void:
	_login_panel.visible = true
	_hud_panel.visible = false
	_camera.input_captured = true
	_login_status.text = message


func _on_login_pressed() -> void:
	IonClient.server_url = _fields.server.text.strip_edges()
	_login_status.text = "Connecting..."
	var result := await IonClient.login(
		_fields.ship.text.strip_edges(),
		_fields.component.text.strip_edges(),
		_fields.password.text,
	)
	if result.ok:
		_login_panel.visible = false
		_hud_panel.visible = true
		_camera.input_captured = false
	else:
		_login_status.text = result.error


func _on_disconnected() -> void:
	_show_login("Disconnected from the server.")


func _on_state_updated(entity: Dictionary) -> void:
	_ship.quaternion = ShipState.orientation(entity)


func _hud_text(entity: Dictionary) -> String:
	var pos := ShipState.floating_position(entity)
	var vel := ShipState.velocity(entity)
	var ang := ShipState.angular_velocity(entity)
	var lines := PackedStringArray()
	if not pos.is_empty():
		var s: Dictionary = pos.sector
		var p: Dictionary = pos.shift
		lines.append("SECTOR %d / %d / %d" % [s.x, s.y, s.z])
		lines.append("POS %.3f / %.3f / %.3f" % [p.x, p.y, p.z])
	lines.append("VEL %.3f / %.3f / %.3f m/s" % [vel.x, vel.y, vel.z])
	lines.append("ANG %.3f / %.3f / %.3f deg/s" % [rad_to_deg(ang.x), rad_to_deg(ang.y), rad_to_deg(ang.z)])
	lines.append("FPS %d" % Engine.get_frames_per_second())
	return "\n".join(lines)
