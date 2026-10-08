extends RefCounted
## ChroniclePanel 검사. tests/run_view_tests.gd 가 불러 run(t) 을 부른다.
## 계약: docs/VIEW-API.md "ChroniclePanel". 픽셀은 tests/chronicle_capture.gd 로 본다.
## 비교 모드(A/B)는 LabMain.start_compare 없이도 확인한다: Experiment 둘을 만들어 패널의 공개 함수
## set_experiments([A, B])·append_events(index, 사건) 로 넣는다(LabMain 이 신호로 하는 것과 같은 길).

const PRESET := "demo_fast"
## 세대 이정표를 5세대마다(기본 100 은 짧은 검사에서 안 나옴)
const SETS := {"record.generation_milestone": 5}
## 씨앗 1 을 이만큼: 채집·저장 발견, 저장고 셋, 세대 이정표가 생김
const TICKS := 760
## 씨앗 2 는 일찍 저장고·첫 밭(행위자 있는 사건)이 생김(씨앗 1 은 422틱에 첫 발견)
const SEED_B := 2
const TICKS_B := 450
## 꾸며 넣는 사건 수(max_items 300 을 넘게)와 그 틱 시작(네 자리 — 틱 열 폭이 그대로)
const SYNTH := 400
const SYNTH_TICK0 := 1000
const SYNTH_KINDS: Array[String] = ["discovery", "store_built", "first_farm", "farm_lost", "milestone", "extinction", "unknown_kind"]
const DT := 1.0 / 60.0
const LONG_TEXT := "아주 긴 사건 문장 — 화면 폭을 여러 번 넘도록 낱말을 계속 이어 붙여서 두 줄 안에 다 들어가지 않는지 확인합니다 (끝 표지 ZZ-끝)"
const KEEP_ALL_TEXT := "버려진 밭 1곳이 풀밭으로 돌아감 (남은 밭 84)"
## 이 모듈이 적어도 하는 검사 수(중간에 스크립트 오류로 끊기면 실행기가 실패로 셈)
const MIN_CHECKS := 60


func run(t) -> void:
	await _real_chronicle(t)
	await _synthetic(t)
	await _compare(t)
	await _with_lab(t)
	_wrap(t)


