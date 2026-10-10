extends RefCounted
## LabMain 검사: 장면·배치·테마, 프레임 진행(배속·멈춤·빨리 감기·예산), 선택 연결, 단축키, 사건 알림,
## 역사 해시(화면을 거쳐도 헤드리스와 같음), 명령줄 대체값, 스냅숏 열기. 프레임은 advance_frame 으로 직접 몬다.
## 4단계: 패널 자리 채우기·자리 접기, 비교 모드(지도 둘·같은 틱 진행·해시·기록·사건·알림 이름표·선택·멸종·끝내기).

const DT := 1.0 / 60.0
## 빨리 감기 측정 세계의 초기 개체 수(씨앗 3 에서 120프레임 내내 살아 있음)
const FF_POPULATION := 60
## 이 모듈이 적어도 하는 검사 수(중간에 스크립트 오류로 끊기면 실행기가 실패로 셈)
const MIN_CHECKS := 287
## 비교 모드 B 에만 준 바꾼 값(B 의 설정에만 들어가야 함)
const B_MUTATION := 0.07
## 최소 창(lab.min_width × lab.min_height = 1280×640)·자리 모두 펼침에서 비교 모드 지도 한 칸의 최소 크기,
## 그리고 1280×720 창에서(검토 J29 전의 최소 창 — 그 크기의 배치 검사도 그대로)
const MIN_COMPARE_MAP := Vector2(320, 360)
const MIN_COMPARE_MAP_720 := Vector2(320, 400)
const SIZE_720 := Vector2i(1280, 720)
## 화면 배율 검사의 창 장식(왼쪽·위, 오른쪽·아래)과 768 높이 노트북의 작업 영역(아래 작업 표시줄 40)
const DECO_TL := Vector2i(8, 32)
const DECO_BR := Vector2i(8, 8)
const LAPTOP_USABLE := Rect2i(0, 0, 1366, 728)
## 그 칸(세로로 긴 칸)에서 지도가 차지하는 칸 높이 몫의 하한(돌려 맞춤 — 북쪽 위 그대로면 약 0.39)
const MIN_COMPARE_HEIGHT_SHARE := 0.55
## 예산 측정 프레임 수. 실제 시계로 잰 시간은 기계 속도에 묶이므로 "예산 + 이 기계의 틱 둘" 안인지만 보고(예산을 무시하고
## 요청한 틱을 모두 돌면 넘음), 예산 규칙 자체는 가짜 시계로 결정적으로 잰다(_budget_rule — 검토 I34)
const BUDGET_FRAMES := 60
const BUDGET_TICK_SLACK := 2.0
## 한 프레임 실제 시간의 멈칫 여유(ms — OS 가 잠시 다른 일을 해도)
const HICCUP_MS := 30.0
## 가짜 시계의 한 틱 비용(ms): [보통 배속인가, 비용]. 예산(10ms·빨리 감기 14ms)보다 싼 틱(여러 틱)과 비싼 틱(적어도 1틱),
## 예산을 나누어떨어뜨리지 않는 값(경계에서 소수 오차가 끼지 않게)
const FAKE_TICK_CASES := [[true, 3.0], [true, 15.0], [false, 3.0], [false, 20.0]]
const FAKE_FRAMES := 10
## 예산보다 훨씬 싼 틱(ms): 64배(프레임당 6.4틱)는 예산에 걸리지 않고 빨리 감기는 예산을 다 써 더 많이 돎
const CHEAP_TICK_MS := 1.0
## 16배(프레임당 1.6틱)에서 혼자 있는 개체가 한 프레임에 그려지는 거리 상한(칸): 1.6틱 × smoothstep 기울기 여유
const MULTI_TICK_MAX_STEP := 1.9
## 실제 시계 예산을 끈 셈의 값(ms) — 결정적으로 재야 하는 검사 동안
const BUDGET_OFF_MS := 1.0e9
## 이 검사가 쓰는 파일(스냅숏·백업·비교·내려받기)은 프로세스별 임시 폴더에(검토 I37: 예전엔 PID 없는 고정 이름
## user://lab_checks_snapshot.json 등과 실제 user://downloads 를 써, 같은 사용자 폴더를 쓰는 저장소 사본끼리 서로의 파일을
## 지울 수 있었음). 처음과 끝에 숨은 파일까지 지운다.
var TMP := "user://lab_checks-%d" % OS.get_process_id()
var SNAP_PATH := TMP.path_join("snapshot.json")
## 실제 _process 경로의 느린 프레임: 형제 노드가 프레임마다 잡아먹는 시간(ms — 엔진이 delta 를 자르는 8/60초보다 훨씬 김)과
## 잴 프레임 수, 실제 배속(틱 ÷ 벽시계)과 표시가 어긋나도 되는 몫
const SLOW_FRAME_MS := 400
const SLOW_FRAMES := 7
const SLOW_SPEED_TOL := 0.15
## 죽은 개체 기록이 생길 때까지 진행하는 한도와 한 번에 진행하는 틱
const DEAD_GUARD_TICKS := 3000
const DEAD_STEP := 20


func run(t) -> void:
	# 헤드리스 뿌리 창은 64×64 — 배치를 재는 검사를 위해 최소 창 크기로(끝나면 되돌림)
	var root_size: Vector2i = t.root.size
	t.root.size = Vector2i(UiConfig.integer("lab.min_width"), UiConfig.integer("lab.min_height"))
	LabMain._remove_tree(ProjectSettings.globalize_path(TMP))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(2)
	lab.set_process(false)
	lab.download_dir = TMP.path_join("downloads")
	await _layout(t, lab)
	await _screen_fit(t, lab)
	_night_threshold(t)
	_run_loop(t, lab)
	_budget(t, lab)
	_ff_pause(t, lab)
	_multi_tick_motion(t, lab)
	_speed_window(t, lab)
	await _slow_process(t, lab)
	_selection(t, lab)
	await _keys(t, lab)
	await _command_keys(t, lab)
	_events(t, lab)
	await _toast_rules(t, lab)
	_extinction(t, lab)
	_hash(t, lab)
	_args(t, lab)
	await _wide_brain(t, lab)
	await _docks(t, lab)
	await _compare(t, lab)
	_compare_select(t, lab)
	await _compare_stop(t, lab)
	_compare_extinction(t, lab)
	await _compare_layout(t, lab)
	_export_fail(t, lab)
	await _dock_empty(t, lab)
	lab.queue_free()
	await t.frames(1)
	t.root.size = root_size
	LabMain._remove_tree(ProjectSettings.globalize_path(TMP))
	t.check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TMP)), "검사 파일을 둔 프로세스별 임시 폴더를 끝에 지움(%s)" % TMP)


func _layout(t, lab: LabMain) -> void:
	t.check(lab.world != null and lab.map_view != null and lab.info_panel != null, "장면이 만들어지고 기본 실험이 열림")
	t.check(lab.world.seed_value == UiConfig.integer("lab.default_seed"), "기본 씨앗으로 시작")
	t.check(lab.theme != null and lab.theme.default_font != null and lab.theme.has_stylebox("pressed", "Button"), "UiTheme 적용(글꼴·단추 모양)")
	t.check(lab.theme.get_font("font", UiTheme.TITLE) == UiTheme.bold_font(), "제목 글꼴 = 나눔고딕 굵게")
	var sv := lab.map_view.get_parent()
	t.check(sv is SubViewport and sv.get_parent() is SubViewportContainer and (sv.get_parent() as SubViewportContainer).stretch, "지도는 늘어나는 SubViewportContainer 안 SubViewport")
	t.check(lab.left_dock is VBoxContainer and lab.bottom_dock is HBoxContainer, "4단계 자리 종류")
	# 4단계 패널 자리 채우기(뼈대든 실제든 노드 이름·종류로 확인)
	var pp := lab.left_dock.get_node_or_null("ParamPanel")
	var gp := lab.bottom_dock.get_node_or_null("GraphPanel")
	var cp := lab.bottom_dock.get_node_or_null("ChroniclePanel")
	var snd := lab.get_node_or_null("LabSound")
	t.check(pp is ParamPanel and pp == lab.param_panel, "ParamPanel → 왼쪽 자리")
	t.check(gp is GraphPanel and gp == lab.graph_panel and cp is ChroniclePanel and cp == lab.chronicle_panel and gp.get_index() < cp.get_index(),
			"GraphPanel(왼쪽)·ChroniclePanel(오른쪽) → 아래 자리")
	t.check(snd is LabSound and snd == lab.lab_sound, "LabSound → 실험실 자식")
	t.check(snd != null and lab.events_tagged.is_connected((snd as LabSound)._on_events), "실험실의 LabSound 가 events_tagged 에 붙음(bind_lab)")
	t.check(lab._left_toggle.text == "실험 조건" and lab.left_dock.get_node_or_null("ParamPanel") != null,
			"왼쪽 자리 접기 단추 이름 = 그 패널 제목 \"%s\"" % lab._left_toggle.text)
	if gp != null and cp != null:
		# 연대기 폭: 넓은 창에서는 chronicle.width, 최소 창에서는 그래프 최소 폭이 들어가게 줄임(min_width 아래로는 안 줄임)
		var cw := (cp as Control).custom_minimum_size.x
		t.check((gp as Control).size_flags_horizontal & Control.SIZE_EXPAND != 0 and cw >= UiConfig.num("chronicle.min_width")
				and cw <= UiConfig.num("chronicle.width") and is_equal_approx((cp as Control).size.x, cw),
				"그래프는 늘어나고 연대기 폭 %.0f ∈ [chronicle.min_width, chronicle.width]" % cw)
		t.check(_fits_window(lab), "최소 창(%s)·자리 모두 펼침: 아래 자리 최소 폭이 넘치지 않고 정보 창이 창 안(오른쪽 끝 %.0f ≤ %.0f)"
				% [str(t.root.size), lab.info_panel.get_global_rect().end.x, lab.size.x])
		t.check(_fits_height(lab), "최소 창(%s): 세로도 창 안(본문 최소 높이 %.0f, 새 실험 단추·아래 자리·정보 창 아래 끝 ≤ %.0f)"
				% [str(t.root.size), (lab.get_node("Column") as Control).get_combined_minimum_size().y, lab.size.y])
		var small: Vector2i = t.root.size
		t.root.size = Vector2i(1600, 900)
		await t.frames(2)
		t.check(is_equal_approx((cp as Control).custom_minimum_size.x, UiConfig.num("chronicle.width")) and _fits_window(lab),
				"1600×900 에서는 연대기 폭 = chronicle.width(%.0f), 창 안" % (cp as Control).custom_minimum_size.x)
		t.root.size = small
		await t.frames(2)
	t.check(lab._left_wrap.visible and lab._bottom_wrap.visible, "패널을 넣은 자리는 보임")
	t.check(is_equal_approx(lab.info_panel.size.y, lab.size.y - lab._top_bar.size.y) and is_equal_approx(lab._bottom_wrap.size.x, lab._left_wrap.size.x + lab._map_area.size.x),
			"정보 창은 아래 자리 옆까지 세로 전체(%.0f), 아래 자리 = 왼쪽 자리 + 지도 폭(%.0f)" % [lab.info_panel.size.y, lab._bottom_wrap.size.x])
	t.check(is_equal_approx(lab.info_panel.custom_minimum_size.x, UiConfig.num("lab.right_panel_width")), "정보 창 폭 = lab.right_panel_width")
	var top_w: float = lab._top_bar.get_combined_minimum_size().x
	t.check(top_w <= UiConfig.num("lab.min_width"), "위쪽 막대 최소 폭 %.0f ≤ 최소 창 폭 %d" % [top_w, UiConfig.integer("lab.min_width")])
	# 가장 긴 표시(큰 틱·빨리 감기 배속·계절 없음)에서도 최소 창 폭 안
	var saved: Array[String] = []
	var labels: Array[Label] = [lab._lbl_tick, lab._lbl_day, lab._lbl_season, lab._lbl_gen, lab._lbl_pop, lab._lbl_stage, lab._lbl_speed]
	var longest: Array[String] = ["1,234,567", "20,577", LabMain.NO_SEASON, "1000.0", "1,000", "농사", "빨리 감기 / 실제 1,234배"]
	for i in labels.size():
		saved.append(labels[i].text)
		labels[i].text = longest[i]
	var long_w: float = lab._top_bar.get_combined_minimum_size().x
	for i in labels.size():
		labels[i].text = saved[i]
	t.check(long_w <= UiConfig.num("lab.min_width"), "가장 긴 상태 글자에서도 위쪽 막대 %.0f ≤ 최소 창 폭" % long_w)
	var all_glyphs := UiTheme.has_glyphs(lab._fast_btn.text) and UiTheme.has_glyphs(lab._paused_badge.text)
	for b in lab._speed_btns:
		all_glyphs = all_glyphs and UiTheme.has_glyphs(b.text)
	t.check(all_glyphs, "위쪽 막대·표지 글자가 모두 나눔고딕에 있음(%s / %s)" % [lab._fast_btn.text, lab._paused_badge.text])
	t.check(not UiTheme.has_glyphs("⏩") and UiTheme.has_glyphs("가▶‖"), "글꼴 글자 확인(⏩ 없음, ▶‖ 있음)")
	t.check(lab._play_btn.icon != null and lab._fast_btn.icon != null, "재생·빨리 감기 아이콘(코드로 그림)")
	var ic := UiTheme.icon(UiTheme.ICON_PLAY, 16).get_image()
	t.check(ic.get_pixel(8, 8).a > 0.9 and ic.get_pixel(1, 1).a < 0.1 and ic.get_pixel(14, 2).a < 0.1, "재생 아이콘 모양(가운데 칠함, 모서리 빔)")
	var ip := UiTheme.icon(UiTheme.ICON_PAUSE, 16).get_image()
	t.check(ip.get_pixel(5, 8).a > 0.9 and ip.get_pixel(8, 8).a < 0.2 and ip.get_pixel(11, 8).a > 0.9, "멈춤 아이콘 모양(막대 둘, 가운데 빔)")
	t.check(lab._speed_btns.size() == (UiConfig.value("speed.steps") as Array).size(), "속도 단추 = speed.steps")
	# 무언가를 더 넣고 빼도 패널이 있는 자리는 그대로 보임(비우면 숨는 것은 끝의 _dock_empty)
	var probe := Label.new()
	probe.text = "시험"
	lab.left_dock.add_child(probe)
	var probe2 := Label.new()
	lab.bottom_dock.add_child(probe2)
	await t.frames(1)
	t.check(lab._left_wrap.visible and lab._bottom_wrap.visible, "자리에 넣으면 보임")
	t.check(is_equal_approx(lab._left_wrap.size.x, UiConfig.num("lab.left_panel_width")) or lab._left_wrap.size.x >= UiConfig.num("lab.left_panel_width"), "왼쪽 자리 폭 ≥ lab.left_panel_width")
	probe.queue_free()
	probe2.queue_free()
	await t.frames(2)
	t.check(lab._left_wrap.visible and lab._bottom_wrap.visible, "더 넣은 것을 빼도 패널이 있는 자리는 보임")


