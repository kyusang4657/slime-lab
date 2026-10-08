extends SceneTree
## 파라미터 패널 캡처(가상 디스플레이, 픽셀 확인용):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/param_capture.gd -- --out=폴더
## 실험실(LabMain)을 숨겨 띄워 패널을 붙이고, 패널만 실제 폭(lab.left_panel_width)·실제 높이(창 높이 − 위쪽 막대 −
## 아래 자리)로 테마 배경 위에 그려 세 장면을 나란히 한 장으로 찍는다:
##   ① 혼자 · 값을 바꿈(강조 띠·"바꾼 값 N개")  ② 비교 모드(A·B 칸)  ③ 고급 설정 펼침(바꾼 값 강조·칸 아래 오류)
## param-panel.png(세 장면, 250KB 이하 확인). --extra 를 주면 장면별 그림과 1280×720 높이 그림도 찍는다.
## 인자: --out=폴더(기본 res://docs/screenshots/v0.1), --extra

## 장면 사이·둘레 배경 폭(픽셀)
const MARGIN := 16
## 1280×720 화면의 창 높이(참고 그림)
const SHORT_HEIGHT := 720
const SIZE_LIMIT := 250 * 1024

var _out := "res://docs/screenshots/v0.1"
var _extra := false
var _frame: PanelContainer
var _panel: ParamPanel
var _lab: LabMain


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--extra":
			_extra = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	# 실험실은 숨겨 둔다(패널이 붙을 실험·알림만 씀). 지도는 그리지 않음
	_lab = load("res://scenes/lab.tscn").instantiate()
	root.add_child(_lab)
	await _frames(1)
	_lab.set_process(false)
	_lab.visible = false
	var bg := ColorRect.new()
	bg.color = UiTheme.color("background")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# 실험실 왼쪽 자리와 같은 감싸개(DockPanel, 폭 lab.left_panel_width)
	_frame = PanelContainer.new()
	_frame.theme = UiTheme.build()
	_frame.theme_type_variation = UiTheme.DOCK
	root.add_child(_frame)
	_panel = _find_panel()
	if _panel == null:
		_panel = ParamPanel.new()
		_panel.bind_lab(_lab)
	elif _panel.get_parent() != null:
		_panel.get_parent().remove_child(_panel)
	_frame.add_child(_panel)
	var h := _dock_height(float(root.size.y))
	var shots: Array[Image] = []
	# ① 혼자 · 값을 바꿈
	_panel.set_value("mutation.rate", 0.08)
	_panel.set_value("seed", 7)
	shots.append(await _shot(h, "param-single.png"))
	if _extra:
		await _shot(_dock_height(SHORT_HEIGHT), "param-single-720.png")
	# ② 비교 모드: B 는 자원량만 다르게
	_panel.set_value("mutation.rate", 0.05)
	_panel.set_value("seed", 1)
	_panel.set_compare_mode(true)
	_panel.set_value("resources.scale", 1.6, 1)
	shots.append(await _shot(h, "param-compare.png"))
	if _extra:
		await _shot(_dock_height(SHORT_HEIGHT), "param-compare-720.png")
	# ③ 고급 설정: B 칸의 값을 몇 개 바꾸고 하나는 범위 밖(칸 아래 오류)
	_panel.set_advanced_open(true)
	_panel.set_advanced_target(1)
	_panel.set_value("map.width", 96, 1)
	_panel.set_value("time.day_ticks", 1, 1)
	_panel.set_value("plants.regrow", 0.15, 1)
	await _frames(3)
	var sc := _panel.control("scroll") as ScrollContainer
	var head := _panel.control("advanced") as Control
	sc.scroll_vertical = int(head.get_global_rect().position.y - (sc.get_global_rect().position.y)) + sc.scroll_vertical - 4
	shots.append(await _shot(h, "param-advanced.png", false))
	# 세 장면을 한 장으로
	var w := 0
	for im in shots:
		w += im.get_width()
	var out := Image.create(w + MARGIN * (shots.size() - 1), shots[0].get_height(), false, Image.FORMAT_RGB8)
	out.fill(UiTheme.color("background"))
	var x := 0
	for im in shots:
		im.convert(Image.FORMAT_RGB8)
		out.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, 0))
		x += im.get_width() + MARGIN
	var path := ProjectSettings.globalize_path(_out.path_join("param-panel.png"))
	var err := out.save_png(path)
	var bytes := FileAccess.get_file_as_bytes(path).size()
	print("저장 %s (%dx%d, %d KB) %s" % [path, out.get_width(), out.get_height(), bytes / 1024, "" if err == OK else "실패 %d" % err])
	if bytes > SIZE_LIMIT:
		printerr("그림이 %d KB 로 250KB 를 넘습니다" % (bytes / 1024))
	print("상태 줄: %s" % _panel.status_text())
	quit(0)


## 실험실 4단계 자리 채우기(통합 뒤)로 이미 붙은 패널이 있으면 그것을 쓴다.
func _find_panel() -> ParamPanel:
	for ch in _lab.left_dock.get_children():
		if ch is ParamPanel:
			return ch as ParamPanel
	return null


## 창 높이에서 위쪽 막대·아래 자리를 뺀 왼쪽 자리 높이.
func _dock_height(win_h: float) -> float:
	return win_h - UiConfig.num("lab.top_bar_min_height") - UiConfig.num("lab.bottom_panel_height")


## 패널을 (MARGIN, 0) 에 폭 lab.left_panel_width × 높이 h 로 놓고 찍는다. reset_scroll 이면 맨 위로.
func _shot(h: float, name: String, reset_scroll: bool = true) -> Image:
	_frame.position = Vector2(MARGIN, 0)
	_frame.size = Vector2(UiConfig.num("lab.left_panel_width"), h)
	if reset_scroll:
		await _frames(2)
		(_panel.control("scroll") as ScrollContainer).scroll_vertical = 0
	await _frames(4)
	var img := root.get_texture().get_image()
	var r := Rect2i(0, 0, int(_frame.size.x) + MARGIN * 2, int(h))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	if _extra:
		var p := ProjectSettings.globalize_path(_out.path_join(name))
		crop.save_png(p)
		print("저장 %s (%dx%d)" % [p, crop.get_width(), crop.get_height()])
	return crop
