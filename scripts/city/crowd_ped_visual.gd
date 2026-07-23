## Near-LOD skinned pedestrian visual (Quaternius Idle/Walk + real MH outfits).
class_name CrowdPedVisual
extends Node3D

const FALLBACK_MALE: Array[String] = [
	"res://assets/humans/male_base.gltf",
	"res://assets/humans/male_base.glb",
]
const FALLBACK_FEMALE: Array[String] = [
	"res://assets/humans/female_base.gltf",
	"res://assets/humans/female_base.glb",
]
const PedOutfitApplierScript := preload("res://scripts/humans/ped_outfit_applier.gd")

var agent_index: int = -1
var _body: Node3D
var _anim: AnimationPlayer
var _mesh: MeshInstance3D
var _female: bool = false
var _ready_visual: bool = false
var _outfit: PedOutfit
var _loaded_path: String = ""


func ensure_body(female: bool, scene_path: String = "") -> void:
	var path := scene_path
	if path == "" or not ResourceLoader.exists(path):
		path = _fallback_path(female)
	if _ready_visual and _female == female and _body != null and _loaded_path == path:
		return
	_clear_body()
	_female = female
	_loaded_path = path
	if path == "" or not ResourceLoader.exists(path):
		_spawn_capsule(female)
		_ready_visual = true
		return
	var packed := load(path)
	if not (packed is PackedScene):
		_spawn_capsule(female)
		_ready_visual = true
		return
	_body = (packed as PackedScene).instantiate() as Node3D
	_body.name = "Body"
	_body.rotation.y = PI
	add_child(_body)
	_disable_mesh_shadows(_body)
	var skel := _find_skeleton(_body)
	if skel != null:
		skel.unique_name_in_owner = true
	_mesh = _find_body_mesh(_body)
	_anim = AnimationPlayer.new()
	_anim.name = "AnimationPlayer"
	_body.add_child(_anim)
	QuaterniusLocomotion.attach_to(_anim)
	_ready_visual = true


func bind_agent(index: int, female: bool, body_scale: float, outfit: PedOutfit = null) -> void:
	agent_index = index
	_outfit = outfit
	var path := ""
	if outfit != null:
		path = outfit.scene_path
	ensure_body(female, path)
	_apply_outfit()
	scale = Vector3(body_scale, body_scale, body_scale)
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT


func unbind_agent() -> void:
	agent_index = -1
	_outfit = null
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


func sync_from_agent(agent: PedAgent) -> void:
	global_position = agent.position
	rotation.y = agent.yaw
	if agent.outfit != null and agent.outfit != _outfit:
		_outfit = agent.outfit
		ensure_body(agent.female, agent.outfit.scene_path)
		_apply_outfit()
	if _anim == null:
		return
	if agent.is_walking():
		QuaterniusLocomotion.play_walk(_anim, agent.walk_speed)
	else:
		QuaterniusLocomotion.play_idle(_anim)


func _apply_outfit() -> void:
	if _outfit == null or _body == null:
		return
	PedOutfitApplierScript.apply_to_body_root(_body, _outfit, _female)


func _fallback_path(female: bool) -> String:
	var paths := FALLBACK_FEMALE if female else FALLBACK_MALE
	for candidate in paths:
		if ResourceLoader.exists(candidate):
			return candidate
	return ""


func _clear_body() -> void:
	_anim = null
	_mesh = null
	_loaded_path = ""
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
	_body = null
	_ready_visual = false


func _spawn_capsule(female: bool) -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.18 if female else 0.2
	capsule.height = 1.65 if female else 1.75
	mi.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.68, 0.54) if female else Color(0.78, 0.58, 0.44)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = capsule.height * 0.5
	_body.add_child(mi)
	_mesh = mi


func _find_body_mesh(root: Node) -> MeshInstance3D:
	## Prefer a mesh whose name looks like the body/skin, else first mesh.
	var first: MeshInstance3D = null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if first == null:
				first = mi
			var nm := String(mi.name).to_lower()
			if nm.contains("body") or nm.contains("skin") or nm.contains("base"):
				return mi
		for c in n.get_children():
			stack.append(c)
	return first


func _disable_mesh_shadows(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for c in n.get_children():
			stack.append(c)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
