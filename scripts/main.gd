class_name Main
extends Node
## Tactical client: 3D flight scene + HUD/panels/palette, autopilot-driven flight (ported from ionizer).

const ARRIVAL_RADIUS_M := 200.0
const DEFAULT_CRUISE_SPEED_MPS := 1000.0
# Labels scale badly with contact count in a dense field; only the nearest get one.
const DIRECTION_MARKER_CONTACT_LIMIT := 10
const RADAR_PANEL_LIMIT := 10

var _scene: FlightScene
var _hud: Hud
var _minimap: Minimap
var _system_panel: ListPanel
var _radar_panel: ListPanel
var _orientation_panel: OrientationPanel
var _markers: DirectionMarkers
var _palette: CommandPalette
var _modal: ModulesModal
var _login: LoginPanel
var _ui_root: Control
var _radar := RadarPoller.new()
var _system_map := SystemMapPoller.new()
var _autopilot := Autopilot.new()
var _modules: Array = []
var _active_goal := {}
var _pending_resume: Variant = null
var _game_started := false
var _hovered := {}
var _snap := {}


func _ready() -> void:
	Models.preload_all()
	_scene = FlightScene.new()
	add_child(_scene)
	add_child(_radar)
	add_child(_system_map)

	var layer := CanvasLayer.new()
	add_child(layer)
	_ui_root = Control.new()
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = UiTheme.make()
	layer.add_child(_ui_root)
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_markers = DirectionMarkers.new()
	_ui_root.add_child(_markers)
	_hud = Hud.new()
	_ui_root.add_child(_hud)
	_hud.logout_pressed.connect(_logout)
	_hud.full_stop_pressed.connect(func(): _engage({"kind": "stop"}))
	_hud.disengage_pressed.connect(_disengage)

	var bottom := HBoxContainer.new()
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("separation", 12)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(bottom)
	var left_column := VBoxContainer.new()
	left_column.size_flags_vertical = Control.SIZE_SHRINK_END
	left_column.add_theme_constant_override("separation", 12)
	_orientation_panel = OrientationPanel.new()
	left_column.add_child(_orientation_panel)
	_minimap = Minimap.new()
	left_column.add_child(_minimap)
	bottom.add_child(left_column)
	_system_panel = ListPanel.new("Sistema stellare")
	_system_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	_system_panel.row_selected.connect(_on_system_row)
	bottom.add_child(_system_panel)
	_radar_panel = ListPanel.new("Contatti radar")
	_radar_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	_radar_panel.row_selected.connect(func(key): _show_ship_menu(key))
	bottom.add_child(_radar_panel)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)

	_modal = ModulesModal.new()
	_ui_root.add_child(_modal)
	_palette = CommandPalette.new(_build_palette_root)
	_ui_root.add_child(_palette)

	_login = LoginPanel.new()
	_ui_root.add_child(_login)
	_login.logged_in.connect(_start_game)

	_autopilot.failed.connect(func(reason): _hud.notify("Autopilota disattivato: %s" % reason))
	ShipState.updated.connect(_on_state)
	IonClient.disconnected.connect(_on_disconnected)

	_set_game_ui_visible(false)
	if IonClient.is_logged_in():
		_start_game()


func _set_game_ui_visible(value: bool) -> void:
	for node in [_hud, _minimap, _orientation_panel, _markers]:
		node.visible = value
	_scene.camera.input_captured = not value
	_login.visible = not value


func _start_game() -> void:
	_game_started = true
	_pending_resume = Persist.get_value("goal")
	_set_game_ui_visible(true)


func _logout() -> void:
	if _autopilot.is_engaged():
		_autopilot.disengage()
	Persist.set_value("goal", null)
	IonClient.logout()
	get_tree().reload_current_scene()


func _on_disconnected() -> void:
	var banner := ColorRect.new()
	banner.color = Color(0, 0, 0, 0.75)
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = "Sessione scaduta — riconnessione…"
	label.add_theme_color_override("font_color", Color("ee8888"))
	label.add_theme_font_size_override("font_size", 20)
	banner.add_child(label)
	_ui_root.add_child(banner)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	await get_tree().create_timer(1.5).timeout
	get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	_scene.camera.input_captured = not _game_started or InputState.captured
	_render_frame()


