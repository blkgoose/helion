class_name RadarHub
extends Node
## Any number of Radar modules merged into one contact list. A smaller-radius (near, fast) radar wins
## for everything inside its range; larger ones only supply contacts beyond the smaller radars' radius.
## Each merged contact carries a 7th element: scan staleness 0 (fresh) .. 1 (two cooldown periods old).

const STALE_PERIODS := 2.0
const MIN_STALE_S := 2.0

var _pollers := {}
var _sorted: Array = []
var _cache: Array = []
var _cache_frame := -1


func sync(entity: Dictionary, modules: Array) -> void:
	var wanted := {}
	for m in modules:
		if m.type in ModuleTabs.RADAR_TYPES:
			wanted[m.module_id] = true
	var changed := false
	for id in wanted:
		if not _pollers.has(id):
			var poller := RadarPoller.new()
			poller.module_id = id
			add_child(poller)
			_pollers[id] = poller
			changed = true
	for id in _pollers.keys():
		if not wanted.has(id):
			_pollers[id].queue_free()
			_pollers.erase(id)
			changed = true
	# Nearest radars tick first so they win the limited concurrent-scan slots.
	for poller in _pollers.values():
		var r = ShipRead.module_field(entity, poller.module_id, "radius_m")
		if r != null and float(r) != poller.radius_m:
			poller.radius_m = float(r)
			changed = true
	if changed:
		_sorted = _pollers.values()
		_sorted.sort_custom(func(a, b): return a.radius_m < b.radius_m)
	for poller in _sorted:
		poller.tick(entity)


## Merged, dead-reckoned contacts (computed once per frame).
func get_predicted(now_ms: float) -> Array:
	var frame := Engine.get_process_frames()
	if frame == _cache_frame:
		return _cache
	_cache_frame = frame
	var ship_position := ShipRead.floating_position(ShipState.latest)
	var out := []
	var taken := {}
	var covered_radius := 0.0
	for poller in _sorted:
		if poller.latest_at_ms <= 0.0:
			continue
		var period := maxf(RadarPoller.cooldown_for_radius(poller.radius_m) * STALE_PERIODS, MIN_STALE_S)
		var stale := clampf((now_ms - poller.latest_at_ms) / 1000.0 / period, 0.0, 1.0)
		for entry in poller.get_predicted(now_ms):
			if taken.has(entry[0]):
				continue
			if covered_radius > 0.0 and not ship_position.is_empty():
				if IonMath.length(IonMath.relative(ship_position, entry[1])) <= covered_radius:
					continue
			taken[entry[0]] = true
			var merged: Array = (entry as Array).duplicate()
			merged.resize(6)
			merged.append(stale)
			out.append(merged)
		covered_radius = maxf(covered_radius, poller.radius_m)
	_cache = out
	return out
