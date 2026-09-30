extends Node
## HTTP client for the ION command endpoint: POST {server}/api/v1 with {token, command}.

signal disconnected

const REQUEST_TIMEOUT_S := 8.0
const DISCONNECT_THRESHOLD := 3

var server_url: String = "http://192.168.1.4:3001/api/v1"
var token: String = ""
var ship_id: String = ""

var _consecutive_failures := 0


func is_logged_in() -> bool:
	return token != ""


func login(id: String, component: String, password: String) -> Dictionary:
	var result := await _send("LOGIN %s %s %s" % [id, component, password], false)
	if result.ok:
		token = result.data
		ship_id = id
		_consecutive_failures = 0
	return result


func logout() -> void:
	token = ""


func get_state() -> Dictionary:
	var result := await _dispatch("GET")
	if result.ok:
		var parsed = JSON.parse_string(result.data)
		if parsed is Dictionary:
			result.data = parsed
		else:
			return _error("GET returned invalid JSON")
	return result


func man(module_id: String) -> Dictionary:
	var result := await _dispatch("MAN %s" % module_id)
	if result.ok:
		var parsed = JSON.parse_string(result.data)
		if parsed is Dictionary:
			result.data = parsed
		else:
			return _error("MAN returned invalid JSON")
	return result


func set_variable(module_id: String, variable: String, value) -> Dictionary:
	var text: String = IonMath.format_number(value) if value is float else str(value)
	return await _dispatch("SET %s %s %s" % [module_id, variable, text])


## For actions whose result is JSON (SystemMap.scan, Radar.scan) rather than "done".
func action_json(module_id: String, action_name: String, params: PackedStringArray = []) -> Dictionary:
	var result := await action(module_id, action_name, params)
	if result.ok:
		var parsed = JSON.parse_string(result.data)
		if parsed == null:
			return _error("%s returned invalid JSON" % action_name)
		result.data = parsed
	return result


func action(module_id: String, action_name: String, params: PackedStringArray = []) -> Dictionary:
	var command := "ACTION %s %s" % [module_id, action_name]
	if not params.is_empty():
		command += " " + " ".join(params)
	return await _dispatch(command)


## Any failure counts (timeouts included), not just an expired token: a dead server is as
## good as a logged-out session from the player's point of view.
func _dispatch(command: String) -> Dictionary:
	var result := await _send(command, true)
	if result.ok:
		_consecutive_failures = 0
	else:
		_consecutive_failures += 1
		if _consecutive_failures >= DISCONNECT_THRESHOLD:
			logout()
			_consecutive_failures = 0
			disconnected.emit()
	return result


func _send(command: String, with_token: bool) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_S
	add_child(http)

	var body := JSON.stringify({"token": token if with_token else null, "command": command})
	var err := http.request(server_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return _error("Network error for command: %s" % command)

	var response: Array = await http.request_completed
	http.queue_free()

	var transport_result: int = response[0]
	var status: int = response[1]
	var raw_body: PackedByteArray = response[3]
	if transport_result == HTTPRequest.RESULT_TIMEOUT:
		return _error("Timeout for command: %s" % command)
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		return _error("Network error for command: %s" % command)
	if status < 200 or status >= 300:
		return _error("HTTP %d for command: %s" % [status, command])

	var text = JSON.parse_string(raw_body.get_string_from_utf8())
	if not text is String:
		return _error("Unexpected response for command: %s" % command)
	if text.begins_with("error: "):
		return _error(text.substr("error: ".length()))
	return {"ok": true, "data": text}


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
