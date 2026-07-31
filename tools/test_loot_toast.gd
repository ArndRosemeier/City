## The find feedback: the card that shows what just arrived, and the two sounds behind it.
##
## Gems land in a panel that is shut while you play, so the card *is* the feedback — if it does not
## come up, or comes up empty, or shows a tally left over from the last chest, the player has no way
## of knowing a chest paid anything. So the cases here are about what a find looks like a moment
## later: stones merged into one card, a fresh haul starting from zero, and an empty chest saying so
## rather than opening in silence.
##
## The sounds are synthesized, which means they can come out silent without anything failing. Their
## sample data is checked for an actual peak for the same reason.
##
## Run: powershell -File tools\run_test.ps1 test_loot_toast
extends Node

const LootToastScript := preload("res://scripts/city/loot_toast.gd")
const CityAudioScript := preload("res://scripts/city/city_audio.gd")
const GemChestPlacerScript := preload("res://scripts/city/gem_chest_placer.gd")
const DistrictInstanceScript := preload("res://scripts/city/district_instance.gd")

const COORD := Vector2i(5, 8)

var _failed := false


## CityRoot without its boot: the group is how `GemChest` finds it, and the loot card is handed in
## rather than built, because `_build_hud` wants a whole session behind it.
class TestCity:
	extends CityRoot

	func _ready() -> void:
		add_to_group("city_root")

	func bind_test_toast(toast: LootToast) -> void:
		_loot_toast = toast


## CityAudio only for its synthesis: the banks load, but nothing here plays.
class TestAudio:
	extends CityAudio

	func chest_open_wav() -> AudioStreamWAV:
		return _build_chest_open()

	func bling_wav() -> AudioStreamWAV:
		return _build_treasure_bling()


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	await _check_stones_merge_into_one_card()
	await _check_a_message_needs_no_stones()
	await _check_it_goes_away_and_the_next_haul_starts_over()
	await _check_a_chest_fills_the_card()
	_check_the_sounds_are_audible()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _make_toast() -> LootToast:
	var toast: LootToast = LootToastScript.new() as LootToast
	toast.name = "Toast"
	add_child(toast)
	await get_tree().process_frame
	return toast


# ---------------------------------------------------------------------------
# The card
# ---------------------------------------------------------------------------

## Three stones out of one chest are one card with three tallies, not three cards fighting for the
## same patch of screen — and a second quartz tops the quartz up instead of adding a second quartz.
func _check_stones_merge_into_one_card() -> void:
	var toast := await _make_toast()
	if toast.is_showing():
		_fail("FAIL the card is up before anything was found")
		toast.queue_free()
		return
	if toast.layer < UiLayers.HUD_MIN or toast.layer > UiLayers.HUD_MAX:
		_fail("FAIL the card sits on layer %d, outside the HUD band a modal hides" % toast.layer)
		toast.queue_free()
		return

	toast.add_gem(VoxelMaterial.GEM_QUARTZ)
	toast.add_gem(VoxelMaterial.GEM_QUARTZ)
	toast.add_gem(VoxelMaterial.GEM_DIAMOND, 2)
	if not toast.is_showing():
		_fail("FAIL the card did not come up for three stones")
		toast.queue_free()
		return
	if toast.card_count() != 2:
		_fail("FAIL two kinds of stone made %d cards" % toast.card_count())
		toast.queue_free()
		return
	if toast.count_of(InventoryCatalog.ID_QUARTZ) != 2:
		_fail("FAIL two quartz read as %d" % toast.count_of(InventoryCatalog.ID_QUARTZ))
		toast.queue_free()
		return
	if toast.count_of(InventoryCatalog.ID_DIAMOND) != 2:
		_fail("FAIL two diamonds read as %d" % toast.count_of(InventoryCatalog.ID_DIAMOND))
		toast.queue_free()
		return
	if toast.count_of(InventoryCatalog.ID_AMBER) != 0:
		_fail("FAIL the card claims amber nobody found")
		toast.queue_free()
		return
	if toast.headline() != LootToast.HEADLINE_DEFAULT:
		_fail("FAIL a plain find is headed '%s'" % toast.headline())
		toast.queue_free()
		return
	toast.set_headline("Chest opened")
	if toast.headline() != "Chest opened":
		_fail("FAIL the headline did not take")
		toast.queue_free()
		return
	print("OK a find of five stones is one card with two tallies")
	toast.queue_free()


