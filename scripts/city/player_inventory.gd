## 25 stackable inventory slots with craft support. Source of truth for collected gems.
class_name PlayerInventory
extends RefCounted

signal changed

var _slots: Array[Dictionary] = []


func _init() -> void:
	InventoryCatalog.ensure_loaded()
	_slots.resize(InventoryCatalog.SLOT_COUNT)
	for i in InventoryCatalog.SLOT_COUNT:
		_slots[i] = {}


func clear() -> void:
	for i in _slots.size():
		_slots[i] = {}
	changed.emit()


func slot_count() -> int:
	return _slots.size()


## Empty slots are {}. Occupied: { "id": String, "count": int }.
func slot_at(index: int) -> Dictionary:
	if index < 0 or index >= _slots.size():
		push_error("PlayerInventory.slot_at: index %d out of range" % index)
		return {}
	return _slots[index].duplicate()


func count_of(item_id: String) -> int:
	if item_id == "" or not InventoryCatalog.has_item(item_id):
		push_error("PlayerInventory.count_of: unknown item '%s'" % item_id)
		return 0
	var total := 0
	for slot in _slots:
		if str(slot.get("id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total


## Adds as many as will fit. Returns the leftover count that did not fit.
func add(item_id: String, amount: int) -> int:
	if amount <= 0:
		push_error("PlayerInventory.add: amount must be > 0 (got %d)" % amount)
		return amount
	var def := InventoryCatalog.item(item_id)
	if def == null:
		return amount
	var left := amount
	## Fill existing stacks first.
	for i in _slots.size():
		if left <= 0:
			break
		var slot: Dictionary = _slots[i]
		if str(slot.get("id", "")) != item_id:
			continue
		var have := int(slot.get("count", 0))
		var room := def.stack_max - have
		if room <= 0:
			continue
		var take := mini(room, left)
		slot["count"] = have + take
		_slots[i] = slot
		left -= take
	## Then empty slots.
	for i in _slots.size():
		if left <= 0:
			break
		if not _slots[i].is_empty():
			continue
		var take2 := mini(def.stack_max, left)
		_slots[i] = {"id": item_id, "count": take2}
		left -= take2
	if left < amount:
		changed.emit()
	return left


## Removes up to amount. Returns false (and changes nothing) if there are not enough.
func remove(item_id: String, amount: int) -> bool:
	if amount <= 0:
		push_error("PlayerInventory.remove: amount must be > 0 (got %d)" % amount)
		return false
	if count_of(item_id) < amount:
		return false
	var left := amount
	## Drain from the end so early slots stay packed when possible.
	for i in range(_slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var slot: Dictionary = _slots[i]
		if str(slot.get("id", "")) != item_id:
			continue
		var have := int(slot.get("count", 0))
		var take := mini(have, left)
		have -= take
		left -= take
		if have <= 0:
			_slots[i] = {}
		else:
			slot["count"] = have
			_slots[i] = slot
	changed.emit()
	return true


func can_craft(recipe_id: String) -> bool:
	var recipe := InventoryCatalog.recipe(recipe_id)
	if recipe == null:
		return false
	for item_id in recipe.inputs.keys():
		var need := int(recipe.inputs[item_id])
		if count_of(String(item_id)) < need:
			return false
	## Output must fit (enough room for leftovers after consume is checked by dry-run).
	return _craft_fits(recipe)


func craft(recipe_id: String) -> bool:
	var recipe := InventoryCatalog.recipe(recipe_id)
	if recipe == null:
		return false
	if not can_craft(recipe_id):
		push_error("PlayerInventory.craft: cannot craft '%s'" % recipe_id)
		return false
	for item_id in recipe.inputs.keys():
		if not remove(String(item_id), int(recipe.inputs[item_id])):
			push_error("PlayerInventory.craft: remove failed mid-craft for '%s'" % item_id)
			return false
	var leftover := add(recipe.output_id, recipe.output_count)
	if leftover != 0:
		push_error(
			"PlayerInventory.craft: output did not fit after consume (%d left of %s)"
			% [leftover, recipe.output_id]
		)
		return false
	return true


## True when consuming inputs would leave room for the output stack.
func _craft_fits(recipe: InventoryCatalog.Recipe) -> bool:
	var sim := _duplicate_slots()
	for item_id in recipe.inputs.keys():
		var need := int(recipe.inputs[item_id])
		if not _sim_remove(sim, String(item_id), need):
			return false
	return _sim_add(sim, recipe.output_id, recipe.output_count) == 0


func _duplicate_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.resize(_slots.size())
	for i in _slots.size():
		out[i] = _slots[i].duplicate()
	return out


func _sim_remove(slots: Array[Dictionary], item_id: String, amount: int) -> bool:
	var left := amount
	for i in range(slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var slot: Dictionary = slots[i]
		if str(slot.get("id", "")) != item_id:
			continue
		var have := int(slot.get("count", 0))
		var take := mini(have, left)
		have -= take
		left -= take
		if have <= 0:
			slots[i] = {}
		else:
			slot["count"] = have
			slots[i] = slot
	return left == 0


func _sim_add(slots: Array[Dictionary], item_id: String, amount: int) -> int:
	var def := InventoryCatalog.item(item_id)
	if def == null:
		return amount
	var left := amount
	for i in slots.size():
		if left <= 0:
			break
		var slot: Dictionary = slots[i]
		if str(slot.get("id", "")) != item_id:
			continue
		var have := int(slot.get("count", 0))
		var room := def.stack_max - have
		if room <= 0:
			continue
		var take := mini(room, left)
		slot["count"] = have + take
		slots[i] = slot
		left -= take
	for i in slots.size():
		if left <= 0:
			break
		if not slots[i].is_empty():
			continue
		var take2 := mini(def.stack_max, left)
		slots[i] = {"id": item_id, "count": take2}
		left -= take2
	return left