## 화면 크기·배율(검토 J08·J28·J29). 정하는 셈은 순수 함수라 OS 없이: OS 배율(Windows DPI·macOS·웹·Wayland), 창에 맞는
## 배율(논리 크기 = 창 ÷ 배율 ≥ 최소 배치), 데스크톱 첫 창(작업 영역 안으로 줄이고 가운데, 제목 표시줄이 화면 안). 그리고 실제
## 배치: 배율 2(웹 dpr 2·레티나) 창에서 논리 크기가 반, 폭 1024 브라우저에서 배율을 줄여 모두 창 안, 768 높이 노트북의 창에서
## 배율 1 그대로 배치가 들어감.
func _screen_fit(t, lab: LabMain) -> void:
	var lo := UiConfig.num("lab.ui_scale_min")
	var hi := UiConfig.num("lab.ui_scale_max")
	var min_l := LabMain.min_logical()
	t.check(is_equal_approx(LabMain.os_scale_of("Windows", "Windows", 1.0, 144), 1.5) and is_equal_approx(LabMain.os_scale_of("Windows", "Windows", 1.0, 0), 1.0)
			and is_equal_approx(LabMain.os_scale_of("macOS", "macOS", 2.0, 220), 2.0) and is_equal_approx(LabMain.os_scale_of("Web", "web", 1.5, 144), 1.5)
			and is_equal_approx(LabMain.os_scale_of("Linux", "Wayland", 2.0, 96), 2.0) and is_equal_approx(LabMain.os_scale_of("Linux", "X11", 2.0, 192), 1.0),
			"OS 배율: Windows DPI÷96, macOS·웹·Wayland 화면 배율, X11 1")
	t.check(is_equal_approx(LabMain.ui_scale_for(Vector2(2732, 1536), 2.0, min_l, lo, hi), 2.0)
			and is_equal_approx(LabMain.ui_scale_for(Vector2(1024, 700), 1.0, min_l, lo, hi), 1024.0 / min_l.x)
			and is_equal_approx(LabMain.ui_scale_for(Vector2(2000, 1000), 2.0, min_l, lo, hi), minf(2000.0 / min_l.x, 1000.0 / min_l.y))
			and is_equal_approx(LabMain.ui_scale_for(Vector2(300, 200), 1.0, min_l, lo, hi), lo)
			and is_equal_approx(LabMain.ui_scale_for(Vector2(20000, 20000), 9.0, min_l, lo, hi), hi),
			"창에 맞는 배율: 바라는 배율 이하, 논리 크기 ≥ 최소 배치(%s), [%.2f, %.2f]" % [str(min_l), lo, hi])
	var start := Vector2(1600, 900)
	# (작업 영역, 바라는 배율, 이름): 768 높이 노트북 · 1920×1080 Windows 150% · 2560×1440 · 둘째 모니터 · 레티나 · 아주 작은 화면
	var cases := [[LAPTOP_USABLE, 1.0, "1366×768"], [Rect2i(0, 0, 1920, 1032), 1.5, "1920×1080 150%"], [Rect2i(0, 0, 2560, 1400), 1.0, "2560×1440"],
			[Rect2i(1920, 0, 1366, 728), 1.0, "둘째 모니터"], [Rect2i(0, 50, 2880, 1610), 2.0, "레티나 1440×900pt"], [Rect2i(0, 0, 800, 560), 1.0, "800×600"]]
	var bad := ""
	for c in cases:
		var u: Rect2i = c[0]
		var p := LabMain.plan_window(u, DECO_TL, DECO_BR, float(c[1]), start, min_l, lo, hi)
		var sz: Vector2i = p.size
		var pos: Vector2i = p.position
		var frame := Rect2i(pos - DECO_TL, sz + DECO_TL + DECO_BR)
		var logical := Vector2(sz) / float(p.scale)
		if not u.encloses(frame) or float(p.scale) > float(c[1]) + 0.001 or logical.x < min_l.x - 1.0 or logical.y < min_l.y - 1.0 \
				or sz.x < int(p.min_size.x) or sz.y < int(p.min_size.y) or logical.x > start.x + 1.0 or logical.y > start.y + 1.0:
			bad += " %s: 창 %s 위치 %s 배율 %.3f" % [str(c[2]), str(sz), str(pos), float(p.scale)]
	t.check(bad == "", "첫 창이 작업 영역 안(제목 표시줄 포함)·논리 크기 ≥ 최소 배치·처음 크기 이하%s" % bad)
	var lap := LabMain.plan_window(LAPTOP_USABLE, DECO_TL, DECO_BR, 1.0, start, min_l, lo, hi)
	t.check(is_equal_approx(float(lap.scale), 1.0) and Vector2i(lap.position) == DECO_TL and int(lap.size.y) == LAPTOP_USABLE.size.y - DECO_TL.y - DECO_BR.y,
			"768 높이 노트북(작업 영역 %s): 배율 1 그대로(최소 배치 높이 %d 가 들어감), 창 %s 가 작업 영역을 채우고 제목 표시줄이 화면 안(위치 %s)"
			% [str(LAPTOP_USABLE.size), int(min_l.y), str(lap.size), str(lap.position)])
	var wide := LabMain.plan_window(Rect2i(0, 0, 2560, 1400), DECO_TL, DECO_BR, 1.0, start, min_l, lo, hi)
	t.check(Vector2(wide.size) == start and Vector2i(wide.position) == Vector2i((2560 - 1616) / 2, (1400 - 940) / 2) + DECO_TL,
			"큰 화면: 처음 크기 %s 그대로 가운데(%s)" % [str(wide.size), str(wide.position)])
	var tiny := LabMain.plan_window(Rect2i(0, 0, 500, 300), DECO_TL, DECO_BR, 1.0, start, min_l, lo, hi)
	t.check(is_equal_approx(float(tiny.scale), lo) and Vector2i(tiny.position) == DECO_TL, "최소 배율로도 넘치는 화면: 왼쪽 위(제목 표시줄이 화면 안) %s" % str(tiny.position))
	# 실제 배치: 창(뿌리) 크기·배율을 바꿔 잼(헤드리스는 OS 창이 없어 뿌리 창으로)
	var keep: Vector2i = t.root.size
	# (창, OS 배율, 이름, 기대 배율)
	var pairs := [[Vector2i(min_l * 2.0), 2.0, "배율 2(레티나·웹 dpr 2) 최소 창", 2.0], [Vector2i(2732, 1536), 2.0, "웹 1366×768 CSS · dpr 2", 2.0],
			[Vector2i(1024, 700), 1.0, "웹 1024×700(폭 1280 아래)", 1024.0 / min_l.x], [Vector2i(1350, 688), 1.0, "768 높이 노트북 창", 1.0]]
	for c in pairs:
		t.root.size = c[0]
		var s := lab.fit_to_window(float(c[1]))
		await t.frames(2)
		var want := Vector2(c[0]) / s
		t.check(is_equal_approx(s, float(c[3])) and is_equal_approx(lab.ui_scale(), s) and is_equal_approx(t.root.content_scale_factor, s) and lab.size.is_equal_approx(want)
				and lab.size.x >= min_l.x - 0.5 and lab.size.y >= min_l.y - 0.5 and _fits_window(lab) and _fits_height(lab),
				"%s: 창 %s · 배율 %.3f → 논리 %s 에 배치가 모두 들어감" % [str(c[2]), str(c[0]), s, str(lab.size)])
	lab.set_ui_scale(1.0)
	t.root.size = keep
	await t.frames(2)
	t.check(is_equal_approx(t.root.content_scale_factor, 1.0) and lab.size.is_equal_approx(Vector2(keep)), "배율 1·최소 창으로 되돌림")


## 세로도 창 안: 본문 최소 높이 ≤ 창, 아래 자리·정보 창 아래 끝 ≤ 창 아래 끝, 패널의 주요 단추(새 실험·나란히 시작)가 창 안.
func _fits_height(lab: LabMain) -> bool:
	var col := lab.get_node("Column") as Control
	var bottom := lab.get_global_rect().end.y + 0.5
	var main_btn := lab.param_panel.control("start_compare" if lab.is_comparing() else "apply") as Control
	return col.get_combined_minimum_size().y <= lab.size.y + 0.5 and lab._bottom_wrap.get_global_rect().end.y <= bottom \
			and lab.info_panel.get_global_rect().end.y <= bottom and (main_btn == null or main_btn.get_global_rect().end.y <= bottom)


## 낮/밤 문턱은 규칙의 밤 판정과 같은 설정 키 time.night_light_threshold(그 세계의 cfg)이고, 화면에서는 한 곳
## (LabMain.is_night)만 읽는다(검토 I77: 예전엔 화면 설정 lab.day_light_threshold 를 따로 읽어, 규칙의 문턱을 바꾸면
## 위쪽 막대 표시와 규칙이 갈라졌음). 화면 쪽 파일(scripts/ui·scripts/view·tests/view·tests 바로 아래의 캡처·ui_driver —
## 규칙 검사 run_tests.gd 와 이 검사 파일은 빼고)을 훑고, 문턱을 바꾼 세계에서 is_night 가 그 문턱을 따르는지 본다.
func _night_threshold(t) -> void:
	var key := "night_light_threshold"
	var hits: Array[String] = []
	for dir in ["res://scripts/ui", "res://scripts/view", "res://tests/view"]:
		_grep(dir, key, hits, true)
	_grep("res://tests", key, hits, false)
	t.check(hits.size() == 1 and hits[0] == "res://scripts/ui/lab_main.gd", "화면에서 밤 문턱(%s)을 읽는 곳은 LabMain.is_night 하나: %s" % [key, str(hits)])
	t.check(not UiConfig.section("lab").has("day_light_threshold"), "화면 설정에 따로 둔 낮/밤 문턱(lab.day_light_threshold)이 없음")
	# 문턱 0.9: 빛이 0.5~0.9 인 틱은 밤(예전 화면 문턱 0.5 로는 낮)
	var w: SimWorld = t.make_world({"time.night_light_threshold": 0.9})
	var seen := {}
	var follows := w != null
	for i in (int(w.cfg.time.day_ticks) if w != null else 0):
		if LabMain.is_night(w) != (w.light < 0.9):
			follows = false
		if w.light >= 0.5 and w.light < 0.9:
			seen.between = true
		w.step()
	t.check(follows and seen.has("between"), "is_night 는 세계 설정의 밤 문턱(0.9)을 따름 — 빛 0.5~0.9 도 밤(%s)" % str(seen.has("between")))


## dir 아래 .gd 가운데 needle 을 담은 파일(규칙 검사 run_tests.gd·이 검사 파일은 뺌). deep = 하위 폴더까지.
static func _grep(dir: String, needle: String, hits: Array[String], deep: bool) -> void:
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		if f.ends_with(".gd") and not path in ["res://tests/view/lab_checks.gd", "res://tests/run_tests.gd"] \
				and FileAccess.get_file_as_string(path).count(needle) > 0:
			hits.append(path)
	if deep:
		for d in DirAccess.get_directories_at(dir):
			_grep(dir.path_join(d), needle, hits, deep)


func _run_loop(t, lab: LabMain) -> void:
	var tps := UiConfig.num("speed.ticks_per_second_1x")
	lab.set_paused(false)
	lab.set_speed(4)
	var counter := {ticked = 0}
	var cb := func(_w: SimWorld) -> void: counter.ticked += 1
	lab.ticked.connect(cb)
	var t0 := lab.world.tick
	for i in 60:
		lab.advance_frame(DT)
	var adv := lab.world.tick - t0
	t.check(absf(float(adv) - 4.0 * tps) <= 1.0, "4배·60프레임(1초) → %d틱(기대 %.0f±1)" % [adv, 4.0 * tps])
	t.check(int(counter.ticked) > 0 and int(counter.ticked) <= adv, "ticked 신호(%d번)" % int(counter.ticked))
	lab.ticked.disconnect(cb)
	t.check(absf(lab.actual_speed() - 4.0) <= 0.35, "실제 배속 ≈ 4 (%.2f)" % lab.actual_speed())
	t.check(lab._lbl_speed.text.begins_with("목표 4배 / 실제"), "배속 표시: " + lab._lbl_speed.text)
	t.check(lab._lbl_tick.text == LabMain._commas(lab.world.tick), "틱 표시: " + lab._lbl_tick.text)
	t.check(lab._lbl_stage.text == SimWorld.STAGE_NAMES[lab.world.stage], "문명 단계 표시: " + lab._lbl_stage.text)
	t.check(LabMain.SEASON_NAMES.has(lab._lbl_season.text) or lab._lbl_season.text == LabMain.NO_SEASON, "계절 표시: " + lab._lbl_season.text)
	t.check(lab._lbl_daynight.text in ["낮", "밤"], "낮/밤 표시: " + lab._lbl_daynight.text)
	# 멈춤
	lab.set_paused(true)
	var tp := lab.world.tick
	for i in 30:
		lab.advance_frame(DT)
	t.check(lab.world.tick == tp, "멈추면 틱이 그대로")
	t.check(lab.speed_text().begins_with("멈춤"), "멈춤 표시: " + lab.speed_text())
	t.check(lab._paused_badge.visible, "지도 위 멈춤 표지")
	t.check(lab.actual_speed() < 4.0 * 0.75, "멈춘 뒤 실제 배속이 내려감(%.2f)" % lab.actual_speed())
	lab.set_paused(false)
	# 빨리 감기: 가벼운 세계에서 64배(프레임당 6.4틱)보다 많이, 예산은 대략 지킴.
	# 세계는 측정 내내 살아 있어야 한다(멸종한 빈 세계의 공짜 틱을 재지 않게 — 아래에서 확인).
	lab.new_experiment("default", {"population.initial": FF_POPULATION}, 3)
	lab.set_speed(64)
	var a := lab.world.tick
	for i in 60:
		lab.advance_frame(DT)
	var n64 := lab.world.tick - a
	lab.set_fast_forward(true)
	t.check(lab.is_fast_forward() and not lab._speed_btns[0].button_pressed and lab._fast_btn.button_pressed, "빨리 감기 단추 켜짐·속도 단추 꺼짐")
	var b := lab.world.tick
	var sum_ms := 0.0
	var max_ms := 0.0
	for i in 60:
		lab.advance_frame(DT)
		sum_ms += lab.last_sim_ms
		max_ms = maxf(max_ms, lab.last_sim_ms)
	var nff := lab.world.tick - b
	var ff := UiConfig.num("speed.fast_forward_budget_ms")
	t.check(lab.world.extinct_tick == -1 and lab.world.population() > 0,
			"빨리 감기 측정 내내 슬라임이 살아 있음(%d마리, 멸종 틱 %d)" % [lab.world.population(), lab.world.extinct_tick])
	# 빨리 감기가 64배보다 더 진행하는지는 기계 속도에 달려(이 세계의 한 틱이 14ms ÷ 6.4 ≈ 2.2ms 를 넘는 기계면 같아짐)
	# 가짜 시계로 잰다(_budget_rule — 검토 I34). 여기서는 출력만
	print("  빨리 감기 %d틱 · 64배 %d틱(같은 60프레임, 실제 시계)" % [nff, n64])
	# 실제 시계: 평균이 "예산 + 이 기계의 틱 둘" 안(기계 속도와 상관없는 꼴 — 검토 I34: 예전엔 평균 ≤ 23ms·최대 ≤ 44ms 라는
	# 실제 시간 단언). 최대는 OS 멈칫에 흔들리므로 출력만, 규칙 자체는 _budget_rule 이 가짜 시계로 잰다
	var ff_tick := sum_ms / maxf(float(nff), 1.0)
	t.check(sum_ms / 60.0 <= ff + BUDGET_TICK_SLACK * ff_tick,
			"빨리 감기 예산 대략 지킴(평균 %.1fms ≤ 예산 %.0fms + 틱 %.0f개 × %.2fms, 최대 %.1fms)" % [sum_ms / 60.0, ff, BUDGET_TICK_SLACK, ff_tick, max_ms])
	t.check(lab.speed_text().begins_with("빨리 감기 / 실제"), "빨리 감기 표시: " + lab.speed_text())
	lab.set_speed(8)
	t.check(not lab.is_fast_forward() and lab._speed_btns[3].button_pressed, "속도를 고르면 빨리 감기 꺼짐")


func _budget(t, lab: LabMain) -> void:
	# 무거운 세계(200마리)에서 64배·0.25초 프레임 = 96틱 요청 → 10ms 예산에 걸려 밀린 몫을 버린다
	lab.new_experiment("default", {}, 4)
	lab.set_speed(64)
	var c0 := lab.world.tick
	lab.advance_frame(0.25)
	var n := lab.world.tick - c0
	var want := int(0.25 * UiConfig.num("speed.ticks_per_second_1x") * 64.0)
	t.check(n >= 1 and n < want and lab.last_budget_hit, "예산에 걸리면 덜 진행(%d틱 < 요청 %d)" % [n, want])
	t.check(lab._acc < 1.0, "밀린 틱을 버려 쌓이지 않음(누적 %.2f)" % lab._acc)
	var est_ms := lab._step_us_est / LabMain.USEC_PER_MS
	t.check(lab.last_sim_ms <= UiConfig.num("speed.sim_budget_ms") + BUDGET_TICK_SLACK * est_ms + HICCUP_MS,
			"프레임 시뮬레이션 시간 %.1fms ≈ 예산(+ 틱 %.0f개 × %.2fms + 멈칫 %.0fms)" % [lab.last_sim_ms, BUDGET_TICK_SLACK, est_ms, HICCUP_MS])
	# 실제 시계: 다음 틱 비용을 미리 더해 보고 멈추므로 평균은 "예산 + 이 기계의 틱 둘" 안(틱 하나가 예산보다 비싼 느린 기계는
	# 프레임당 1틱 = 평균 ≈ 틱 하나라 역시 안). 예산을 무시하고 요청한 6.4틱을 모두 돌면 넘는다. 수치는 출력(성능 기록)
	for mode in ["64배", "빨리 감기"]:
		var budget := UiConfig.num("speed.sim_budget_ms")
		if mode == "64배":
			lab.set_speed(64)
		else:
			lab.set_fast_forward(true)
			budget = UiConfig.num("speed.fast_forward_budget_ms")
		var times: Array[float] = []
		var ticks := 0
		for i in BUDGET_FRAMES:
			ticks += lab.advance_frame(DT)
			times.append(lab.last_sim_ms)
		times.sort()
		var mean := 0.0
		for v in times:
			mean += v
		mean /= float(times.size())
		var p95: float = times[int(float(times.size()) * 0.95)]
		var per_tick := mean / maxf(float(ticks) / float(BUDGET_FRAMES), 1.0)
		print("  예산(%s, %d마리): 평균 %.2fms, 95%% %.2fms, 최대 %.2fms, 틱당 약 %.2fms, 프레임당 %.2f틱 (예산 %.0fms)"
				% [mode, lab.world.population(), mean, p95, times.back(), per_tick, float(ticks) / float(BUDGET_FRAMES), budget])
		t.check(mean <= budget + BUDGET_TICK_SLACK * per_tick,
				"%s 예산 지킴(실제 시계): 평균 %.2fms ≤ 예산 %.0fms + 틱 %.0f개 × %.2fms" % [mode, mean, budget, BUDGET_TICK_SLACK, per_tick])
	lab.set_speed(64)
	_budget_rule(t, lab)
	# 아주 큰 프레임 시간은 speed.max_frame_delta_s 로 자른다
	lab.set_speed(1)
	lab._acc = 0.0
	var c1 := lab.world.tick
	lab.advance_frame(10.0)
	t.check(lab.world.tick - c1 <= int(UiConfig.num("speed.max_frame_delta_s") * UiConfig.num("speed.ticks_per_second_1x")) + 1, "큰 프레임 시간을 잘라 한꺼번에 몰아 돌지 않음")


## 가짜 시계: 실험 A 의 틱 × 한 틱 비용(µs) — 틱을 돌 때만 시간이 흐른다.
class FakeClock extends RefCounted:
	var lab: LabMain
	var cost_us := 0.0

	func now() -> int:
		return int(float(lab.experiment(0).world.tick) * cost_us)


