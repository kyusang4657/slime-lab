extends SceneTree
## 그래프 패널 캡처(가상 디스플레이, 픽셀 확인용):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/graph_capture.gd -- --out=폴더
## 실험실 아래 자리와 같은 바탕(DockPanel) 위에 GraphPanel 만 띄워, 1600×260 과 1000×220 두 크기를 위아래로 붙여 찍는다.
##   graphs-single.png   시연용(demo_fast)·씨앗 1 을 TICKS 틱. 위: 출생·사망 켬 + 개체 수 그래프에 마우스 값,
##                       아래: 가로축 평균 세대 + 평균 에너지 + 시점 표시(채집 발견 틱)
##   graphs-compare.png  A 기본 · B 시연용(씨앗 1, 각 TICKS 틱). 위: 기술 단계 그래프에 마우스 값, 아래: 가로축 평균 세대 +
##                       출생·사망 + B 의 농사 발견 시점(실험마다 자기 세대에) + 개체 수 그래프 오른쪽(A 가 이르지 못한 세대)에 마우스 값
## --extra 를 주면 참고용도 찍는다(문서에는 넣지 않음): graphs-1280.png(1280×720 창의 아래 자리 폭 ≈ 834, 비교),
##   graphs-edge.png(멸종한 자원 없음 세계 + 평균 특성에 마우스 값 / 줄 하나뿐인 새 실험 / 실험 없음)
## 인자: --out=폴더(기본 res://docs/screenshots/v0.1), --ticks=N, --seed=N, --copy=폴더(그림을 그곳에도 복사), --extra
## LabMain 없이 실험을 직접 만들어 GraphPanel.load_experiments 로 넘긴다(비교 모드 이름표 A/B 도 LabMain 처럼 붙임).

const TICKS := 2500
const SEED := 1
## 그림 둘레·두 크기 사이 배경 폭(픽셀)
const MARGIN := 16
const BIG := Vector2i(1600, 260)
const SMALL := Vector2i(1000, 220)
## 마우스 값을 보일 가로 위치(그림 영역 폭에 대한 비)
const HOVER_FRAC_SINGLE := 0.66
const HOVER_FRAC_COMPARE := 0.55
const HOVER_FRAC_GEN := 0.9
const MAX_BYTES := 250 * 1024

var _out := "res://docs/screenshots/v0.1"
var _copy := ""
var _ticks := TICKS
var _seed := SEED
var _extra := false
var _vp: SubViewport
var _wrap: PanelContainer
var _panel: GraphPanel
var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--copy="):
			_copy = a.substr(7)
		elif a.begins_with("--ticks="):
			_ticks = int(a.substr(8))
		elif a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a == "--extra":
			_extra = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	# 창 크기와 무관하게 찍으려고 따로 그리는 SubViewport(테마 배경 + 아래 자리와 같은 DockPanel)
	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	_vp.size = BIG + Vector2i(MARGIN, MARGIN) * 2
	root.add_child(_vp)
	var bg := ColorRect.new()
	bg.color = UiTheme.color("background")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(bg)
	_wrap = PanelContainer.new()
	_wrap.theme = UiTheme.build()
	_wrap.theme_type_variation = UiTheme.DOCK
	_vp.add_child(_wrap)
	_panel = GraphPanel.new()
	_wrap.add_child(_panel)

	# ── 혼자: 시연용 ──
	var a := _make("demo_fast", _seed, "")
	a.step_n(_ticks)
	print("혼자: %s, 기록 %d줄, 단계 %d, 발견 %s" % [a.label, a.rows().size(), a.world.stage, str(a.world.discovery_tick)])
	_panel.load_experiments([a])
	_panel.set_show_flows(true)
	var top := await _grab(BIG, 0, HOVER_FRAC_SINGLE)
	_panel.set_show_flows(false)
	_panel.set_x_axis(GraphPanel.X_GEN)
	_panel.set_trait(GraphPanel.TRAIT_COLS.find(GraphPanel.C_ENERGY))
	_panel.set_cursor_tick(a.world.discovery_tick[SimWorld.STAGE_STORE])
	var bottom := await _grab(SMALL, -1, 0.0)
	_save(_stack(top, bottom), "graphs-single.png")

	# ── 비교: A 기본 · B 시연용 ──
	var xa := _make("default", _seed, "A")
	var xb := _make("demo_fast", _seed, "B")
	xa.step_n(_ticks)
	xb.step_n(_ticks)
	print("비교: %s / %s" % [xa.display_name(), xb.display_name()])
	_panel.set_x_axis(GraphPanel.X_TICK)
	_panel.set_trait(0)
	_panel.load_experiments([xa, xb])
	var ctop := await _grab(BIG, GraphPanel.GRAPH_CIV, HOVER_FRAC_COMPARE)
	# 아래: 세대 축 + B 의 농사 발견 시점(실험마다 자기 세대에 세로선) + A 가 이르지 못한 세대에 마우스 값
	_panel.set_x_axis(GraphPanel.X_GEN)
	_panel.set_show_flows(true)
	_panel.set_cursor_tick(xb.world.discovery_tick[SimWorld.STAGE_FARM])
	var cbottom := await _grab(SMALL, GraphPanel.GRAPH_POP, HOVER_FRAC_GEN)
	_panel.set_show_flows(false)
	_panel.set_x_axis(GraphPanel.X_TICK)
	_save(_stack(ctop, cbottom), "graphs-compare.png")
	if _extra:
		await _extras(xa, xb)
	print("RESULT: %d failed (graph capture)" % _fails)
	quit(1 if _fails > 0 else 0)


