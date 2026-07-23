## Documents and validates the anatomy attachment contract for humans.
## Full genital meshes are not required for the POC; this ensures they remain possible.
class_name AnatomySlotContract
extends RefCounted

const REQUIRED_PROXY_BONE := &"pelvis"
const CROTCH_SLOT_ID := &"crotch"


static func assert_ready(pedestrian: Pedestrian) -> void:
	var anatomy := pedestrian.get_node_or_null("AnatomySlot") as AnatomyProxy
	if anatomy == null:
		push_error("AnatomySlotContract: Pedestrian missing AnatomySlot child")
		return
	if anatomy.slot_id != CROTCH_SLOT_ID:
		push_warning("AnatomySlotContract: expected slot_id '%s'" % CROTCH_SLOT_ID)
	if anatomy.bone_name != REQUIRED_PROXY_BONE:
		push_warning("AnatomySlotContract: expected bone '%s' for future proxies" % REQUIRED_PROXY_BONE)
	# Proxy mesh may be empty; that is intentional for the nude-incomplete POC.
	if anatomy.proxy_visible and anatomy.get_node_or_null("ProxyMesh") == null:
		push_warning("AnatomySlotContract: proxy_visible but no ProxyMesh child")