func _check_a_message_needs_no_stones() -> void:
	var toast := await _make_toast()
	toast.show_message("The chest is empty")
	if not toast.is_showing():
		_fail("FAIL a message did not put the card up")
		toast.queue_free()
		return
	if toast.card_count() != 0:
		_fail("FAIL a message invented %d stones" % toast.card_count())
		toast.queue_free()
		return
	if toast.headline() != "The chest is empty":
		_fail("FAIL the message reads '%s'" % toast.headline())
		toast.queue_free()
		return
	## And a find after a message drops the message's own wording for the stones' own.
	toast.add_gem(VoxelMaterial.GEM_TOPAZ)
	if toast.count_of(InventoryCatalog.ID_TOPAZ) != 1:
		_fail("FAIL a stone found after a message was not counted")
		toast.queue_free()
		return
	print("OK an empty chest says so with no stones on the card")
	toast.queue_free()


## The card is a moment's feedback, so it has to leave — and the haul after it must start at zero,
## or a later chest would appear to pay out what an earlier one did.
func _check_it_goes_away_and_the_next_haul_starts_over() -> void:
	var toast := await _make_toast()
	toast.add_gem(VoxelMaterial.GEM_SAPPHIRE, 3)
	await get_tree().create_timer(LootToast.HOLD_SEC + LootToast.FADE_SEC + 0.35).timeout
	if toast.is_showing():
		_fail("FAIL the card is still up long after the find")
		toast.queue_free()
		return
	if toast.card_count() != 0 or toast.count_of(InventoryCatalog.ID_SAPPHIRE) != 0:
		_fail("FAIL a faded card kept %d stones" % toast.count_of(InventoryCatalog.ID_SAPPHIRE))
		toast.queue_free()
		return
	toast.add_gem(VoxelMaterial.GEM_SAPPHIRE)
	if toast.count_of(InventoryCatalog.ID_SAPPHIRE) != 1:
		_fail(
			"FAIL the next find opened on a tally of %d"
			% toast.count_of(InventoryCatalog.ID_SAPPHIRE)
		)
		toast.queue_free()
		return
	if toast.headline() != LootToast.HEADLINE_DEFAULT:
		_fail("FAIL the new find kept the old headline '%s'" % toast.headline())
		toast.queue_free()
		return
	## Closing it by hand leaves nothing behind either — this is the path a district hop takes.
	toast.hide_now()
	if toast.is_showing() or toast.card_count() != 0:
		_fail("FAIL the card survived being closed")
		toast.queue_free()
		return
	print("OK the card fades away and the next find starts from zero")
	toast.queue_free()


# ---------------------------------------------------------------------------
# End to end
# ---------------------------------------------------------------------------

