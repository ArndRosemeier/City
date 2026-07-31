## The "you found this" card: one spinning preview per stone that just arrived, its running count,
## then it fades.
##
## Gems used to land in a closed panel. The inventory is shut while you play, so a chest paid its
## haul into a number nobody was looking at — the click was the only feedback that anything at all
## had happened.
##
## Hauls coalesce rather than queue. A chest hands over three stones in one frame and a seam hands
## them over one every few seconds; both read better as a single tally that is topped up and has its
## clock restarted than as popups stacking behind each other.
##
## The CanvasLayer's own `visible` belongs to `CityRoot`, which hides the whole HUD band while a
## modal owns the screen. This node drives `_root` instead — driving `visible` here would mean
## closing the inventory brought back a toast that had already faded.
class_name LootToast
extends CanvasLayer

## How long the card stays up after the last thing arrived, and how long it takes to go.
const HOLD_SEC := 2.6
const FADE_SEC := 0.55
## The swell as the card appears. Short enough that a fast second haul still reads as one card.
const POP_SEC := 0.22
## How long a card stays lit after its count went up, so topping up an existing stone is visible.
const FLASH_SEC := 0.5

const CARD_PX := 66.0
const VIEW_SIZE := Vector2i(64, 64)
const CAM_FOV := 35.0
## Slack between the item's bounding sphere and the edge of the square render target.
const CAM_FIT_MARGIN := 1.12
## A slow turn: the facets catch the light, which is what makes a gem read as a gem at 64 px.
const SPIN_DEG_PER_SEC := 48.0

## Clear of the crosshair and above the energy bar, measured up from the bottom of the screen.
const STRIP_BOTTOM_PX := 196.0
const STRIP_HEIGHT_PX := 132.0

const HEADLINE_DEFAULT := "Found"


## One stone's card: the preview, the tally, and how recently that tally moved.
class Card:
	extends RefCounted

	var item_id: String = ""
	var count: int = 0
	var root: Control
	var mesh: MeshInstance3D
	var count_label: Label
	var flash: float = 0.0


var _root: Control
var _panel: PanelContainer
var _headline: Label
var _row: HBoxContainer
## item_id → Card, in the order the stones arrived.
var _cards: Dictionary[String, Card] = {}
var _hold_left: float = 0.0
var _alpha: float = 0.0
var _age: float = 0.0


func _ready() -> void:
	layer = UiLayers.HUD_LOOT
	_build_ui()
	set_process(false)


# ---------------------------------------------------------------------------
# Showing loot
# ---------------------------------------------------------------------------

## Add `count` of an inventory item to the card that is up, starting one if there is none.
func add_item(item_id: String, count: int = 1) -> void:
	if count <= 0:
		push_error("LootToast.add_item: %d of '%s' is not a find" % [count, item_id])
		return
	if InventoryCatalog.item(item_id) == null:
		push_error("LootToast.add_item: '%s' is not an item" % item_id)
		return
	if not _showing():
		_reset()
	var card: Card = _cards.get(item_id)
	if card == null:
		card = _make_card(item_id)
		if card == null:
			return
		_cards[item_id] = card
	card.count += count
	card.count_label.text = "×%d" % card.count
	card.flash = FLASH_SEC
	_begin_hold()


func add_gem(gem_mat_id: int, count: int = 1) -> void:
	var item_id := InventoryCatalog.item_id_for_gem(gem_mat_id)
	if item_id.is_empty():
		push_error("LootToast.add_gem: %d is not a gem" % gem_mat_id)
		return
	add_item(item_id, count)


## What the card says above the stones. Set after the grants, so a chest can name itself.
func set_headline(text: String) -> void:
	_headline.text = text if not text.is_empty() else HEADLINE_DEFAULT


## A card with words and no stones — an empty chest is worth saying out loud too.
func show_message(text: String) -> void:
	_reset()
	set_headline(text)
	_begin_hold()


func is_showing() -> bool:
	return _showing()


func card_count() -> int:
	return _cards.size()


## Tally shown for `item_id` right now, 0 when it is not on the card.
func count_of(item_id: String) -> int:
	var card: Card = _cards.get(item_id)
	return 0 if card == null else card.count


func headline() -> String:
	return _headline.text


func hide_now() -> void:
	_alpha = 0.0
	_hold_left = 0.0
	_finish()


# ---------------------------------------------------------------------------
# Timing
# ---------------------------------------------------------------------------

func _showing() -> bool:
	return _root.visible


func _begin_hold() -> void:
	_hold_left = HOLD_SEC
	_alpha = 1.0
	_root.visible = true
	set_process(true)


