## Optional anatomy / clothing attachment slot.
## Keep crotch (and later clothes) as a proxy that follows the skeleton —
## never bake incomplete anatomy into materials or morph index assumptions.
class_name AnatomyProxy
extends Node3D

enum SlotKind {
	NONE,
	ANATOMY,
	CLOTHING,
}

@export var slot_kind: SlotKind = SlotKind.ANATOMY
@export var slot_id: StringName = &"crotch"
@export var bone_name: StringName = &"pelvis"
## When true, a MeshInstance3D child named "ProxyMesh" is shown if present.
@export var proxy_visible: bool = false

var _skeleton: Skeleton3D
var _proxy_mesh: MeshInstance3D
var _bone_idx: int = -1


func setup(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_proxy_mesh = get_node_or_null("ProxyMesh") as MeshInstance3D
	if _proxy_mesh != null:
		_proxy_mesh.visible = proxy_visible
	if _skeleton != null:
		_bone_idx = _skeleton.find_bone(String(bone_name))
		if _bone_idx < 0:
			push_warning("AnatomyProxy: bone '%s' not found on skeleton" % bone_name)


func set_proxy_mesh(mesh: Mesh, visible: bool = true) -> void:
	if _proxy_mesh == null:
		_proxy_mesh = MeshInstance3D.new()
		_proxy_mesh.name = "ProxyMesh"
		add_child(_proxy_mesh)
	_proxy_mesh.mesh = mesh
	proxy_visible = visible
	_proxy_mesh.visible = visible


func clear_proxy() -> void:
	if _proxy_mesh != null:
		_proxy_mesh.mesh = null
		_proxy_mesh.visible = false
	proxy_visible = false


func _process(_delta: float) -> void:
	if _skeleton == null or _bone_idx < 0:
		return
	global_transform = _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone_idx)
