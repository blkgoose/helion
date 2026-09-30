class_name RadarHub
extends Node
## All Radar modules merged into one contact list. A smaller-radius (near, fast) radar wins for
## everything inside its range; a larger-radius (deep) radar only supplies contacts the near ones
## can't see, i.e. beyond their radius.

var _pollers := {}


func sync(entity: Dictionary, modules: Array) -> void:
	var wanted := {}
	for m in modules:
		if m.type in ModuleTabs.RADAR_TYPES:
			wanted[m.module_id] = true
	for id in wanted:
		if not _pollers.has(id):
			var poller := RadarPoller.new()
			poller.module_id = id
			add_child(poller)
			_pollers[id] = poller
	for id in _pollers.keys():
		if not wanted.has(id):
			_pollers[id].queue_free()
			_pollers.erase(id)
	for poller in _pollers.values():
		poller.tick(entity)


func _sorted_pollers() -> Array:
	var list := _pollers.values()
	list.sort_custom(func(a, b): return a.radius_m < b.radius_m)
	return list


## Merged, dead-reckoned contacts. `ship_position` (floating) is used to decide which radar owns a contact.
func get_predicted(now_ms: float) -> Array:
	var ship_position := ShipRead.floating_position(ShipState.latest)
	var out := []
	var taken := {}
	var covered: Array = []
	for poller in _sorted_pollers():
		var entries: Array = poller.get_predicted(now_ms)
		for entry in entries:
			if taken.has(entry[0]):
				continue
			if not ship_position.is_empty() and not covered.is_empty():
				var distance := IonMath.length(IonMath.relative(ship_position, entry[1]))
				var inside_fresher := false
				for c in covered:
					if distance <= c:
						inside_fresher = true
						break
				if inside_fresher:
					continue
			taken[entry[0]] = true
			out.append(entry)
		if poller.latest_at_ms > 0.0:
			covered.append(poller.radius_m)
	return out