## 예산 규칙(결정적 — 검토 I34): 가짜 시계로 한 틱 비용을 정해 두고 잰다. 다음 틱까지 하면 예산을 넘을 것 같으면 멈추되 적어도
## 1틱, 보통 배속은 밀린 몫을 버림 → 프레임당 max(1, floor(예산 ÷ 비용))틱, 시뮬레이션 시간 = 틱 × 비용, 한 틱 추정 = 비용.
## 어느 기계에서나 같은 값(예전엔 실제 시계로 "250마리 한 틱 ≤ 10.5ms" 를 단언하는 꼴이었음).
func _budget_rule(t, lab: LabMain) -> void:
	lab.new_experiment("default", {}, 4)
	lab.set_paused(false)
	var clock := FakeClock.new()
	clock.lab = lab
	var keep_clock: Callable = lab._clock_us
	lab._clock_us = clock.now
	for c in FAKE_TICK_CASES:
		var normal := bool(c[0])
		var cost_ms := float(c[1])
		var budget := UiConfig.num("speed.sim_budget_ms") if normal else UiConfig.num("speed.fast_forward_budget_ms")
		var want := maxi(1, floori(budget / cost_ms))
		if normal:
			lab.set_speed(64)
		else:
			lab.set_fast_forward(true)
		clock.cost_us = cost_ms * LabMain.USEC_PER_MS
		lab._step_us_est = 0.0
		var got := PackedInt32Array()
		var ok := true
		for i in FAKE_FRAMES:
			var n := lab.advance_frame(DT)
			got.append(n)
			ok = ok and n == want and is_equal_approx(lab.last_sim_ms, float(want) * cost_ms) and lab.last_budget_hit
			ok = ok and (not normal or lab._acc < 1.0)
		ok = ok and is_equal_approx(lab._step_us_est, clock.cost_us)
		t.check(ok, "예산 규칙(가짜 시계, %s, 틱 %.0fms, 예산 %.0fms): 프레임당 %d틱 = max(1, floor(예산 ÷ 틱)), 시간 = 틱 × 비용, 추정 = 비용 %s"
				% ["64배" if normal else "빨리 감기", cost_ms, budget, want, str(got)])
	# 가벼운 틱: 64배는 요청한 만큼(프레임당 6.4틱 — 예산에 걸리지 않음), 빨리 감기는 예산을 다 써서 더 많이
	clock.cost_us = CHEAP_TICK_MS * LabMain.USEC_PER_MS
	lab._step_us_est = clock.cost_us
	lab.set_speed(64)
	lab.advance_frame(DT)
	var a := lab.world.tick
	var hit := false
	for i in FAKE_FRAMES:
		lab.advance_frame(DT)
		hit = hit or lab.last_budget_hit
	var n64 := lab.world.tick - a
	var want64 := roundi(float(FAKE_FRAMES) * DT * UiConfig.num("speed.ticks_per_second_1x") * 64.0)
	lab.set_fast_forward(true)
	var b := lab.world.tick
	for i in FAKE_FRAMES:
		lab.advance_frame(DT)
	var nff := lab.world.tick - b
	var want_ff := FAKE_FRAMES * floori(UiConfig.num("speed.fast_forward_budget_ms") / CHEAP_TICK_MS)
	t.check(not hit and absi(n64 - want64) <= 1 and nff == want_ff and nff > n64,
			"가벼운 틱(가짜 시계 %.0fms): 64배 %d프레임 %d틱(요청 %d, 예산에 걸리지 않음) < 빨리 감기 %d틱(= 프레임 × floor(예산 ÷ 틱))"
			% [CHEAP_TICK_MS, FAKE_FRAMES, n64, want64, nff])
	lab._clock_us = keep_clock
	lab.set_speed(64)


func _selection(t, lab: LabMain) -> void:
	var w := lab.world
	var id := w.s_id[0]
	lab.map_view.slime_clicked.emit(id)
	t.check(lab.info_panel.current_id() == id and lab.selected_id() == id, "지도 클릭 신호 → 정보 창 #%d" % id)
	lab.map_view.slime_clicked.emit(-1)
	t.check(lab.info_panel.current_id() == -1 and lab.selected_id() == -1, "빈 곳 클릭 → 선택 해제")
	var id2 := w.s_id[1]
	lab.info_panel.slime_requested.emit(id2)
	t.check(lab.info_panel.current_id() == id2, "정보 창 가계 항목 → 그 개체 선택")
	lab.info_panel.follow_toggled.emit(true)
	t.check(lab.map_view.follow_selected, "따라가기 단추 → 지도 따라가기 켬")
	lab.info_panel.follow_toggled.emit(false)
	t.check(not lab.map_view.follow_selected, "따라가기 끔")
	lab.select_slime(999999)
	t.check(lab.selected_id() == -1 and lab.info_panel.current_id() == -1, "없는 id 는 선택 해제")
	lab.select_slime(id2)
	# 정보 창 새로 고침: refresh_frames 마다(뼈대·실제 모두 current_id 유지)
	lab.set_paused(true)
	for i in UiConfig.integer("info.refresh_frames") + 1:
		lab.advance_frame(DT)
	t.check(lab.info_panel.current_id() == id2, "프레임이 지나도 선택 유지")
	lab.set_paused(false)


func _keys(t, lab: LabMain) -> void:
	lab.set_paused(false)
	_key(t, KEY_SPACE)
	t.check(lab.is_paused(), "스페이스 → 멈춤")
	_key(t, KEY_SPACE)
	t.check(not lab.is_paused(), "스페이스 → 다시 재생")
	var steps: Array = UiConfig.value("speed.steps")
	_key(t, KEY_3)
	t.check(lab.target_speed() == int(steps[2]), "3 키 → %d배" % int(steps[2]))
	_key(t, KEY_7)
	t.check(lab.target_speed() == int(steps[6]), "7 키 → %d배" % int(steps[6]))
	var f0 := lab.map_view.follow_selected
	_key(t, KEY_F)
	t.check(lab.map_view.follow_selected != f0, "F → 따라가기 바꿈")
	t.check(lab.info_panel._follow.button_pressed == lab.map_view.follow_selected, "F → 정보 창 따라가기 단추도 같은 상태")
	_key(t, KEY_F)
	t.check(lab.info_panel._follow.button_pressed == lab.map_view.follow_selected, "F 다시 → 정보 창 따라가기 단추도 되돌아감")
	_follow_dead(t, lab)
	lab.select_slime(lab.world.s_id[0])
	_key(t, KEY_ESCAPE)
	t.check(lab.selected_id() == -1 and lab.info_panel.current_id() == -1, "Esc → 선택 해제")
	# 글 입력 칸(4단계)에 초점이 있으면 단축키를 쓰지 않는다
	var le := LineEdit.new()
	lab.left_dock.add_child(le)
	await t.frames(2)
	le.grab_focus()
	var sp := lab.target_speed()
	_key(t, KEY_SPACE)
	_key(t, KEY_1)
	t.check(le.has_focus() and not lab.is_paused() and lab.target_speed() == sp, "글 입력 칸에 초점이 있으면 단축키 무시")
	# 읽기 전용 칸(고급 설정의 배열·글자 값)은 글자를 받지 않으므로 초점이 있어도 단축키 동작
	le.editable = false
	_key(t, KEY_SPACE)
	t.check(le.has_focus() and lab.is_paused(), "읽기 전용 칸에 초점이 있어도 단축키 동작(스페이스 → 멈춤)")
	lab.set_paused(false)
	le.editable = true
	le.release_focus()
	le.queue_free()
	await t.frames(2)
	_key(t, KEY_1)
	t.check(lab.target_speed() == int(steps[0]), "초점이 풀리면 단축키 다시 동작")
	await _focus_release(t, lab)
	# 배타적인 대화 상자(4단계 파일 대화 상자 등)가 떠 있으면 무시
	var dlg := AcceptDialog.new()
	dlg.exclusive = true
	dlg.visible = false
	lab.add_child(dlg)
	dlg.position = Vector2i(100, 100)
	dlg.size = Vector2i(240, 120)
	dlg.visible = true
	await t.frames(1)
	var p0 := lab.is_paused()
	_key(t, KEY_SPACE)
	t.check(lab.is_paused() == p0, "대화 상자가 떠 있으면 단축키 무시")
	dlg.queue_free()
	await t.frames(2)
	_key(t, KEY_SPACE)
	t.check(lab.is_paused() != p0, "대화 상자를 닫으면 다시 동작")
	lab.set_paused(false)


## 죽은(기록만 남은) 개체를 고른 채 F: 따라가기를 켜지 않고 알림(정보 창 따라가기 단추가 꺼지는 규칙과 같게). 검토 I41: 예전엔
## "따라가기 켬" 이라 알리고 실제로는 따라가지 않았으며, 켜진 채 남아 다음에 고른 개체를 바로 따라갔음. 켜진 따라가기는 끌 수 있음.
func _follow_dead(t, lab: LabMain) -> void:
	var w := lab.world
	var dead := -1
	var guard := 0
	while dead < 0 and guard < DEAD_GUARD_TICKS:
		for k in w.lin_pa.size():
			if w.index_of_id(k) == -1:
				dead = k
				break
		if dead < 0:
			lab.step_ticks(DEAD_STEP)
			guard += DEAD_STEP
	lab.map_view.follow_selected = false
	lab.select_slime(dead)
	_key(t, KEY_F)
	var vt := lab.visible_toasts()
	var last := str(vt.back().text) if not vt.is_empty() else ""
	t.check(dead >= 0 and lab.selected_id() == dead and not lab.map_view.follow_selected and not lab.info_panel._follow.button_pressed
			and last == LabMain.FOLLOW_DEAD_TEXT, "죽은 개체 #%d 를 고른 채 F → 따라가기 켜지 않음(정보 창 단추도), 알림 \"%s\"" % [dead, last])
	lab.select_slime(w.s_id[0])
	t.check(not lab.map_view.follow_selected, "그 뒤 살아 있는 개체를 골라도 저절로 따라가지 않음")
	_key(t, KEY_F)
	t.check(lab.map_view.follow_selected and lab.info_panel._follow.button_pressed, "살아 있는 개체는 F → 따라가기 켬")
	lab.select_slime(dead)
	_key(t, KEY_F)
	t.check(not lab.map_view.follow_selected and not lab.info_panel._follow.button_pressed, "따라가던 중 죽은 개체로 옮겨도 F 로 따라가기를 끔")


## 키보드만으로(검토 J16): 초점이 없을 때 Tab → 파라미터 패널 첫 칸(자리를 접었으면 정보 창), Ctrl+N·S·O·E → 패널의 새 실험·
## 스냅숏 저장·열기·내보내기 단추와 같은 동작(자리를 접어도, 글 칸에 초점이 있어도 — 적던 값을 확정), 단추 말풍선에 단축키,
## 정보 창 단추(따라가기·가계)는 키보드 초점을 받음. 예전엔 단추가 모두 FOCUS_NONE·Ctrl 조합을 버려 마우스 없이 할 수 없었음.
func _command_keys(t, lab: LabMain) -> void:
	var pp := lab.param_panel
	lab.new_experiment("default", {}, 1)
	lab.set_paused(true)
	await t.frames(1)
	lab.get_viewport().gui_release_focus()
	_key(t, KEY_TAB)
	var f := lab.get_viewport().gui_get_focus_owner()
	t.check(f != null and pp.is_ancestor_of(f) and f == lab.first_focus(), "초점이 없을 때 Tab → 파라미터 패널 첫 칸(%s)" % (str(f.name) if f != null else "없음"))
	# 글 칸에 초점이 있는 채 씨앗을 적고 Ctrl+N → 그 값을 확정하고 새 실험(단추와 같음)
	var sle := pp.control("seed:0") as LineEdit
	if sle != null:
		sle.grab_focus()
		sle.text = "77"
	var w0 := lab.world
	_command_key(t, KEY_N)
	t.check(lab.world != w0 and lab.world.seed_value == 77 and lab.world.tick == 0 and (sle == null or not sle.has_focus()),
			"Ctrl+N → 적던 씨앗을 확정하고 새 실험(씨앗 %s)" % str(lab.world.seed_value))
	# 자리를 접어도(단추가 화면에 없어도) 들음
	lab.set_dock_open(LabMain.DOCK_LEFT, false)
	await t.frames(1)
	w0 = lab.world
	_command_key(t, KEY_N)
	t.check(lab.world != w0, "왼쪽 자리를 접어도 Ctrl+N → 새 실험")
	# 자리를 접고 개체를 고르면 Tab → 정보 창 단추(키보드 초점을 받음)
	lab.select_slime(lab.world.s_id[0])
	await t.frames(1)
	lab.get_viewport().gui_release_focus()
	_key(t, KEY_TAB)
	f = lab.get_viewport().gui_get_focus_owner()
	t.check(f != null and lab.info_panel.is_ancestor_of(f) and lab.info_panel._follow.focus_mode == Control.FOCUS_ALL,
			"자리를 접었으면 Tab → 정보 창 단추(%s)" % (str(f.name) if f != null else "없음"))
	lab.get_viewport().gui_release_focus()
	lab.select_slime(-1)
	lab.set_dock_open(LabMain.DOCK_LEFT, true)
	await t.frames(1)
	# Ctrl+S·Ctrl+O → 저장·열기 대화 상자(단추와 같은 길)
	for c in [[KEY_S, "SaveSnapshotDialog"], [KEY_O, "OpenSnapshotDialog"]]:
		_command_key(t, c[0])
		await t.frames(1)
		var d := pp.find_child(str(c[1]), true, false) as Window
		t.check(d != null and d.visible, "Ctrl+%s → %s" % [OS.get_keycode_string(c[0]), str(c[1])])
		if d != null:
			d.hide()
		await t.frames(1)
	# Ctrl+E(웹 모드: 결과 zip 내려받기 — 공용 user://experiments 에 쓰지 않게), 웹에서 숨긴 "스냅숏 열기" 의 Ctrl+O 는 아무것도 안 함
	pp.set_web_mode(true)
	lab.last_download_name = ""
	_command_key(t, KEY_E)
	t.check(lab.last_download_name.ends_with(".zip"), "Ctrl+E → 내보내기 단추와 같음(웹: 결과 zip %s)" % lab.last_download_name)
	var dl_path := lab.download_dir.path_join(lab.last_download_name)
	t.check(lab.download_dir.begins_with(TMP) and FileAccess.file_exists(dl_path), "내려받기는 이 검사의 임시 폴더에(%s — 실제 %s 아님)" % [dl_path, LabMain.DOWNLOAD_DIR])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(lab.download_dir.path_join(lab.last_download_name)))
	var od := pp.find_child("OpenSnapshotDialog", true, false) as Window
	_command_key(t, KEY_O)
	await t.frames(1)
	t.check(od == null or not od.visible, "웹 모드(스냅숏 열기 숨김)에서 Ctrl+O 는 아무것도 안 함")
	pp.set_web_mode(false)
	# 말풍선에 단축키, Ctrl 없는 N 은 아무것도 안 함
	var tips := PackedStringArray()
	for id in ["apply", "start_compare", "save", "open", "export"]:
		var bb := pp.control(id) as BaseButton
		if bb != null and bb.shortcut != null and bb.shortcut_in_tooltip:
			tips.append("%s=%s" % [id, bb.shortcut.get_as_text()])
	var want_tips := "apply=%s start_compare=%s save=%s open=%s export=%s" % [LabMain.command_shortcut(KEY_N, "").get_as_text(),
			LabMain.command_shortcut(KEY_N, "").get_as_text(), LabMain.command_shortcut(KEY_S, "").get_as_text(),
			LabMain.command_shortcut(KEY_O, "").get_as_text(), LabMain.command_shortcut(KEY_E, "").get_as_text()]
	t.check(" ".join(tips) == want_tips and want_tips.contains("Ctrl+N"), "패널 단추 말풍선에 단축키(%s)" % " ".join(tips))
	w0 = lab.world
	_key(t, KEY_N)
	t.check(lab.world == w0, "Ctrl 없이 N 은 새 실험 아님")
	lab.set_paused(false)


