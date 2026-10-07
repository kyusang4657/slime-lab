class_name LabMain
extends Control
## (뼈대) 실험실 주 화면. 계약: docs/VIEW-API.md "LabMain".

signal ticked(world: SimWorld)
signal events(list: Array)

var world: SimWorld
var map_view: MapView
var info_panel: InfoPanel
var left_dock: VBoxContainer
var bottom_dock: HBoxContainer
var _speed := 1
var _paused := false
var _fast := false
var _acc := 0.0


func _ready() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	left_dock = VBoxContainer.new()
	root.add_child(left_dock)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(svc)
	var sv := SubViewport.new()
	svc.add_child(sv)
	map_view = MapView.new()
	sv.add_child(map_view)
	info_panel = InfoPanel.new()
	root.add_child(info_panel)
	bottom_dock = HBoxContainer.new()
	add_child(bottom_dock)
	new_experiment(str(UiConfig.value("lab.default_preset")), {}, UiConfig.integer("lab.default_seed"))


func new_experiment(preset: String, overrides: Dictionary, seed_value: int) -> String:
	var b := SimConfig.build(preset, overrides)
	if b.error != "":
		return b.error
	var w := SimWorld.new()
	var e := w.setup(b.config, seed_value)
	if e != "":
		return e
	world = w
	map_view.bind(world)
	return ""


func open_snapshot(path: String) -> String:
	var r := SimSnapshot.load_file(path)
	if r.world == null:
		return r.error
	world = r.world
	map_view.bind(world)
	return ""


func set_speed(mult: int) -> void:
	_speed = mult


func set_paused(p: bool) -> void:
	_paused = p


func set_fast_forward(on: bool) -> void:
	_fast = on


func select_slime(id: int) -> void:
	map_view.set_selected(id)
	if id < 0:
		info_panel.clear()
	else:
		info_panel.show_slime(world, id)


func actual_speed() -> float:
	return float(_speed)


func _process(delta: float) -> void:
	if world == null or _paused:
		return
	map_view.before_steps()
	_acc += delta * UiConfig.num("speed.ticks_per_second_1x") * float(_speed)
	var n := 0
	while _acc >= 1.0:
		world.step()
		_acc -= 1.0
		n += 1
	map_view.update_view(_acc)
	if n > 0:
		ticked.emit(world)
		var ev := world.drain_events()
		if not ev.is_empty():
			events.emit(ev)
