## GTP client for KataGo. Phase 1 talks to a local process via OS.execute_with_pipe;
## the public methods are the surface a future in-process GDExtension should match.
class_name KatagoEngine
extends RefCounted

const DEFAULT_DIR := "res://tools/katago"
const DEFAULT_MODEL := "kata1-b18c384nbt.bin.gz"
const DEFAULT_CFG := "smoke.cfg"

var _stdio: FileAccess = null
var _stderr: FileAccess = null
var _pid: int = -1
var _alive: bool = false
var _buf: String = ""


func is_running() -> bool:
	return _alive and _stdio != null and _stdio.is_open()


## Start KataGo GTP. `backend` is "eigen" (default, reliable) or "opencl".
func start(backend: String = "eigen", max_visits: int = 16) -> void:
	stop()
	var dir := ProjectSettings.globalize_path(DEFAULT_DIR)
	var backend_dir := "opencl" if backend == "opencl" else "eigen"
	var exe := dir.path_join(backend_dir).path_join("katago.exe")
	var model := dir.path_join(DEFAULT_MODEL)
	var cfg := dir.path_join(DEFAULT_CFG)
	if not FileAccess.file_exists(exe):
		push_error("KatagoEngine: missing %s — run tools/ensure_katago.ps1" % exe)
		assert(false, "KatagoEngine: engine not fetched")
		return
	if not FileAccess.file_exists(model):
		push_error("KatagoEngine: missing %s — run tools/ensure_katago.ps1" % model)
		assert(false, "KatagoEngine: model not fetched")
		return
	if not FileAccess.file_exists(cfg):
		push_error("KatagoEngine: missing %s" % cfg)
		assert(false, "KatagoEngine: config missing")
		return

	var args := PackedStringArray(
		["gtp", "-model", model, "-config", cfg, "-override-config", "maxVisits=%d" % max_visits]
	)
	## Blocking pipes: callers should drive GTP from a worker thread or accept stalls.
	var info: Dictionary = OS.execute_with_pipe(exe, args, true)
	if info.is_empty():
		push_error("KatagoEngine: failed to spawn %s" % exe)
		assert(false, "KatagoEngine: spawn failed")
		return
	_stdio = info["stdio"] as FileAccess
	_stderr = info.get("stderr") as FileAccess
	_pid = int(info.get("pid", -1))
	_alive = _stdio != null and _stdio.is_open()
	if not _alive:
		push_error("KatagoEngine: pipe not open after spawn")
		assert(false, "KatagoEngine: pipe closed")
		return
	## Discard banner until GTP is ready: first real handshake is `protocol_version`.
	var proto := command("protocol_version")
	if not proto.begins_with("="):
		push_error("KatagoEngine: bad protocol_version reply: %s" % proto)
		assert(false, "KatagoEngine: GTP handshake failed")
		stop()
		return


func stop() -> void:
	if _alive and _stdio != null and _stdio.is_open():
		_write_raw("quit\n")
	if _pid >= 0:
		OS.kill(_pid)
	_stdio = null
	_stderr = null
	_pid = -1
	_alive = false
	_buf = ""


func command(cmd: String) -> String:
	if not is_running():
		push_error("KatagoEngine.command: not running (%s)" % cmd)
		assert(false, "KatagoEngine: not running")
		return ""
	_write_raw(cmd.strip_edges() + "\n")
	return _read_response()


func clear_board() -> void:
	_expect_ok(command("clear_board"))


func set_boardsize(n: int) -> void:
	_expect_ok(command("boardsize %d" % n))


## GTP color: "b" / "w". Returns vertex like "D4" or "pass".
func genmove(color: String) -> String:
	var c := color.strip_edges().to_lower()
	if c != "b" and c != "w" and c != "black" and c != "white":
		push_error("KatagoEngine.genmove: bad color '%s'" % color)
		assert(false, "KatagoEngine: bad color")
		return ""
	var reply := command("genmove %s" % c)
	if not reply.begins_with("="):
		push_error("KatagoEngine.genmove failed: %s" % reply)
		assert(false, "KatagoEngine: genmove failed")
		return ""
	var body := reply.substr(1).strip_edges()
	## Success payload may be multi-line; first line is the move.
	var line := body.split("\n")[0].strip_edges()
	return line


func play(color: String, vertex: String) -> void:
	_expect_ok(command("play %s %s" % [color, vertex]))


func engine_name() -> String:
	var reply := command("name")
	if reply.begins_with("="):
		return reply.substr(1).strip_edges().split("\n")[0]
	return ""


func _expect_ok(reply: String) -> void:
	if not reply.begins_with("="):
		push_error("KatagoEngine: GTP error: %s" % reply)
		assert(false, "KatagoEngine: GTP error")


func _write_raw(text: String) -> void:
	_stdio.store_buffer(text.to_utf8_buffer())
	_stdio.flush()


## GTP responses end with a blank line after =... or ?...
func _read_response() -> String:
	var lines: PackedStringArray = PackedStringArray()
	while true:
		var line := _read_line()
		if line == "":
			break
		lines.append(line)
	return "\n".join(lines)


func _read_line() -> String:
	while true:
		var nl := _buf.find("\n")
		if nl >= 0:
			var line := _buf.substr(0, nl)
			_buf = _buf.substr(nl + 1)
			## Normalize CRLF leftovers.
			if line.ends_with("\r"):
				line = line.substr(0, line.length() - 1)
			return line
		if _stdio == null or not _stdio.is_open():
			push_error("KatagoEngine: stdout closed while reading")
			assert(false, "KatagoEngine: stdout closed")
			return ""
		var chunk: PackedByteArray = _stdio.get_buffer(4096)
		if chunk.is_empty():
			## Blocking mode should wait; empty can mean EOF.
			if _stdio.get_error() != OK:
				push_error("KatagoEngine: stdout error %d" % _stdio.get_error())
				assert(false, "KatagoEngine: stdout error")
				return ""
			OS.delay_msec(5)
			continue
		_buf += chunk.get_string_from_utf8()
	return ""