## The whole point: click a chest and the stones it paid are on screen, named for the chest. Then
## the same click in a district with nothing left says the chest was empty instead of paying twice.
func _check_a_chest_fills_the_card() -> void:
	var city := TestCity.new()
	city.name = "ToastCity"
	add_child(city)
	city.set_process(false)
	city.set_physics_process(false)
	await get_tree().process_frame
	var toast := await _make_toast()
	city.bind_test_toast(toast)

	var stocked: Dictionary[int, int] = {VoxelMaterial.GEM_EMERALD: 30}
	city.get_economy().ensure_row(COORD, stocked)
	city.get_inventory().clear()

	var district: DistrictInstance = DistrictInstanceScript.new() as DistrictInstance
	district.name = "ToastDistrict"
	district.coord = COORD
	add_child(district)
	var chest := district.ensure_gem_chests().place_chest(
		COORD, Vector3(2.0, 1.0, 2.0), 0.0, 31337
	)
	if chest == null:
		_fail("FAIL the chest could not be built")
		_free_case(city, district, toast)
		return
	chest.interact_at_world(chest.global_position)
	var paid := city.get_inventory().count_of(InventoryCatalog.ID_EMERALD)
	if paid <= 0:
		_fail("FAIL the chest paid nothing out of a stocked district")
		_free_case(city, district, toast)
		return
	if not toast.is_showing():
		_fail("FAIL opening a chest put nothing on screen")
		_free_case(city, district, toast)
		return
	if toast.headline() != "Chest opened":
		_fail("FAIL the card is headed '%s' rather than naming the chest" % toast.headline())
		_free_case(city, district, toast)
		return
	if toast.count_of(InventoryCatalog.ID_EMERALD) != paid:
		_fail(
			"FAIL the chest paid %d emeralds and the card shows %d"
			% [paid, toast.count_of(InventoryCatalog.ID_EMERALD)]
		)
		_free_case(city, district, toast)
		return

	## Same chest, stripped district: the card must say so rather than repeat the last haul.
	toast.hide_now()
	while city.get_economy().try_take(COORD, VoxelMaterial.GEM_EMERALD):
		pass
	var empty_chest := district.gem_chests.place_chest(COORD, Vector3(4.0, 1.0, 2.0), 0.0, 77)
	if empty_chest == null:
		_fail("FAIL the second chest could not be built")
		_free_case(city, district, toast)
		return
	empty_chest.interact_at_world(empty_chest.global_position)
	if toast.card_count() != 0:
		_fail("FAIL an empty chest put %d stones on the card" % toast.card_count())
		_free_case(city, district, toast)
		return
	if not toast.headline().contains("empty"):
		_fail("FAIL an empty chest is headed '%s'" % toast.headline())
		_free_case(city, district, toast)
		return
	print("OK a chest puts its %d stones on the card, an empty one says it is empty" % paid)
	_free_case(city, district, toast)


func _free_case(city: TestCity, district: DistrictInstance, toast: LootToast) -> void:
	district.destroy_and_clear(null)
	toast.queue_free()
	city.queue_free()


# ---------------------------------------------------------------------------
# The sounds
# ---------------------------------------------------------------------------

## Both are built sample by sample, so a wrong envelope makes a stream that exists, plays, reports
## no error and cannot be heard. Peak amplitude is the only thing that actually catches that.
func _check_the_sounds_are_audible() -> void:
	var audio: TestAudio = TestAudio.new()
	audio.name = "TestAudio"
	add_child(audio)
	for probe: Array in [
		["chest lid", audio.chest_open_wav()], ["treasure bling", audio.bling_wav()]
	]:
		var what: String = probe[0]
		var wav: AudioStreamWAV = probe[1]
		if wav == null:
			_fail("FAIL the %s was not built" % what)
			continue
		if wav.data.size() < 2000:
			_fail("FAIL the %s is %d bytes long, which is nothing" % [what, wav.data.size()])
			continue
		var peak := _peak_of(wav)
		if peak < 0.2:
			_fail("FAIL the %s peaks at %.3f, so it is inaudible" % [what, peak])
			continue
		if peak > 0.999:
			_fail("FAIL the %s peaks at %.3f, so it is clipping" % [what, peak])
			continue
		print("OK the %s runs %.2f s and peaks at %.2f" % [what, _seconds_of(wav), peak])
	audio.queue_free()


## Loudest sample as a fraction of full scale, from 16-bit little-endian mono data.
func _peak_of(wav: AudioStreamWAV) -> float:
	if wav.format != AudioStreamWAV.FORMAT_16_BITS:
		_fail("FAIL a synthesized sound is not 16-bit, so it cannot be measured")
		return 0.0
	var data := wav.data
	var peak := 0
	var i := 0
	while i + 1 < data.size():
		var raw := data[i] | (data[i + 1] << 8)
		if raw >= 32768:
			raw -= 65536
		peak = maxi(peak, absi(raw))
		i += 2
	return float(peak) / 32767.0


func _seconds_of(wav: AudioStreamWAV) -> float:
	return float(wav.data.size() / 2) / float(wav.mix_rate)