# ---- input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _game_started or InputState.captured:
		return
	if event is InputEventMouseMotion:
		_hovered = _scene.pick((event as InputEventMouseMotion).position)
		_scene.show_hover(_hovered)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if not _hovered.is_empty() else Input.CURSOR_ARROW)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			var hit := _scene.pick(button.position)
			if hit.is_empty():
				_palette.close()
			elif hit.kind == "ship":
				_show_ship_menu(hit.entity_id)
			else:
				_show_body_menu(hit.entry_index, hit.body_kind)


# ---- state ---------------------------------------------------------------

func _on_state(entity: Dictionary) -> void:
	if not _game_started:
		return
	_hud.update_state(entity)
	var orientation = ShipRead.orientation(entity)
	var ship_position := ShipRead.floating_position(entity)
	var modules := ShipRead.modules(entity)
	_modules = modules
	_modal.set_modules(modules)
	_autopilot.set_modules(modules, entity)

	_scene.camera.set_ship_position(Vector3.ZERO)
	var aim: Variant = null
	if not _active_goal.is_empty() and _active_goal.kind != "stop" and not ship_position.is_empty():
		var target := _resolve_goal(_active_goal).get_target.call(IonMath.now_ms()) as Dictionary
		if not target.is_empty():
			aim = IonMath.to_vec3(IonMath.relative(ship_position, target))
	_scene.camera.set_aim_point(aim)
	var size = ShipRead.size(entity)
	if size != null:
		_scene.set_own_ship_size(size)

	_try_resume()
	_autopilot.tick(entity)
	var goal_distance: Variant = null
	if _autopilot.is_engaged() and not ship_position.is_empty() and not _active_goal.is_empty() and _active_goal.kind != "stop":
		var goal_target := _resolve_goal(_active_goal).get_target.call(IonMath.now_ms()) as Dictionary
		if not goal_target.is_empty():
			goal_distance = IonMath.length(IonMath.relative(ship_position, goal_target))
	_hud.update_autopilot(_autopilot.is_engaged(), _autopilot.label, _autopilot.phase, goal_distance)
	if not _autopilot.is_engaged() and not _active_goal.is_empty():
		Persist.set_value("goal", null)
		_active_goal = {}

	_orientation_panel.update_state(orientation, ShipRead.engine_activations(entity, modules), ShipRead.fuel_levels(entity, modules))

	var system_module := modules.filter(func(m): return m.type in ModuleTabs.SYSTEM_MAP_TYPES)
	_system_map.set_module_id(system_module[0].module_id if not system_module.is_empty() else "")
	var radar_module := modules.filter(func(m): return m.type in ModuleTabs.RADAR_TYPES)
	_radar.set_module_id(radar_module[0].module_id if not radar_module.is_empty() else "")

	if ship_position.is_empty():
		return
	var velocity = ShipRead.velocity(entity)
	var angular = ShipRead.angular_velocity(entity)
	var now := IonMath.now_ms()
	var vel_now: Vector3 = velocity if velocity != null else Vector3.ZERO
	var ang_now: Vector3 = angular if angular != null else Vector3.ZERO
	var accel := Vector3.ZERO
	var ang_accel := Vector3.ZERO
	if not _snap.is_empty():
		var sdt := (now - float(_snap.at_ms)) / 1000.0
		if sdt > 0.01:
			accel = _snap.accel.lerp((vel_now - _snap.velocity) / sdt, 0.5)
			if orientation != null and _snap.orientation != null:
				var dq: Quaternion = ((_snap.orientation as Quaternion).inverse() * (orientation as Quaternion)).normalized()
				if dq.w < 0.0:
					dq = Quaternion(-dq.x, -dq.y, -dq.z, -dq.w)
				ang_now = (dq.get_axis() * dq.get_angle() / sdt) if dq.get_angle() > 1e-6 else Vector3.ZERO
			ang_accel = _snap.ang_accel.lerp((ang_now - _snap.angular) / sdt, 0.5)
		else:
			accel = _snap.accel
			ang_accel = _snap.ang_accel
	_snap = {
		"accel": accel,
		"ang_accel": ang_accel,
		"position": ship_position,
		"velocity": velocity if velocity != null else Vector3.ZERO,
		"angular": ang_now,
		"orientation": orientation,
		"at_ms": now,
	}
	var entries := _system_map.latest
	var contacts := _radar.get_predicted(IonMath.now_ms())
	_update_panels(ship_position, entries, contacts)
	_render_frame()


