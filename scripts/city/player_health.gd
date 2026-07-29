## The player's wounds. Deliberately not the energy pool.
##
## `CityWalker` already owns a hundred-point pool that regenerates, and it is an ability budget:
## spending it is how a laser or a stomp is paid for, and running it dry is an inconvenience.
## This one is the other thing entirely — it only ever goes down because something hit you, it
## comes back on its own once nothing has for a while, and reaching the bottom of it ends the
## run. Sharing one number between the two would mean firing the blaster brought you closer to
## death, which is not a game.
##
## Kept as its own object rather than as four more fields on the walker so the depletion rule can
## be tested on its own: whether game over fires on the fourth orb and not the third is the one
## thing in a damage model that must not be discovered in play.
class_name PlayerHealth
extends RefCounted

const DamageSourceScript := preload("res://scripts/city/damage_source.gd")

signal changed(current: float, maximum: float)
## The hit that finished the pool, so the game-over screen can name it.
signal depleted(source: DamageSource.Id)

var _maximum: float = 100.0
var _regen_per_sec: float = 4.0
var _regen_delay_sec: float = 6.0
var _current: float = 100.0
## Seconds of quiet still owed before regeneration resumes.
var _regen_block_sec: float = 0.0


## The knobs, checked once instead of clamped every frame. A pool with no maximum or a negative
## regeneration is a configuration mistake, not something to paper over.
func configure(maximum: float, regen_per_sec: float, regen_delay_sec: float) -> void:
	if maximum <= 0.0:
		push_error("PlayerHealth: a maximum of %f is not a pool" % maximum)
		return
	if regen_per_sec < 0.0:
		push_error("PlayerHealth: regeneration of %f per second is backwards" % regen_per_sec)
		return
	if regen_delay_sec < 0.0:
		push_error("PlayerHealth: a regeneration delay of %f seconds is backwards" % regen_delay_sec)
		return
	_maximum = maximum
	_regen_per_sec = regen_per_sec
	_regen_delay_sec = regen_delay_sec
	_current = _maximum
	_regen_block_sec = 0.0
	changed.emit(_current, _maximum)


func current() -> float:
	return _current


func maximum() -> float:
	return _maximum


func fraction() -> float:
	return clampf(_current / _maximum, 0.0, 1.0)


func is_depleted() -> bool:
	return _current <= 0.0


## Seconds of quiet left before regeneration starts again. Zero while it is running.
func seconds_until_regen() -> float:
	return _regen_block_sec


## One hit at 1× the table amount. Returns the points actually taken, which is zero only when
## the player is already down — a hit on a corpse is not a second game over.
func apply_damage(source: DamageSource.Id) -> float:
	return apply_damage_scaled(source, 1.0)


## One hit scaled by `scale` (a body's resolved `damage_mult`). Scale must be positive — a
## zero or negative multiplier is a content bug, not a miss.
func apply_damage_scaled(source: DamageSource.Id, scale: float) -> float:
	if DamageSourceScript.target(source) != DamageSourceScript.Target.PLAYER:
		push_error(
			"PlayerHealth: %s hurts creatures, not the player"
			% DamageSourceScript.source_name(source)
		)
		return 0.0
	if scale <= 0.0:
		push_error(
			"PlayerHealth: damage scale %f for %s is not a hit"
			% [scale, DamageSourceScript.source_name(source)]
		)
		return 0.0
	if is_depleted():
		return 0.0
	var before := _current
	_current = maxf(_current - DamageSourceScript.amount(source) * scale, 0.0)
	_regen_block_sec = _regen_delay_sec
	changed.emit(_current, _maximum)
	var taken := before - _current
	var tree := Engine.get_main_loop() as SceneTree
	var log_node: Node = null
	if tree != null:
		log_node = tree.root.get_node_or_null("DamageLog")
	if log_node != null and log_node.has_method("record"):
		log_node.call(
			"record",
			DamageSourceScript.source_name(source),
			"player",
			source,
			taken,
			_current,
			_maximum,
			is_depleted()
		)
	if is_depleted():
		depleted.emit(source)
	return taken


## Out-of-combat recovery. The delay is spent first and the same frame does not also heal, so
## "six seconds since the last hit" means six seconds and not five and a frame.
func tick(delta: float) -> void:
	if is_depleted() or _current >= _maximum:
		return
	if _regen_block_sec > 0.0:
		_regen_block_sec = maxf(0.0, _regen_block_sec - delta)
		return
	var before := _current
	_current = minf(_current + _regen_per_sec * delta, _maximum)
	if not is_equal_approx(before, _current):
		changed.emit(_current, _maximum)
