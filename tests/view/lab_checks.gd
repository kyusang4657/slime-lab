extends RefCounted
## LabMain 검사: 장면·배치·테마, 프레임 진행(배속·멈춤·빨리 감기·예산), 선택 연결, 단축키, 사건 알림,
## 역사 해시(화면을 거쳐도 헤드리스와 같음), 명령줄 대체값, 스냅숏 열기. 프레임은 advance_frame 으로 직접 몬다.

const DT := 1.0 / 60.0
## 빨리 감기 측정 세계의 초기 개체 수(씨앗 3 에서 120프레임 내내 살아 있음)
const FF_POPULATION := 60
## 이 모듈이 적어도 하는 검사 수(중간에 스크립트 오류로 끊기면 실행기가 실패로 셈)
const MIN_CHECKS := 119
## 예산 측정 프레임 수, 평균 시뮬레이션 시간이 예산을 넘어도 되는 몫(ms)
const BUDGET_FRAMES := 60
const BUDGET_SLACK_MS := 0.5
## 16배(프레임당 1.6틱)에서 혼자 있는 개체가 한 프레임에 그려지는 거리 상한(칸): 1.6틱 × smoothstep 기울기 여유
const MULTI_TICK_MAX_STEP := 1.9
const SNAP_PATH := "user://lab_checks_snapshot.json"


func run(t) -> void:
	# 헤드리스 뿌리 창은 64×64 — 배치를 재는 검사를 위해 최소 창 크기로(끝나면 되돌림)
	var root_size: Vector2i = t.root.size
	t.root.size = Vector2i(UiConfig.integer("lab.min_width"), UiConfig.integer("lab.min_height"))
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(2)
	lab.set_process(false)
	await _layout(t, lab)
	_run_loop(t, lab)
	_budget(t, lab)
	_ff_pause(t, lab)
	_multi_tick_motion(t, lab)
	_speed_window(t, lab)
	_selection(t, lab)
	await _keys(t, lab)
	_events(t, lab)
	await _toast_rules(t, lab)
	_extinction(t, lab)
	_hash(t, lab)
	_args(t, lab)
	await _wide_brain(t, lab)
	lab.queue_free()
	await t.frames(1)
	t.root.size = root_size


func _layout(t, lab: LabMain) -> void:
	t.check(lab.world != null and lab.map_view != null and lab.info_panel != null, "장면이 만들어지고 기본 실험이 열림")
	t.check(lab.world.seed_value == UiConfig.integer("lab.default_seed"), "기본 씨앗으로 시작")
	t.check(lab.theme != null and lab.theme.default_font != null and lab.theme.has_stylebox("pressed", "Button"), "UiTheme 적용(글꼴·단추 모양)")
	t.check(lab.theme.get_font("font", UiTheme.TITLE) == UiTheme.bold_font(), "제목 글꼴 = 나눔고딕 굵게")
	var sv := lab.map_view.get_parent()
	t.check(sv is SubViewport and sv.get_parent() is SubViewportContainer and (sv.get_parent() as SubViewportContainer).stretch, "지도는 늘어나는 SubViewportContainer 안 SubViewport")
	t.check(lab.left_dock is VBoxContainer and lab.bottom_dock is HBoxContainer, "4단계 자리 종류")
	t.check(not lab._left_wrap.visible and not lab._bottom_wrap.visible, "빈 자리는 숨김")
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
	# 4단계가 무언가를 넣으면 보이고, 비우면 다시 숨는다
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
	t.check(not lab._left_wrap.visible and not lab._bottom_wrap.visible, "비우면 다시 숨김")


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
	t.check(nff > n64, "빨리 감기 %d틱 > 64배 %d틱(같은 60프레임)" % [nff, n64])
	t.check(sum_ms / 60.0 <= ff * 1.5 + 2.0 and max_ms <= ff + 30.0, "빨리 감기 예산 대략 지킴(평균 %.1fms, 최대 %.1fms, 예산 %.0fms)" % [sum_ms / 60.0, max_ms, ff])
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
	t.check(lab.last_sim_ms <= UiConfig.num("speed.sim_budget_ms") + 30.0, "프레임 시뮬레이션 시간 %.1fms ≈ 예산" % lab.last_sim_ms)
	# 다음 틱 비용을 미리 더해 보고 멈추므로 평균은 예산 안(+여유), 95% 는 예산 + 한 틱 안
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
		print("  예산(%s, %d마리): 평균 %.2fms, 95%% %.2fms, 최대 %.2fms, 틱당 약 %.2fms (예산 %.0fms)" % [mode, lab.world.population(), mean, p95, times.back(), per_tick, budget])
		t.check(mean <= budget + BUDGET_SLACK_MS and p95 <= budget + 2.0 * per_tick,
				"%s 예산 지킴: 평균 %.2fms ≤ %.1f, 95%% %.2fms ≤ 예산 + 틱 둘" % [mode, mean, budget + BUDGET_SLACK_MS, p95])
	lab.set_speed(64)
	# 아주 큰 프레임 시간은 speed.max_frame_delta_s 로 자른다
	lab.set_speed(1)
	lab._acc = 0.0
	var c1 := lab.world.tick
	lab.advance_frame(10.0)
	t.check(lab.world.tick - c1 <= int(UiConfig.num("speed.max_frame_delta_s") * UiConfig.num("speed.ticks_per_second_1x")) + 1, "큰 프레임 시간을 잘라 한꺼번에 몰아 돌지 않음")


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
	le.release_focus()
	le.queue_free()
	await t.frames(2)
	_key(t, KEY_1)
	t.check(lab.target_speed() == int(steps[0]), "초점이 풀리면 단축키 다시 동작")
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