## Runs every frame: dead-reckons the ship between 15 Hz polls so motion and rotation look continuous.
func _render_frame() -> void:
	if _snap.is_empty():
		return
	var dt := clampf((IonMath.now_ms() - float(_snap.at_ms)) / 1000.0, 0.0, 0.25)
	var base: Dictionary = _snap.position
	var v: Vector3 = _snap.velocity
	var d: Vector3 = v * dt + 0.5 * (_snap.accel as Vector3) * dt * dt
	var ship_position := {
		"sector": base.sector,
		"shift": {"x": base.shift.x + d.x, "y": base.shift.y + d.y, "z": base.shift.z + d.z},
	}
	var orientation: Variant = _snap.orientation
	if orientation != null:
		var w: Vector3 = (_snap.angular as Vector3) + 0.5 * (_snap.ang_accel as Vector3) * dt
		if w.dot(_snap.angular as Vector3) < 0.0:
			w = Vector3.ZERO
		if w.length() > 1e-6:
			orientation = ((orientation as Quaternion) * Quaternion(w.normalized(), w.length() * dt)).normalized()
		_scene.set_own_ship_orientation(orientation)

	_scene.advance_dust(ship_position)
	var entries := _system_map.latest
	var contacts := _radar.get_predicted(IonMath.now_ms())
	_scene.starfield.update(ship_position, entries)
	_minimap.update_data(ship_position, orientation, entries, contacts)

	var contact_data: Array = []
	for contact in contacts:
		var rel := IonMath.relative(ship_position, contact[1])
		contact_data.append({
			"entity_id": contact[0],
			"size": float(contact[2]),
			"kind": contact[3],
			"position": IonMath.to_vec3(rel),
			"distance_m": IonMath.length(rel),
		})
	_scene.sync_contacts(contact_data)

	var nearest := contact_data.duplicate()
	nearest.sort_custom(func(a, b): return a.distance_m < b.distance_m)
	var marker_entries: Array = []
	for p in _scene.starfield.pickables:
		marker_entries.append({"icon": "☉" if p.kind == "star" else "●", "world_position": p.position, "distance_m": p.distance_m})
	for c in nearest.slice(0, DIRECTION_MARKER_CONTACT_LIMIT):
		marker_entries.append({"icon": IonMath.contact_icon(c.kind), "world_position": c.position, "distance_m": c.distance_m})
	var own_size = ShipRead.size(ShipState.latest)
	if _scene.camera.position.length() > maxf(120.0, (own_size if own_size != null else 30.0) * 4.0):
		var sector: Dictionary = ship_position.sector
		marker_entries.append({"icon": "▲", "world_position": Vector3.ZERO, "distance_m": 0.0, "text": "▲ Tu — settore %d / %d / %d" % [sector.x, sector.y, sector.z]})
	_markers.update_markers(_scene.camera, marker_entries)