## ① 실제 연대기: 다시 읽기·순서·글·덧붙이기·거르기, 연대기를 고치지 않음
func _real_chronicle(t) -> void:
	var x: Experiment = Experiment.create(PRESET, SETS, 1).experiment
	t.check(x != null, "실험 만들기")
	if x == null:
		return
	x.step_n(TICKS)
	var ch: Array = x.world.chronicle
	var copy: Array = ch.duplicate(true)
	var kinds := {}
	for e: Dictionary in ch:
		kinds[e.kind] = true
	t.check(ch.size() >= 6 and kinds.has("discovery") and kinds.has("store_built") and kinds.has("milestone"),
			"연대기에 발견·저장고·세대 사건이 있음(%d개 %s)" % [ch.size(), kinds.keys()])
	var panel := ChroniclePanel.new()
	panel.position = Vector2.ZERO
	panel.size = Vector2(UiConfig.num("chronicle.width"), UiConfig.num("lab.bottom_panel_height"))
	t.root.add_child(panel)
	await t.frames(2)
	t.check(panel.item_count() == 0 and panel.older_count() == 0, "처음엔 빈 목록")
	t.check(panel.max_items == UiConfig.integer("chronicle.max_items"), "최대 줄 수 = ui.chronicle.max_items")
	t.check(is_equal_approx(panel.custom_minimum_size.x, UiConfig.num("chronicle.width")), "너비 = ui.chronicle.width")
	panel.set_experiments([x])
	await t.frames(1)
	t.check(panel.item_count() == ch.size(), "다시 읽기: 줄 수 %d = 연대기 %d" % [panel.item_count(), ch.size()])
	t.check(panel.item_text(0) == _fmt(ch.back()), "맨 위 = 가장 최근 사건: " + panel.item_text(0))
	t.check(panel.item_text(ch.size() - 1) == _fmt(ch[0]), "맨 아래 = 가장 오래된 사건: " + panel.item_text(ch.size() - 1))
	t.check(_non_increasing(panel), "줄의 틱이 위에서 아래로 줄어듦(최신이 위)")
	var all_match := true
	for i in ch.size():
		if panel.item_text(i) != _fmt(ch[ch.size() - 1 - i]):
			all_match = false
	t.check(all_match, "모든 줄 = \"틱 N · 평균 G세대 · 문장\"(연대기 역순)")
	# 다시 읽은 뒤 아직 비우지 않은 사건(이미 읽은 것)이 와도 두 번 넣지 않는다
	var pending := x.world.drain_events()
	t.check(pending.size() == ch.size(), "세계에 아직 비우지 않은 사건 %d개" % pending.size())
	panel.append_events(0, pending)
	t.check(panel.item_count() == ch.size(), "다시 읽은 틱 이하의 사건은 건너뜀(중복 없음)")
	# 새 사건 덧붙이기(실제 진행)
	var n0 := ch.size()
	var guard := 0
	while x.world.chronicle.size() == n0 and guard < 1500:
		x.step()
		guard += 1
	var ev := x.world.drain_events()
	t.check(not ev.is_empty(), "더 진행해 새 사건 %d개(틱 %d)" % [ev.size(), x.world.tick])
	copy = x.world.chronicle.duplicate(true)
	panel.append_events(0, ev)
	await t.frames(1)
	t.check(panel.item_count() == x.world.chronicle.size() and panel.item_text(0) == _fmt(x.world.chronicle.back()),
			"events_tagged 로 덧붙임 → 맨 위: " + panel.item_text(0))
	panel.append_events(5, ev)
	t.check(panel.item_count() == x.world.chronicle.size(), "없는 실험 번호의 사건은 무시")
	# 거르기
	var want := _group_counts(x.world.chronicle)
	var filters_ok := true
	for g in range(1, ChroniclePanel.FILTER_NAMES.size()):
		panel.set_filter(g)
		if panel.item_count() != int(want.get(g, 0)) or panel.group_count(g) != int(want.get(g, 0)):
			filters_ok = false
		for i in panel.item_count():
			if int(panel.item(i).group) != g:
				filters_ok = false
	t.check(filters_ok, "거르기 묶음마다 그 종류만, 수도 맞음 %s" % [want])
	panel.set_filter(ChroniclePanel.FILTER_BUILD)
	var build_kinds_ok := panel.item_count() > 0
	for i in panel.item_count():
		if not (str(panel.item(i).kind) in ["store_built", "first_farm"]):
			build_kinds_ok = false
	t.check(build_kinds_ok, "건물 = 저장고·첫 밭")
	panel.set_filter(ChroniclePanel.FILTER_EXTINCTION)
	t.check(panel.item_count() == 0 and panel.older_count() == 0, "멸종 없음 → 빈 목록")
	# 거르기 단추(OptionButton)로 고르기
	var btn := t.node(panel, "Head/Filter") as OptionButton
	if btn != null:
		t.check(btn.item_count == ChroniclePanel.FILTER_NAMES.size() and btn.get_item_text(0).begins_with("전체"), "거르기 항목 6개(전체·발견·건물·밭 잃음·세대·멸종)")
		var idx := btn.get_item_index(ChroniclePanel.FILTER_DISCOVERY)
		btn.select(idx)
		btn.item_selected.emit(idx)
		t.check(panel.filter() == ChroniclePanel.FILTER_DISCOVERY and panel.item_count() == int(want.get(ChroniclePanel.FILTER_DISCOVERY, 0)),
				"거르기 단추로 발견만")
		t.check(btn.get_item_text(idx) == "발견 (%d)" % int(want.get(ChroniclePanel.FILTER_DISCOVERY, 0)), "거르기 항목에 사건 수: " + btn.get_item_text(idx))
		t.check(btn.focus_mode == Control.FOCUS_NONE, "거르기 단추는 초점을 받지 않음(스페이스 = 멈춤)")
	panel.set_filter(ChroniclePanel.FILTER_ALL)
	t.check(panel.item_count() == x.world.chronicle.size(), "전체로 되돌림")
	# 연대기 사전을 고치지 않음(줄은 우리 사본)
	t.check(SimConfig.deep_equal(copy, x.world.chronicle), "연대기 내용이 그대로(화면 캐시를 연대기 사전에 쓰지 않음)")
	# 빈 실험으로 다시 채우면 비워짐
	panel.set_experiments([Experiment.create(PRESET, SETS, 1).experiment])
	t.check(panel.item_count() == 0, "새 실험(experiments_changed) → 처음부터 다시 읽어 비움")
	panel.queue_free()
	await t.frames(1)


