## Thread-safe sink: Godot Logger → main-thread UI queue on ErrorOverlay.
extends Logger

var _overlay: Node
var _mutex := Mutex.new()


func configure(overlay: Node) -> void:
	_overlay = overlay


func _log_message(message: String, error: bool) -> void:
	if not error:
		return
	## stderr print_error path (not push_error).
	_enqueue("ERROR", message.strip_edges(), "", 0)


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	script_backtraces: Array
) -> void:
	## Skip warnings in the blocking popup — still show script/engine errors.
	if error_type == Logger.ERROR_TYPE_WARNING:
		return
	var kind := "ERROR"
	match error_type:
		Logger.ERROR_TYPE_SCRIPT:
			kind = "SCRIPT"
		Logger.ERROR_TYPE_SHADER:
			kind = "SHADER"
		_:
			kind = "ERROR"
	var detail := rationale.strip_edges()
	if detail.is_empty():
		detail = code.strip_edges()
	var loc := file
	if line > 0:
		loc = "%s:%d" % [file, line]
	if not function.is_empty():
		loc = "%s (%s)" % [loc, function]
	## Append a short backtrace tip when present (debug builds).
	if script_backtraces != null and script_backtraces.size() > 0:
		var bt: Variant = script_backtraces[0]
		if bt != null and bt.has_method("format"):
			var formatted: String = str(bt.call("format", 0, 6))
			if not formatted.is_empty():
				detail = "%s\n%s" % [detail, formatted]
	_enqueue(kind, detail, loc, error_type)


func _enqueue(kind: String, detail: String, location: String, error_type: int) -> void:
	if detail.is_empty() and location.is_empty():
		return
	_mutex.lock()
	var overlay := _overlay
	_mutex.unlock()
	if overlay == null or not is_instance_valid(overlay):
		return
	## call_deferred is thread-safe for marshalling onto the main thread.
	overlay.call_deferred("enqueue_error", kind, detail, location, error_type)
