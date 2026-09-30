class_name OrientationPanel
extends HBoxContainer
## 3D attitude widget (world axes + red cone along the ship's +X) with engine and fuel gauges.

const SIZE_PX := 120

var _cone: Node3D
var _engines: VBoxContainer
var _fuel: VBoxContainer


func _ready() -> void:
	var frame := PanelContainer.new()
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE_PX, SIZE_PX)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	frame.add_child(container)
	add_child(frame)

	var camera := Camera3D.new()
	camera.fov = 45
	viewport.add_child(camera)
	camera.position = Vector3(2, 1.5, 2.5)
	camera.look_at(Vector3.ZERO)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 40, 0)
	viewport.add_child(light)

	for axis in 3:
		var dir := Vector3.ZERO
		dir[axis] = 1.0
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.02
		mesh.bottom_radius = 0.02
		mesh.height = 1.4
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = [Color("ff4444"), Color("44ff44"), Color("4488ff")][axis]
		var bar := MeshInstance3D.new()
		bar.mesh = mesh
		bar.material_override = material
		bar.position = dir * 0.7
		if axis == 0:
			bar.rotation_degrees = Vector3(0, 0, -90)
		elif axis == 2:
			bar.rotation_degrees = Vector3(90, 0, 0)
		viewport.add_child(bar)

	_cone = Node3D.new()
	viewport.add_child(_cone)
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 0.25
	cone_mesh.height = 1.0
	cone_mesh.radial_segments = 6
	var cone_material := StandardMaterial3D.new()
	cone_material.albedo_color = Color("cc3333")
	var cone := MeshInstance3D.new()
	cone.mesh = cone_mesh
	cone.material_override = cone_material
	cone.rotation_degrees = Vector3(0, 0, -90)
	_cone.add_child(cone)

	var gauges := VBoxContainer.new()
	_engines = VBoxContainer.new()
	_fuel = VBoxContainer.new()
	gauges.add_child(_engines)
	gauges.add_child(_fuel)
	add_child(gauges)


func update_state(orientation: Variant, engines: Array, fuels: Array) -> void:
	if orientation != null:
		_cone.quaternion = orientation
	_sync_bars(_engines, engines.map(func(e): return {"text": "%s %d%%" % [e.type, e.activation], "pct": e.activation, "color": UiTheme.ACCENT}))
	_sync_bars(_fuel, fuels.map(func(f): return {"text": "Fuel %d kg" % f.fuel_kg, "pct": f.fuel_kg / ShipRead.FUEL_CAPACITY_KG * 100.0, "color": Color("f5a623")}))


func _sync_bars(parent: VBoxContainer, items: Array) -> void:
	while parent.get_child_count() > items.size():
		var extra := parent.get_child(parent.get_child_count() - 1)
		parent.remove_child(extra)
		extra.queue_free()
	while parent.get_child_count() < items.size():
		var cell := VBoxContainer.new()
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(110, 5)
		bar.color = Color("222222")
		var fill := ColorRect.new()
		fill.size = Vector2(0, 5)
		bar.add_child(fill)
		cell.add_child(label)
		cell.add_child(bar)
		parent.add_child(cell)
	for i in items.size():
		var cell := parent.get_child(i)
		cell.get_child(0).text = items[i].text
		var fill: ColorRect = cell.get_child(1).get_child(0)
		fill.color = items[i].color
		fill.size = Vector2(110.0 * clampf(items[i].pct / 100.0, 0.0, 1.0), 5)