## ② 꾸민 사건 400개: 최대 줄 수·"더 오래된 K개"·거르기 수·노드 수 그대로·보이는 줄만 그림·새 줄만 접음·긴 문장
func _synthetic(t) -> void:
	var x: Experiment = Experiment.create(PRESET, SETS, 1).experiment
	var panel := ChroniclePanel.new()
	panel.size = Vector2(UiConfig.num("chronicle.width"), UiConfig.num("lab.bottom_panel_height"))
	t.root.add_child(panel)
	panel.set_experiments([x])
	await t.frames(2)
	var nodes0 := _count_nodes(panel)
	var list: Array = []
	var want := {}
	for i in SYNTH:
		var kind := SYNTH_KINDS[i % SYNTH_KINDS.size()]
		list.append({tick = SYNTH_TICK0 + i, kind = kind, actor = -1, text = "꾸민 사건 %d" % i, mean_gen = float(i) * 0.1})
		var g := int(ChroniclePanel.GROUP_OF.get(kind, 0))
		want[g] = int(want.get(g, 0)) + 1
	panel.append_events(0, list)
	await t.frames(2)
	var cap := UiConfig.integer("chronicle.max_items")
	t.check(panel.item_count() == mini(cap, SYNTH) and panel.older_count() == SYNTH - mini(cap, SYNTH),
			"최대 %d줄, 더 오래된 %d개(%d / %d)" % [cap, SYNTH - cap, panel.item_count(), panel.older_count()])
	t.check(int(panel.item(0).tick) == SYNTH_TICK0 + SYNTH - 1 and int(panel.item(cap - 1).tick) == SYNTH_TICK0 + SYNTH - cap,
			"남는 것은 최신 %d개" % cap)
	t.check(panel.group_count(ChroniclePanel.FILTER_ALL) == SYNTH, "전체 수 = %d(모르는 종류도 전체에)" % SYNTH)
	var counts_ok := true
	for g in range(1, ChroniclePanel.FILTER_NAMES.size()):
		if panel.group_count(g) != int(want.get(g, 0)):
			counts_ok = false
	t.check(counts_ok, "묶음별 수 %s" % [want])
	panel.set_filter(ChroniclePanel.FILTER_BUILD)
	t.check(panel.item_count() == int(want[ChroniclePanel.FILTER_BUILD]) and panel.older_count() == 0, "건물 거르기: 한도 아래면 더 오래된 것 없음")
	panel.set_filter(ChroniclePanel.FILTER_ALL)
	t.check(_count_nodes(panel) == nodes0, "줄이 %d개여도 노드 수 그대로(%d)" % [panel.item_count(), nodes0])
	await t.frames(2)
	var st: Dictionary = panel.list_stats()
	var lc := panel.list_control()
	var max_visible := ceili(lc.size.y / _min_row_h()) + 1
	t.check(int(st.drawn) > 0 and int(st.drawn) <= max_visible, "보이는 줄만 그림(%d줄, 목록 높이 %.0f)" % [int(st.drawn), lc.size.y])
	t.check(float(st.height) > lc.size.y, "목록 전체 높이 %.0f > 보이는 높이(스크롤)" % float(st.height))
	var bar := t.node(panel, "Card").find_child("Scroll", true, false) as VScrollBar
	t.check(bar != null and bar.modulate.a > 0.5 and is_equal_approx(bar.max_value, float(st.height)), "스크롤 막대가 보이고 범위 = 전체 높이")
	# 풍선 도움말: 줄 위 위치 → 그 줄의 도움말(Control.get_tooltip 이 _get_tooltip 을 부름)
	var r0 := panel.item_rect(0)
	var local0 := lc.get_global_transform().affine_inverse() * r0.get_center()
	t.check(lc.get_tooltip(local0) == panel.item_tooltip(0) and panel.item_tooltip(0).contains(panel.item(0).text), "줄 위 풍선 도움말 = 그 줄 설명")
	# 휠로 스크롤(실제 입력)
	if bar != null:
		var v0 := bar.value
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.factor = 1.0
		wheel.position = r0.get_center()
		wheel.global_position = r0.get_center()
		t.root.push_input(wheel)
		await t.frames(1)
		t.check(bar.value > v0, "휠을 내리면 아래로 스크롤(%.0f → %.0f)" % [v0, bar.value])
		bar.value = 0.0
		await t.frames(1)
	# 고른 줄은 거르기를 바꿨다 와도 그대로(그래프 시점 표시와 맞게)
	panel.activate_item(2)
	var sel_tick := int(panel.item(2).tick)
	panel.set_filter(ChroniclePanel.FILTER_DISCOVERY)
	panel.set_filter(ChroniclePanel.FILTER_ALL)
	t.check(lc.get("selected") is Dictionary and int((lc.get("selected") as Dictionary).get("tick", -1)) == sel_tick, "거르기를 바꿔도 고른 줄 유지")
	# 띠 색 = ui.chronicle.colors, 묶음마다 다름
	var cols := {}
	for g in ChroniclePanel.COLOR_KEYS.size():
		cols[ChroniclePanel.group_color(g).to_html()] = true
	t.check(cols.size() == ChroniclePanel.COLOR_KEYS.size() and ChroniclePanel.group_color(ChroniclePanel.FILTER_EXTINCTION) == UiConfig.color("chronicle.colors.extinction"),
			"묶음 띠 색 %d가지(ui.chronicle.colors)" % cols.size())
	# 새 사건 하나 → 그 줄만 접음(같은 틱이라 열 폭 그대로)
	var shaped0 := int(panel.list_stats().shaped)
	panel.append_events(0, [{tick = SYNTH_TICK0 + SYNTH - 1, kind = "milestone", actor = -1, text = "같은 틱의 새 사건", mean_gen = 40.0}])
	await t.frames(1)
	t.check(int(panel.list_stats().shaped) == shaped0 + 1, "새 사건 하나 → 문장 하나만 새로 접음(%d → %d)" % [shaped0, int(panel.list_stats().shaped)])
	t.check(panel.item_text(0).ends_with("같은 틱의 새 사건"), "같은 틱이면 나중 사건이 위")
	# 스크롤해 읽던 줄은 새 사건이 와도 제자리
	if bar != null:
		panel.scroll_to_item(50)
		await t.frames(1)
		var r50 := panel.item_rect(50)
		panel.append_events(0, [{tick = SYNTH_TICK0 + SYNTH, kind = "farm_lost", actor = -1, text = "읽는 중에 온 사건", mean_gen = 40.0}])
		await t.frames(1)
		var r51 := panel.item_rect(51)
		t.check(r50.size.y > 0.0 and absf(r51.position.y - r50.position.y) < 0.5, "읽던 줄(50 → 51)이 같은 자리(%.1f → %.1f)" % [r50.position.y, r51.position.y])
		bar.value = 0.0
	# 긴 문장: 최대 줄 수에서 말줄임, 풍선 도움말에 전체
	panel.append_events(0, [{tick = SYNTH_TICK0 + SYNTH + 1, kind = "discovery", actor = -1, text = LONG_TEXT, mean_gen = 41.0}])
	await t.frames(1)
	var rr := panel.item_rect(0)
	var font := panel.get_theme_font("font", "Label")
	var fs := UiConfig.integer("chronicle.text_font_size")
	var max_h := float(UiConfig.integer("chronicle.text_max_lines")) * font.get_height(fs) + 2.0 * UiConfig.num("chronicle.row_pad_v") + 1.0
	t.check(rr.size.y > 0.0 and rr.size.y <= max_h + 0.5, "긴 문장 줄 높이 %.0f ≤ %d줄 높이 %.0f" % [rr.size.y, UiConfig.integer("chronicle.text_max_lines"), max_h])
	t.check(panel.item_tooltip(0).contains(LONG_TEXT) and panel.item_tooltip(0).contains("틱 %s" % _commas(SYNTH_TICK0 + SYNTH + 1)), "풍선 도움말에 문장 전체·틱")
	t.check(panel.item_text(0).ends_with(LONG_TEXT), "item_text 는 잘리지 않은 문장")
	# 크기: 자리 안에 듦
	var ms := panel.get_combined_minimum_size()
	t.check(ms.x <= UiConfig.num("chronicle.width") + 0.5, "최소 너비 %.0f ≤ ui.chronicle.width" % ms.x)
	t.check(ms.y <= UiConfig.num("lab.bottom_panel_height") - 2.0 * UiConfig.num("theme.panel_padding"), "최소 높이 %.0f 가 아래 자리 안" % ms.y)
	panel.queue_free()
	await t.frames(1)


