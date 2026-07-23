## Spawns a crowd of pedestrians with randomized sex and proportions.
class_name HumanSpawner
extends Node3D

const PEDESTRIAN_SCENE := preload("res://scenes/human/pedestrian.tscn")

@export var count: int = 24
@export var spawn_radius: float = 18.0
@export var spawn_seed: int = 42

var _rng := RandomNumberGenerator.new()


func spawn_crowd() -> void:
	_rng.seed = spawn_seed
	for i in range(count):
		var ped := PEDESTRIAN_SCENE.instantiate() as Pedestrian
		ped.name = "Pedestrian_%d" % i
		var sex := Pedestrian.Sex.MALE if _rng.randf() < 0.5 else Pedestrian.Sex.FEMALE
		var props := BodyProportions.random(_rng)
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(2.0, spawn_radius)
		ped.position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		add_child(ped)
		ped.setup(sex, props, _rng)