## Ctrl(맥은 Cmd) + code 를 실제 키 입력으로.
func _command_key(t, code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.command_or_control_autoremap = true
		t.root.push_input(e)


func _key(t, code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		t.root.push_input(e)


## 글자를 실제 키 입력으로(숫자·점·빈칸).
func _type(t, text: String) -> void:
	for ch in text:
		var c := ch.unicode_at(0)
		var code: Key = KEY_PERIOD if ch == "." else KEY_SPACE if ch == " " else (KEY_0 + (c - 48)) as Key
		for pressed in [true, false]:
			var e := InputEventKey.new()
			e.keycode = code
			e.physical_keycode = code
			e.unicode = c if pressed else 0
			e.pressed = pressed
			t.root.push_input(e)


## 뿌리 창에 실제 마우스 입력(움직임 → 왼쪽 누름 → 뗌).
func _click(t, pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	t.root.push_input(mm)
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = pos
		mb.global_position = pos
		t.root.push_input(mb)


## 파라미터 패널의 칸을 스크롤해 화면에 보이게. 새 실험·비교 단추 등은 스크롤 밖 고정 바닥(Footer)에 있어 그대로 둔다.
func _reveal(pp: ParamPanel, c: Control) -> void:
	var sc := pp.control("scroll") as ScrollContainer
	if sc != null and sc.is_ancestor_of(c):
		sc.ensure_control_visible(c)


## 파라미터 패널 글 칸에 적은 뒤 칸 밖(새 실험 단추·지도)을 누르면 초점이 풀려 단축키가 바로 동작하고, 친 키가 칸에
## 들어가 다음 실험에 확정되지 않는다(고치기 전: 씨앗 "42" + 스페이스·"4" → "42 4", 멈춤·배속 그대로).
## 씨앗 칸은 글 칸(LineEdit — 검토 고침 g4: 예전 SpinBox 의 식 계산·실수 반올림을 없앰). 초점을 가진 칸 자체를 누르면 초점 그대로.
## 실제 앱에서는 마우스를 뗄 때 select_all_on_focus 가 글자 전체를 고르지만 push_input 은 Input 의 단추 상태를 바꾸지 않아
## 엔진이 누르는 순간 고른 뒤 누른 자리에 커서를 둔다 — 그래서 누른 뒤 직접 전체를 고른다.
func _focus_release(t, lab: LabMain) -> void:
	var pp := lab.param_panel
	var sle := pp.control("seed:0") as LineEdit
	var field := pp.control("field:mutation.rate:0") as LineEdit
	var apply_btn := pp.control("apply") as Control
	t.check(sle != null and field != null and apply_btn != null, "파라미터 패널의 씨앗 칸·돌연변이율 칸·새 실험 단추")
	if sle == null or field == null or apply_btn == null:
		return
	var steps: Array = UiConfig.value("speed.steps")
	lab.set_paused(false)
	lab.set_speed(int(steps[0]))
	var map_mid := lab._map_container.get_global_rect().get_center()
	_reveal(pp, sle)
	await t.frames(2)
	_click(t, sle.get_global_rect().get_center())
	await t.frames(1)
	sle.select_all()
	_type(t, "42")
	await t.frames(1)
	t.check(sle.has_focus() and sle.text == "42", "씨앗 칸을 눌러 \"%s\" 입력(초점 %s)" % [sle.text, str(sle.has_focus())])
	_reveal(pp, apply_btn)
	await t.frames(2)
	_click(t, apply_btn.get_global_rect().get_center())
	await t.frames(1)
	t.check(not sle.has_focus() and lab.world.seed_value == 42, "새 실험 단추를 누르면 칸 초점이 풀리고 씨앗 42 로 새 실험(씨앗 %d)" % lab.world.seed_value)
	_click(t, map_mid)
	await t.frames(1)
	lab.set_paused(false)
	_key(t, KEY_SPACE)
	_key(t, KEY_4)
	t.check(lab.is_paused() and lab.target_speed() == int(steps[3]) and sle.text == "42",
			"그 뒤 스페이스 → 멈춤, 4 → %d배, 씨앗 칸 글자 그대로 \"%s\"" % [lab.target_speed(), sle.text])
	t.check(int(pp.current_settings(0).seed) == 42, "다음 실험 씨앗도 42 그대로(%s)" % str(pp.current_settings(0).seed))
	# 씨앗 칸에 "43"(Enter 없음) → 지도를 누르면 확정·초점이 풀려 스페이스가 동작
	_reveal(pp, sle)
	await t.frames(2)
	_click(t, sle.get_global_rect().get_center())
	await t.frames(1)
	sle.select_all()
	_type(t, "43")
	_click(t, map_mid)
	await t.frames(1)
	var paused0 := lab.is_paused()
	_key(t, KEY_SPACE)
	t.check(int(pp.current_settings(0).seed) == 43 and not sle.has_focus() and lab.is_paused() != paused0,
			"씨앗 칸 43 뒤 지도를 누르면 확정(씨앗 %s)·초점이 풀려 스페이스가 동작" % str(pp.current_settings(0).seed))
	# 돌연변이율 칸: 칸 안을 다시 눌러도 초점 그대로, 지도를 누르면 그 값이 확정되고 단축키 동작
	_reveal(pp, field)
	await t.frames(2)
	_click(t, field.get_global_rect().get_center())
	await t.frames(1)
	field.select_all()
	_type(t, "0.07")
	_click(t, field.get_global_rect().get_center())
	await t.frames(1)
	t.check(field.has_focus() and field.text == "0.07", "초점을 가진 칸 자체를 누르면 초점 그대로(\"%s\")" % field.text)
	_click(t, map_mid)
	await t.frames(1)
	lab.set_paused(false)
	_key(t, KEY_SPACE)
	_key(t, KEY_2)
	var ov: Dictionary = pp.current_settings(0).overrides
	t.check(not field.has_focus() and lab.is_paused() and lab.target_speed() == int(steps[1]) and field.text == "0.07"
			and is_equal_approx(float(ov.get("mutation.rate", -1.0)), 0.07),
			"돌연변이율 0.07 → 지도 누름: 값 확정(%s), 스페이스·2 동작(배속 %d), 칸 \"%s\"" % [str(ov.get("mutation.rate")), lab.target_speed(), field.text])
	pp.revert()
	lab.set_paused(false)
	await t.frames(1)

func _events(t, lab: LabMain) -> void:
	t.check(lab.new_experiment("demo_fast", {}, 1) == "", "demo_fast 실험")
	var got: Array = []
	# 청취자가 사건 사전을 고쳐 써도(4단계 연대기 창이 꾸미는 경우 등) 세계의 연대기는 그대로여야 한다
	var spoil := func(list: Array) -> void:
		got.append_array(list)
		for e in list:
			e["text"] = "★ " + str(e.get("text", ""))
	lab.events.connect(spoil)
	# events_tagged 는 따로 깊은 사본(signal 마다 사본 하나): events 청취자가 고쳐 써도 events_tagged 청취자는 원래 문장
	var tagged_texts: Array[String] = []
	var keep_tagged := func(_i: int, list: Array) -> void:
		for e in list:
			tagged_texts.append(str(e.get("text", "")))
	lab.events_tagged.connect(keep_tagged)
	var s0 := lab.world.stage
	var k := 0
	# 검사가 세계를 직접 진행(화면이 아님) → 다음 프레임에 LabMain 이 사건을 소비
	while lab.world.stage == s0 and k < 5000:
		lab.world.step()
		k += 1
	t.check(lab.world.stage != s0, "demo_fast 가 %d틱 안에 단계가 바뀜" % k)
	lab.set_paused(true)
	lab.advance_frame(DT)
	var disc := false
	for e in got:
		if str(e.get("kind", "")) == "discovery":
			disc = true
	t.check(disc, "events 신호에 발견 사건(%d건)" % got.size())
	lab.events.disconnect(spoil)
	lab.events_tagged.disconnect(keep_tagged)
	var spoiled := false
	for s in tagged_texts:
		spoiled = spoiled or s.begins_with("★ ")
	t.check(not tagged_texts.is_empty() and tagged_texts.size() == got.size() and not spoiled,
			"events 청취자가 고쳐 써도 events_tagged 청취자의 사본은 그대로(signal 마다 사본, %d건)" % tagged_texts.size())
	var ref: SimWorld = t.make_world({}, 1, "demo_fast")
	ref.step_n(lab.world.tick)
	t.check(SimRecorder.chronicle_csv(lab.world) == SimRecorder.chronicle_csv(ref), "events 청취자가 사건을 고쳐 써도 연대기(chronicle.csv)가 헤드리스와 같음")
	var toast_disc := false
	for v in lab.visible_toasts():
		if v.kind == "discovery":
			toast_disc = true
	t.check(toast_disc, "발견 알림이 보임")
	var disc_border := Color.BLACK
	for d in lab._toasts:
		if d.kind == "discovery":
			disc_border = _border(d.panel)
	t.check(disc_border.is_equal_approx(Color(UiTheme.color("accent"), LabMain.TOAST_HIGHLIGHT_ALPHA)), "발견 알림 = 강조 색 테두리")
	lab.show_toast("시험 멸종", "extinction", 12)
	t.check(_border(lab._toasts.back().panel).is_equal_approx(Color(UiTheme.color("danger"), LabMain.TOAST_HIGHLIGHT_ALPHA)), "멸종 알림 = 위험 색 테두리")
	for i in UiConfig.integer("lab.toast_max") + 3:
		lab.show_toast("알림 %d" % i)
	t.check(lab.visible_toasts().size() == UiConfig.integer("lab.toast_max"), "알림은 최대 lab.toast_max 개")
	var frames := int(ceil(UiConfig.num("lab.toast_seconds") / 0.2)) + 1
	for i in frames:
		lab.advance_frame(0.2)
	t.check(lab.visible_toasts().is_empty(), "알림은 toast_seconds 뒤 사라짐")
	lab.set_paused(false)


## 보이는 알림 가운데 group 이 같은 첫 알림(없으면 {}).
func _toast_of(vt: Array[Dictionary], group: String) -> Dictionary:
	for v in vt:
		if str(v.get("group", "?")) == group:
			return v
	return {}


func _border(p: PanelContainer) -> Color:
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	return sb.border_color if sb != null else Color.BLACK


func _hash(t, lab: LabMain) -> void:
	lab.new_experiment("default", {}, 11)
	lab.set_paused(false)
	lab.set_speed(8)
	for i in 150:
		lab.advance_frame(DT)
		if i == 70:
			lab.select_slime(lab.world.s_id[0])
	lab.set_fast_forward(true)
	var every := int(lab.world.cfg.hash.every)
	var ff_from := lab.world.tick
	# 빨리 감기로만 진행한 틱도 해시 검사점을 지나게(검사점 사이는 해시가 그대로라 아무것도 증명하지 못함)
	var target := (ff_from / every + 1) * every
	var guard := 0
	while lab.world.tick <= target and guard < 600:
		lab.advance_frame(DT)
		guard += 1
	var ref: SimWorld = t.make_world({}, 11)
	ref.step_n(lab.world.tick)
	t.check(lab.world.tick > target and lab.world.history_hash == ref.history_hash,
			"화면으로 %d틱(빨리 감기 %d → %d, 검사점 %d 지남) 진행해도 역사 해시가 헤드리스와 같음" % [lab.world.tick, ff_from, lab.world.tick, target])
	var diff: String = t.same_state(lab.world, ref)
	t.check(diff == "", "화면으로 진행한 끝 상태(개체·에너지·유전체·먹이 배열)가 헤드리스와 같음 %s" % diff)
	lab.set_speed(1)


func _args(t, lab: LabMain) -> void:
	var def_cfg: Dictionary = SimConfig.build("default", {}).config
	var changed := {n = 0}
	lab.world_changed.connect(func(_w: SimWorld) -> void: changed.n += 1)
	lab.select_slime(lab.world.s_id[0])
	var err := lab.apply_args(PackedStringArray(["--preset=없는예설정", "--seed=5", "--out=무시"]))
	t.check(err != "" and lab.world != null and lab.world.seed_value == 5 and SimConfig.deep_equal(lab.world.cfg, def_cfg), "잘못된 --preset → 기본 예설정(씨앗 5 유지)")
	t.check(_has_toast(lab, "error"), "명령줄 오류는 알림으로 보임")
	t.check(lab.selected_id() == -1 and lab.info_panel.current_id() == -1, "새 실험은 선택을 비움")
	t.check(int(changed.n) >= 1, "world_changed 신호")
	err = lab.apply_args(PackedStringArray(["--seed=abc"]))
	t.check(err != "" and lab.world.seed_value == UiConfig.integer("lab.default_seed"), "잘못된 --seed → 기본 씨앗")
	err = lab.apply_args(PackedStringArray(["--preset=demo_fast", "--seed=9"]))
	t.check(err == "" and lab.world.seed_value == 9 and SimConfig.deep_equal(lab.world.cfg, SimConfig.build("demo_fast", {}).config), "--preset=demo_fast --seed=9")
	err = lab.apply_args(PackedStringArray(["--snapshot=user://없는_스냅숏.json"]))
	t.check(err != "" and lab.world != null and lab.world.tick == 0, "없는 --snapshot → 새 실험으로 엶")
	# 스냅숏 열기: 같은 틱·해시, 선택·누적 초기화
	lab.world.step_n(30)
	var tick := lab.world.tick
	var h := lab.world.history_hash
	t.check(SimSnapshot.save_file(lab.world, SNAP_PATH) == "", "스냅숏 저장")
	lab.select_slime(lab.world.s_id[0])
	err = lab.apply_args(PackedStringArray(["--snapshot=" + SNAP_PATH]))
	t.check(err == "" and lab.world.tick == tick and lab.world.history_hash == h, "--snapshot 으로 열기(틱 %d)" % lab.world.tick)
	t.check(lab.selected_id() == -1 and lab._acc == 0.0, "스냅숏 열면 선택·누적 초기화")
	# 연 실험의 그래프·시계열은 연 틱부터(스냅숏에는 기록기 줄이 없음) — 알림으로 알림(검토 J19)
	var opened_note := false
	for v in lab.visible_toasts():
		opened_note = opened_note or (v.kind == "info" and str(v.text).contains(SNAP_PATH.get_file()) and str(v.text).contains("틱 %s 부터" % LabMain._commas(tick)))
	t.check(opened_note, "스냅숏 열기 알림에 파일 이름·기록 시작 틱(%s)" % str(lab.visible_toasts()))
	t.check(lab.open_snapshot("user://없는_스냅숏.json") != "" and lab.world.tick == tick, "열기 실패면 지금 세계 유지")
	# 읽기가 끊긴 결과(빈 사전 — 스냅숏 읽는 함수가 스크립트 오류로 끊기면 이렇게 돌아옴)도 실패로: 오류 문장, 세계 그대로
	# (검토 I04: 예전엔 끊긴 결과의 기본값 ""(= 성공)이 그대로 나가 알림 없이 세계도 그대로, --snapshot= 이면 실험 0개)
	var w_before := lab.world
	t.check(lab.open_result({}, "user://끊긴.json") != "" and lab.world == w_before and lab.experiments.size() == 1,
			"끊긴 읽기 결과 → 실패 문장, 지금 세계 그대로")
	t.check(lab.open_result({experiment = null, error = "", status = "failed"}, "user://빈.json").contains("빈.json"), "이유 없는 실패도 문장(파일 이름)")
	# 명령줄 경계(검토 I42): "=" 없이 띄어 쓴 아는 인자는 오류(실행기도 거부), int64 를 넘는 씨앗은 오류(엔진 오류 줄 없이),
	# 잘못된 값의 알림에는 실제로 쓸 값
	var def_seed := UiConfig.integer("lab.default_seed")
	err = lab.apply_args(PackedStringArray(["--seed", "5"]))
	t.check(err.contains("--seed=값") and lab.world.seed_value == def_seed, "\"--seed 5\" → 오류 알림, 기본 씨앗(%s): %s" % [str(lab.world.seed_value), err])
	err = lab.apply_args(PackedStringArray(["--snapshot", SNAP_PATH, "--preset", "demo_fast"]))
	t.check(err.contains("--snapshot=값") and err.contains("--preset=값") and lab.world.tick == 0, "\"--snapshot 경로\"·\"--preset 이름\" → 오류, 새 실험: %s" % err)
	err = lab.apply_args(PackedStringArray(["--seed=99999999999999999999"]))
	t.check(err.contains("범위") and lab.world.seed_value == def_seed, "int64 를 넘는 씨앗 → 범위 오류, 기본 씨앗: %s" % err)
	err = lab.apply_args(PackedStringArray(["--seed=5", "--seed=abc"]))
	t.check(lab.world.seed_value == 5 and err.contains("쓸 씨앗: 5") and not err.contains("기본 씨앗"), "앞의 씨앗 5 를 쓰고 알림도 5: %s" % err)
	err = lab.apply_args(PackedStringArray(["--preset=demo_fast", "--preset=없는예설정"]))
	t.check(SimConfig.deep_equal(lab.world.cfg, SimConfig.build("demo_fast", {}).config) and err.contains("쓸 예설정: demo_fast"), "앞의 예설정을 쓰고 알림도: %s" % err)
	var int64_min := -9223372036854775807 - 1
	t.check(LabMain.seed_text_error("9223372036854775807") == "" and LabMain.seed_text_error("-9223372036854775808") == ""
			and LabMain.seed_text_error("+0005") == "" and LabMain.seed_text_error("9223372036854775808") != ""
			and LabMain.seed_text_error("-9223372036854775809") != "" and LabMain.seed_text_error("00000000000000000000000001") == "",
			"씨앗 글자 범위(int64 끝값까지 받고 넘으면 오류, 앞의 0 은 무시)")
	err = lab.apply_args(PackedStringArray(["--seed=-9223372036854775808"]))
	t.check(err == "" and lab.world.seed_value == int64_min, "INT64_MIN 씨앗을 받음")
	# 씨앗 표기는 str(엔진 "%d" 는 INT64_MIN 에 부호를 두 번 — 검토 J31): 실험 이름·창 제목·기본 내보내기 이름·내려받기 이름
	var want_seed := "씨앗 -9223372036854775808"
	t.check(lab.experiments[0].label.ends_with(want_seed) and lab.get_window().title.ends_with(want_seed) and not lab.get_window().title.contains("--")
			and lab.default_export_dir().ends_with("-seed-9223372036854775808"),
			"INT64_MIN 씨앗 표기: \"%s\" / \"%s\" / %s" % [lab.experiments[0].label, lab.get_window().title, lab.default_export_dir().get_file()])
	t.check(lab.download_snapshot(0) == "" and lab.last_download_name.contains("-seed-9223372036854775808-tick0") and not lab.last_download_name.contains("--"),
			"INT64_MIN 스냅숏 내려받기 이름: %s" % lab.last_download_name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(lab.download_dir.path_join(lab.last_download_name)))
	lab.new_experiment("default", {}, 1)
	for p in [SNAP_PATH, SNAP_PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _has_toast(lab: LabMain, kind: String) -> bool:
	for v in lab.visible_toasts():
		if v.kind == kind:
			return true
	return false


## 빨리 감기 중 멈추거나 보통 속도로 돌아가도 모든 슬라임이 지금 칸 근처에 그려진다(고치기 전: 마지막 빨리 감기
## 프레임 이전의 낡은 자리로 3~10칸 튐). 선택 고리도 선택 개체의 지금 칸에.
func _ff_pause(t, lab: LabMain) -> void:
	lab.new_experiment("default", {}, 1)
	lab.set_paused(false)
	lab.set_speed(8)
	for i in 30:
		lab.advance_frame(DT)
	var w := lab.world
	lab.select_slime(w.s_id[w.population() / 2])
	var tl := UiConfig.num("map.tile_size")
	var bound := maxf(MapView.stack_max(), UiConfig.num("map.store_slime_offset")) * tl + 0.01
	lab.set_fast_forward(true)
	for i in 10:
		lab.advance_frame(DT)
	lab.set_paused(true)
	lab.advance_frame(DT)
	# 빨리 감기 중 멈춤: 막대는 다시 재생하면 돌 방식(빨리 감기)을 적는다(검토 J33: 예전엔 꺼진 속도 단추의 "목표 8배")
	t.check(lab.speed_text() == "멈춤 · 빨리 감기" and lab._lbl_speed.text == lab.speed_text() and lab._fast_btn.button_pressed,
			"빨리 감기 중 멈춤 표시: \"%s\"" % lab._lbl_speed.text)
	var d := _max_drift(lab)
	t.check(d <= bound, "빨리 감기 중 멈춤: 모든 슬라임이 지금 칸에(가장 먼 %.2f칸 ≤ %.2f, 고치기 전 3~4칸)" % [d, bound])
	var ri := lab.map_view.ring_info()
	var si := w.index_of_id(lab.selected_id())
	var rp: Vector3 = ri.position
	var ring_d := Vector2(rp.x - (float(w.s_x[si]) + 0.5) * tl, rp.z - (float(w.s_y[si]) + 0.5) * tl).length() if si >= 0 else INF
	t.check(ri.visible and ring_d <= bound, "빨리 감기 중 멈춤: 선택 고리가 선택 개체의 지금 칸(%.2f칸)" % ring_d)
	# 빨리 감기 → 1배: 한 틱 보간 이상 미끄러지지 않음
	lab.set_paused(false)
	for i in 10:
		lab.advance_frame(DT)
	lab.set_speed(1)
	lab.advance_frame(DT)
	d = _max_drift(lab)
	t.check(d <= tl + bound, "빨리 감기 → 1배: 한 틱 보간 이상 벗어난 개체 없음(가장 먼 %.2f칸, 고치기 전 3~10칸)" % d)
	lab.select_slime(-1)


## 그려진 위치와 지금 칸 가운데의 가장 큰 거리(칸).
func _max_drift(lab: LabMain) -> float:
	var w := lab.world
	var tl := UiConfig.num("map.tile_size")
	var worst := 0.0
	for k in w.population():
		var p := lab.map_view.slime_instance_position(k)
		worst = maxf(worst, Vector2(p.x - (float(w.s_x[k]) + 0.5) * tl, p.z - (float(w.s_y[k]) + 0.5) * tl).length())
	return worst


## 16배(프레임당 1.6틱): 2틱 프레임도 마지막 한 틱만 보간하므로 혼자 있는 개체가 한 프레임에 크게 튀지 않음
## (고치기 전: 2틱을 한 틱 몫 alpha 로 보간해 2.6칸 튀었다가 멈춤).
func _multi_tick_motion(t, lab: LabMain) -> void:
	lab.new_experiment("default", {"population.initial": 40}, 5)
	lab.set_paused(false)
	lab.set_speed(16)
	var w := lab.world
	var tl := UiConfig.num("map.tile_size")
	var last := {}
	var worst := 0.0
	var seen := 0
	var multi := 0
	var budget_frames := 0
	# 실제 시계 예산(sim_budget_ms)은 이 동안 끈다: 기계가 바쁘면 예산에 걸린 프레임이 틱·프레임 짝을 바꿔 잰 값이
	# 실행마다 달라졌다(부하가 큰 때 1.92칸으로 한 번 실패). 끄면 프레임마다 틱 수가 정해져 어느 기계에서나 같은 값.
	var keep_budget := lab._budget_ms
	lab._budget_ms = BUDGET_OFF_MS
	for f in 120:
		var n := lab.advance_frame(DT)
		# 예산에 걸린 프레임은 밀린 틱을 버리므로(F18) 한 프레임 이동이 원래 길다 — 기계 부하에 따라 생기므로 재지 않는다
		if lab.last_budget_hit:
			budget_frames += 1
			last = {}
			continue
		if n >= 2:
			multi += 1
		var occ := {}
		for i in w.population():
			var c := w.s_y[i] * w.w + w.s_x[i]
			occ[c] = int(occ.get(c, 0)) + 1
		var now := {}
		for i in w.population():
			if int(occ[w.s_y[i] * w.w + w.s_x[i]]) != 1:
				continue
			var p := lab.map_view.slime_instance_position(i)
			now[w.s_id[i]] = Vector2(p.x, p.z)
			if last.has(w.s_id[i]):
				worst = maxf(worst, (now[w.s_id[i]] as Vector2).distance_to(last[w.s_id[i]]) / tl)
				seen += 1
		last = now
	lab._budget_ms = keep_budget
	t.check(multi > 0 and seen > 0 and worst <= MULTI_TICK_MAX_STEP and budget_frames == 0,
			"16배: 2틱 프레임 %d번(예산 걸린 프레임 %d번 제외), 혼자 있는 개체의 한 프레임 이동 최대 %.2f칸 ≤ %.1f(고치기 전 2.6칸)" % [multi, budget_frames, worst, MULTI_TICK_MAX_STEP])


## 실제 배속 창: 다시 재생·배속 바꿈 직후 거짓 "뒤처짐" 경고 없음(F09), 느린 프레임(4FPS 미만)은 정직하게 낮게(F10),
## 따라가면 정확히 목표 배속(소수 틱 몫까지 셈, F11).
func _speed_window(t, lab: LabMain) -> void:
	lab.new_experiment("default", {"population.initial": FF_POPULATION}, 3)
	var warn := UiTheme.color("warn")
	lab.set_paused(false)
	lab.set_speed(1)
	for i in 120:
		lab.advance_frame(DT)
	lab.set_paused(true)
	for i in 120:
		lab.advance_frame(DT)
	lab.set_paused(false)
	lab.advance_frame(DT)
	t.check(lab.speed_text().contains("실제 —") and _speed_color(lab) != warn, "다시 재생 직후: \"%s\"(경고 색 아님)" % lab.speed_text())
	var warned := false
	for i in 90:
		lab.advance_frame(DT)
		warned = warned or _speed_color(lab) == warn
	t.check(not warned and lab.speed_text() == "목표 1배 / 실제 1.0배", "다시 재생 뒤 1.5초 동안 경고 없음, \"%s\"" % lab.speed_text())
	lab.set_speed(8)
	lab.advance_frame(DT)
	t.check(lab.speed_text().contains("실제 —") and _speed_color(lab) != warn, "배속을 올린 직후: \"%s\"(경고 색 아님)" % lab.speed_text())
	warned = false
	var hit := false
	for i in 90:
		lab.advance_frame(DT)
		warned = warned or _speed_color(lab) == warn
		hit = hit or lab.last_budget_hit
	t.check(not hit and not warned and lab.speed_text() == "목표 8배 / 실제 8.0배", "배속 8 로 1.5초: 경고 없음, \"%s\"" % lab.speed_text())
	# 정수 틱 반올림 없음: 여러 화면 빠르기·배속에서 언제나 정확히 목표
	for c in [[1, 1.0 / 75.0], [2, 1.0 / 144.0], [2, 0.006944], [4, 1.0 / 75.0], [1, 1.0 / 240.0]]:
		lab.set_speed(int(c[0]))
		var want := "목표 %d배 / 실제 %d.0배" % [int(c[0]), int(c[0])]
		var bad := ""
		for i in int(3.0 / float(c[1])):
			lab.advance_frame(float(c[1]))
			var txt := lab.speed_text()
			if not txt.contains("—") and txt != want:
				bad = txt
			if _speed_color(lab) == warn:
				bad = "경고 색"
		t.check(bad == "" and absf(lab.actual_speed() - float(c[0])) < 0.05,
				"%d배 · 프레임 %.4f초: 실제 배속 언제나 \"%s\" (%s, %.3f)" % [int(c[0]), float(c[1]), want, bad, lab.actual_speed()])
	# 4FPS 미만(잘린 프레임 시간): 실제 = 0.75배, 경고 색. 실제 시계 예산은 끈다 — 프레임당 1.5틱이 예산에 걸리면(한 틱이
	# 5ms 를 넘는 느린 기계) 진행이 줄어 기계 속도에 따라 실패했다(검토 I34 — 이 검사는 배속 셈을 보지 예산을 보지 않음)
	var keep_budget := lab._budget_ms
	lab._budget_ms = BUDGET_OFF_MS
	lab.set_speed(1)
	for i in 12:
		lab.advance_frame(1.0 / 3.0)
	lab._budget_ms = keep_budget
	lab._refresh_status(true)
	t.check(absf(lab.actual_speed() - 0.75) < 0.02 and _speed_color(lab) == warn,
			"3FPS·1배: 실제 %.2f배(= 0.75, 잘리지 않은 프레임 시간), 경고 색" % lab.actual_speed())


## 실제 _process 경로로 느린 프레임(형제 노드가 프레임마다 SLOW_FRAME_MS 를 씀 — 약 2.5 FPS). 엔진은 _process 의 delta 를
## max_physics_steps_per_frame ÷ physics_ticks_per_second(8/60초)에서 잘라 넘기지만, 실험실은 벽시계 간격으로 재므로
## "실제 M배" = 진행한 틱 ÷ 벽시계 ÷ 1배 틱 수, 1배에서 경고 색. 진행도 speed.max_frame_delta_s 만큼은 따라감
## (검토 J04: 예전엔 잘린 delta 로 재 실제 약 0.3배인데 "실제 1.0배"·경고 없음 — 이 길을 지나는 검사가 없었음).
class SlowFrames extends Node:
	var ms := 0

	func _process(_delta: float) -> void:
		OS.delay_msec(ms)


func _slow_process(t, lab: LabMain) -> void:
	lab.new_experiment("default", {"population.initial": FF_POPULATION}, 3)
	lab.set_paused(false)
	lab.set_speed(1)
	var slow := SlowFrames.new()
	slow.ms = SLOW_FRAME_MS
	t.root.add_child(slow)
	# 실제 시계 예산은 끈다: 프레임당 1.5틱이 예산에 걸리면(느린 기계) 진행이 max_frame_delta_s 를 따라가지 못해 기계 속도에
	# 따라 실패했다(검토 I34 — 이 검사는 프레임 시간을 재는 길을 보지 예산을 보지 않음)
	var keep_budget := lab._budget_ms
	lab._budget_ms = BUDGET_OFF_MS
	lab.set_process(true)
	await t.frames(2)
	# set_process 전의 간격(앞 검사들의 시간)은 빼고 잼
	lab._reset_speed_window()
	var start := float(lab.world.tick) + lab._acc
	var us0 := Time.get_ticks_usec()
	await t.frames(SLOW_FRAMES)
	var wall := float(Time.get_ticks_usec() - us0) / LabMain.USEC_PER_S
	var ticks := float(lab.world.tick) + lab._acc - start
	lab.set_process(false)
	lab._budget_ms = keep_budget
	t.root.remove_child(slow)
	slow.free()
	var tps := UiConfig.num("speed.ticks_per_second_1x")
	var real := ticks / wall / tps
	# 진행은 프레임마다 min(프레임 시간, max_frame_delta_s) × tps 틱 → 기대 배속 = 그 몫 ÷ 프레임 시간
	var frame_s := wall / float(SLOW_FRAMES)
	var expect := minf(frame_s, UiConfig.num("speed.max_frame_delta_s")) / frame_s
	lab._refresh_status(true)
	t.check(absf(lab.actual_speed() - real) < SLOW_SPEED_TOL and lab.actual_speed() < UiConfig.num("speed.behind_ratio")
			and _speed_color(lab) == UiTheme.color("warn"),
			"느린 프레임(%dms·_process): 표시 실제 %.2f배 ≈ 틱 ÷ 벽시계 %.2f배(%.1f틱 / %.2f초), 경고 색" % [SLOW_FRAME_MS, lab.actual_speed(), real, ticks, wall])
	t.check(absf(real - expect) < SLOW_SPEED_TOL, "느린 프레임(%.2f초)의 진행도 max_frame_delta_s 까지는 따라감(%.2f배 ≈ %.2f배)" % [frame_s, real, expect])


func _speed_color(lab: LabMain) -> Color:
	return lab._lbl_speed.get_theme_color("font_color")


## 알림 규칙: 세계를 바꾸면 앞 세계 알림이 사라짐(F13), 밭 잃음은 하나로 묶고 강조 알림은 덜 중요한 것보다 늦게 지움(F21),
## 긴 문장은 지도 폭 안에서 줄을 바꾸고 오류는 더 오래 보임(F22).
func _toast_rules(t, lab: LabMain) -> void:
	lab.set_paused(true)
	lab.show_toast("시험 멸종", "extinction", 5)
	lab.show_toast("시험 발견", "discovery", 6)
	t.check(lab.new_experiment("default", {}, 1) == "" and lab.visible_toasts().is_empty(), "새 실험 → 앞 세계의 알림을 지움")
	await t.frames(1)
	t.check(lab._toast_box.get_child_count() == 0, "알림 상자도 비었음(%d)" % lab._toast_box.get_child_count())
	# 강조 알림으로 꽉 찼을 때 새 일반 알림(단축키 반응 등)은 바로 사라지지 않고, 가장 오래된 강조 알림이 밀려남
	var cap := UiConfig.integer("lab.toast_max")
	for k in cap:
		lab.show_toast("시험 발견 %d" % k, "discovery", k)
	lab.show_toast("따라가기 켬", "info", cap)
	var texts: Array[String] = []
	for vt in lab.visible_toasts():
		texts.append(str(vt.text))
	t.check(texts.size() == cap and texts.has("따라가기 켬") and not texts.has("시험 발견 0") and texts.has("시험 발견 1"),
			"강조 알림으로 꽉 찼을 때 새 알림이 보이고 가장 오래된 강조 알림이 밀려남: %s" % [texts])
	lab._clear_toasts()
	await t.frames(1)
	lab.set_paused(true)
	# 백업에서 연 스냅숏: 바뀐 세계 위에 경고 알림 하나
	var path := TMP.path_join("backup.json")
	lab.world.step_n(10)
	SimSnapshot.save_file(lab.world, path)
	SimSnapshot.save_file(lab.world, path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{}")  # JSON 으로는 맞지만 스냅숏 형식이 아님(엔진 JSON 오류 줄 없이 깨진 원본 흉내)
	f.close()
	lab.show_toast("앞 알림", "info")
	t.check(lab.open_snapshot(path) == "", "깨진 원본 → 백업에서 열기")
	var warns := 0
	var warn_text := ""
	for v in lab.visible_toasts():
		if v.kind == "warn":
			warns += 1
			warn_text = str(v.text)
	t.check(warns == 1 and lab.visible_toasts().size() == 1, "백업 경고 알림 하나만 남음(%d개 중 경고 %d)" % [lab.visible_toasts().size(), warns])
	# 경고에 원본이 깨진 이유(검토 I04: 예전엔 Experiment.from_snapshot 이 이유를 버려 "…열었습니다: " 뒤가 비었음)와
	# 기록이 연 틱부터라는 안내(검토 J19)
	var reason := str(SimSnapshot.from_text("{}").error)
	t.check(reason != "" and warn_text.contains("(%s)" % reason) and warn_text.contains("틱 %s 부터" % LabMain._commas(lab.world.tick)),
			"백업 경고에 깨진 이유·기록 시작 틱: \"%s\"" % warn_text)
	for p in [path, path + ".bak", path + ".broken"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	lab._clear_toasts()
	# 밭 잃음 10번 → 알림 하나 "×10", 마지막 문장
	for i in 10:
		lab.show_toast("버려진 밭 1곳이 풀밭으로 돌아감 (남은 밭 %d)" % (20 - i), "farm_lost", 100 + i)
	var vt := lab.visible_toasts()
	t.check(vt.size() == 1 and int(vt[0].count) == 10 and str(vt[0].text).contains("남은 밭 11"), "밭 잃음 10번 → 알림 하나(×%d)" % (int(vt[0].count) if not vt.is_empty() else 0))
	# 비교 모드 이름표(group)가 다르면 따로 묶음: A·B 번갈아 4번씩 → 알림 둘(각 ×4), A 한 번 더 → A 만 ×5, 이름표 없음은 셋째
	lab._clear_toasts()
	for i in 4:
		lab.show_toast("A · 버려진 밭 %d" % i, "farm_lost", 400 + i, "A")
		lab.show_toast("B · 버려진 밭 %d" % i, "farm_lost", 400 + i, "B")
	vt = lab.visible_toasts()
	t.check(vt.size() == 2 and _toast_of(vt, "A").get("count", 0) == 4 and _toast_of(vt, "B").get("count", 0) == 4
			and str(_toast_of(vt, "A").get("text", "")) == "A · 버려진 밭 3" and str(_toast_of(vt, "B").get("text", "")) == "B · 버려진 밭 3",
			"밭 잃음 묶기는 이름표(group)마다: A ×%s · B ×%s" % [str(_toast_of(vt, "A").get("count")), str(_toast_of(vt, "B").get("count"))])
	lab.show_toast("A · 버려진 밭 9", "farm_lost", 409, "A")
	vt = lab.visible_toasts()
	t.check(vt.size() == 2 and _toast_of(vt, "A").get("count", 0) == 5 and _toast_of(vt, "B").get("count", 0) == 4 and str(vt.back().group) == "A",
			"A 한 번 더 → A 만 ×5(맨 아래로), B ×4 그대로")
	lab.show_toast("버려진 밭", "farm_lost", 410)
	vt = lab.visible_toasts()
	t.check(vt.size() == 3 and _toast_of(vt, "").get("count", 0) == 1, "이름표 없는 밭 잃음은 따로(알림 셋)")
	# 강조 알림(멸종)은 일상 알림 묶음에 밀려나지 않음
	lab._clear_toasts()
	lab.show_toast("멸종 — 마지막 개체가 사라짐", "extinction", 300)
	for i in 5:
		lab.show_toast("버려진 밭 %d" % i, "farm_lost", 301 + i)
	for i in 4:
		lab.show_toast("평균 %d세대 도달" % i, "milestone", 310 + i)
	var kinds: Array[String] = []
	for v in lab.visible_toasts():
		kinds.append(str(v.kind))
	t.check(kinds.size() == UiConfig.integer("lab.toast_max") and kinds.has("extinction") and kinds.count("farm_lost") <= 1,
			"넘치면 강조 알림이 아닌 것부터 지움: %s" % [kinds])
	lab._clear_toasts()
	for i in 5:
		lab.show_toast("발견 %d" % i, "discovery", i)
	t.check(lab.visible_toasts().size() == UiConfig.integer("lab.toast_max") and str(lab.visible_toasts()[0].text) == "발견 1",
			"모두 강조면 가장 오래된 것부터 지움")
	lab._clear_toasts()
	# 긴 오류 문장: 지도 안에서 줄을 바꾸고, toast_error_seconds 동안
	var long := "스냅숏을 열 수 없습니다(/home/researcher/experiments/2026-10-07/very-long-folder-name/sub/snapshot-tick-0012000.json): 파일이 없습니다 — 새 실험으로 엽니다"
	lab.show_toast(long + long, "error")
	await t.frames(2)
	var panel: PanelContainer = lab._toasts.back().panel
	var area := lab._map_area.get_global_rect()
	var pr := panel.get_global_rect()
	var room := minf(UiConfig.num("lab.toast_max_width"), area.size.x - 2.0 * UiConfig.num("lab.map_overlay_margin"))
	t.check(area.encloses(pr) and pr.size.x <= room + 1.0 and pr.size.y > 2.0 * UiTheme.regular_font().get_height(UiConfig.integer("lab.font_size")),
			"긴 오류 알림: 지도 안(%s ⊂ %s), 폭 ≤ %.0f, 여러 줄" % [pr, area, room])
	t.check(is_equal_approx(float(lab.visible_toasts()[0].left), UiConfig.num("lab.toast_error_seconds")), "오류 알림은 toast_error_seconds 동안")
	lab._clear_toasts()
	lab.set_paused(false)


## 멸종: 그 순간 멈추고(lab.pause_on_extinction), 멸종 표지·평균 세대 "—"·정보 창 멸종 안내. 다시 재생하면 빈 지도가 계속,
## 새 실험은 저절로 재생. 설정을 끄면 멈추지 않음.
func _extinction(t, lab: LabMain) -> void:
	lab.new_experiment("no_resources", {}, 1)
	lab.set_paused(false)
	lab.set_speed(64)
	var guard := 0
	while lab.world.extinct_tick < 0 and guard < 600:
		lab.advance_frame(DT)
		guard += 1
	var et := lab.world.extinct_tick
	t.check(et >= 0 and lab.is_paused(), "멸종하는 순간 멈춤(틱 %d)" % et)
	var tk := lab.world.tick
	for i in 30:
		lab.advance_frame(DT)
	t.check(lab.world.tick == tk, "멸종 뒤 멈춘 채 틱이 그대로")
	t.check(lab._lbl_gen.text == "—" and lab._extinct_badge.visible and lab._extinct_badge.text.contains(LabMain._commas(et)),
			"평균 세대 \"%s\", 멸종 표지 \"%s\"" % [lab._lbl_gen.text, lab._extinct_badge.text])
	t.check(lab.info_panel.summary_text().contains("멸종") and lab.info_panel.summary_text().contains(LabMain._commas(et)),
			"정보 창 안내: " + lab.info_panel.summary_text())
	# 고를 개체가 없으니 "지도에서 슬라임을 클릭하면…" 도움말을 숨김(검토 I48 — 예전엔 두 문장이 어긋난 채 함께 보였음)
	t.check(not lab.info_panel.empty_hint_visible(), "멸종 안내 아래에 클릭 도움말이 없음")
	t.check(lab._top_bar.get_combined_minimum_size().x <= UiConfig.num("lab.min_width"), "멸종 표시에서도 위쪽 막대가 최소 창 폭 안")
	lab.set_paused(false)
	for i in 5:
		lab.advance_frame(DT)
	# 멸종한 세계는 더 진행하지 않는다(실행기처럼 — 검토 I13: 예전엔 빈 세계가 계속 돌아 내보낸 요약·연대기가 실행기와 달랐음)
	t.check(lab.world.tick == tk and not lab.is_paused() and lab.speed_text() == LabMain.EXTINCT_SPEED_TEXT and lab._lbl_speed.text == LabMain.EXTINCT_SPEED_TEXT
			and _speed_color(lab) == UiTheme.color("text"),
			"다시 재생해도 멸종한 세계는 틱 %d 그대로(지금 %d), 막대 \"%s\"(경고 색 아님)" % [tk, lab.world.tick, lab._lbl_speed.text])
	lab.set_paused(true)
	lab.new_experiment("default", {}, 1)
	t.check(lab.is_paused() and lab.info_panel.summary_text().contains("슬라임을 눌러") and lab.info_panel.empty_hint_visible(),
			"새 세계: 사용자가 멈춘 상태는 그대로, 안내는 처음 문구(클릭 도움말도)")
	# 멸종 때문에 저절로 멈춘 상태는 새 실험에서 풀림
	lab.new_experiment("no_resources", {}, 1)
	lab.set_paused(false)
	guard = 0
	while lab.world.extinct_tick < 0 and guard < 600:
		lab.advance_frame(DT)
		guard += 1
	lab.new_experiment("default", {}, 1)
	t.check(not lab.is_paused() and not lab._extinct_badge.visible, "멸종으로 멈춘 뒤 새 실험 → 다시 재생, 표지 없음")
	# 설정을 끄면 멈추지 않는다
	var lab_cfg: Dictionary = UiConfig.data()["lab"]
	var keep: Variant = lab_cfg["pause_on_extinction"]
	lab_cfg["pause_on_extinction"] = false
	lab.new_experiment("no_resources", {}, 1)
	lab.set_paused(false)
	guard = 0
	while lab.world.extinct_tick < 0 and guard < 600:
		lab.advance_frame(DT)
		guard += 1
	var t2 := lab.world.tick
	for i in 5:
		lab.advance_frame(DT)
	lab_cfg["pause_on_extinction"] = keep
	t.check(not lab.is_paused() and lab.world.tick == t2 and t2 == lab.world.extinct_tick, "pause_on_extinction 끄면 멈추지 않음(세계는 멸종한 틱 %d 그대로)" % t2)
	# Home 키 = 지도 전체 보기(따라가기 끔)
	lab.new_experiment("default", {}, 1)
	lab.select_slime(lab.world.s_id[0])
	lab.map_view.focus_on(lab.world.s_id[0])
	lab.map_view.follow_selected = true
	lab.info_panel.set_follow(true)
	var cam := lab.map_view.get_camera()
	t.check(lab._handle_key(KEY_HOME) and not lab.map_view.follow_selected and not lab.info_panel._follow.button_pressed
			and float(cam.get("distance")) > UiConfig.num("camera.focus_distance"), "Home → 지도 전체 보기, 따라가기 끔(정보 창 단추도)")
	t.check(lab._fit_btn.text == LabMain.FIT_TEXT and LabMain.MAP_HINT.contains("Home"), "지도 위 \"전체 보기\" 단추·도움말")
	lab.select_slime(-1)


## 큰 두뇌(설정이 허용하는 은닉 64)를 골라도 정보 창·지도 폭이 그대로(열지도는 창 안에 맞추거나 가로로 스크롤).
func _wide_brain(t, lab: LabMain) -> void:
	lab.new_experiment("default", {"brain.hidden": 64, "brain.memory_units": 16, "population.initial": 30}, 2)
	await t.frames(2)
	var pw := lab.info_panel.size.x
	var mw := lab._map_area.size.x
	lab.select_slime(lab.world.s_id[0])
	await t.frames(2)
	var pw2 := lab.info_panel.size.x
	var mw2 := lab._map_area.size.x
	lab.select_slime(-1)
	await t.frames(2)
	t.check(is_equal_approx(pw, pw2) and is_equal_approx(mw, mw2) and is_equal_approx(lab._map_area.size.x, mw),
			"은닉 64·기억 16 개체를 골라도 정보 창 %.0f→%.0f·지도 %.0f→%.0f 폭 그대로" % [pw, pw2, mw, mw2])


# ════════════════════════════ 4단계 ════════════════════════════

## 자리 접기: 지도 오른쪽 아래 단추(눌림 = 보임)·set_dock_open. 접으면 지도가 그만큼 커지고, 접은 자리는 자식이 들어와도 숨긴 채.
## 조작 도움말은 지도가 좁으면(1280 창, 자리 펼침) 두 줄, 넓으면 한 줄이고 접기 단추와 겹치지 않음.
func _docks(t, lab: LabMain) -> void:
	lab.new_experiment("default", {}, 1)
	await t.frames(2)
	t.check(lab._dock_toggles.visible and lab._left_toggle.visible and lab._bottom_toggle.visible and lab._left_toggle.button_pressed
			and lab._bottom_toggle.button_pressed and lab.is_dock_open(LabMain.DOCK_LEFT) and lab.is_dock_open(LabMain.DOCK_BOTTOM),
			"자리 접기 단추 둘(펼침 = 눌림)")
	var area0 := lab._map_area.size
	t.check(lab._hint_label.text.contains("\n") and _overlays_ok(lab), "좁은 지도(%.0f): 조작 도움말 두 줄, 접기 단추와 안 겹치고 지도 안" % area0.x)
	# 단추로 아래 자리 접기(toggled 신호)
	lab._bottom_toggle.button_pressed = false
	await t.frames(2)
	var bh := UiConfig.num("lab.bottom_panel_height")
	t.check(not lab.is_dock_open(LabMain.DOCK_BOTTOM) and not lab._bottom_wrap.visible and lab._map_area.size.y >= area0.y + bh - 1.0,
			"아래 자리 접기 → 지도 높이 %.0f → %.0f" % [area0.y, lab._map_area.size.y])
	lab.set_dock_open(LabMain.DOCK_LEFT, false)
	await t.frames(2)
	t.check(not lab._left_wrap.visible and not lab._left_toggle.button_pressed and lab._map_area.size.x >= area0.x + UiConfig.num("lab.left_panel_width") - 1.0,
			"왼쪽 자리 접기(set_dock_open) → 지도 폭 %.0f → %.0f, 단추도 꺼짐" % [area0.x, lab._map_area.size.x])
	t.check(not lab._hint_label.text.contains("\n") and _overlays_ok(lab), "넓은 지도(%.0f): 조작 도움말 한 줄" % lab._map_area.size.x)
	# 접은 자리는 자식이 들어와도 숨긴 채
	var probe := Label.new()
	lab.bottom_dock.add_child(probe)
	await t.frames(1)
	t.check(not lab._bottom_wrap.visible and lab._bottom_toggle.visible, "접은 자리에 자식이 들어와도 숨긴 채")
	probe.queue_free()
	lab._left_toggle.button_pressed = true
	lab.set_dock_open(LabMain.DOCK_BOTTOM, true)
	await t.frames(2)
	t.check(lab._left_wrap.visible and lab._bottom_wrap.visible and lab._bottom_toggle.button_pressed and lab._map_area.size.is_equal_approx(area0),
			"다시 펴면 자리·지도 크기 되돌아감(%s)" % str(lab._map_area.size))


## 도움말·접기 단추가 지도 자리 안이고 서로 겹치지 않음.
func _overlays_ok(lab: LabMain) -> bool:
	var area := Rect2(Vector2.ZERO, lab._map_area.size)
	var hr := _rect(lab._hint)
	var tr := _rect(lab._dock_toggles)
	return area.encloses(hr) and area.encloses(tr) and not hr.intersects(tr)


func _rect(c: Control) -> Rect2:
	return Rect2(c.position, c.size)


## 비교 모드: 시작 오류, 지도 둘 나란히(각자 SubViewport·3D 세계·표지), 위쪽 막대, 프레임마다 같은 틱 수, B 지도 갱신,
## 사건(events_tagged 0·1, events 는 A 만)·알림 이름표, recorded 0·1, 해시·상태가 헤드리스와 같음.
func _compare(t, lab: LabMain) -> void:
	lab.set_paused(true)
	lab.new_experiment("default", {}, 1)
	var before := lab.world
	var lists := []
	var on_changed := func(list: Array) -> void: lists.append(list.size())
	lab.experiments_changed.connect(on_changed)
	var e1 := lab.start_compare({preset = "없는예설정"}, {preset = "default"})
	var e2 := lab.start_compare({preset = "default", seed = 1}, {preset = "없는예설정", seed = 1})
	t.check(e1.begins_with("A: ") and e2.begins_with("B: ") and lab.world == before and not lab.is_comparing() and lists.is_empty(),
			"비교 시작 실패 → \"A: …\"/\"B: …\" 오류, 지금 실험 그대로 (%s / %s)" % [e1, e2])
	var rec: Array[int] = [0, 0]
	var tagged: Array[int] = [0, 0]
	var plain: Array[int] = [0]
	var on_rec := func(i: int, _row: Dictionary) -> void: rec[i] += 1
	var on_tag := func(i: int, list: Array) -> void: tagged[i] += list.size()
	var on_ev := func(list: Array) -> void: plain[0] += list.size()
	lab.recorded.connect(on_rec)
	lab.events_tagged.connect(on_tag)
	lab.events.connect(on_ev)
	var err := lab.start_compare({preset = "demo_fast", overrides = {}, seed = 1}, {preset = "demo_fast", overrides = {"mutation.rate": B_MUTATION}, seed = 2})
	var xa := lab.experiment(0)
	var xb := lab.experiment(1)
	t.check(err == "" and lab.is_comparing() and lab.experiments.size() == 2 and xa.tag == "A" and xb.tag == "B" and lists == [2],
			"비교 시작: 실험 [A, B], experiments_changed(2) (%s, %s)" % [err, lists])
	if xb == null:
		return
	t.check(lab.world == xa.world and lab.map_view == lab.map_view_of(0) and lab.map_view.world == xa.world and lab.map_view_of(1) != null
			and lab.map_view_of(1).world == xb.world, "world = A 의 세계, 지도 A·B 가 각자 세계를 그림")
	t.check(is_equal_approx(float(xb.world.cfg.mutation.rate), B_MUTATION) and not is_equal_approx(float(xa.world.cfg.mutation.rate), B_MUTATION),
			"B 의 바꾼 값은 B 에만(돌연변이율 A %.2f · B %.2f)" % [float(xa.world.cfg.mutation.rate), float(xb.world.cfg.mutation.rate)])
	await t.frames(2)
	var ca := lab._map_container
	var cb := lab._map_area.get_node_or_null("MapContainerB") as SubViewportContainer
	t.check(cb != null and lab.map_view_of(1).get_viewport().get_parent() == cb, "B 지도 = MapContainerB ⊃ SubViewport ⊃ MapView")
	if cb == null:
		return
	var gap := float(UiConfig.integer("compare.gap_px"))
	t.check(is_zero_approx(ca.position.x) and is_equal_approx(cb.position.x - (ca.position.x + ca.size.x), gap)
			and is_equal_approx(cb.position.x + cb.size.x, lab._map_area.size.x) and absf(ca.size.x - cb.size.x) <= 1.0
			and is_equal_approx(ca.size.y, lab._map_area.size.y) and is_equal_approx(cb.size.y, ca.size.y),
			"A | B 나란히: 폭 %.0f + 사이 %.0f + %.0f = 지도 자리 %.0f" % [ca.size.x, gap, cb.size.x, lab._map_area.size.x])
	var va := lab._map_viewport
	var vb := lab.map_view_of(1).get_viewport() as SubViewport
	t.check(va.own_world_3d and vb.own_world_3d and va.find_world_3d() != vb.find_world_3d() and Vector2(vb.size).is_equal_approx(cb.size),
			"B 의 3D 세계가 따로, 뷰포트 = 칸 크기(%s)" % str(vb.size))
	var ha := lab._map_area.get_node_or_null("MapTitle") as Control
	var hb := lab._map_area.get_node_or_null("MapTitleB") as Control
	# 이름은 칸 폭에 맞춰 줄일 수 있다(G33): 전체 이름 = 실험 이름, 보이는 글에 자기 씨앗
	t.check(hb != null and _title_text(ha).begins_with("A|") and _title_text(hb).begins_with("B|")
			and lab._panes[0].full_title == xa.label and lab._panes[1].full_title == xb.label
			and _title_text(ha).contains("씨앗 1") and _title_text(hb).contains("씨앗 2"),
			"지도마다 표지: %s / %s" % [_title_text(ha), _title_text(hb)])
	if hb != null:
		t.check(_rect(ca).encloses(_rect(ha)) and _rect(cb).encloses(_rect(hb)), "표지가 자기 지도 칸 안")
	# 왼쪽 자리를 접어 지도가 넓어지면 조작 도움말(두 줄)은 A 지도 칸 안에(두 지도 사이를 걸치지 않게)
	t.check(_overlays_ok(lab), "비교 모드 도움말·접기 단추가 지도 안, 서로 안 겹침")
	# 최소 창·자리 펼침(A 칸 약 338px): 두 줄도 안 들어가면 키 줄을 나눈 세 줄로 A 칸 안에(통합 때 더함 — 두 지도 사이를 걸치던 것)
	t.check(_rect(ca).encloses(_rect(lab._hint)) and lab._hint_label.text.count("\n") == 2,
			"좁은 비교 모드(A 칸 %.0f): 도움말 세 줄로 A 칸 안(%s)" % [ca.size.x, _rect(lab._hint)])
	lab.set_dock_open(LabMain.DOCK_LEFT, false)
	await t.frames(2)
	t.check(_rect(ca).encloses(_rect(lab._hint)) and _overlays_ok(lab), "넓어진 비교 모드: 도움말이 A 지도 칸 안(%s ⊂ %s)" % [_rect(lab._hint), _rect(ca)])
	lab.set_dock_open(LabMain.DOCK_LEFT, true)
	await t.frames(2)
	lab.advance_frame(DT)
	t.check(lab._cmp_box.visible and not lab._single_box.visible and lab._cmp_pop[0].text == LabMain._commas(xa.world.population())
			and lab._cmp_pop[1].text == LabMain._commas(xb.world.population()) and lab._cmp_stage[1].text == SimWorld.STAGE_NAMES[xb.world.stage],
			"위쪽 막대: [A] %s · %s │ [B] %s · %s" % [lab._cmp_pop[0].text, lab._cmp_stage[0].text, lab._cmp_pop[1].text, lab._cmp_stage[1].text])
	t.check(lab._top_bar.get_combined_minimum_size().x <= UiConfig.num("lab.min_width"), "비교 모드 위쪽 막대도 최소 창 폭 안")
	t.check(lab.default_export_dir().get_file().ends_with("-seed1-vs-seed2"), "비교 모드 기본 내보내기 폴더에 두 씨앗: %s" % lab.default_export_dir().get_file())
	_compare_portrait(t, lab)
	await _compare_toasts(t, lab)
	# 진행: 프레임마다 A·B 가 같은 틱 수
	lab.set_paused(false)
	lab.set_speed(8)
	var same := true
	var total := 0
	for i in 60:
		var a0 := xa.world.tick
		var b0 := xb.world.tick
		var n := lab.advance_frame(DT)
		same = same and xa.world.tick - a0 == n and xb.world.tick - b0 == n
		total += n
	t.check(same and total > 0 and xa.world.tick == xb.world.tick, "8배 60프레임: 프레임마다 A·B 가 같은 틱 수(합 %d틱)" % total)
	var tl := UiConfig.num("map.tile_size")
	var bound := maxf(MapView.stack_max(), UiConfig.num("map.store_slime_offset")) * tl + 0.01
	t.check(lab.map_view_of(1)._has_prev and _max_drift_of(lab, 1) <= tl + bound,
			"B 지도도 틱마다 보간 기억·프레임마다 갱신(가장 먼 %.2f칸)" % _max_drift_of(lab, 1))
	# 두 쪽 모두 발견할 때까지: 사건은 실험마다, 알림 앞에 이름표
	lab.set_paused(true)
	var prefixes := {}
	var bad := ""
	var guard := 0
	while (xa.world.stage == 0 or xb.world.stage == 0 or tagged[1] == 0) and guard < 200:
		lab.step_ticks(25)
		lab.advance_frame(DT)
		for v in lab.visible_toasts():
			var s := str(v.text)
			if s.begins_with("A · "):
				prefixes["A"] = true
			elif s.begins_with("B · "):
				prefixes["B"] = true
			else:
				bad = s
		guard += 1
	t.check(xa.world.stage > 0 and xb.world.stage > 0, "A·B 모두 발견(틱 %d, 단계 %d·%d)" % [xa.world.tick, xa.world.stage, xb.world.stage])
	t.check(tagged[0] > 0 and tagged[1] > 0 and plain[0] == tagged[0],
			"events_tagged 0·1 모두(A %d·B %d건), events 는 A 만(%d건)" % [tagged[0], tagged[1], plain[0]])
	t.check(prefixes.has("A") and prefixes.has("B") and bad == "", "비교 모드 사건 알림 앞에 \"A · \"/\"B · \"(%s %s)" % [prefixes.keys(), bad])
	var every := int(xa.world.cfg.record.every)
	t.check(rec[0] == xa.world.tick / every and rec[1] == rec[0] and xa.rows().size() == rec[0] + 1 and xb.rows().size() == rec[1] + 1,
			"recorded(0)·(1) 각 %d·%d번(기대 %d), 기록 줄 %d·%d" % [rec[0], rec[1], xa.world.tick / every, xa.rows().size(), xb.rows().size()])
	# 해시 검사점을 지나 헤드리스와 같음
	lab.set_paused(false)
	lab.set_fast_forward(true)
	var hevery := int(xa.world.cfg.hash.every)
	var target := (xa.world.tick / hevery + 1) * hevery
	guard = 0
	while xa.world.tick <= target and guard < 600:
		lab.advance_frame(DT)
		guard += 1
	lab.set_speed(1)
	lab.set_paused(true)
	var ra: SimWorld = t.make_world({}, 1, "demo_fast")
	ra.step_n(xa.world.tick)
	var rb: SimWorld = t.make_world({"mutation.rate": B_MUTATION}, 2, "demo_fast")
	rb.step_n(xb.world.tick)
	t.check(xa.world.tick > target and xa.world.history_hash == ra.history_hash and t.same_state(xa.world, ra) == "",
			"A: 화면으로 %d틱(검사점 %d 지남) 진행해도 해시·상태가 헤드리스와 같음 %s" % [xa.world.tick, target, t.same_state(xa.world, ra)])
	t.check(xb.world.tick == xa.world.tick and xb.world.history_hash == rb.history_hash and t.same_state(xb.world, rb) == "",
			"B: 같은 %d틱, 해시·상태가 헤드리스와 같음 %s" % [xb.world.tick, t.same_state(xb.world, rb)])
	lab.experiments_changed.disconnect(on_changed)
	lab.recorded.disconnect(on_rec)
	lab.events_tagged.disconnect(on_tag)
	lab.events.disconnect(on_ev)


## 비교 모드 지도 칸(1280 창 약 338×456 — 세로로 긴 칸): 지도를 돌려(ui.compare.portrait_yaw_deg) 칸 높이를 더 씀
## (고치기 전 약 39%), 두 지도가 같은 방향, 지도 위 나침반 "북 →"·정보 창 방향 화살표가 화면 방향.
func _compare_portrait(t, lab: LabMain) -> void:
	var share := [0.0, 0.0]
	for k in 2:
		var mv := lab.map_view_of(k)
		var w := lab.experiment(k).world
		var cam := mv.get_camera()
		var vs := Vector2((mv.get_viewport() as SubViewport).size)
		var tl := UiConfig.num("map.tile_size")
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in [Vector3.ZERO, Vector3(w.w * tl, 0, 0), Vector3(w.w * tl, 0, w.h * tl), Vector3(0, 0, w.h * tl)]:
			var sp := cam.unproject_position(c)
			lo = lo.min(sp)
			hi = hi.max(sp)
		share[k] = (hi.y - lo.y) / maxf(vs.y, 1.0)
		t.check(lo.x >= -1.0 and lo.y >= -1.0 and hi.x <= vs.x + 1.0 and hi.y <= vs.y + 1.0, "지도 %d 전체가 칸 안(%s ~ %s, 칸 %s)" % [k, str(lo), str(hi), str(vs)])
	t.check(share[0] >= MIN_COMPARE_HEIGHT_SHARE and share[1] >= MIN_COMPARE_HEIGHT_SHARE,
			"세로로 긴 비교 칸: 지도가 칸 높이의 %.0f%% · %.0f%% ≥ %.0f%%(돌려 맞춤 — 고치기 전 약 39%%)" % [share[0] * 100.0, share[1] * 100.0, MIN_COMPARE_HEIGHT_SHARE * 100.0])
	var turns := lab.view_turns(0)
	var hb := lab._map_area.get_node_or_null("MapTitleB")
	var nb := hb.find_child("North", true, false) as Label if hb != null else null
	t.check(turns != 0 and lab.view_turns(1) == turns and lab._panes[0].north.visible and nb != null and nb.visible
			and nb.text == "북 " + LabMain.ARROWS[turns], "두 지도 같은 방향(%d), 나침반 \"%s\"" % [turns, nb.text if nb != null else ""])
	# 정보 창 방향: 낱말은 그대로, 화살표는 화면 방향
	var wb := lab.experiment(1).world
	var id := wb.s_id[0]
	lab.select_slime(id, 1)
	lab.advance_frame(DT)
	var hd := int(wb.slime_info(id).heading)
	t.check(lab.info_panel._v_head.text == "%s %s" % [InfoPanel.HEADING_WORDS[hd], InfoPanel.HEADING_ARROWS[(hd + turns) % 4]],
			"정보 창 방향 \"%s\"(화면 기준 화살표)" % lab.info_panel._v_head.text)
	lab.select_slime(-1)


## 비교 모드 알림: 실험 알림(group A/B)은 그 지도 칸 안(칸 폭 안에서 줄바꿈 — 고치기 전에는 두 지도 사이 가운데에 걸침),
## 앞에 실험 색 이름표 상자. 이름표 없는 알림은 칸 알림 아래 공용 묶음. _show_event 가 실험 이름표를 group 으로.
func _compare_toasts(t, lab: LabMain) -> void:
	lab._clear_toasts()
	var long := "B 의 아주 긴 알림 문장 — 저장고 근처의 밭이 버려져 풀밭으로 돌아갔고 남은 밭은 하나뿐입니다"
	lab.show_toast("B · " + long, "discovery", 10, "B")
	lab.show_toast("A · 첫 밭 일굼", "first_farm", 11, "A")
	lab.show_toast("결과를 내보냈습니다: /긴/경로/아무데나", "info")
	await t.frames(2)
	var inside := true
	var chips := true
	var shared_top := INF
	var pane_bottom := 0.0
	for e: Dictionary in lab._toasts:
		var r := (e.panel as Control).get_global_rect()
		var g := str(e.group)
		if g == "":
			shared_top = minf(shared_top, r.position.y)
			continue
		var c := lab._panes[Experiment.TAGS.find(g)].container.get_global_rect()
		inside = inside and c.encloses(r)
		pane_bottom = maxf(pane_bottom, r.end.y)
		chips = chips and (e.panel as Node).find_child("Tag", true, false) != null and not str((e.body as Label).text).begins_with(g + " ·")
	t.check(lab._toasts.size() == 3 and inside, "실험 알림은 자기 지도 칸 안(긴 B 알림도 칸 폭 안에서 줄바꿈)")
	t.check(chips, "실험 알림 앞에 실험 색 이름표 상자(본문에서는 \"A · \" 를 뺌, visible_toasts 의 text 는 그대로)")
	t.check(shared_top >= pane_bottom, "이름표 없는 알림은 칸 알림 아래(%.0f ≥ %.0f) — 겹치지 않음" % [shared_top, pane_bottom])
	# 칸마다 lab.toast_max ÷ 칸 수 개까지(좁은 칸에서 길어진 알림이 그 지도를 다 덮지 않게), 가장 새 것은 남음
	lab._clear_toasts()
	for i in 4:
		lab.show_toast("A · 알림 %d" % i, "info", i, "A")
	lab.show_toast("B · 알림", "info", 9, "B")
	var per := maxi(1, UiConfig.integer("lab.toast_max") / 2)
	var na := 0
	for v in lab.visible_toasts():
		na += 1 if str(v.group) == "A" else 0
	t.check(na == per and str(_toast_of(lab.visible_toasts(), "A").get("text", "")) == "A · 알림 %d" % (4 - per) and _toast_of(lab.visible_toasts(), "B").size() > 0,
			"비교 칸마다 알림 %d개까지(A %d개, 오래된 것부터 지움), B 칸은 따로" % [per, na])
	lab._clear_toasts()
	lab._show_event({kind = "farm_lost", text = "버려진 밭", tick = 1}, 0)
	lab._show_event({kind = "farm_lost", text = "버려진 밭", tick = 2}, 1)
	lab._show_event({kind = "farm_lost", text = "버려진 밭", tick = 3}, 0)
	var vt := lab.visible_toasts()
	t.check(vt.size() == 2 and _toast_of(vt, "A").get("count", 0) == 2 and _toast_of(vt, "B").get("count", 0) == 1
			and str(_toast_of(vt, "A").get("text", "")) == "A · 버려진 밭",
			"사건 알림(_show_event)은 실험 이름표가 group — 밭 잃음도 실험마다 따로 묶음")
	lab._clear_toasts()


## 표지 글자 "이름표|실험 이름"(이름표가 숨었으면 "|이름").
func _title_text(head: Node) -> String:
	if head == null:
		return ""
	var tag := head.find_child("Tag", true, false) as Control
	var title := head.find_child("Title", true, false) as Label
	var tag_text := ""
	if tag != null and tag.visible and tag.get_child_count() > 0:
		tag_text = (tag.get_child(0) as Label).text
	return "%s|%s" % [tag_text, title.text if title != null else ""]


## k 번째 지도에 그려진 위치와 그 세계의 지금 칸 가운데의 가장 큰 거리(칸).
func _max_drift_of(lab: LabMain, k: int) -> float:
	var w := lab.experiment(k).world
	var mv := lab.map_view_of(k)
	var tl := UiConfig.num("map.tile_size")
	var worst := 0.0
	for i in w.population():
		var p := mv.slime_instance_position(i)
		worst = maxf(worst, Vector2(p.x - (float(w.s_x[i]) + 0.5) * tl, p.z - (float(w.s_y[i]) + 0.5) * tl).length())
	return worst


## 비교 모드 선택: B 지도 클릭 → B 의 개체(정보 창 이름표 B, 고리는 B 지도에만), 가계 이동은 같은 실험 안,
## 따라가기·F 는 선택 지도, A 를 고르면 B 따라가기 꺼짐, Esc·빈 곳·없는 실험 = 해제, B "전체 보기" 는 B 만.
func _compare_select(t, lab: LabMain) -> void:
	var xa := lab.experiment(0)
	var xb := lab.experiment(1)
	if xb == null:
		t.check(false, "비교 모드가 아님")
		return
	var wb := xb.world
	var idb := -1
	for i in wb.population():
		if int(wb.slime_info(wb.s_id[i]).parent_a) >= 0:
			idb = wb.s_id[i]
			break
	lab.map_view_of(1).slime_clicked.emit(idb)
	t.check(idb >= 0 and lab.selected_id() == idb and lab.selected_index() == 1 and lab.info_panel.current_id() == idb
			and lab.info_panel.current_tag() == "B" and lab.info_panel._world == wb, "B 지도 클릭 → B 의 #%d, 정보 창 이름표 \"%s\"" % [idb, lab.info_panel.current_tag()])
	t.check(lab.map_view_of(1).ring_info().visible and not lab.map_view.ring_info().visible, "선택 고리는 B 지도에만")
	var pa := int(wb.slime_info(idb).parent_a)
	lab.info_panel.slime_requested.emit(pa)
	t.check(lab.selected_id() == pa and lab.selected_index() == 1 and lab.info_panel._world == wb and lab.info_panel.current_tag() == "B",
			"정보 창 가계 → 같은 실험(B) 안에서 #%d" % pa)
	lab.select_slime(idb, 1)
	lab.info_panel.follow_toggled.emit(true)
	t.check(lab.map_view_of(1).follow_selected and not lab.map_view.follow_selected, "따라가기 단추 → B 지도만 따라감")
	var ida := xa.world.s_id[0]
	lab.map_view.slime_clicked.emit(ida)
	t.check(lab.selected_index() == 0 and lab.info_panel.current_tag() == "A" and lab.info_panel._world == xa.world and lab.map_view.ring_info().visible
			and not lab.map_view_of(1).ring_info().visible and not lab.map_view_of(1).follow_selected and not lab.info_panel._follow.button_pressed,
			"A 개체를 고르면 이름표 A·고리는 A 에만, B 따라가기 꺼짐(정보 창 단추도)")
	_key(t, KEY_F)
	t.check(lab.map_view.follow_selected and not lab.map_view_of(1).follow_selected and lab.info_panel._follow.button_pressed
			and str(lab.visible_toasts().back().text).begins_with("A 지도"), "F → 선택한 A 지도 따라가기, 알림 \"%s\"" % str(lab.visible_toasts().back().text))
	_key(t, KEY_F)
	t.check(not lab.map_view.follow_selected, "F 다시 → 끔")
	lab.select_slime(idb, 1)
	_key(t, KEY_ESCAPE)
	t.check(lab.selected_id() == -1 and lab.selected_index() == -1 and lab.info_panel.current_id() == -1 and not lab.map_view.ring_info().visible
			and not lab.map_view_of(1).ring_info().visible, "Esc → 선택 해제(두 지도 모두 고리 없음)")
	t.check(lab.info_panel.current_tag() == "", "B 개체를 고른 뒤 Esc → 정보 창 이름표도 없음(\"%s\")" % lab.info_panel.current_tag())
	lab.select_slime(idb, 1)
	lab.map_view_of(1).slime_clicked.emit(-1)
	t.check(lab.selected_id() == -1, "B 지도 빈 곳 → 해제")
	lab.select_slime(idb, 5)
	t.check(lab.selected_id() == -1, "없는 실험 번호 → 해제")
	# B 의 "전체 보기" 단추는 B 지도만
	lab.select_slime(idb, 1)
	lab.map_view_of(1).focus_on(idb)
	lab.map_view_of(1).follow_selected = true
	lab.map_view.focus_on(ida)
	var hb := lab._map_area.get_node_or_null("MapTitleB")
	var fb := hb.find_child("FitButton", true, false) as Button if hb != null else null
	if fb != null:
		fb.pressed.emit()
	var focus := UiConfig.num("camera.focus_distance")
	t.check(fb != null and not lab.map_view_of(1).follow_selected and float(lab.map_view_of(1).get_camera().get("distance")) > focus
			and float(lab.map_view.get_camera().get("distance")) <= focus + 0.01, "B \"전체 보기\" → B 지도만 전체(A 카메라 그대로)")
	lab.fit_map()
	t.check(float(lab.map_view.get_camera().get("distance")) > focus, "Home(fit_map()) → 모든 지도 전체 보기")
	lab.select_slime(-1)


## 비교 끝: A 만 남고(같은 세계·틱·선택, 이름표 없음) B 지도·표지가 사라지며 A 지도가 자리 전체. A 는 이어서 진행.
## 새 실험·스냅숏 열기도 비교를 끝냄.
func _compare_stop(t, lab: LabMain) -> void:
	var xa := lab.experiment(0)
	var wa := lab.world
	var ida := wa.s_id[0]
	lab.select_slime(ida, 0)
	var lists := []
	var on_changed := func(list: Array) -> void: lists.append(list.size())
	lab.experiments_changed.connect(on_changed)
	var tick := wa.tick
	# 이름표 없는 오류 알림은 비교를 끝내도 남고, 이름표 붙은 알림(사건·F 키)만 지워짐
	lab.show_toast("내보내기 실패: B/timeseries.csv", "error")
	lab._show_event({kind = "discovery", text = "시험 발견", tick = tick}, 1)
	lab.select_slime(ida, 0)
	_key(t, KEY_F)
	_key(t, KEY_F)
	# (F 가 카메라를 그 개체로 옮겼으니 전체 보기로 되돌림 — 사용자가 움직인 카메라는 비교를 끝내도 그대로 두므로)
	lab.fit_map()
	lab.stop_compare()
	await t.frames(2)
	var texts: Array[String] = []
	for v in lab.visible_toasts():
		texts.append(str(v.text))
	t.check(texts.has("내보내기 실패: B/timeseries.csv") and texts.size() == 2 and texts.back().begins_with("비교를 끝냈습니다"),
			"비교 끝: 이름표 없는 오류 알림은 남고 A·B 알림·\"A 지도 따라가기\" 알림만 지움 %s" % [texts])
	t.check(lab.view_turns(0) == 0 and not lab._panes[0].north.visible, "혼자 모드 지도는 다시 북쪽 위(나침반 숨김)")
	t.check(not lab.is_comparing() and lab.experiments.size() == 1 and lab.experiment(0) == xa and lab.world == wa and wa.tick == tick
			and xa.tag == "" and lists == [1], "비교 끝 → A 만(같은 세계·틱 %d), 이름표 없음, experiments_changed(1) %s" % [wa.tick, lists])
	t.check(lab._map_area.get_node_or_null("MapContainerB") == null and lab._map_area.get_node_or_null("MapTitleB") == null and lab.map_view_of(1) == null,
			"B 지도·표지 지움")
	t.check(lab._map_container.size.is_equal_approx(lab._map_area.size) and _title_text(lab._map_area.get_node_or_null("MapTitle")) == "|" + xa.label,
			"A 지도가 지도 자리 전체(%s), 표지 \"%s\"" % [str(lab._map_container.size), _title_text(lab._map_area.get_node_or_null("MapTitle"))])
	t.check(lab.selected_id() == ida and lab.selected_index() == 0 and lab.info_panel.current_tag() == "" and lab.map_view.ring_info().visible,
			"A 의 선택은 그대로, 정보 창 이름표 없음")
	lab.advance_frame(DT)
	t.check(lab._single_box.visible and not lab._cmp_box.visible, "위쪽 막대 혼자 모드로")
	lab.set_paused(false)
	lab.set_speed(8)
	for i in 30:
		lab.advance_frame(DT)
	lab.set_paused(true)
	var ref: SimWorld = t.make_world({}, 1, "demo_fast")
	ref.step_n(wa.tick)
	t.check(wa.tick > tick and t.same_state(wa, ref) == "", "비교를 끝낸 뒤 A 가 이어서 진행(%d틱, 헤드리스와 같은 상태) %s" % [wa.tick, t.same_state(wa, ref)])
	lab.stop_compare()
	t.check(lists == [1], "비교 중이 아니면 stop_compare 는 아무것도 안 함")
	lab.experiments_changed.disconnect(on_changed)
	# 새 실험·스냅숏 열기도 비교를 끝낸다
	t.check(lab.start_compare({preset = "default", seed = 3}, {preset = "default", seed = 4}) == "" and lab.is_comparing(), "다시 비교 시작")
	# B 개체를 고른 채 비교를 끝내면 선택·이름표 모두 없음
	lab.select_slime(lab.experiment(1).world.s_id[0], 1)
	var had_b := lab.info_panel.current_tag() == "B"
	lab.stop_compare()
	t.check(had_b and lab.selected_id() == -1 and lab.info_panel.current_id() == -1 and lab.info_panel.current_tag() == "",
			"B 를 고른 채 비교 끝 → 선택 해제, 정보 창 이름표 없음(\"%s\")" % lab.info_panel.current_tag())
	lab.start_compare({preset = "default", seed = 3}, {preset = "default", seed = 4})
	lab.new_experiment("default", {}, 5)
	t.check(not lab.is_comparing() and lab._map_area.get_node_or_null("MapContainerB") == null and lab.world.seed_value == 5 and lab.experiment(0).tag == "",
			"새 실험 → 비교 끝(지도 하나)")
	var path := TMP.path_join("compare.json")
	t.check(SimSnapshot.save_file(lab.world, path) == "", "스냅숏 저장")
	lab.start_compare({preset = "default", seed = 3}, {preset = "default", seed = 4})
	t.check(lab.open_snapshot(path) == "" and not lab.is_comparing() and lab.map_view_of(1) == null, "스냅숏 열기 → 비교 끝")
	for p in [path, path + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## 비교 모드 멸종: 한쪽만 멸종하면 멈추지 않고(같은 틱으로 계속 견줌) 그 지도에만 표지·"A · " 멸종 알림·정보 창 안내,
## 모두 멸종하면 멈춤. 새 실험은 다시 재생.
func _compare_extinction(t, lab: LabMain) -> void:
	lab.start_compare({preset = "no_resources", seed = 1}, {preset = "demo_fast", seed = 1})
	var xa := lab.experiment(0)
	var xb := lab.experiment(1)
	lab.set_paused(false)
	lab.set_speed(64)
	var saw := false
	var guard := 0
	while xa.world.extinct_tick < 0 and guard < 600:
		lab.advance_frame(DT)
		guard += 1
	for v in lab.visible_toasts():
		saw = saw or (v.kind == "extinction" and str(v.text).begins_with("A · "))
	for i in 5:
		lab.advance_frame(DT)
	# 멸종한 A 는 멸종한 틱 그대로(실행기처럼 — 검토 I13), 살아남은 B 만 진행. 위쪽 막대 틱은 "A/B"
	t.check(xa.world.extinct_tick >= 0 and xb.world.extinct_tick < 0 and not lab.is_paused() and xa.world.tick == xa.world.extinct_tick
			and xb.world.tick > xa.world.tick and lab._lbl_tick.text == "%s/%s" % [LabMain._commas(xa.world.tick), LabMain._commas(xb.world.tick)],
			"A 만 멸종(틱 %d) → 멈추지 않고 B 만 계속(A 틱 %d, B 틱 %d, 막대 \"%s\")" % [xa.world.extinct_tick, xa.world.tick, xb.world.tick, lab._lbl_tick.text])
	var hb := lab._map_area.get_node_or_null("MapTitleB")
	var bb := hb.find_child("ExtinctBadge", true, false) as Label if hb != null else null
	t.check(lab._extinct_badge.visible and lab._extinct_badge.text.contains(LabMain._commas(xa.world.extinct_tick)) and bb != null and not bb.visible,
			"멸종 표지는 A 지도에만(\"%s\")" % lab._extinct_badge.text)
	t.check(saw, "멸종 알림 \"A · …\"")
	t.check(lab.info_panel.summary_text().contains("A 는 멸종") and lab.info_panel.summary_text().contains("B 지도"), "정보 창 안내: " + lab.info_panel.summary_text())
	t.check(_empty_inside(lab), "정보 창 멸종 안내가 창 여백(info.padding) 안에서 줄을 바꿈(%s ⊂ %s)"
			% [str(lab.info_panel._empty_label.get_global_rect()), str(lab.info_panel.get_global_rect())])
	lab.start_compare({preset = "no_resources", seed = 1}, {preset = "no_resources", seed = 2})
	xa = lab.experiment(0)
	xb = lab.experiment(1)
	lab.set_paused(false)
	guard = 0
	while (xa.world.extinct_tick < 0 or xb.world.extinct_tick < 0) and guard < 1200:
		lab.advance_frame(DT)
		guard += 1
	var tk := xa.world.tick
	for i in 5:
		lab.advance_frame(DT)
	t.check(xa.world.extinct_tick >= 0 and xb.world.extinct_tick >= 0 and lab.is_paused() and xa.world.tick == tk,
			"A·B 모두 멸종(틱 %d·%d) → 멈춤" % [xa.world.extinct_tick, xb.world.extinct_tick])
	t.check(lab.info_panel.summary_text().contains("모두 멸종") and not lab.info_panel.empty_hint_visible(),
			"정보 창 안내(클릭 도움말 없음): " + lab.info_panel.summary_text())
	lab.new_experiment("default", {}, 1)
	t.check(not lab.is_paused() and not lab._extinct_badge.visible, "모두 멸종으로 멈춘 뒤 새 실험 → 다시 재생")
	lab.set_paused(true)


## 정보 창 빈 안내 글이 창 안쪽 여백(info.padding) 안(고치기 전: 창 폭 전체를 써 양쪽 끝에 닿음).
func _empty_inside(lab: LabMain) -> bool:
	var pad := UiConfig.num("info.padding")
	var pr := lab.info_panel.get_global_rect().grow(-pad + 0.5)
	return lab.info_panel._empty_label.is_visible_in_tree() and pr.encloses(lab.info_panel._empty_label.get_global_rect())


## 최소 창(1280×720)·자리 모두 펼침에서 비교 모드: 지도 칸 ≥ MIN_COMPARE_MAP, 긴 실험 이름은 "…"(표지가 칸 안),
## 계절이 다르면 "A/B", 하루 길이가 다르면 "날" 숨김, 가장 긴 표시에서도 위쪽 막대가 최소 창 폭 안.
func _compare_layout(t, lab: LabMain) -> void:
	lab.start_compare({preset = "demo_fast", seed = 1}, {preset = "harsh_winter", seed = 1})
	await t.frames(2)
	var ca := lab._map_container
	var cb := lab._map_area.get_node_or_null("MapContainerB") as Control
	t.check(cb != null and ca.size.x >= MIN_COMPARE_MAP.x and ca.size.y >= MIN_COMPARE_MAP.y and cb.size.x >= MIN_COMPARE_MAP.x and cb.size.y >= MIN_COMPARE_MAP.y,
			"최소 창에서 비교 지도 한 칸 %s ≥ %s(창 %s)" % [str(ca.size), str(MIN_COMPARE_MAP), str(t.root.size)])
	t.check(_fits_window(lab) and _fits_height(lab), "비교 모드(파라미터 B 칸·범례 둘)에서도 배치가 창 안(정보 창 오른쪽 끝 %.0f)" % lab.info_panel.get_global_rect().end.x)
	# 1280×720 창(검토 J29 전의 최소 창)에서도 같은 배치 검사
	var small: Vector2i = t.root.size
	t.root.size = SIZE_720
	await t.frames(2)
	t.check(ca.size.x >= MIN_COMPARE_MAP_720.x and ca.size.y >= MIN_COMPARE_MAP_720.y and cb.size.x >= MIN_COMPARE_MAP_720.x
			and cb.size.y >= MIN_COMPARE_MAP_720.y and _fits_window(lab) and _fits_height(lab),
			"1280×720 창에서 비교 지도 한 칸 %s ≥ %s, 배치가 창 안" % [str(ca.size), str(MIN_COMPARE_MAP_720)])
	t.root.size = small
	await t.frames(2)
	var ha :=lab._map_area.get_node_or_null("MapTitle") as Control
	var title := ha.find_child("Title", true, false) as Label
	var natural := title.get_theme_font("font").get_string_size(lab._panes[0].full_title, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
	var hb := lab._map_area.get_node_or_null("MapTitleB") as Control
	t.check(title.custom_minimum_size.x < natural and _rect(ca).encloses(_rect(ha)) and hb != null and _rect(cb).encloses(_rect(hb)),
			"긴 실험 이름은 줄여(%.0f < %.0f) 표지가 칸 안" % [title.custom_minimum_size.x, natural])
	# 같은 예설정·다른 씨앗(G33): 줄여도 예설정 이름만 줄이고 " · 씨앗 N" 은 남아 두 지도의 이름이 갈림(예전: 끝을 잘라 둘 다
	# "시연·검사용(아주 빠른 발견…")
	lab.start_compare({preset = "demo_fast", seed = 1}, {preset = "demo_fast", seed = 2})
	await t.frames(2)
	var shown := PackedStringArray()
	var tails_ok := true
	for k in 2:
		var tl := lab._panes[k].title
		var tw := tl.get_theme_font("font").get_string_size(tl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tl.get_theme_font_size("font_size")).x
		shown.append(tl.text)
		tails_ok = tails_ok and tl.text.ends_with("씨앗 %d" % (k + 1)) and tl.text.contains(GraphPanel.ELLIPSIS) and tw <= tl.size.x + 0.5
		tails_ok = tails_ok and _rect(lab._panes[k].container).encloses(_rect(lab._panes[k].head)) and lab._panes[k].full_title == lab.experiment(k).label
	t.check(tails_ok and shown[0] != shown[1], "좁은 비교 지도 이름: 예설정 이름만 줄이고 씨앗은 남김 %s" % str(shown))
	# 씨앗이 같고 값만 다른 비교(멈춤 표지까지 붙어 가장 좁을 때): 씨앗 대신 A·B 를 가르는 값을 남김(4단계 최종 점검: 예전엔
	# 둘 다 "… · 씨앗 1 · 돌연…", 고급 키는 "plants.regro…" / "plants.regrow…")
	lab.set_paused(true)
	for pair in [["mutation.rate", 0.08, 0.02, "0.08", "0.02"], ["plants.regrow", 0.5, 0.25, "=0.5", "=0.25"]]:
		lab.start_compare({preset = "demo_fast", seed = 1, overrides = {pair[0]: pair[1]}},
				{preset = "demo_fast", seed = 1, overrides = {pair[0]: pair[2]}})
		lab.set_paused(true)
		await t.frames(2)
		var vals := PackedStringArray()
		var vals_ok := true
		for k in 2:
			var tl := lab._panes[k].title
			var tw := tl.get_theme_font("font").get_string_size(tl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tl.get_theme_font_size("font_size")).x
			vals.append(tl.text)
			vals_ok = vals_ok and lab._panes[k].paused.visible and tl.text.contains(GraphPanel.ELLIPSIS) and tw <= tl.size.x + 0.5
			vals_ok = vals_ok and tl.text.ends_with(str(pair[3 + k])) and _rect(lab._panes[k].container).encloses(_rect(lab._panes[k].head))
		t.check(vals_ok and vals[0] != vals[1], "좁은 비교 지도 이름(씨앗 같고 %s 만 다름, 멈춤): 가르는 값을 남김 %s" % [pair[0], str(vals)])
	t.check(LabMain.fit_tail(" · 씨앗 2 · 돌연변이 0.08", 1e6, func(x: String) -> float: return float(x.length()), false) == "… · 씨앗 2 · 돌연변이 0.08"
			and LabMain.fit_tail(" · 씨앗 1 · 돌연변이 0.08", 1e6, func(x: String) -> float: return float(x.length()), true) == "… · 돌연변이 0.08"
			and LabMain.fit_tail(" · 씨앗 1 · 돌연변이 0.08 · 자원 1.4", 15.0, func(x: String) -> float: return float(x.length()), true) == "… · 돌연변이 0.08…"
			and LabMain.fit_tail(" · 씨앗 1 · plants.regrow=0.5", 15.0, func(x: String) -> float: return float(x.length()), true) == "… · plants…=0.5",
			"꼬리 줄임 규칙(씨앗이 같으면 씨앗 대신 첫 값, 그다음 끝 줄임, 그다음 이름 줄임)")
	lab.start_compare({preset = "demo_fast", seed = 1}, {preset = "harsh_winter", seed = 1})
	await t.frames(2)
	# 계절이 다른 때(빠른 계절 2일 vs 혹독한 겨울 5일)
	lab.step_ticks(130)
	lab.advance_frame(DT)
	var wa := lab.experiment(0).world
	var wb := lab.experiment(1).world
	var want := "%s/%s" % [LabMain.SEASON_NAMES[wa.season], LabMain.SEASON_NAMES[wb.season]]
	t.check(wa.season != wb.season and lab._lbl_season.text == want and lab._day_chip.visible, "계절이 다르면 \"%s\"(날은 같아 보임)" % lab._lbl_season.text)
	var w1 := _longest_bar(lab)
	t.check(w1 <= UiConfig.num("lab.min_width"), "비교 모드 가장 긴 표시(계절 A/B)에서도 위쪽 막대 %.0f ≤ 최소 창 폭" % w1)
	# 하루 길이가 다르면(고급 설정) 날을 숨긴다 — 계절 없음/계절, 낮/밤까지 다른 가장 긴 경우
	lab.start_compare({preset = "default", seed = 1}, {preset = "default", overrides = {"time.day_ticks": 45, "time.season_days": 0}, seed = 1})
	lab.step_ticks(50)
	lab.advance_frame(DT)
	t.check(not lab._day_chip.visible and lab._lbl_season.text.contains("/" + LabMain.NO_SEASON), "하루 길이가 다르면 날 숨김, 계절 \"%s\"" % lab._lbl_season.text)
	lab._lbl_daynight.text = "낮/밤"
	var w2 := _longest_bar(lab)
	t.check(w2 <= UiConfig.num("lab.min_width"), "하루 길이가 다른 가장 긴 표시에서도 위쪽 막대 %.0f ≤ 최소 창 폭" % w2)
	lab.new_experiment("default", {}, 1)
	t.check(lab._day_chip.visible and not lab._lbl_season.text.contains("/"), "혼자로 돌아오면 날 다시 보임")


## 배치가 창 안에 들어가는지: 본문 최소 폭 ≤ 창 폭, 정보 창 오른쪽 끝 = 창 오른쪽 끝, 아래 자리 = 왼쪽 자리 + 지도 폭(넘친 폭 없음).
## (통합 때 더함: 연대기 420 + 그래프 최소 540 이 1280 창의 아래 자리를 넘어 정보 창이 46px 밖으로 밀렸던 것)
func _fits_window(lab: LabMain) -> bool:
	var body := lab.info_panel.get_parent() as Control
	var ip := lab.info_panel.get_global_rect()
	var lab_r := lab.get_global_rect()
	var bottom_ok := not lab._bottom_wrap.visible or absf(lab._bottom_wrap.size.x - (lab._left_wrap.size.x if lab._left_wrap.visible else 0.0) - lab._map_area.size.x) < 0.5
	return body.get_combined_minimum_size().x <= lab.size.x + 0.5 and absf(ip.end.x - lab_r.end.x) < 0.5 and bottom_ok


## 비교 모드 상태 글자를 가장 길게 바꿔 위쪽 막대 최소 폭을 잰다(다음 프레임에 제자리로).
func _longest_bar(lab: LabMain) -> float:
	lab._lbl_tick.text = "1,234,567"
	lab._lbl_day.text = "20,577"
	for k in 2:
		lab._cmp_pop[k].text = "1,000"
		lab._cmp_stage[k].text = "농사"
	lab._lbl_speed.text = "빨리 감기 / 실제 1,234배"
	return lab._top_bar.get_combined_minimum_size().x


## 내보내기에서 지정한 파일을 실패로 돌려주는 실험(실제 디스크 오류 없이 — 엔진 ERROR 줄 없이 — 실패 길을 검사).
class FailingExperiment extends Experiment:
	var fail := false

	func export_dir(dir: String, with_lineage: bool = true) -> PackedStringArray:
		if fail:
			return PackedStringArray(["summary.json", "timeseries.csv"])
		return super(dir, with_lineage)


## 비교 모드 내보내기 실패: 어느 실험의 어느 파일인지("B/timeseries.csv" — 고치기 전에는 파일 이름만이라 A 인지 B 인지
## 몰랐음), 다 쓴 쪽은 "A 는 저장됨: 경로".
func _export_fail(t, lab: LabMain) -> void:
	var list: Array = []
	for k in 2:
		var fx := FailingExperiment.new()
		fx.preset = "default"
		fx.seed_value = k + 1
		fx.label = Experiment.default_label("default", {}, k + 1)
		fx._adopt(t.make_world({}, k + 1))
		fx.fail = k == 1
		list.append(fx)
	lab._adopt_list(list)
	var dir := TMP.path_join("export")
	var abs_dir := ProjectSettings.globalize_path(dir)
	var msg := lab.export_csv(dir)
	var a_dir := abs_dir.path_join("A")
	t.check(msg.begins_with("내보내기 실패: ") and msg.contains("B/summary.json") and msg.contains("B/timeseries.csv") and not msg.contains("A/summary.json")
			and not msg.contains("A/timeseries.csv") and msg.contains("A 는 저장됨: " + a_dir), "비교 모드 내보내기 실패 = 어느 실험의 파일인지: %s" % msg)
	t.check(FileAccess.file_exists(a_dir.path_join("timeseries.csv")) and _has_toast(lab, "error"), "A 의 결과는 쓰였고 오류 알림")
	LabMain._remove_tree(abs_dir)
	t.check(not DirAccess.dir_exists_absolute(abs_dir), "임시 내보내기 폴더를 지움(숨은 .gdignore 까지)")
	lab.new_experiment("default", {}, 1)


## 패널을 모두 빼면 자리째 숨고(접기 단추도), 다시 넣으면 보인다.
func _dock_empty(t, lab: LabMain) -> void:
	var panels: Array[Control] = [lab.param_panel, lab.graph_panel, lab.chronicle_panel]
	var parents: Array[Node] = []
	for p in panels:
		parents.append(p.get_parent())
		p.get_parent().remove_child(p)
	await t.frames(2)
	t.check(not lab._left_wrap.visible and not lab._bottom_wrap.visible and not lab._dock_toggles.visible, "빈 자리는 숨김(접기 단추도)")
	for i in panels.size():
		parents[i].add_child(panels[i])
	await t.frames(2)
	t.check(lab._left_wrap.visible and lab._bottom_wrap.visible and lab._dock_toggles.visible and lab.bottom_dock.get_child(0) == lab.graph_panel,
			"다시 넣으면 보임")