## ③ 비교 모드: 줄 앞 A/B, 두 연대기를 틱 순으로 섞음(같은 틱이면 B 가 위), 누르면 row_activated(틱, 행위자, 번호)
func _compare(t) -> void:
	var a: Experiment = Experiment.create(PRESET, SETS, 1).experiment
	var b: Experiment = Experiment.create(PRESET, SETS, SEED_B).experiment
	a.step_n(TICKS_B)
	b.step_n(TICKS_B)
	a.tag = "A"
	b.tag = "B"
	var na := a.world.chronicle.size()
	var nb := b.world.chronicle.size()
	t.check(na > 0 and nb > 0, "두 실험 모두 사건(A %d · B %d)" % [na, nb])
	var panel := ChroniclePanel.new()
	panel.size = Vector2(UiConfig.num("chronicle.width"), 300)
	t.root.add_child(panel)
	panel.set_experiments([a, b])
	await t.frames(2)
	t.check(panel.item_count() == na + nb, "두 연대기를 모두(%d)" % panel.item_count())
	var prefix_ok := true
	var a_rows := 0
	for i in panel.item_count():
		var it := panel.item(i)
		var tag := "A" if int(it.index) == 0 else "B"
		if not panel.item_text(i).begins_with(tag + " · 틱 "):
			prefix_ok = false
		if int(it.index) == 0:
			a_rows += 1
	t.check(prefix_ok and a_rows == na, "줄 앞에 A/B(A %d줄)" % a_rows)
	t.check(_non_increasing(panel), "두 실험을 섞어도 틱이 위에서 아래로 줄어듦")
	t.check(panel.item_tooltip(0).contains(b.display_name()) or panel.item_tooltip(0).contains(a.display_name()), "풍선 도움말에 실험 이름(A · …)")
	# 같은 틱의 사건: B(뒤 실험)가 위
	var tk := TICKS_B + 5
	panel.append_events(0, [{tick = tk, kind = "milestone", actor = -1, text = "A 의 사건", mean_gen = 3.0}])
	panel.append_events(1, [{tick = tk, kind = "milestone", actor = -1, text = "B 의 사건", mean_gen = 3.0}])
	t.check(panel.item_text(0).begins_with("B · ") and panel.item_text(1).begins_with("A · "), "같은 틱이면 B 가 위(A 다음 B 를 진행)")
	panel.set_filter(ChroniclePanel.FILTER_BUILD)
	t.check(panel.item_count() == panel.group_count(ChroniclePanel.FILTER_BUILD) and panel.item_count() > 0, "비교 모드에서도 거르기(건물 %d)" % panel.item_count())
	# 행위자 있는 B 의 줄(첫 밭)을 누르면 row_activated(틱, 행위자, 1)
	var got: Array = []
	panel.row_activated.connect(func(tick: int, actor: int, index: int) -> void: got.append([tick, actor, index]))
	var bi := -1
	for i in panel.item_count():
		if int(panel.item(i).actor) >= 0 and int(panel.item(i).index) == 1:
			bi = i
			break
	t.check(bi >= 0, "B 에 행위자가 있는 사건(첫 밭)")
	if bi >= 0:
		var it := panel.item(bi)
		panel.activate_item(bi)
		t.check(got.size() == 1 and got[0] == [int(it.tick), int(it.actor), 1], "누르면 row_activated(틱 %d, #%d, B)" % [int(it.tick), int(it.actor)])
		# 실제 마우스 클릭(뷰포트 입력)으로도
		panel.scroll_to_item(bi)
		await t.frames(1)
		var r := panel.item_rect(bi)
		_click(t, r.get_center())
		await t.frames(1)
		t.check(got.size() == 2 and got[1] == got[0], "마우스로 줄을 눌러도 같음")
	panel.queue_free()
	await t.frames(1)