func _update_panels(ship_position: Dictionary, entries: Array, contacts: Array) -> void:
	var bodies: Array = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		if e.kind != "star" and e.kind != "planet":
			continue
		bodies.append({"index": i, "entry": e, "distance": IonMath.length(IonMath.relative(ship_position, e.position))})
	bodies.sort_custom(func(a, b):
		var a_star: bool = a.entry.kind == "star"
		var b_star: bool = b.entry.kind == "star"
		if a_star != b_star:
			return a_star
		return a.distance < b.distance)
	var system_rows: Array = []
	for b in bodies:
		var is_star: bool = b.entry.kind == "star"
		system_rows.append({
			"key": "%d:%s" % [b.index, b.entry.kind],
			"text": "%s %s — %s, ⌀ %d km, %s" % ["☉" if is_star else "●", "stella" if is_star else "pianeta", IonMath.format_distance(b.distance), roundi(float(b.entry.diameter_m) / 1000.0), IonMath.format_mass(float(b.entry.mass_kg))],
		})
	_system_panel.set_rows(system_rows)

	var rows: Array = []
	for c in contacts:
		rows.append({"id": c[0], "size": float(c[2]), "kind": c[3], "distance": IonMath.length(IonMath.relative(ship_position, c[1]))})
	rows.sort_custom(func(a, b): return a.distance < b.distance)
	var radar_rows: Array = []
	for r in rows.slice(0, RADAR_PANEL_LIMIT):
		radar_rows.append({"key": r.id, "text": "%s %s — %.2f km, ⌀ %d m" % [IonMath.contact_icon(r.kind), str(r.id).substr(0, 8), r.distance / 1000.0, roundi(r.size)]})
	_radar_panel.set_rows(radar_rows)


func _on_system_row(key: String) -> void:
	var parts := key.split(":")
	_show_body_menu(int(parts[0]), parts[1])


# ---- autopilot goals -------------------------------------------------------

## Builds the live target closure for a persisted goal; {get_target, arrival_radius, target_radius_m, label}.
func _resolve_goal(goal: Dictionary) -> Dictionary:
	match goal.kind:
		"shipApproach":
			var id: String = goal.entityId
			return {
				"get_target": func(now_ms: float) -> Dictionary:
					for c in _radar.get_predicted(now_ms):
						if c[0] == id:
							return c[1]
					return {},
				"arrival_radius": float(goal.arrivalRadius),
				"target_radius_m": float(goal.targetRadiusM),
				"label": goal.label,
			}
		"bodyApproach":
			var index := int(goal.entryIndex)
			return {
				"get_target": func(_now_ms: float) -> Dictionary:
					var entries := _system_map.latest
					return entries[index].position if index < entries.size() else {},
				"arrival_radius": float(goal.arrivalRadius),
				"target_radius_m": float(goal.targetRadiusM),
				"label": goal.label,
			}
		_:
			return {
				"get_target": Autopilot.orbit_target_position(goal.center, float(goal.radiusM), float(goal.startedAtMs)),
				"arrival_radius": float(goal.arrivalRadius),
				"target_radius_m": 0.0,
				"label": goal.label,
			}


func _engage(goal: Dictionary) -> void:
	_autopilot.set_modules(_modules, ShipState.latest)
	if goal.kind == "stop":
		_autopilot.engage_stop()
	else:
		var r := _resolve_goal(goal)
		var is_orbit: bool = goal.kind == "orbit"
		_autopilot.engage(
			r.get_target, r.arrival_radius, r.target_radius_m, r.label,
			not is_orbit and goal.get("pointOnly", false),
			DEFAULT_CRUISE_SPEED_MPS if is_orbit else float(goal.get("maxCruiseSpeedMps", DEFAULT_CRUISE_SPEED_MPS)),
		)
	Persist.set_value("goal", goal)
	_active_goal = goal
	_scene.camera.resume_auto_orient()


func _disengage() -> void:
	_autopilot.disengage()
	Persist.set_value("goal", null)
	_active_goal = {}


## Resumed once the target's poller has data, so the autopilot doesn't read "target lost" on the first tick.
func _try_resume() -> void:
	if _pending_resume == null:
		return
	var goal: Dictionary = _pending_resume
	if goal.kind == "stop" or not (_resolve_goal(goal).get_target.call(IonMath.now_ms()) as Dictionary).is_empty():
		_pending_resume = null
		_engage(goal)
		_autopilot.resume_phase(Persist.get_value("phase"))


static func _parse_cruise_speed(value: String) -> float:
	var text := IonMath.expand_numeric_suffix(value)
	var parsed := float(text) if text.is_valid_float() else 0.0
	return parsed if parsed > 0.0 else DEFAULT_CRUISE_SPEED_MPS


# ---- menus -------------------------------------------------------------------

func _distance_label(position: Dictionary) -> String:
	var ship_position := ShipRead.floating_position(ShipState.latest)
	if ship_position.is_empty():
		return ""
	return " — " + IonMath.format_distance(IonMath.length(IonMath.relative(ship_position, position)))