## 참고용: 1280 창 폭, 멸종·줄 하나·실험 없음
func _extras(xa: Experiment, xb: Experiment) -> void:
	var narrow := Vector2i(UiConfig.integer("lab.min_width") - UiConfig.integer("chronicle.width") - 26, UiConfig.integer("lab.bottom_panel_height"))
	_panel.load_experiments([xa, xb])
	_panel.set_show_flows(true)
	var n1 := await _grab(narrow, GraphPanel.GRAPH_POP, 0.4)
	_panel.set_show_flows(false)
	_panel.set_x_axis(GraphPanel.X_GEN)
	var n2 := await _grab(narrow, GraphPanel.GRAPH_CIV, 0.8)
	_panel.set_x_axis(GraphPanel.X_TICK)
	_save(_stack(n1, n2), "graphs-1280.png")
	var dead := _make("no_resources", _seed, "")
	var guard := 0
	while dead.world.extinct_tick < 0 and guard < 5000:
		dead.step()
		guard += 1
	# 멸종한 틱의 기록 줄(개체 수 0)은 Experiment.step() 이 쓴다(4단계 검토 G03) — 멸종 표시를 위해 더 돌리지 않음
	print("멸종: 틱 %d, 기록 %d줄" % [dead.world.extinct_tick, dead.rows().size()])
	_panel.load_experiments([dead])
	var e1 := await _grab(SMALL, GraphPanel.GRAPH_TRAIT, 0.97)
	_panel.load_experiments([_make("default", _seed, "")])
	var e2 := await _grab(SMALL, GraphPanel.GRAPH_POP, 0.5)
	_panel.load_experiments([])
	var e3 := await _grab(SMALL, -1, 0.0)
	_save(_stack(_stack(e1, e2), e3), "graphs-edge.png")


func _make(preset: String, seed_value: int, tag: String) -> Experiment:
	var r := Experiment.create(preset, {}, seed_value)
	var x: Experiment = r.experiment
	x.tag = tag
	return x


## 패널을 size 로 놓고(그림 왼쪽 위 MARGIN), hover_graph 번째 그래프의 hover_frac 자리에 마우스 값을 보인 뒤 그 영역을 잘라 온다.
func _grab(sz: Vector2i, hover_graph: int, hover_frac: float) -> Image:
	_vp.size = sz + Vector2i(MARGIN, MARGIN) * 2
	_wrap.position = Vector2(MARGIN, MARGIN)
	_wrap.size = Vector2(sz)
	_panel.clear_hover()
	await _frames(3)
	if hover_graph >= 0:
		var v := _panel.view(hover_graph)
		v.layout_now()
		v.hover_at(Vector2(v.plot.position.x + v.plot.size.x * hover_frac, v.plot.get_center().y))
	await _frames(3)
	var img := _vp.get_texture().get_image()
	if img.get_size() != sz + Vector2i(MARGIN, MARGIN) * 2 or _wrap.size != Vector2(sz):
		printerr("크기가 다름: 그림 %s, 패널 %s(최소 크기보다 작게 놓았나?)" % [str(img.get_size()), str(_wrap.size)])
		_fails += 1
	return img


## 두 그림을 위아래로(배경색 바탕, 왼쪽 정렬)
func _stack(a: Image, b: Image) -> Image:
	var w := maxi(a.get_width(), b.get_width())
	var out := Image.create(w, a.get_height() + b.get_height(), false, a.get_format())
	out.fill(UiTheme.color("background"))
	out.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
	out.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(0, a.get_height()))
	return out


func _save(img: Image, name: String) -> void:
	img.convert(Image.FORMAT_RGB8)
	var path := _out.path_join(name)
	var err := img.save_png(path)
	var bytes := FileAccess.get_file_as_bytes(path).size()
	print("저장 %s (%dx%d, %d KB) %s" % [path, img.get_width(), img.get_height(), bytes / 1024, "" if err == OK else "실패 %d" % err])
	if err != OK or bytes > MAX_BYTES:
		printerr("그림 저장 실패 또는 %d KB 넘음: %s" % [MAX_BYTES / 1024, name])
		_fails += 1
	if _copy != "":
		DirAccess.make_dir_recursive_absolute(_copy)
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), _copy.path_join(name))