## ④ 실험실에 붙여: experiments_changed·events_tagged 연결, 누르면 request_cursor·select_slime, 해시 그대로
func _with_lab(t) -> void:
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(1)
	lab.set_process(false)
	lab.set_paused(true)
	var panel := ChroniclePanel.new()
	lab.bottom_dock.add_child(panel)
	panel.bind_lab(lab)
	t.check(panel.item_count() == lab.world.chronicle.size(), "bind_lab 이 지금 실험을 바로 읽음")
	t.check(lab.new_experiment(PRESET, SETS, SEED_B) == "", "새 실험")
	t.check(panel.item_count() == 0, "새 실험 → 빈 목록")
	lab.step_ticks(TICKS_B)
	lab.advance_frame(DT)
	var ch: Array = lab.world.chronicle
	t.check(ch.size() > 0 and panel.item_count() == ch.size() and panel.item_text(0) == _fmt(ch.back()),
			"advance_frame 의 events_tagged 로 덧붙음(%d / %d)" % [panel.item_count(), ch.size()])
	var ref: SimWorld = t.make_world(SETS, SEED_B, PRESET)
	ref.step_n(lab.world.tick)
	var diff: String = t.same_state(lab.world, ref)
	t.check(diff == "" and ref.history_hash == lab.world.history_hash, "연대기 창이 붙어도 역사·상태가 헤드리스와 같음 %s" % diff)
	# 다시 붙여도(bind_lab 두 번) 줄이 두 번 들어가지 않음
	panel.bind_lab(lab)
	lab.step_ticks(40)
	lab.advance_frame(DT)
	t.check(panel.item_count() == lab.world.chronicle.size(), "bind_lab 을 다시 불러도 한 번씩만(%d)" % panel.item_count())
	# 행위자가 있는 줄(첫 밭)을 마우스로 누르면 그래프 시점 요청 + 그 개체 선택
	var cursor: Array[int] = []
	lab.cursor_tick_requested.connect(func(tk: int) -> void: cursor.append(tk))
	var fi := -1
	for i in panel.item_count():
		if int(panel.item(i).actor) >= 0:
			fi = i
			break
	t.check(fi >= 0, "행위자가 있는 사건(첫 밭)이 있음")
	await t.frames(2)
	if fi >= 0:
		var it := panel.item(fi)
		panel.scroll_to_item(fi)
		await t.frames(1)
		var r := panel.item_rect(fi)
		t.check(r.size.y > 0.0, "그 줄이 화면에 보임")
		_click(t, r.get_center())
		await t.frames(1)
		t.check(cursor.size() == 1 and cursor[0] == int(it.tick), "누르면 lab.request_cursor(틱 %d)" % int(it.tick))
		t.check(lab.selected_id() == int(it.actor), "행위자 #%d 선택(지금 %d)" % [int(it.actor), lab.selected_id()])
	# 행위자 없는 줄: 시점만, 선택은 그대로
	var ni := -1
	for i in panel.item_count():
		if int(panel.item(i).actor) < 0:
			ni = i
			break
	if ni >= 0:
		var before := lab.selected_id()
		panel.activate_item(ni)
		t.check(cursor.back() == int(panel.item(ni).tick) and lab.selected_id() == before, "행위자 없는 줄은 시점만")
	panel.queue_free()
	lab.queue_free()
	await t.frames(1)