func _show_ship_menu(entity_id: String) -> void:
	var contact: Variant = null
	for c in _radar.latest:
		if c[0] == entity_id:
			contact = c
	var radius := float(contact[2]) / 2.0 if contact != null else 0.0
	var short := entity_id.substr(0, 8)
	var orbit_radius := maxf(Autopilot.safe_orbit_radius_m(radius, 0.0, _autopilot.get_measured_accel()), ARRIVAL_RADIUS_M)
	var turret := _modules.filter(func(m): return m.type == "Turret")
	var items: Array = [
		{"label": "Orbit", "node": {"kind": "run", "run": func():
			if contact == null:
				return
			_engage({"kind": "orbit", "center": contact[1], "radiusM": orbit_radius, "arrivalRadius": ARRIVAL_RADIUS_M, "startedAtMs": IonMath.now_ms(), "label": "Orbit " + short})}},
		{"label": "Approach", "node": {"kind": "edit", "value": str(int(DEFAULT_CRUISE_SPEED_MPS)), "commit": func(value: String):
			_engage({"kind": "shipApproach", "entityId": entity_id, "arrivalRadius": ARRIVAL_RADIUS_M, "targetRadiusM": radius, "label": "Approach " + short, "maxCruiseSpeedMps": _parse_cruise_speed(value)})}},
		{"label": "Point", "node": {"kind": "run", "run": func():
			_engage({"kind": "shipApproach", "entityId": entity_id, "arrivalRadius": ARRIVAL_RADIUS_M, "targetRadiusM": radius, "label": "Point " + short, "pointOnly": true})}},
		{"label": "Target", "node": {"kind": "run", "run": func():
			if not turret.is_empty():
				IonClient.set_variable(turret[0].module_id, "target", entity_id)}},
	]
	_palette.open_list("Nave %s%s" % [short, _distance_label(contact[1]) if contact != null else ""], items)


func _show_body_menu(entry_index: int, kind: String) -> void:
	var entries := _system_map.latest
	if entry_index >= entries.size():
		return
	var entry: Dictionary = entries[entry_index]
	var position: Dictionary = entry.position
	var radius := float(entry.diameter_m) / 2.0
	var orbit_radius := maxf(Autopilot.safe_orbit_radius_m(radius, float(entry.mass_kg), _autopilot.get_measured_accel()), ARRIVAL_RADIUS_M)
	var items: Array = [
		{"label": "Orbit", "node": {"kind": "run", "run": func():
			_engage({"kind": "orbit", "center": position, "radiusM": orbit_radius, "arrivalRadius": ARRIVAL_RADIUS_M, "startedAtMs": IonMath.now_ms(), "label": "Orbit " + kind})}},
		{"label": "Approach", "node": {"kind": "edit", "value": str(int(DEFAULT_CRUISE_SPEED_MPS)), "commit": func(value: String):
			_engage({"kind": "bodyApproach", "entryIndex": entry_index, "arrivalRadius": ARRIVAL_RADIUS_M, "targetRadiusM": radius, "label": "Approach " + kind, "maxCruiseSpeedMps": _parse_cruise_speed(value)})}},
		{"label": "Point", "node": {"kind": "run", "run": func():
			_engage({"kind": "bodyApproach", "entryIndex": entry_index, "arrivalRadius": ARRIVAL_RADIUS_M, "targetRadiusM": radius, "label": "Point " + kind, "pointOnly": true})}},
	]
	_palette.open_list("%s%s" % [kind, _distance_label(position)], items)


# ---- command palette tree ------------------------------------------------------

