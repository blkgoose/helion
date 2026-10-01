extends Node
## Client for the ION CDN (http://aletflix.duckdns.org:8080/openapi.json): GET /model?id=&type= -> GLB.
## type is one of ship | planet | star | asteroid; id must match ^[A-Za-z0-9_-]{1,128}$.
##
## Downloads are queued and started closest first (the own ship is at distance 0). Callers poll get_model() every frame, which
## also refreshes the distance; requests nobody polls for a while are dropped.

const BASE_URL := "http://aletflix.duckdns.org:8080"
const TYPES := ["ship", "planet", "star", "asteroid"]
const REQUEST_TIMEOUT_S := 30.0
const RETRY_AFTER_MS := 10000
const MAX_CONCURRENT := 4
const STALE_FRAMES := 60

var _scenes := {}
var _in_flight := {}
var _failed_at := {}
var _wanted := {}


## The parsed glTF scene root for (type, id), or null while it is still being downloaded.
## `distance_m` from the ship orders the download queue.
func get_model(type: String, id: String, distance_m: float = 0.0) -> Node:
	var key := _key(type, id)
	if _scenes.has(key):
		return _scenes[key]
	if _in_flight.has(key) or type not in TYPES or id == "" or id.length() > 128:
		return null
	if _failed_at.has(key) and Time.get_ticks_msec() - _failed_at[key] < RETRY_AFTER_MS:
		return null
	_wanted[key] = {
		"type": type,
		"id": id,
		"priority": distance_m,
		"frame": Engine.get_process_frames(),
	}
	return null


func _process(_delta: float) -> void:
	var frame := Engine.get_process_frames()
	while _in_flight.size() < MAX_CONCURRENT and not _wanted.is_empty():
		var best_key := ""
		var best_priority := INF
		for key in _wanted.keys():
			if frame - _wanted[key].frame > STALE_FRAMES:
				_wanted.erase(key)
			elif _wanted[key].priority < best_priority:
				best_priority = _wanted[key].priority
				best_key = key
		if best_key == "":
			break
		var request: Dictionary = _wanted[best_key]
		_wanted.erase(best_key)
		_download(request.type, request.id, best_key)


func _key(type: String, id: String) -> String:
	return "%s:%s" % [type, id]


func _download(type: String, id: String, key: String) -> void:
	_in_flight[key] = true
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_S
	add_child(http)
	var url := "%s/model?id=%s&type=%s" % [BASE_URL, id.uri_encode(), type]
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		_fail(key)
		return
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		_fail(key)
		return
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	if doc.append_from_buffer(response[3], "", state) != OK:
		_fail(key)
		return
	var scene := doc.generate_scene(state)
	if scene == null:
		_fail(key)
		return
	_in_flight.erase(key)
	_scenes[key] = scene


func _fail(key: String) -> void:
	_in_flight.erase(key)
	_failed_at[key] = Time.get_ticks_msec()
	push_warning("CDN model download failed: %s" % key)