func _key(t, code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		t.root.push_input(e)


func _events(t, lab: LabMain) -> void:
	t.check(lab.new_experiment("fast_civ", {}, 1) == "", "fast_civ 실험")
	var got: Array = []
	# 청취자가 사건 사전을 고쳐 써도(4단계 연대기 창이 꾸미는 경우 등) 세계의 연대기는 그대로여야 한다
	var spoil := func(list: Array) -> void:
		got.append_array(list)
		for e in list:
			e["text"] = "★ " + str(e.get("text", ""))
	lab.events.connect(spoil)
	var s0 := lab.world.stage
	var k := 0
	# 검사가 세계를 직접 진행(화면이 아님) → 다음 프레임에 LabMain 이 사건을 소비
	while lab.world.stage == s0 and k < 5000:
		lab.world.step()
		k += 1
	t.check(lab.world.stage != s0, "fast_civ 가 %d틱 안에 단계가 바뀜" % k)
	lab.set_paused(true)
	lab.advance_frame(DT)
	var disc := false
	for e in got:
		if str(e.get("kind", "")) == "discovery":
			disc = true
	t.check(disc, "events 신호에 발견 사건(%d건)" % got.size())
	lab.events.disconnect(spoil)
	var ref: SimWorld = t.make_world({}, 1, "fast_civ")
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
	err = lab.apply_args(PackedStringArray(["--preset=fast_civ", "--seed=9"]))
	t.check(err == "" and lab.world.seed_value == 9 and SimConfig.deep_equal(lab.world.cfg, SimConfig.build("fast_civ", {}).config), "--preset=fast_civ --seed=9")
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
	t.check(lab.open_snapshot("user://없는_스냅숏.json") != "" and lab.world.tick == tick, "열기 실패면 지금 세계 유지")
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
	var bound := maxf(MapView.STACK_MAX, UiConfig.num("map.store_slime_offset")) * tl + 0.01
	lab.set_fast_forward(true)
	for i in 10:
		lab.advance_frame(DT)
	lab.set_paused(true)
	lab.advance_frame(DT)
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
	for f in 120:
		var n := lab.advance_frame(DT)
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
	t.check(multi > 0 and seen > 0 and worst <= MULTI_TICK_MAX_STEP,
			"16배: 2틱 프레임 %d번, 혼자 있는 개체의 한 프레임 이동 최대 %.2f칸 ≤ %.1f(고치기 전 2.6칸)" % [multi, worst, MULTI_TICK_MAX_STEP])


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
	# 4FPS 미만(잘린 프레임 시간): 실제 = 0.75배, 경고 색
	lab.set_speed(1)
	for i in 12:
		lab.advance_frame(1.0 / 3.0)
	lab._refresh_status(true)
	t.check(absf(lab.actual_speed() - 0.75) < 0.02 and _speed_color(lab) == warn,
			"3FPS·1배: 실제 %.2f배(= 0.75, 잘리지 않은 프레임 시간), 경고 색" % lab.actual_speed())


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
	lab.set_paused(true)
	# 백업에서 연 스냅숏: 바뀐 세계 위에 경고 알림 하나
	var path := "user://lab_checks_backup.json"
	lab.world.step_n(10)
	SimSnapshot.save_file(lab.world, path)
	SimSnapshot.save_file(lab.world, path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{}")  # JSON 으로는 맞지만 스냅숏 형식이 아님(엔진 JSON 오류 줄 없이 깨진 원본 흉내)
	f.close()
	lab.show_toast("앞 알림", "info")
	t.check(lab.open_snapshot(path) == "", "깨진 원본 → 백업에서 열기")
	var warns := 0
	for v in lab.visible_toasts():
		if v.kind == "warn":
			warns += 1
	t.check(warns == 1 and lab.visible_toasts().size() == 1, "백업 경고 알림 하나만 남음(%d개 중 경고 %d)" % [lab.visible_toasts().size(), warns])
	for p in [path, path + ".bak", path + ".broken"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	lab._clear_toasts()
	# 밭 잃음 10번 → 알림 하나 "×10", 마지막 문장
	for i in 10:
		lab.show_toast("버려진 밭 1곳이 풀밭으로 돌아감 (남은 밭 %d)" % (20 - i), "farm_lost", 100 + i)
	var vt := lab.visible_toasts()
	t.check(vt.size() == 1 and int(vt[0].count) == 10 and str(vt[0].text).contains("남은 밭 11"), "밭 잃음 10번 → 알림 하나(×%d)" % (int(vt[0].count) if not vt.is_empty() else 0))
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
	t.check(lab._top_bar.get_combined_minimum_size().x <= UiConfig.num("lab.min_width"), "멸종 표시에서도 위쪽 막대가 최소 창 폭 안")
	lab.set_paused(false)
	for i in 5:
		lab.advance_frame(DT)
	t.check(lab.world.tick > tk and not lab.is_paused(), "다시 재생하면 빈 지도가 계속 진행")
	lab.set_paused(true)
	lab.new_experiment("default", {}, 1)
	t.check(lab.is_paused() and lab.info_panel.summary_text().contains("슬라임을 눌러"), "새 세계: 사용자가 멈춘 상태는 그대로, 안내는 처음 문구")
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
	t.check(not lab.is_paused() and lab.world.tick > t2, "pause_on_extinction 끄면 멸종 뒤에도 진행")
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