func _build_navigation_items() -> Array:
	var ship_position := ShipRead.floating_position(ShipState.latest)
	if ship_position.is_empty():
		return []
	var out: Array = []
	var entries := _system_map.latest
	for i in entries.size():
		var e: Dictionary = entries[i]
		if e.kind != "star" and e.kind != "planet":
			continue
		var d := IonMath.length(IonMath.relative(ship_position, e.position))
		var kind: String = e.kind
		out.append({"d": d, "label": "%s %s — %s" % ["☉" if kind == "star" else "●", "stella" if kind == "star" else "pianeta", IonMath.format_distance(d)],
			"open": func(): _show_body_menu(i, kind)})
	for c in _radar.get_predicted(IonMath.now_ms()):
		var d := IonMath.length(IonMath.relative(ship_position, c[1]))
		var id: String = c[0]
		out.append({"d": d, "label": "%s %s — %s" % [IonMath.contact_icon(c[3]), id.substr(0, 8), IonMath.format_distance(d)],
			"open": func(): _show_ship_menu(id)})
	out.sort_custom(func(a, b): return a.d < b.d)
	return out.map(func(o): return {"label": o.label, "node": {"kind": "run", "run": o.open}})


func _module_function_items(module_id: String) -> Array:
	var result := await IonClient.man(module_id)
	if not result.ok:
		return [{"label": result.error, "node": {"kind": "info"}}]
	var manifest: Dictionary = result.data
	var items: Array = []
	for v in manifest.get("variables", []):
		var name: String = v.name
		var shown := IonMath.format_value(v.get("value"))
		if not v.get("mutable", false):
			items.append({"label": "%s: %s" % [name, shown], "node": {"kind": "info"}})
		elif v.get("type") == "component_ref":
			var wanted = (v.get("constraints") if v.get("constraints") is Dictionary else {}).get("component_type")
			items.append({"label": "%s — %s" % [name, shown], "node": {"kind": "picker", "load": func():
				return _modules.filter(func(m): return m.type == wanted).map(func(m): return {
					"label": "%s %s" % [m.type, m.module_id.substr(0, 8)],
					"node": {"kind": "run", "run": func(): IonClient.set_variable(module_id, name, m.module_id)}})}})
		else:
			items.append({"label": "%s — %s" % [name, shown], "node": {"kind": "edit", "value": shown, "commit": func(value: String):
				IonClient.set_variable(module_id, name, IonMath.expand_numeric_suffix(value))}})
	for a in manifest.get("actions", []):
		var action_name: String = a.name
		var params: Array = a.get("params", [])
		if params.is_empty():
			items.append({"label": action_name, "node": {"kind": "run", "run": func(): IonClient.action(module_id, action_name)}})
		else:
			items.append({"label": "%s (%s)" % [action_name, ", ".join(params.map(func(p): return p.name))], "node": {"kind": "edit", "value": "", "commit": func(value: String):
				var parts := PackedStringArray()
				for token in value.strip_edges().split(" ", false):
					parts.append(IonMath.expand_numeric_suffix(token))
				IonClient.action(module_id, action_name, parts)}})
	return items


func _module_group_item(label: String, modules: Array, extra: Array) -> Dictionary:
	return {"label": label, "node": {"kind": "list", "load": func():
		if modules.size() == 1 and extra.is_empty():
			return await _module_function_items(modules[0].module_id)
		var items := extra.duplicate()
		for m in modules:
			var id: String = m.module_id
			items.append({"label": "%s %s" % [m.type, id.substr(0, 8)], "node": {"kind": "list", "load": func(): return await _module_function_items(id)}})
		return items}}


func _build_palette_root() -> Array:
	var groups := {}
	for m in _modules:
		var tab := ModuleTabs.tab_for(m.type)
		var key: String = ModuleTabs.LABELS[tab] if tab != "" else m.type
		if not groups.has(key):
			groups[key] = []
		groups[key].append(m)
	var propulsion_label: String = ModuleTabs.LABELS["propulsion"]
	var engaged := _autopilot.is_engaged()
	var extra: Array = [
		{"label": "Ferma autopilota" if engaged else "Nessuna manovra attiva", "node": {"kind": "run", "run": _disengage} if engaged else {"kind": "info"}},
		{"label": "Full stop", "node": {"kind": "run", "run": func(): _engage({"kind": "stop"})}},
	]
	if not groups.has(propulsion_label):
		groups[propulsion_label] = []
	var items: Array = [{"label": "Naviga", "node": {"kind": "list", "load": _build_navigation_items}}]
	for label in groups:
		items.append(_module_group_item(label, groups[label], extra if label == propulsion_label else []))
	return items
