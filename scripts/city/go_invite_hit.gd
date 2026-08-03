## StaticBody on an invite ped — swallows world_interact into GamingArena.invite_tier.
extends StaticBody3D


func interact_at_world(_pos: Vector3) -> bool:
	var tier_s := str(get_meta("go_invite_tier", "novice"))
	var n: Node = self
	while n != null:
		if n is GamingArena:
			return (n as GamingArena).invite_tier(StringName(tier_s))
		n = n.get_parent()
	return true
