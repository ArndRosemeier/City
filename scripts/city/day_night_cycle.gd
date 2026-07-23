## Advances time of day and drives sun, moon, sky shader, fog, ambient, and street lights.
class_name DayNightCycle
extends Node

signal night_factor_changed(night_factor: float)

const SKY_SHADER := "res://assets/city/shaders/city_sky.gdshader"

## Full day length in real seconds (sunrise→sunrise).
@export var day_length_sec: float = 420.0
## 0..24 start hour (6 = morning).
@export var start_hour: float = 8.5
@export var max_sun_energy: float = 1.45
@export var min_sun_energy: float = 0.0
@export var max_moon_energy: float = 0.42
@export var max_sun_elevation_deg: float = 72.0
@export var ambient_day: float = 0.42
## Keep nights readable — city should still feel lit by moon + sky.
@export var ambient_night: float = 0.34
@export var fog_density_day: float = 0.0016
@export var fog_density_night: float = 0.0024
@export var cloud_speed: float = 0.014
@export var cloud_cover: float = 0.58

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial

var _hour: float = 8.5
var _night_factor: float = 0.0
var _cloud_time: float = 0.0
var _accum_broadcast: float = 0.0


func setup(sun_light: DirectionalLight3D, moon_light: DirectionalLight3D, env: Environment, sky_mat: ShaderMaterial) -> void:
	sun = sun_light
	moon = moon_light
	environment = env
	sky_material = sky_mat
	_hour = start_hour
	if sky_material != null:
		sky_material.set_shader_parameter("cloud_speed", cloud_speed)
		sky_material.set_shader_parameter("cloud_cover", cloud_cover)
	add_to_group(&"day_night")
	_apply(true)


func get_hour() -> float:
	return _hour


func get_night_factor() -> float:
	return _night_factor


func set_hour(hour: float) -> void:
	_hour = fposmod(hour, 24.0)
	_apply(true)


## Flip between midday and midnight (N key).
func toggle_day_night() -> void:
	if get_night_factor() >= 0.45:
		set_hour(12.0)
	else:
		set_hour(0.0)


func _process(delta: float) -> void:
	if sun == null or environment == null or sky_material == null:
		return
	var span := maxf(day_length_sec, 30.0)
	_hour = fposmod(_hour + delta * (24.0 / span), 24.0)
	_cloud_time += delta
	_apply(false)
	## Don't spam street-light updates every frame.
	_accum_broadcast += delta
	if _accum_broadcast >= 0.2:
		_accum_broadcast = 0.0
		night_factor_changed.emit(_night_factor)


func _apply(force_signal: bool) -> void:
	var t := _hour / 24.0
	## Elevation: below horizon at night, peaks near noon.
	var elev_norm := sin(t * TAU - PI * 0.5)
	var elev_deg := elev_norm * max_sun_elevation_deg
	var azim_deg := t * 360.0 - 90.0
	sun.rotation_degrees = Vector3(-elev_deg, azim_deg, 0.0)

	var day_amount := smoothstep(-0.12, 0.28, elev_norm)
	var night := 1.0 - day_amount
	var dawn_dusk := 1.0 - absf(elev_norm) * 2.0
	dawn_dusk = clampf(dawn_dusk, 0.0, 1.0) * day_amount

	## Warm golden hour near the horizon; white-cyan at noon.
	var sun_day := Color(1.0, 0.96, 0.88)
	var sun_golden := Color(1.0, 0.62, 0.28)
	var sun_col := sun_day.lerp(sun_golden, dawn_dusk)
	sun.light_color = sun_col
	sun.light_energy = lerpf(min_sun_energy, max_sun_energy, day_amount)
	sun.shadow_enabled = day_amount > 0.08

	## Moon opposite the sun — soft blue fill so night streets stay readable.
	if moon != null:
		moon.rotation_degrees = Vector3(elev_deg * 0.85, azim_deg + 180.0, 0.0)
		moon.light_color = Color(0.62, 0.72, 1.0)
		moon.light_energy = max_moon_energy * smoothstep(0.15, 0.85, night)
		moon.shadow_enabled = false
		moon.visible = night > 0.05

	## Brighter night sky palette (was nearly black).
	var day_top := Color(0.30, 0.56, 0.92)
	var day_horizon := Color(0.74, 0.86, 0.96)
	var golden_horizon := Color(1.0, 0.58, 0.32)
	var night_top := Color(0.10, 0.16, 0.30)
	var night_horizon := Color(0.20, 0.28, 0.45)
	var top := day_top.lerp(night_top, night)
	var horizon := day_horizon.lerp(golden_horizon, dawn_dusk).lerp(night_horizon, night)

	sky_material.set_shader_parameter("night_factor", night)
	sky_material.set_shader_parameter("dawn_factor", dawn_dusk)
	sky_material.set_shader_parameter("cloud_time", _cloud_time)
	sky_material.set_shader_parameter("day_top", day_top)
	sky_material.set_shader_parameter("day_horizon", day_horizon)
	sky_material.set_shader_parameter("golden_horizon", golden_horizon)
	sky_material.set_shader_parameter("night_top", night_top)
	sky_material.set_shader_parameter("night_horizon", night_horizon)
	sky_material.set_shader_parameter("ground_color", Color(0.10, 0.10, 0.11).lerp(Color(0.06, 0.07, 0.1), night))

	## Ambient / fog / glow — nights stay luminous.
	environment.ambient_light_color = top.lerp(Color(0.45, 0.55, 0.85), 0.4)
	environment.ambient_light_energy = lerpf(ambient_day, ambient_night, night)
	environment.fog_light_color = horizon.lerp(Color(0.22, 0.28, 0.42), night * 0.55)
	environment.fog_density = lerpf(fog_density_day, fog_density_night, night)
	environment.glow_intensity = lerpf(0.45, 0.7, night)
	environment.glow_bloom = lerpf(0.1, 0.18, night)
	environment.tonemap_exposure = lerpf(1.0, 1.12, night)

	var prev := _night_factor
	_night_factor = night
	if force_signal or absf(prev - _night_factor) > 0.01:
		night_factor_changed.emit(_night_factor)
