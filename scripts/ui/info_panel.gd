class_name InfoPanel
extends PanelContainer
## (뼈대) 개체 정보 창. 계약: docs/VIEW-API.md "InfoPanel".

signal slime_requested(id: int)
signal follow_toggled(on: bool)

var _world: SimWorld
var _id := -1
var _label := Label.new()


func _ready() -> void:
	add_child(_label)
	clear()


func show_slime(world: SimWorld, id: int) -> void:
	_world = world
	_id = id
	refresh()


func clear() -> void:
	_id = -1
	_label.text = "슬라임을 눌러 고르세요"


func refresh() -> void:
	if _world == null or _id < 0:
		return
	var d := _world.slime_info(_id)
	_label.text = "#%d %d세대" % [_id, int(d.get("gen", 0))]


func current_id() -> int:
	return _id