## Clear the card down to nothing and restart its entrance. Called when loot arrives after the last
## card has gone, so an old tally is never added to.
func _reset() -> void:
	for id: String in _cards.keys():
		var card: Card = _cards[id]
		card.root.queue_free()
	_cards.clear()
	_headline.text = HEADLINE_DEFAULT
	_age = 0.0


func _process(delta: float) -> void:
	_age += delta
	if _hold_left > 0.0:
		_hold_left = maxf(_hold_left - delta, 0.0)
	else:
		_alpha = maxf(_alpha - delta / FADE_SEC, 0.0)
	_root.modulate.a = _alpha
	_animate_panel()
	_animate_cards(delta)
	if _alpha <= 0.0:
		_finish()


## A swell on the way in. The card is centred by a container, so scaling it around its own middle
## does not move it.
func _animate_panel() -> void:
	var pop := 1.0
	if _age < POP_SEC:
		var k := _age / POP_SEC
		pop = lerpf(0.86, 1.0, smoothstep(0.0, 1.0, k)) + 0.08 * sin(PI * k)
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * pop


func _animate_cards(delta: float) -> void:
	var spin := deg_to_rad(SPIN_DEG_PER_SEC * delta)
	for id: String in _cards.keys():
		var card: Card = _cards[id]
		if card.mesh != null and is_instance_valid(card.mesh):
			card.mesh.rotate_y(spin)
		if card.flash <= 0.0:
			continue
		card.flash = maxf(card.flash - delta, 0.0)
		var k := card.flash / FLASH_SEC
		card.root.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.9, 1.7, 1.0), k)


func _finish() -> void:
	_reset()
	_root.visible = false
	_root.modulate.a = 0.0
	set_process(false)


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)

	## A full-width strip with a centring container in it, so the card stays centred at whatever
	## width the haul needs without any offset arithmetic.
	var strip := Control.new()
	strip.name = "Strip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -STRIP_BOTTOM_PX - STRIP_HEIGHT_PX
	strip.offset_bottom = -STRIP_BOTTOM_PX
	_root.add_child(strip)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip.add_child(centre)

	_panel = PanelContainer.new()
	_panel.name = "Card"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.78)
	style.border_color = Color(0.95, 0.82, 0.45, 0.55)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)
	centre.add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "Body"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)

	_headline = Label.new()
	_headline.name = "Headline"
	_headline.text = HEADLINE_DEFAULT
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_headline.add_theme_font_size_override("font_size", 15)
	_headline.add_theme_color_override("font_color", Color(0.98, 0.9, 0.66))
	_headline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_headline.add_theme_constant_override("outline_size", 4)
	box.add_child(_headline)

	_row = HBoxContainer.new()
	_row.name = "Stones"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 10)
	box.add_child(_row)


## One preview + tally + name, in a world of its own. Null when the item has no icon to show,
## which is a content fault rather than a reason to put an empty square on screen.
func _make_card(item_id: String) -> Card:
	var mesh := InventoryItemVisual.make_mesh(item_id)
	if mesh == null:
		return null
	var card := Card.new()
	card.item_id = item_id
	card.mesh = mesh

	var holder := VBoxContainer.new()
	holder.name = "Card_%s" % item_id
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override("separation", 0)
	card.root = holder

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(CARD_PX, CARD_PX)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(stack)

	var vp_host := SubViewportContainer.new()
	vp_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_host.stretch = true
	vp_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(vp_host)

	var vp := SubViewport.new()
	vp.size = VIEW_SIZE
	vp.transparent_bg = true
	## One stone against nothing. Without a world of its own the preview camera, light and mesh
	## would all land in the city.
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp_host.add_child(vp)

	var world := Node3D.new()
	world.name = "PreviewWorld"
	vp.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	light.light_energy = 1.25
	world.add_child(light)
	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	## Built detached, so the aim has to come from the given eye point rather than a global one.
	cam.look_at_from_position(_camera_position(), Vector3.ZERO, Vector3.UP)
	world.add_child(cam)
	world.add_child(mesh)

	var count_label := Label.new()
	count_label.name = "Count"
	count_label.text = "×%d" % 0
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	count_label.offset_right = -2
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.add_theme_font_size_override("font_size", 15)
	count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	count_label.add_theme_constant_override("outline_size", 4)
	stack.add_child(count_label)
	card.count_label = count_label

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = InventoryCatalog.display_name(item_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	name_label.add_theme_constant_override("outline_size", 3)
	holder.add_child(name_label)

	_row.add_child(holder)
	return card


## Far enough back that the stone's bounding sphere fits the square target at `CAM_FOV`.
static func _camera_position() -> Vector3:
	var half_fov := deg_to_rad(CAM_FOV * 0.5)
	var back := InventoryItemVisual.bounding_radius() * CAM_FIT_MARGIN / sin(half_fov)
	return Vector3(0.0, back * 0.11, back)
