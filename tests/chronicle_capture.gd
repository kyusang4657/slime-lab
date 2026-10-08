extends SceneTree
## 연대기 창 캡처(가상 디스플레이, 픽셀 확인용):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/chronicle_capture.gd -- --out=폴더
## demo_fast(아주 빠른 발견)·씨앗 1 을 세대 이정표 10세대마다(record.generation_milestone)로 TICKS 틱 진행해
## 발견·저장고·첫 밭·밭 잃음·세대 사건이 다 있는 연대기를 만들고, 실험실 아래 자리와 같은 바탕(DockPanel) 위에 찍는다.
##   chronicle.png  왼쪽 = 420×220(실험실 아래 자리 높이, 첫 밭 줄을 누른 상태), 오른쪽 = 420×300(같은 실험, 더 긴 자리)
## --extra 를 주면 참고용도 찍는다: chronicle-compare.png(A/B 두 실험), chronicle-filter.png(건물·밭 잃음 거르기),
##   chronicle-limit.png(max_items 를 줄여 "더 오래된 K개"), chronicle-empty.png(빈 안내),
##   chronicle-extinct.png(번식한 뒤 사라진 세계의 멸종 줄 — 평균 세대 = 마지막 개체군)
## 인자: --out=폴더(기본 res://docs/screenshots/v0.1), --seed=N, --ticks=N, --extra

const TICKS := 2130
const SEED := 1
const PRESET := "demo_fast"
const SETS := {"record.generation_milestone": 10}
## 그림 둘레·사이 배경 폭(픽셀)
const MARGIN := 16
## 두 높이(아래 자리 = ui.lab.bottom_panel_height, 더 긴 자리)
const TALL := 300
## 참고 캡처의 "더 오래된" 한도
const LIMIT_ITEMS := 6
## 참고 캡처의 멸종 세계(기본 예설정·자원 절반 — 씨앗 1 은 4세대까지 번식한 뒤 699틱에 멸종)와 진행 한도
const EXTINCT_PRESET := "default"
const EXTINCT_SETS := {"resources.scale": 0.5}
const EXTINCT_MAX_TICKS := 5000

