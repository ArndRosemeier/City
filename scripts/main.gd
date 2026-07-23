## Main demo scene: ground stub, vehicle marker, human crowd + showcase HUD.
extends Node3D

const ShowcaseHudScript := preload("res://scripts/showcase_hud.gd")

@onready var city: CityStub = $City
@onready var vehicles: VehicleStub = $Vehicles
@onready var humans: HumanSpawner = $Humans
@onready var camera: Camera3D = $Camera3D

var _orbit_paused: bool = false
var _orbit_t: float = 0.0
var _hud: CanvasLayer


func _ready() -> void:
	city.generate_placeholder_ground()
	vehicles.spawn_placeholder_marker()
	humans.spawn_crowd()
	_hud = ShowcaseHudScript.new()
	_hud.name = "ShowcaseHud"
	add_child(_hud)
	_hud.reshuffle_requested.connect(_on_reshuffle)
	_hud.orbit_pause_toggled.connect(_on_orbit_pause)
	_orbit_t = 0.0
	_update_camera()


func _process(delta: float) -> void:
	if not _orbit_paused:
		_orbit_t += delta * 0.22
	_update_camera()


func _update_camera() -> void:
	camera.position = Vector3(sin(_orbit_t) * 18.0, 9.5, cos(_orbit_t) * 18.0)
	camera.look_at(Vector3(0.0, 1.1, 0.0))


func _on_reshuffle() -> void:
	for child in humans.get_children():
		child.queue_free()
	# Wait one frame so queue_free completes before respawn.
	await get_tree().process_frame
	humans.spawn_seed = randi()
	humans.spawn_crowd()


func _on_orbit_pause(paused: bool) -> void:
	_orbit_paused = paused
