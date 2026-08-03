## Process-wide refcounted NativeKataGo handle (Human-SL rank ladder).
class_name GoEnginePool
extends RefCounted

const GoRankScript := preload("res://scripts/city/go_rank.gd")

## Fixed visit budget for Human-SL play (pass/resign + light search). Rank sets strength.
const HUMAN_VISITS := 40

static var _refs: int = 0
static var _eng: Object = null
static var _rank: String = "5k"


static func acquire(rank: String) -> Object:
	if not ClassDB.class_exists(&"NativeKataGo"):
		push_error("GoEnginePool: NativeKataGo missing — build tools/build_city_katago.ps1")
		return null
	var token := normalize_rank(rank)
	if _eng != null and is_instance_valid(_eng) and bool(_eng.call("is_loaded")):
		_refs += 1
		if token != _rank:
			_eng.call("set_rank", token)
			_rank = token
		return _eng
	_eng = ClassDB.instantiate(&"NativeKataGo")
	if _eng == null:
		push_error("GoEnginePool: instantiate failed")
		return null
	if not _reload(token):
		_eng = null
		return null
	_refs = 1
	return _eng


static func release() -> void:
	_refs = maxi(_refs - 1, 0)
	if _refs == 0 and _eng != null and is_instance_valid(_eng):
		_eng.call("unload")
		_eng = null
		_rank = "5k"


static func normalize_rank(rank: String) -> String:
	var t := rank.strip_edges().to_lower()
	if t.begins_with("rank_"):
		t = t.substr(5)
	for r in GoRankScript.RANKS:
		if String(r) == t:
			return t
	push_warning("GoEnginePool: unknown rank '%s', using 5k" % rank)
	return "5k"


static func _reload(rank: String) -> bool:
	var model := ProjectSettings.globalize_path("res://tools/katago/b18c384nbt-humanv0.bin.gz")
	var cfg := ProjectSettings.globalize_path("res://addons/city_katago/human_rank.cfg")
	if not FileAccess.file_exists(model):
		push_error("GoEnginePool: missing human model %s — run tools/ensure_katago.ps1" % model)
		return false
	if not bool(_eng.call("load", model, cfg, HUMAN_VISITS)):
		push_error("GoEnginePool: NativeKataGo.load failed")
		return false
	_eng.call("set_rank", rank)
	_rank = rank
	return true