var _out := "res://docs/screenshots/v0.1"
var _seed := SEED
var _ticks := TICKS
var _extra := false


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a.begins_with("--ticks="):
			_ticks = int(a.substr(8))
		elif a == "--extra":
			_extra = true
	DirAccess.make_dir_recursive_absolute(_out)
	var r := Experiment.create(PRESET, SETS, _seed)
	var x: Experiment = r.experiment
	if x == null:
		printerr("실험을 만들 수 없음: " + str(r.error))
		quit(1)
		return
	x.step_n(_ticks)
	var counts := {}
	for e: Dictionary in x.world.chronicle:
		counts[e.kind] = int(counts.get(e.kind, 0)) + 1
	print("틱 %d · 연대기 %d개 %s" % [x.world.tick, x.world.chronicle.size(), counts])

	var bg := ColorRect.new()
	bg.color = UiConfig.color("theme.background")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var w := UiConfig.num("chronicle.width")
	var h := UiConfig.num("lab.bottom_panel_height")
	var left := _dock(Vector2(MARGIN, MARGIN), w, h)
	var right := _dock(Vector2(MARGIN * 2 + left.dock.size.x, MARGIN), w, TALL)
	for p: ChroniclePanel in [left.panel, right.panel]:
		p.set_experiments([x])
	await _frames(3)
	# 왼쪽: 행위자가 있는 줄(첫 밭)을 누른 상태
	var pl: ChroniclePanel = left.panel
	for i in pl.item_count():
		if int(pl.item(i).actor) >= 0:
			pl.activate_item(i)
			pl.scroll_to_item(i)
			break
	await _frames(3)
	print("왼쪽 맨 위 줄: %s" % pl.item_text(0))
	_shot(Rect2i(0, 0, int(right.dock.position.x + right.dock.size.x) + MARGIN, TALL + MARGIN * 2), "chronicle.png")
	if not _extra:
		quit(0)
		return
	left.dock.queue_free()
	right.dock.queue_free()
	# A/B: 같은 예설정의 씨앗 1·2
	var r2 := Experiment.create(PRESET, SETS, _seed + 1)
	var y: Experiment = r2.experiment
	y.step_n(_ticks)
	x.tag = "A"
	y.tag = "B"
	var cmp := _dock(Vector2(MARGIN, MARGIN), w, TALL)
	(cmp.panel as ChroniclePanel).set_experiments([x, y])
	await _frames(3)
	_shot(_rect(cmp), "chronicle-compare.png")
	(cmp.panel as ChroniclePanel).set_filter(ChroniclePanel.FILTER_BUILD)
	await _frames(3)
	_shot(_rect(cmp), "chronicle-filter.png")
	(cmp.panel as ChroniclePanel).set_filter(ChroniclePanel.FILTER_FARM_LOST)
	await _frames(3)
	_shot(_rect(cmp), "chronicle-filter-farm.png")
	cmp.dock.queue_free()
	x.tag = ""
	var lim := _dock(Vector2(MARGIN, MARGIN), w, h)
	var pk: ChroniclePanel = lim.panel
	pk.max_items = LIMIT_ITEMS
	pk.set_experiments([x])
	await _frames(3)
	var list := pk.list_control()
	var bar := list.get_parent().get_node("Scroll") as VScrollBar
	bar.value = bar.max_value
	await _frames(3)
	_shot(_rect(lim), "chronicle-limit.png")
	lim.dock.queue_free()
	var empty := _dock(Vector2(MARGIN, MARGIN), w, h)
	var r3 := Experiment.create(PRESET, SETS, _seed)
	(empty.panel as ChroniclePanel).set_experiments([r3.experiment])
	await _frames(3)
	_shot(_rect(empty), "chronicle-empty.png")
	empty.dock.queue_free()
	# 멸종: 번식한 뒤 사라진 세계 — 멸종 줄의 평균 세대가 마지막 개체군의 것(0.00 이 아님)
	var r4 := Experiment.create(EXTINCT_PRESET, EXTINCT_SETS, _seed)
	var z: Experiment = r4.experiment
	var guard := 0
	while z != null and not z.world.is_extinct() and guard < EXTINCT_MAX_TICKS:
		z.step()
		guard += 1
	var ext := _dock(Vector2(MARGIN, MARGIN), w, h)
	(ext.panel as ChroniclePanel).set_experiments([z])
	await _frames(3)
	print("멸종 줄: %s" % (ext.panel as ChroniclePanel).item_text(0))
	_shot(_rect(ext), "chronicle-extinct.png")
	quit(0)


## 실험실 아래 자리와 같은 바탕(DockPanel, 안쪽 여백 theme.panel_padding) 안에 연대기 창 하나. 높이 h = 자리 전체 높이.
func _dock(pos: Vector2, w: float, h: float) -> Dictionary:
	var dock := PanelContainer.new()
	dock.theme = UiTheme.build()
	dock.theme_type_variation = UiTheme.DOCK
	var pad := UiConfig.num("theme.panel_padding")
	dock.position = pos
	dock.size = Vector2(w + 2.0 * pad, h)
	root.add_child(dock)
	var p := ChroniclePanel.new()
	dock.add_child(p)
	return {dock = dock, panel = p}


func _rect(d: Dictionary) -> Rect2i:
	var dock: Control = d.dock
	return Rect2i(0, 0, int(dock.position.x + dock.size.x) + MARGIN, int(dock.position.y + dock.size.y) + MARGIN)


func _shot(r: Rect2i, name: String) -> void:
	var img := root.get_texture().get_image()
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	var path := _out.path_join(name)
	var err := crop.save_png(path)
	var kb := FileAccess.get_file_as_bytes(path).size() / 1024
	print("저장 %s (%dx%d, %dKB) %s" % [path, crop.get_width(), crop.get_height(), kb, "" if err == OK else "실패 %d" % err])
