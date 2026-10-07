extends RefCounted
## LabMain 검사: 장면·배치·테마, 프레임 진행(배속·멈춤·빨리 감기·예산), 선택 연결, 단축키, 사건 알림,
## 역사 해시(화면을 거쳐도 헤드리스와 같음), 명령줄 대체값, 스냅숏 열기. 프레임은 advance_frame 으로 직접 몬다.

const DT := 1.0 / 60.0
const SNAP_PATH := "user://lab_checks_snapshot.json"


func run(t) -> void:
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(2)
	lab.set_process(false)
	await _layout(t, lab)
	_run_loop(t, lab)
	_budget(t, lab)
	_selection(t, lab)
	await _keys(t, lab)
	_events(t, lab)
	_hash(t, lab)
	_args(t, lab)
	lab.queue_free()
	await t.frames(1)


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
	# 빨리 감기: 가벼운 세계에서 64배(프레임당 6.4틱)보다 많이, 예산은 대략 지킴
	lab.new_experiment("default", {"population.initial": 20}, 3)
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
	_key(t, KEY_F)
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
	lab.events.connect(func(list: Array) -> void: got.append_array(list))
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
	for i in 3:
		lab.advance_frame(DT)
	var ref: SimWorld = t.make_world({}, 11)
	ref.step_n(lab.world.tick)
	t.check(lab.world.tick > 100 and lab.world.history_hash == ref.history_hash, "화면으로 %d틱 진행해도 역사 해시가 헤드리스와 같음" % lab.world.tick)
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