## ⑤ 낱말 단위 줄바꿈(한글 음절 사이에서 끊지 않음)·말줄임
func _wrap(t) -> void:
	var font: Font = UiTheme.regular_font()
	var fs := UiConfig.integer("chronicle.text_font_size")
	var w := font.get_string_size(KEEP_ALL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.8
	var lines := ChroniclePanel.wrap_text(font, KEEP_ALL_TEXT, fs, w, 3)
	t.check(lines.size() == 2 and " ".join(lines) == KEEP_ALL_TEXT, "낱말 단위로 접음(음절 사이 끊지 않음): %s" % [lines])
	var fit := true
	for ln in lines:
		if font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w + 0.5:
			fit = false
	t.check(fit, "접은 줄이 폭 안")
	var two := ChroniclePanel.wrap_text(font, LONG_TEXT, fs, 200.0, 2, "…")
	t.check(two.size() == 2 and two[1].ends_with("…") and font.get_string_size(two[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= 200.5,
			"최대 줄 수를 넘으면 마지막 줄 말줄임: %s" % [two])
	var one := ChroniclePanel.wrap_text(font, "가나다라마바사아자차카타파하가나다라마바사아자차카타파하", fs, 60.0, 9)
	var one_fit := one.size() > 1
	for ln in one:
		if font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 60.5:
			one_fit = false
	t.check(one_fit and "".join(one) == "가나다라마바사아자차카타파하가나다라마바사아자차카타파하", "폭보다 긴 낱말만 글자 단위로 자름")


# ── 도움 ──

## 줄 글 기대값: "틱 N · 평균 G세대 · 문장"
func _fmt(e: Dictionary) -> String:
	return "틱 %s · 평균 %.1f세대 · %s" % [_commas(int(e.tick)), float(e.mean_gen), str(e.text)]


func _commas(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _non_increasing(panel: ChroniclePanel) -> bool:
	for i in range(1, panel.item_count()):
		if int(panel.item(i).tick) > int(panel.item(i - 1).tick):
			return false
	return true


func _group_counts(ch: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in ch:
		var g := int(ChroniclePanel.GROUP_OF.get(str(e.kind), 0))
		out[g] = int(out.get(g, 0)) + 1
	return out


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


## 한 줄짜리 줄 높이(가장 작은 줄)
func _min_row_h() -> float:
	var font: Font = UiTheme.regular_font()
	var lh := maxf(font.get_height(UiConfig.integer("chronicle.text_font_size")), font.get_height(UiConfig.integer("lab.font_size_small")))
	return lh + 2.0 * UiConfig.num("chronicle.row_pad_v") + 1.0


## 뷰포트에 실제 마우스 입력(움직임 → 왼쪽 누름 → 뗌)
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
