class_name MapView
extends Node3D
## (뼈대) 지도 관찰 창. 계약: docs/VIEW-API.md "MapView".

signal slime_clicked(id: int)

var world: SimWorld
var follow_selected := false
var _camera: Camera3D
var _selected := -1


func _ready() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.4, 0.0)
	add_child(light)


func bind(w: SimWorld) -> void:
	world = w
	if _camera != null and world != null:
		_camera.position = Vector3(world.w * 0.5, 40.0, world.h * 0.5 + 30.0)
		_camera.look_at(Vector3(world.w * 0.5, 0.0, world.h * 0.5))


func before_steps() -> void:
	pass


func update_view(_alpha: float) -> void:
	pass


func set_selected(id: int) -> void:
	_selected = id


func pick_slime(_screen_pos: Vector2) -> int:
	return -1


func focus_on(_id: int) -> void:
	pass


func get_camera() -> Camera3D:
	return _camera


func view_stats() -> Dictionary:
	return {slimes = 0, plants = 0, stores = 0, farms = 0, triangles_estimate = 0}
